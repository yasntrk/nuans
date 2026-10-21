"""Generates the shade library JSON files that ship with the app.

WHY THIS SCRIPT EXISTS, AND WHAT IT IS NOT

The values it writes are NOT measurements and NOT quoted from any published
table. They are a structural scaffold: a monotonic grid laid out so that the
ordering of each guide holds - lighter shades really are lighter, a higher
chroma step really is more chromatic, the hue columns really do sit in the
right order - inside the lightness and chroma range natural teeth occupy.

Shipping a scaffold rather than nothing lets the matching, mixing, recipe and
report paths run from first launch, and lets a clinician see the shape of a
result before calibrating anything. Shipping it rather than recalled numbers is
the point: a recalled L*a*b* table would look authoritative and be wrong, and
nobody downstream could tell. Every entry is tagged
`unverifiedPlaceholder`, the library reports its clinical coverage, and the
confidence score is held down while any placeholder is in play.

The fix is not a better guess. It is the per-tab clinical calibration flow:
the clinic measures its own physical guide once and those measurements replace
these values, which is also the only way to account for the guide's own age,
batch and wear.

Run:  python3 -I tools/shade_libraries/generate.py
"""

import json
import math
import pathlib
import sys

EPS, KAPPA = 216 / 24389, 24389 / 27
D65 = (0.95047, 1.0, 1.08883)


def lch_to_lab(lightness, chroma, hue_degrees):
    radians = math.radians(hue_degrees)
    return (
        round(lightness, 2),
        round(chroma * math.cos(radians), 2),
        round(chroma * math.sin(radians), 2),
    )


# --- the scaffold model ----------------------------------------------------
#
# One line per hue family: the lightness and chroma of its first step, and how
# much each further step moves. Teeth sit roughly between L* 60 and 85 with a
# chroma of 10 to 35 and a hue angle in the yellow-red quadrant, so the grid is
# laid out inside that window.

CLASSICAL_FAMILIES = {
    # family: (codes, hue angle, first lightness, first chroma, dL, dC)
    "A": (["A1", "A2", "A3", "A3.5", "A4"], 76.0, 78.0, 14.0, -3.0, 5.0),
    "B": (["B1", "B2", "B3", "B4"], 83.0, 79.0, 12.0, -2.8, 4.5),
    "C": (["C1", "C2", "C3", "C4"], 74.0, 73.0, 11.0, -3.2, 3.5),
    "D": (["D2", "D3", "D4"], 72.0, 74.0, 12.0, -3.0, 3.8),
}

# Value group 0 is the lightest; each group steps down in lightness. Chroma
# steps are the codes the guide prints. The three hue columns are ordered
# yellower (L), middle (M), redder (R).
MASTER_LIGHTNESS_AT_GROUP_ZERO = 84.0
MASTER_LIGHTNESS_PER_GROUP = -4.2
MASTER_CHROMA_AT_STEP_ONE = 8.0
MASTER_CHROMA_PER_STEP = 6.5
MASTER_HUE = {"L": 88.0, "M": 80.0, "R": 72.0}

MASTER_CODES = [
    "0M1", "0M2", "0M3",
    "1M1", "1M2",
    "2L1.5", "2L2.5", "2M1", "2M2", "2M3", "2R1.5", "2R2.5",
    "3L1.5", "3L2.5", "3M1", "3M2", "3M3", "3R1.5", "3R2.5",
    "4L1.5", "4L2.5", "4M1", "4M2", "4M3", "4R1.5", "4R2.5",
    "5M1", "5M2", "5M3",
]


def classical_entries():
    entries = []
    for family, (codes, hue, l0, c0, dl, dc) in CLASSICAL_FAMILIES.items():
        for step, code in enumerate(codes):
            lightness = l0 + dl * step
            chroma = c0 + dc * step
            entries.append((code, lch_to_lab(lightness, chroma, hue)))
    return entries


def master_entries():
    entries = []
    for code in MASTER_CODES:
        group = int(code[0])
        hue_letter = code[1]
        chroma_step = float(code[2:])
        lightness = MASTER_LIGHTNESS_AT_GROUP_ZERO + MASTER_LIGHTNESS_PER_GROUP * group
        chroma = MASTER_CHROMA_AT_STEP_ONE + MASTER_CHROMA_PER_STEP * (chroma_step - 1)
        entries.append((code, lch_to_lab(lightness, chroma, MASTER_HUE[hue_letter])))
    return entries


