"""Checks the store copy for claims the product cannot support.

A phone camera is not a spectrophotometer, and the honest position on that is
stated in the specification, in the onboarding and on the result screen. Store
copy is where it is most tempting to quietly drop: the listing is marketing, it
is written last, and nobody downstream reads it against the architecture.

So the constraint is enforced mechanically. This script fails the build if the
listing starts claiming accuracy the measurement does not have, or stops saying
what it cannot do.

Run:  python3 -I tools/store/check_copy.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
METADATA = ROOT / "fastlane" / "metadata"

# Phrases that would overclaim. Checked in both languages everywhere, because a
# Turkish listing with an English superlative in it is just as wrong.
OVERCLAIMS = [
    "lab-accurate",
    "laboratory accurate",
    "spectrophotometer-grade",
    "as accurate as a spectrophotometer",
    "spektrofotometre kadar",
    "guaranteed",
    "garanti",
    "100% accurate",
    "perfect match",
    "kusursuz",
    "tam doğru",
    "certified",
    "sertifikalı",
    "medical device",
    "tıbbi cihaz",
    "clinically proven",
    "klinik olarak kanıtlanmış",
]

# The limit has to be stated in the long description of every locale.
REQUIRED_LIMITS = {
    "tr": "spektrofotometre değildir",
    "tr-TR": "spektrofotometre değildir",
    "en-US": "not a spectrophotometer",
}

# The responsibility disclaimer, likewise.
REQUIRED_DISCLAIMERS = {
    "tr": "hekim/teknisyen sorumluluğundadır",
    "tr-TR": "hekim/teknisyen sorumluluğundadır",
    "en-US": "responsibility of the clinician",
}

# Marketing copy only. The reviewer notes are a different kind of document: they
# say "it does not diagnose", which is the disclaimer rather than a claim.
SKIP_DIRECTORIES = {"review_information"}


def long_description(locale_dir):
    for name in ("description.txt", "full_description.txt"):
        candidate = locale_dir / name
        if candidate.exists():
            return candidate
    return None


def main():
    problems = []
    checked = 0

    for path in sorted(METADATA.rglob("*.txt")):
        if SKIP_DIRECTORIES & set(path.parts):
            continue
        text = path.read_text()
        lowered = text.lower()
        checked += 1
        for phrase in OVERCLAIMS:
            if phrase in lowered:
                # "does not diagnose" and similar negations are disclaimers.
                window = lowered[max(0, lowered.index(phrase) - 40):
                                 lowered.index(phrase) + len(phrase)]
                if re.search(r"\b(not|no|never|değil|yoktur|hiçbir)\b", window):
                    continue
                problems.append(f'{path.relative_to(ROOT)}: claims "{phrase}"')

    for store in ("ios", "android"):
        base = METADATA / store
        if not base.exists():
            problems.append(f"missing metadata for {store}")
            continue
        locales = [d for d in base.iterdir()
                   if d.is_dir() and d.name not in SKIP_DIRECTORIES]
        if len(locales) < 2:
            problems.append(
                f"{store}: the listing must exist in both Turkish and English, "
                f"found {[d.name for d in locales]}"
            )
        for locale_dir in locales:
            description = long_description(locale_dir)
            if description is None:
                problems.append(f"{locale_dir.relative_to(ROOT)}: no description")
                continue
            body = description.read_text().lower()
            limit = REQUIRED_LIMITS.get(locale_dir.name)
            if limit and limit not in body:
                problems.append(
                    f"{description.relative_to(ROOT)}: does not state that the "
                    f'camera is not a spectrophotometer (looked for "{limit}")'
                )
            disclaimer = REQUIRED_DISCLAIMERS.get(locale_dir.name)
            if disclaimer and disclaimer not in body:
                problems.append(
                    f"{description.relative_to(ROOT)}: missing the "
                    f"responsibility disclaimer"
                )

    print(f"checked {checked} metadata files")
    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print("  -", problem)
        return 1
    print("store copy states its limits and claims nothing it cannot support")
    return 0


if __name__ == "__main__":
    sys.exit(main())
