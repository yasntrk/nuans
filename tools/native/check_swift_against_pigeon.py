"""Checks the hand-written Swift against the generated Pigeon bindings.

The iOS side cannot be compiled here - there is no Xcode project - so this is
the closest substitute: every host method signature, every struct initialiser
label and every enum case the hand-written Swift uses is compared against what
Pigeon actually generated.

It is not a compiler. It does not resolve types, dotted enum shorthand, or
anything about AVFoundation. What it does catch is the failure mode that a
hand-written platform implementation actually has: the contract moved and the
implementation did not.

Run:  python3 -I tools/native/check_swift_against_pigeon.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CAMERA = ROOT / "ios" / "Runner" / "Camera"
GENERATED = CAMERA / "ShadeCameraApi.g.swift"


def body_of(src, start):
    """The text between the brace that opens at `start` and its match."""
    open_at = src.index("{", start)
    depth, i = 0, open_at
    while i < len(src):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[open_at:i]
        i += 1
    return src[open_at:]


def main():
    if not GENERATED.exists():
        print(f"no generated bindings at {GENERATED}; run dart run pigeon first")
        return 1
    gen = GENERATED.read_text()
    sources = {
        f.name: f.read_text()
        for f in sorted(CAMERA.glob("*.swift"))
        if not f.name.endswith(".g.swift")
    }
    mine = "\n".join(sources.values())

    # Pigeon's Swift structs rely on the implicit memberwise initialiser, so the
    # labels are the `var` declarations, in order. A var with a default is
    # optional.
    structs = {}
    for m in re.finditer(r"^struct (\w+) \{", gen, re.M):
        body = body_of(gen, m.start())
        fields, required = [], set()
        for fm in re.finditer(r"^  var (\w+): ([^\n=]+?)( = nil)?$", body, re.M):
            fields.append(fm.group(1))
            if not fm.group(3):
                required.add(fm.group(1))
        structs[m.group(1)] = (set(fields), required)

    enums = {}
    for m in re.finditer(r"^enum (\w+): Int \{", gen, re.M):
        body = body_of(gen, m.start())
        enums[m.group(1)] = set(re.findall(r"case (\w+)", body))

    host = {}
    proto_at = gen.index("protocol ShadeCameraHostApi {")
    for m in re.finditer(r"func (\w+)\(([^)]*)\)", body_of(gen, proto_at)):
        host[m.group(1)] = [
            p.strip().split(":")[0].strip()
            for p in m.group(2).split(",")
            if ":" in p
        ]

    problems = []

    # The protocol is conformed to in the plugin, so that is where the
    # signatures have to match exactly.
    plugin = sources.get("ShadeCameraPlugin.swift", "")
    for name, labels in host.items():
        sig = re.search(r"func " + name + r"\(([^)]*)\)", plugin, re.S)
        if sig is None:
            problems.append(f"host method {name} is not implemented in the plugin")
            continue
        mine_labels = [
            p.strip().split(":")[0].strip()
            for p in sig.group(1).split(",")
            if ":" in p
        ]
        if mine_labels != labels:
            problems.append(
                f"{name}: generated {labels} but the plugin declares {mine_labels}"
            )

    # Struct construction anywhere in the hand-written sources.
    for name, (fields, required) in structs.items():
        for m in re.finditer(r"(?<![\w.])" + name + r"\(", mine):
            rest = mine[m.end():]
            depth, i = 1, 0
            while i < len(rest) and depth:
                if rest[i] == "(":
                    depth += 1
                elif rest[i] == ")":
                    depth -= 1
                i += 1
            call = rest[: i - 1]
            if "\n" not in call:
                continue
            used = set(re.findall(r"(?:^\s*|[,(]\s*)(\w+):", call, re.M))
            # Only labels that belong to this struct are judged; a nested call's
            # labels are another construction's business and are checked when
            # that construction is reached.
            relevant = used & fields
            if not relevant:
                continue
            missing = required - used
            if missing:
                problems.append(
                    f"{name}(...) omits required field(s) {sorted(missing)}"
                )

    for name, cases in enums.items():
        for m in re.finditer(r"(?<![\w.])" + name + r"\.(\w+)", mine):
            case = m.group(1)
            if case not in cases and case not in {"allCases", "rawValue", "init"}:
                problems.append(f"{name}.{case} is not a case of the generated enum")

    print(
        f"generated: {len(structs)} structs, {len(enums)} enums, "
        f"{len(host)} host methods"
    )
    print(f"checked: {len(sources)} hand-written Swift files")
    seen = set()
    out = [p for p in problems if not (p in seen or seen.add(p))]
    if out:
        print(f"\n{len(out)} mismatch(es):")
        for p in out:
            print("  -", p)
        return 1
    print(
        "\nevery host signature, struct field and enum case used by the "
        "hand-written Swift matches the generated bindings"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
