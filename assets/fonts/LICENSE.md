# Fonts

`NotoSans-Regular.ttf`, `NotoSans-Medium.ttf`, `NotoSans-Bold.ttf`

Noto Sans, from the Noto project, copyright The Noto Project Authors, licensed
under the SIL Open Font License, Version 1.1. The full licence text is in
`OFL.txt` beside these files, as the licence requires of anyone redistributing
the font binaries.

Source: https://github.com/notofonts/notofonts.github.io (hinted static TTFs).

Embedded in the generated PDF reports because the `pdf` package's built-in
fonts cannot render ç, ğ, ı, İ, ö, ş or ü, and a clinical report that silently
drops a letter from a patient's name is not a report.
