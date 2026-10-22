#!/usr/bin/env bash
#
# Formats the hand-written Dart, and only the hand-written Dart.
#
# Generated files are committed exactly as their generator emits them, because
# that is the only form the codegen freshness checks can diff against. Running
# `dart format lib` instead reformats pigeon's output and breaks that check -
# which has happened twice, both times by reflex. One definition of what gets
# formatted, used by CI and by hand, is cheaper than remembering.
#
#   tools/format.sh            # format in place
#   tools/format.sh --check    # fail if anything is unformatted (CI)

set -euo pipefail
cd "$(dirname "$0")/.."

# No mapfile and no process substitution: macOS still ships bash 3.2, and this
# has to run there as well as on the CI runner.
hand_written() {
  git ls-files 'lib/*.dart' 'lib/**/*.dart' 'test/*.dart' 'test/**/*.dart' \
    'tools/**/*.dart' 'packages/*/lib/**/*.dart' 'packages/*/test/**/*.dart' \
    | grep -v '[.]g[.]dart$'
}

if [ "${1:-}" = "--check" ]; then
  hand_written | xargs dart format --output=none --set-exit-if-changed
else
  hand_written | xargs dart format
fi
