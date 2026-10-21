# CONTEXT

The vocabulary this repository uses, and the few words it deliberately refuses.
Maintained inline: a term enters this file when a decision turned on it.

## Clinical terms, both languages

The pair is fixed. Neither side drifts, and no screen uses a synonym.

| Türkçe | English | What it means here |
|---|---|---|
| Servikal | Cervical | The third of the tooth nearest the gingival margin. In this app a fixed third of the overlay silhouette, not an anatomical boundary. |
| Gövde | Body | The middle third. The region a single-shade match is normally read from. |
| İnsizal | Incisal | The third nearest the incisal edge. Lightest and most translucent. |
| Dentin | Dentin | The layer carrying the chroma, under the enamel. |
| Emaye | Enamel | The outer layer, carrying the translucency. |
| Opak | Opaque | The ceramic layer that masks a metal substructure. |
| Translüsensi | Translucency | How much light passes through rather than returning. **Estimated, never measured** in this version. |
| Ton | Hue | Which colour, as an angle on the hue circle. |
| Kroma | Chroma | How saturated. |
| Parlaklık | Value | How light. `L*` in CIELAB. |
| Renk skalası | Shade guide | The physical set of tabs a tooth is matched against. |
| Test fırınlaması | Test firing | Firing a sample to confirm a recipe before making the restoration. |
| Güven skoru | Confidence score | How far a measurement can be trusted, as High, Medium or Low. |

Not translated, ever: shade codes (`A1`, `2M2`), FDI tooth numbers (`11`, `21`),
brand names, and the symbols `L*`, `a*`, `b*`, `C*`, `ΔE00`.

## Terms with a precise meaning in this repository

**Superpixel** — one 2x2 Bayer block reduced to `R`, `mean(G1, G2)`, `B`. Not a
demosaiced pixel: three channels genuinely measured at the same place, at half
the spatial resolution.

**Capture transform** — the single matrix `exposureScale · ccm · diag(gains)`
that converts camera space to tristimulus values for one capture. One per
capture, shared by every region of it. That sharing is the only reason the three
regions and the shade tab in the same frame are comparable.

**Structural neighbour** — two shades adjacent in the guide's own layout, which
is the only pair a mixture may be formed from. Not a distance in Lab: the linear
mixing model holds while components are close and stops holding when they are
not, so the guide's structure is what keeps the model inside its validity.

**Structural scaffold** — the shade values that ship. Ordered so the guide's own
ordering holds, inside the range teeth occupy, and **not measured**. Replaced by
the clinic's own per-tab measurements. Marked `unverifiedPlaceholder` in data and
flagged on every screen that rests on one.

**Relative mode** — holding a physical shade tab in the same frame as the tooth.
Produces two things: a global correction for the capture, and a tooth-to-tab
difference that depends on no library, no profile and no matrix.

**Limited mode** — a device without manual sensor control, lockable white
balance or RAW output. The measurement still runs, with a low-confidence badge,
because a repeatable relative reading is worth more to a technician than no
reading.

**Hard override** — a condition that pins the confidence to Low whatever the
weighted score says. Exists because a weighted sum lets good terms mask a fatal
one.

## Words this repository does not use

**"Accurate"** of a measurement, unqualified. A phone camera has three channels
and no spectrum. Say what was measured, under which illuminant, with which
confidence.

**"Detected"** of the grey card. Nothing is detected: a slot is *validated*
against uniformity, signal range, quadrant colour spread and a plausible colour
temperature. The word mattered because the original specification's "a\* and b\*
are about zero after correction" check turned out to validate a blue lens cap
just as happily.

**"Calibrated"** of a library whose values ship with the app. Those are a
scaffold. A library is calibrated when the clinic has measured its own guide.

**"Measured"** of translucency. It is inferred from a blue shift, and every
statement derived from it is labelled as an estimate.
