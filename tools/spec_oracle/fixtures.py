"""Generates the expected values embedded in packages/shade_core tests.

Every literal in the Dart tests that is not published reference data comes from
here, so the test numbers are computed, never recalled. Run:

    python3 -I tools/spec_oracle/fixtures.py
"""

import contextlib
import importlib.util
import io
import math
import pathlib
import random

D65 = (0.95047, 1.0, 1.08883)
D50 = (0.96422, 1.0, 0.82521)
EPS, KAPPA = 216 / 24389, 24389 / 27

SRGB_TO_XYZ = [
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041],
]
BRADFORD = [
    [0.8951, 0.2664, -0.1614],
    [-0.7502, 1.7135, 0.0367],
    [0.0389, -0.0685, 1.0296],
]


def apply(m, v):
    return tuple(sum(m[r][c] * v[c] for c in range(3)) for r in range(3))


def inv3(m):
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]


def mul(m, n):
    return [[sum(m[r][k] * n[k][c] for k in range(3)) for c in range(3)] for r in range(3)]


def srgb_decode(s):
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def f(t):
    return t ** (1 / 3) if t > EPS else (KAPPA * t + 16) / 116


def to_lab(xyz, wp=D65):
    fx, fy, fz = (f(xyz[i] / wp[i]) for i in range(3))
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def to_lch(lab):
    L, a, b = lab
    return (L, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360)


def bradford(src, dst):
    s, d = apply(BRADFORD, src), apply(BRADFORD, dst)
    diag = [[d[0] / s[0], 0, 0], [0, d[1] / s[1], 0], [0, 0, d[2] / s[2]]]
    return mul(mul(inv3(BRADFORD), diag), BRADFORD)


def row(label, v, nd=10):
    print(f"{label:<34}" + "  ".join(f"{x:.{nd}f}" for x in v))


print("=== sRGB encoded -> linear ===")
for name, s in [("0.5", 0.5), ("0.04045", 0.04045), ("0.03", 0.03)]:
    print(f"{name:<34}{srgb_decode(s):.12f}")

print("\n=== sRGB -> XYZ(D65) -> Lab -> LCh ===")
for name, rgb in [
    ("white 1,1,1", (1.0, 1.0, 1.0)),
    ("black 0,0,0", (0.0, 0.0, 0.0)),
    ("mid grey 0.5", (0.5, 0.5, 0.5)),
    ("red 1,0,0", (1.0, 0.0, 0.0)),
    ("green 0,1,0", (0.0, 1.0, 0.0)),
    ("blue 0,0,1", (0.0, 0.0, 1.0)),
    ("tooth-ish 0.84,0.80,0.71", (0.84, 0.80, 0.71)),
]:
    lin = tuple(srgb_decode(c) for c in rgb)
    xyz = apply(SRGB_TO_XYZ, lin)
    lab = to_lab(xyz)
    lch = to_lch(lab)
    print(f"\n{name}")
    row("  linear", lin)
    row("  XYZ", xyz)
    row("  Lab", lab, 7)
    row("  LCh", lch, 7)

print("\n=== invariants ===")
row("sRGB matrix * (1,1,1)", apply(SRGB_TO_XYZ, (1, 1, 1)))
row("D65 white point", D65)
print("\nXYZ -> sRGB (inverse, for the assert):")
for r in inv3(SRGB_TO_XYZ):
    row("  ", r, 7)

print("\n=== Bradford D50 -> D65 ===")
M = bradford(D50, D65)
for r in M:
    row("  ", r, 10)
row("M_cat * D50 white", apply(M, D50))
row("(must equal D65)", D65)
print(f"L* of 18% neutral           {to_lab((D65[0]*0.18, 0.18, D65[2]*0.18))[0]:.10f}")

print("\n=== grey card correction ===")
card = (0.3100, 0.4500, 0.3900)        # linear camera RGB median of the card
gains = (card[1] / card[0], 1.0, card[1] / card[2])
sigma = 0.18 / card[1]
row("gains", gains, 12)
print(f"exposure scale sigma          {sigma:.12f}")
balanced = tuple(gains[i] * card[i] for i in range(3))
row("balanced card", balanced, 12)

