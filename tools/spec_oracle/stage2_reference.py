"""Reference oracle for the Aşama 2 algorithm spec.

NOT shipped code and NOT part of the Flutter build. This file exists so that the
formulas written into docs/architecture/02-algorithms.md are executable, and so
that the Dart implementation in packages/shade_core can be cross-checked against
an independent transcription of the same spec.

Run:  python3 -I tools/spec_oracle/stage2_reference.py

Covered: CIEDE2000 (section 10), white-point preserving constrained least
squares (section 6.2), XYZ->Lab (section 7).
"""

import math
import random

# ---------- 1. CIEDE2000, exactly as section 10 of the doc ----------
POW25_7 = 6103515625

def ciede2000(lab1, lab2, kL=1.0, kC=1.0, kH=1.0):
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1s = math.hypot(a1, b1)
    C2s = math.hypot(a2, b2)
    Cbs = (C1s + C2s) / 2
    G = 0.5 * (1 - math.sqrt(Cbs**7 / (Cbs**7 + POW25_7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = 0.0 if (a1p == 0 and b1 == 0) else math.degrees(math.atan2(b1, a1p)) % 360
    h2p = 0.0 if (a2p == 0 and b2 == 0) else math.degrees(math.atan2(b2, a2p)) % 360
    dLp = L2 - L1
    dCp = C2p - C1p
    if C1p * C2p == 0:
        dhp = 0.0
    elif abs(h2p - h1p) <= 180:
        dhp = h2p - h1p
    elif h2p - h1p > 180:
        dhp = h2p - h1p - 360
    else:
        dhp = h2p - h1p + 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp) / 2)
    Lbp = (L1 + L2) / 2
    Cbp = (C1p + C2p) / 2
    if C1p * C2p == 0:
        hbp = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hbp = (h1p + h2p) / 2
    elif h1p + h2p < 360:
        hbp = (h1p + h2p + 360) / 2
    else:
        hbp = (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hbp - 30))
           + 0.24 * math.cos(math.radians(2 * hbp))
           + 0.32 * math.cos(math.radians(3 * hbp + 6))
           - 0.20 * math.cos(math.radians(4 * hbp - 63)))
    dTheta = 30 * math.exp(-(((hbp - 275) / 25) ** 2))
    RC = 2 * math.sqrt(Cbp**7 / (Cbp**7 + POW25_7))
    SL = 1 + 0.015 * (Lbp - 50) ** 2 / math.sqrt(20 + (Lbp - 50) ** 2)
    SC = 1 + 0.045 * Cbp
    SH = 1 + 0.015 * Cbp * T
    RT = -math.sin(math.radians(2 * dTheta)) * RC
    l, c, h = dLp / (kL * SL), dCp / (kC * SC), dHp / (kH * SH)
    return math.sqrt(l*l + c*c + h*h + RT * c * h), (l, c, h)

print("== CIEDE2000 ==")
# The one pair quoted in the brief (Sharma/Wu/Dalal 2005 test data).
de, comp = ciede2000((50.0000, 2.6772, -79.7751), (50.0000, 0.0000, -82.7485))
print(f"brief pair      -> {de:.4f}   expected 2.0425   {'OK' if abs(de-2.0425)<1e-4 else 'FAIL'}")
print(f"identical       -> {ciede2000((50,10,10),(50,10,10))[0]:.6f}  expected 0")
print(f"symmetry        -> {abs(ciede2000((60,5,-3),(61,-4,8))[0] - ciede2000((61,-4,8),(60,5,-3))[0]):.2e} (must be ~0)")
# hue wrap: 0/360 boundary must not blow up
a = ciede2000((50, 1.0, 0.001), (50, 1.0, -0.001))[0]
print(f"hue wrap at 0deg-> {a:.6f} (must be small, not NaN)")
# neutral pair: C1'C2' = 0 branch
print(f"both neutral    -> {ciede2000((50,0,0),(55,0,0))[0]:.6f} (pure lightness)")
# component sign convention: reference = candidate shade, sample = tooth
de2, (l, c, h) = ciede2000((70.0, 2.0, 18.0), (73.0, 2.0, 18.0))
print(f"tooth lighter   -> l={l:+.3f} (must be positive)")

