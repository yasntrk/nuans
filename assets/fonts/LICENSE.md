# Fonts

`NotoSans-Regular.ttf`, `NotoSans-Medium.ttf`, `NotoSans-Bold.ttf`

Noto Sans, from the Noto project, licensed under the SIL Open Font License 1.1.
Source: https://github.com/notofonts/notofonts.github.io (hinted static TTFs).

Embedded in the generated PDF reports because the `pdf` package's built-in
standard fonts have no glyphs for ç, ğ, ı, İ, ö, ş or ü, so a Turkish report
built on them loses characters exactly where the clinical terms are. Verified
coverage: all Turkish letters in both cases, plus Δ for the ΔE00 label.

The full OFL text ships with the upstream release and must be included in the
application's licence notices before any store submission.