def library(identifier, system, name_tr, name_en, compatibility, entries):
    return {
        "schemaVersion": 1,
        "id": identifier,
        "system": system,
        "name": {"tr": name_tr, "en": name_en},
        "compatibility": compatibility,
        "whitePoint": "D65_2deg",
        "provenance": {
            "kind": "structuralScaffold",
            "generatedBy": "tools/shade_libraries/generate.py",
            "tr": (
                "Bu değerler ÖLÇÜM DEĞİLDİR ve hiçbir yayımlanmış tablodan "
                "alınmamıştır. Skalanın kendi sıralamasını koruyan yapısal bir "
                "iskelettir. Klinik, kendi fiziksel skalasını bir kez ölçerek "
                "bu değerleri değiştirmelidir."
            ),
            "en": (
                "These values are NOT measurements and are not taken from any "
                "published table. They are a structural scaffold that preserves "
                "the guide's own ordering. A clinic must replace them by "
                "measuring its own physical guide once."
            ),
        },
        "entries": [
            {
                "code": code,
                "lab": {"l": lab[0], "a": lab[1], "b": lab[2]},
                "source": "unverifiedPlaceholder",
                "measuredAtUtc": None,
            }
            for code, lab in entries
        ],
    }


def ciede2000(lab1, lab2):
    L1, a1, b1 = lab1
    L2, a2, b2 = lab2
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = 0.0 if (a1p == 0 and b1 == 0) else math.degrees(math.atan2(b1, a1p)) % 360
    h2p = 0.0 if (a2p == 0 and b2 == 0) else math.degrees(math.atan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    if C1p * C2p == 0:
        dhp = 0.0
    elif abs(h2p - h1p) <= 180:
        dhp = h2p - h1p
    elif h2p - h1p > 180:
        dhp = h2p - h1p - 360
    else:
        dhp = h2p - h1p + 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp) / 2)
    Lb, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
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
    RC = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    SL = 1 + 0.015 * (Lb - 50) ** 2 / math.sqrt(20 + (Lb - 50) ** 2)
    SC, SH = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
    RT = -math.sin(math.radians(2 * dTheta)) * RC
    l, c, h = dLp / SL, dCp / SC, dHp / SH
    return math.sqrt(l * l + c * c + h * h + RT * c * h)


def report(name, entries):
    labs = [lab for _, lab in entries]
    pairs = [
        (ciede2000(labs[i], labs[j]), entries[i][0], entries[j][0])
        for i in range(len(labs)) for j in range(i + 1, len(labs))
    ]
    pairs.sort()
    lightness = [lab[0] for lab in labs]
    chroma = [math.hypot(lab[1], lab[2]) for lab in labs]
    print(f"\n{name}: {len(entries)} entries")
    print(f"  L* range   {min(lightness):.1f} .. {max(lightness):.1f}")
    print(f"  C* range   {min(chroma):.1f} .. {max(chroma):.1f}")
    print(f"  closest pair  dE00 {pairs[0][0]:.3f}  ({pairs[0][1]} / {pairs[0][2]})")
    print(f"  median pair   dE00 {pairs[len(pairs)//2][0]:.3f}")
    if pairs[0][0] < 0.8:
        print("  WARNING: two shades are closer than the perceptibility "
              "threshold, so a match between them would be arbitrary")
    return pairs[0][0]


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    out = root / "assets" / "shade_libraries"
    out.mkdir(parents=True, exist_ok=True)

    classical = classical_entries()
    master = master_entries()

    files = {
        "vita_classical_compatible.json": library(
            "vita_classical_compatible",
            "classicalCompatible",
            "16 renkli klasik skala uyumlu",
            "16-shade classical guide compatible",
            "VITA classical compatible",
            classical,
        ),
        "vita_3d_master_compatible.json": library(
            "vita_3d_master_compatible",
            "threeDimensionalMasterCompatible",
            "29 renkli üç boyutlu skala uyumlu",
            "29-shade three-dimensional guide compatible",
            "VITA 3D-MASTER compatible",
            master,
        ),
    }
    for filename, payload in files.items():
        (out / filename).write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
        )
        print(f"wrote assets/shade_libraries/{filename}")

    smallest = min(report("classical", classical), report("3d-master", master))
    print(f"\nsmallest separation across both guides: dE00 {smallest:.3f}")
    return 0 if smallest >= 0.8 else 1


if __name__ == "__main__":
    sys.exit(main())
