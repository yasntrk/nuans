#!/usr/bin/env python3
"""Checks that Flutter engine APIs are only touched from the platform thread.

Why this exists
---------------

Two bugs in this repository came from the same mistake, and the second one
crashed the application on a tester's phone:

  * events were sent to Dart from the camera thread, and
  * the preview texture was registered from the camera thread.

Both are calls into the Flutter engine, and the engine asserts the thread. On
Android the assertion is visible in the bytecode: ``FlutterJNI`` begins
``dispatchPlatformMessage``, ``registerTexture``, ``unregisterTexture`` and
``markTextureFrameAvailable`` with ``ensureRunningOnMainThread()``, which
throws. An exception escaping a ``HandlerThread`` ends the process, so the
symptom is the application vanishing with no message at all - which is exactly
what was reported.

The native layer deliberately runs its own threads, so the rule cannot be
"never use another thread". It is "every engine call goes through one named
helper", and that is what this checks: the guarded symbols may appear only
inside the helper that marshals them, or on their own declaration.

It is a text check, not a compiler. It cannot prove the helper is correct; it
can only stop the next call site from quietly skipping it.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


class Rule:
    """One guarded symbol and the function allowed to use it."""

    def __init__(self, symbol: str, helpers: list[str], reason: str):
        self.symbol = symbol
        self.helpers = helpers
        self.reason = reason


KOTLIN = ROOT / "android/app/src/main/kotlin/com/nuans/app/camera/Camera2SessionController.kt"
SWIFT = ROOT / "ios/Runner/Camera/CaptureSessionController.swift"

KOTLIN_RULES = [
    Rule(
        "events",
        ["emit"],
        "a platform channel send reaches FlutterJNI.dispatchPlatformMessage, "
        "which asserts the main thread",
    ),
    Rule(
        "textureRegistry",
        ["requireTextureEntry"],
        "registering a texture reaches FlutterJNI.registerTexture, which "
        "asserts the main thread",
    ),
]

SWIFT_RULES = [
    Rule(
        "events",
        ["emit"],
        "a platform channel send belongs on the platform thread",
    ),
    Rule(
        "textureRegistry",
        ["init", "DispatchQueue.main"],
        "registering a texture belongs on the platform thread, so it may be "
        "named only where the controller is handed it or inside a queue hop",
    ),
]

def is_declaration(line: str, symbol: str) -> bool:
    """True when the line declares ``symbol`` rather than calling through it.

    Tied to the symbol on purpose. A looser rule that exempted any ``val x =``
    line also exempted ``val entry = textureRegistry.createSurfaceTexture()``,
    which is the exact line this checker exists to catch - and it did pass,
    until it was tried against the bug.
    """
    name = re.escape(symbol)
    return bool(
        re.match(rf"^\s*(private\s+)?(val|var|let)\s+{name}\b", line)
        or re.match(rf"^\s*(private\s+)?{name}:\s*\w", line)
        or re.match(rf"^\s*self\.{name}\s*=\s*{name}\s*$", line)
    )


def block_ranges(lines: list[str], pattern: re.Pattern) -> list:
    """Line ranges (1-based, inclusive) of every brace block ``pattern`` opens."""
    ranges = []
    for index, line in enumerate(lines):
        if not pattern.search(line):
            continue
        # Walk forward to the opening brace, then match braces to the close.
        depth = 0
        opened = False
        for cursor in range(index, len(lines)):
            for character in lines[cursor]:
                if character == "{":
                    depth += 1
                    opened = True
                elif character == "}":
                    depth -= 1
            if opened and depth == 0:
                ranges.append((index + 1, cursor + 1))
                break
    return ranges


def helper_ranges(lines: list[str], name: str) -> list:
    """Line ranges of every region allowed to name a guarded symbol.

    Usually a function. ``init`` is spelled without ``func`` in Swift, and
    ``DispatchQueue.main`` is not a function at all but the queue hop itself -
    which is the thing that actually puts the call on the platform thread.
    """
    if name == "init":
        return block_ranges(lines, re.compile(r"\binit\s*\("))
    if name == "DispatchQueue.main":
        return block_ranges(lines, re.compile(r"DispatchQueue\.main\.(sync|async)"))
    return block_ranges(lines, re.compile(rf"\b(fun|func)\s+{re.escape(name)}\s*\("))


def check(path: pathlib.Path, rules: list[Rule]) -> list[str]:
    if not path.exists():
        return [f"{path.relative_to(ROOT)}: missing"]
    lines = path.read_text().splitlines()
    problems = []
    for rule in rules:
        allowed = []
        for helper in rule.helpers:
            found = helper_ranges(lines, helper)
            if not found:
                problems.append(
                    f"{path.relative_to(ROOT)}: no function named "
                    f"{helper!r} to hold {rule.symbol!r}"
                )
            allowed.extend(found)
        word = re.compile(rf"\b{re.escape(rule.symbol)}\b")
        for number, line in enumerate(lines, start=1):
            if not word.search(line):
                continue
            if line.lstrip().startswith(("//", "*", "/*", "///")):
                continue
            if is_declaration(line, rule.symbol):
                continue
            if any(start <= number <= end for start, end in allowed):
                continue
            problems.append(
                f"{path.relative_to(ROOT)}:{number}: {rule.symbol!r} outside "
                f"{' or '.join(rule.helpers)}() - {rule.reason}\n"
                f"    {line.strip()}"
            )
    return problems


def main() -> int:
    problems = check(KOTLIN, KOTLIN_RULES) + check(SWIFT, SWIFT_RULES)
    if problems:
        print("platform-thread rule broken:\n")
        for problem in problems:
            print("  -", problem)
        print(
            "\nRoute the call through the marshalling helper. An engine call "
            "on a background thread\nthrows, and on a HandlerThread that ends "
            "the process with no message."
        )
        return 1
    print(
        "every Flutter engine call in the hand-written native code goes "
        "through its platform-thread helper"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