# ---------- 2. White-point preserving constrained least squares, section 6.2 ----------
def mat_inv3(m):
    (a,b,c),(d,e,f),(g,h,i) = m
    det = a*(e*i-f*h) - b*(d*i-f*g) + c*(d*h-e*g)
    return [[(e*i-f*h)/det, (c*h-b*i)/det, (b*f-c*e)/det],
            [(f*g-d*i)/det, (a*i-c*g)/det, (c*d-a*f)/det],
            [(d*h-e*g)/det, (b*g-a*h)/det, (a*e-b*d)/det]]

def fit_row(X, y, w_r):
    n = len(X)
    G = [[sum(X[k][i]*X[k][j] for k in range(n)) for j in range(3)] for i in range(3)]
    Gi = mat_inv3(G)
    Xty = [sum(X[k][i]*y[k] for k in range(n)) for i in range(3)]
    a_u = [sum(Gi[i][j]*Xty[j] for j in range(3)) for i in range(3)]
    Gi1 = [sum(Gi[i][j] for j in range(3)) for i in range(3)]
    denom = sum(Gi1)
    corr = (w_r - sum(a_u)) / denom
    return [a_u[i] + Gi1[i]*corr for i in range(3)]

def sse(X, y, a):
    return sum((sum(X[k][i]*a[i] for i in range(3)) - y[k])**2 for k in range(len(X)))

print("\n== constrained least squares ==")
random.seed(7)
X = [[random.uniform(0.02, 1.0) for _ in range(3)] for _ in range(24)]
M_true = [[0.72, 0.21, 0.02], [0.28, 0.80, -0.08], [0.01, -0.12, 1.20]]
w = (0.95047, 1.0, 1.08883)
ok = True
for r in range(3):
    y = [sum(M_true[r][i]*X[k][i] for i in range(3)) + random.gauss(0, 0.004) for k in range(24)]
    a = fit_row(X, y, w[r])
    # (a) constraint satisfied exactly
    con = abs(sum(a) - w[r])
    # (b) optimal among constrained solutions: perturb inside the constraint plane
    base = sse(X, y, a)
    worse = True
    for _ in range(4000):
        d = [random.gauss(0, 1) for _ in range(3)]
        m = sum(d)/3
        d = [(di - m)*1e-3 for di in d]          # stays on 1'a = w_r
        if sse(X, y, [a[i]+d[i] for i in range(3)]) < base - 1e-15:
            worse = False
            break
    print(f"row {r}: constraint residual {con:.2e}  minimal-under-perturbation {worse}")
    ok &= con < 1e-12 and worse
# (c) the invariant that matters: M.(1,1,1) = white point
M = [fit_row(X, [sum(M_true[r][i]*X[k][i] for i in range(3)) for k in range(24)], w[r]) for r in range(3)]
neutral = [sum(M[r][i]*1.0 for i in range(3)) for r in range(3)]
print(f"M*(1,1,1) = ({neutral[0]:.6f}, {neutral[1]:.6f}, {neutral[2]:.6f})  target {w}")

# and the downstream invariant: a balanced neutral gives a*=b*=0 exactly
EPS, KAPPA = 216/24389, 24389/27
def f(t): return t ** (1/3) if t > EPS else (KAPPA*t + 16)/116
def to_lab(XYZ, wp=w):
    fx, fy, fz = f(XYZ[0]/wp[0]), f(XYZ[1]/wp[1]), f(XYZ[2]/wp[2])
    return (116*fy - 16, 500*(fx - fy), 200*(fy - fz))
L, A, B = to_lab(neutral)
print(f"neutral -> Lab = ({L:.6f}, {A:.2e}, {B:.2e})   a*,b* must be ~0")
print(f"18% card L* = {to_lab([w[0]*0.18, 0.18, w[2]*0.18])[0]:.2f}  expected 49.50")
print("\nALL CHECKS", "PASSED" if ok and abs(A) < 1e-9 and abs(B) < 1e-9 else "FAILED")