print("\n=== robust ROI fixture ===")
# 400 lattice samples: a smooth cervical-to-incisal ramp plus 5% specular spikes
random.seed(42)
clean, dirty = [], []
for i in range(400):
    y = 0.42 + 0.00025 * i                       # linear Y ramp
    base = (y * 1.06, y, y * 0.74)               # a yellowish, tooth-like triple
    clean.append(base)
    if i % 20 == 0:                              # 20 of 400 = 5% specular
        dirty.append(tuple(c * 1.8 for c in base))
    elif i % 37 == 0:                            # a few shadow samples
        dirty.append(tuple(c * 0.45 for c in base))
    else:
        dirty.append(base)
print(f"samples {len(dirty)}  specular {sum(1 for i in range(400) if i % 20 == 0)}"
      f"  shadow {sum(1 for i in range(400) if i % 20 and i % 37 == 0)}")
row("clean mean XYZ", tuple(sum(s[i] for s in clean) / len(clean) for i in range(3)), 12)
print("first 3 dirty samples:", [tuple(round(c, 10) for c in s) for s in dirty[:3]])

print("\n=== sRGB matrix derived from primaries (exact white point) ===")
# IEC 61966-2-1 primaries. Deriving the matrix from these makes
# M * (1,1,1) == the white point EXACTLY, which the published 7-digit matrix
# does not (its rows sum to Y = 1.0000001).
PRIMARIES = {"r": (0.6400, 0.3300), "g": (0.3000, 0.6000), "b": (0.1500, 0.0600)}


def rgb_to_xyz_matrix(primaries, wp):
    cols = {}
    for key, (x, y) in primaries.items():
        cols[key] = (x / y, 1.0, (1.0 - x - y) / y)
    m = [[cols["r"][r], cols["g"][r], cols["b"][r]] for r in range(3)]
    s = apply(inv3(m), wp)
    return [[m[r][c] * s[c] for c in range(3)] for r in range(3)]


DERIVED = rgb_to_xyz_matrix(PRIMARIES, D65)
for r in DERIVED:
    row("  ", r, 10)
row("derived * (1,1,1)", apply(DERIVED, (1, 1, 1)), 15)
row("published * (1,1,1)", apply(SRGB_TO_XYZ, (1, 1, 1)), 15)
print("max |derived - published| = %.3e" % max(
    abs(DERIVED[r][c] - SRGB_TO_XYZ[r][c]) for r in range(3) for c in range(3)))
row("white -> Lab (derived)", to_lab(apply(DERIVED, (1, 1, 1))), 15)
for name, rgb in [("red", (1.0, 0, 0)), ("mid grey", (0.5, 0.5, 0.5)),
                  ("tooth-ish", (0.84, 0.80, 0.71))]:
    lin = tuple(srgb_decode(c) for c in rgb)
    lab = to_lab(apply(DERIVED, lin))
    row(f"{name} -> Lab (derived)", lab, 7)

print("\n=== CIEDE2000 ===")
spec = importlib.util.spec_from_file_location(
    "ref", pathlib.Path(__file__).with_name("stage2_reference.py"))
ref = importlib.util.module_from_spec(spec)
with contextlib.redirect_stdout(io.StringIO()):
    spec.loader.exec_module(ref)
print("published pair (Sharma 2005): %.10f" % ref.ciede2000(
    (50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485))[0])
print("\nregression pairs produced BY THIS ORACLE (not published reference data):")
pairs = [
    ("neutral lightness", (50.0, 0.0, 0.0), (55.0, 0.0, 0.0)),
    ("hue wrap near 0 deg", (60.0, 5.0, -2.0), (60.0, 5.0, 2.0)),
    ("chroma only", (70.0, 2.0, 18.0), (70.0, 2.0, 24.0)),
    ("tooth vs shade tab", (82.2986328, -0.2668886, 12.7115859), (80.5, 1.2, 15.0)),
    ("large hue step", (40.0, 30.0, -40.0), (40.0, -30.0, 40.0)),
]
for name, a, b in pairs:
    de, (l, c, h) = ref.ciede2000(a, b)
    print(f"  {name:<22} dE00={de:.10f}  l={l:+.10f} c={c:+.10f} h={h:+.10f}")
