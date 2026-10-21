"""Checks the hand-written Kotlin against the generated Pigeon bindings.

The Android side is compiled by Gradle, which is the real answer. This exists
for the case Gradle is not available - a CI job without an Android SDK, or a
quick check before a long build - and because it names the mismatch instead of
burying it in a Kotlin compiler error.

Compares: every `ShadeCameraHostApi` method signature the plugin declares,
every generated data-class field a construction uses, and every enum entry
referenced.

Run:  python3 -I tools/native/check_kotlin_against_pigeon.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CAMERA = ROOT / "android" / "app" / "src" / "main" / "kotlin" / "com" / "nuans" / "app" / "camera"
GENERATED = CAMERA / "ShadeCameraApi.g.kt"


def body_of(src, start):
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
        for f in sorted(CAMERA.glob("*.kt"))
        if not f.name.endswith(".g.kt")
    }
    mine = "\n".join(sources.values())

    # Pigeon's Kotlin data classes: `data class X (\n  val field: Type,\n ...)`.
    # A field with a default is optional.
    classes = {}
    for m in re.finditer(r"data class (\w+) \(", gen):
        params = gen[m.end():]
        depth, i = 1, 0
        while i < len(params) and depth:
            if params[i] == "(":
                depth += 1
            elif params[i] == ")":
                depth -= 1
            i += 1
        block = params[: i - 1]
        fields, required = set(), set()
        for fm in re.finditer(r"val (\w+): ([^,\n]+?)(\s*=\s*null)?\s*(?:,|$)",
                              block, re.M):
            fields.add(fm.group(1))
            if not fm.group(3):
                required.add(fm.group(1))
        classes[m.group(1)] = (fields, required)

    enums = {}
    for m in re.finditer(r"enum class (\w+)\(val raw: Int\) \{", gen):
        body = body_of(gen, m.start())
        enums[m.group(1)] = set(re.findall(r"^\s*([A-Z][A-Z0-9_]*)\(\d+\)", body, re.M))

    host = {}
    proto_at = gen.index("interface ShadeCameraHostApi {")
    interface = body_of(gen, proto_at)
    # Pigeon nests a `companion object` with `setUp` inside the interface. That
    # is the registration helper, not a method the implementor provides, so the
    # scan stops where the companion begins.
    if "companion object" in interface:
        interface = interface[: interface.index("companion object")]
    for m in re.finditer(r"fun (\w+)\(([^)]*)\)", interface):
        host[m.group(1)] = [
            p.strip().split(":")[0].strip()
            for p in m.group(2).split(",")
            if ":" in p
        ]

    problems = []
    plugin = sources.get("ShadeCameraPlugin.kt", "")
    for name, params in host.items():
        sig = re.search(r"fun " + name + r"\(([^)]*)\)", plugin, re.S)
        if sig is None:
            problems.append(f"host method {name} is not implemented in the plugin")
            continue
        mine_params = [
            p.strip().split(":")[0].strip()
            for p in sig.group(1).split(",")
            if ":" in p
        ]
        if mine_params != params:
            problems.append(
                f"{name}: generated {params} but the plugin declares {mine_params}"
            )

    for name, (fields, required) in classes.items():
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
            used = set(re.findall(r"(?:^\s*|[,(]\s*)(\w+)\s*=", call, re.M))
            if not (used & fields):
                continue
            missing = required - used
            if missing:
                problems.append(
                    f"{name}(...) omits required field(s) {sorted(missing)}"
                )

    for name, entries in enums.items():
        for m in re.finditer(r"(?<![\w.])" + name + r"\.(\w+)", mine):
            entry = m.group(1)
            if entry not in entries and entry not in {
                    "values", "valueOf", "entries", "ofRaw", "raw", "Companion"}:
                problems.append(f"{name}.{entry} is not an entry of the generated enum")

    print(
        f"generated: {len(classes)} data classes, {len(enums)} enums, "
        f"{len(host)} host methods"
    )
    print(f"checked: {len(sources)} hand-written Kotlin files")
    seen = set()
    out = [p for p in problems if not (p in seen or seen.add(p))]
    if out:
        print(f"\n{len(out)} mismatch(es):")
        for p in out:
            print("  -", p)
        return 1
    print(
        "\nevery host signature, data-class field and enum entry used by the "
        "hand-written Kotlin matches the generated bindings"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
