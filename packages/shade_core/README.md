# shade_core

The colour engine of Nuans. Pure Dart: no Flutter, no file system, no clock, no
randomness. Every function is total and deterministic, so the whole package is
unit testable and the same input always produces the same output.

Specification: [`docs/architecture/02-algorithms.md`](../../docs/architecture/02-algorithms.md).
Boundary rationale: [`docs/adr/0001-color-math-boundary.md`](../../docs/adr/0001-color-math-boundary.md).

## What lives here

| Directory | Contents |
|---|---|
| `src/colorimetry` | linear algebra, white points, sRGB transfer, XYZ/Lab/LCh, Bradford adaptation, CIEDE2000, McCamy CCT |
| `src/calibration` | colour correction matrix fitting, grey card correction, capture transform, grey card validation, device profile |
| `src/capture` | value types for the linear camera-space samples the native layer returns |
| `src/statistics` | median / MAD / trimmed mean, robust region reduction with specular and shadow rejection |
| `src/matching` | shade libraries, brute force nearest search, component deviations, acceptability thresholds |

## Two rules this package never breaks

1. **No user-facing text.** Every result is a machine code (`ComponentMagnitude.slight`,
   `GrayCardIssue.mixedLight`). Localisation happens in the Flutter layer, from ARB files.
2. **Averaging happens in linear XYZ, never in Lab.** Lab is perceptually non-linear;
   averaging there biases the result.

## Reference oracle

The formulas in the specification are also implemented in Python under
[`tools/spec_oracle/`](../../tools/spec_oracle/). The expected values embedded in the
tests of this package were produced there, so they are computed rather than recalled.
