/// Every named constant of the colour pipeline, with its provenance.
///
/// The specification (`docs/architecture/02-algorithms.md`, section 15)
/// requires that no bare number appears in the core logic. Values are tagged:
///
/// * **standard** - taken from a published standard or paper.
/// * **protocol** - fixed by the capture protocol of this project.
/// * **decision** - chosen here, with the reasoning given in the doc comment.
/// * **placeholder** - needs field measurement before it can be trusted.
library;

// ---------------------------------------------------------------------------
// Colorimetry - standard
// ---------------------------------------------------------------------------

/// CIE 15:2004 lightness breakpoint, `216 / 24389`.
///
/// Kept as an exact rational rather than a rounded decimal; rounding introduces
/// a small discontinuity in `L*` right at the breakpoint.
const double kLabEpsilon = 216 / 24389;

/// CIE 15:2004 linear-segment slope, `24389 / 27`.
const double kLabKappa = 24389 / 27;

/// sRGB transfer function parameters (IEC 61966-2-1).
const double kSrgbDecodeBreakpoint = 0.04045;
const double kSrgbEncodeBreakpoint = 0.0031308;
const double kSrgbLinearSlope = 12.92;
const double kSrgbOffset = 0.055;
const double kSrgbExponent = 2.4;

/// `25^7`, precomputed for CIEDE2000's chroma rolloff terms.
const double kCiede2000Pow25To7 = 6103515625;

/// Determinant magnitude below which a 3x3 matrix is treated as singular.
///
/// **decision** - well below any physically meaningful colour matrix, far above
/// the rounding noise of a double.
const double kMinInvertibleDeterminant = 1e-12;

// ---------------------------------------------------------------------------
// Capture protocol
// ---------------------------------------------------------------------------

/// Fraction of the white level above which a Bayer block counts as clipped.
///
/// **protocol**. Tested on the four raw samples *before* the greens are
/// averaged, otherwise a single clipped green sample is hidden by the average.
const double kBayerClippingThreshold = 0.95;

/// Frames per burst. **protocol**
const int kBurstFrameCount = 3;

/// Sample budget per region of interest. **decision** - see ADR-0001: the
/// sampling error of the trimmed mean at this count is about 0.03 L*, an order
/// and a half below the 0.8 decision threshold.
const int kMaxSamplesPerRoi = 4096;

/// Sample budget per reference chart patch. **decision** - same reasoning,
/// smaller patches.
const int kMaxSamplesPerChartPatch = 512;

/// Share of the white level the grey card is exposed to.
///
/// **decision** - the card reflects about 18%, so placing it at 0.45 leaves the
/// tooth (reflecting 60-70%, plus surface glare) roughly 1.3 stops of headroom
/// before clipping.
const double kExposureTargetGrayLuma = 0.45;

/// Acceptable window for the measured grey card signal. **decision**
const double kExposureGrayLumaMin = 0.20;
const double kExposureGrayLumaMax = 0.70;

/// A frame is accepted only if its sharpness reaches this share of the sharpest
/// frame in the same burst.
///
/// **decision** - an absolute sharpness floor is device dependent; a relative
/// gate is not, and the absolute floor still catches a burst that is blurry
/// end to end.
const double kFrameRelativeSharpnessFactor = 0.60;

// ---------------------------------------------------------------------------
// Grey card
// ---------------------------------------------------------------------------

/// Luminance factor of the neutral card, relative to a perfect diffuser.
///
/// **placeholder** - real "18% grey" cards measure between 0.17 and 0.19 and
/// are not spectrally flat. Read the actual value from the card's data sheet
/// and store it with the device profile.
const double kGrayCardReflectanceY = 0.18;

/// Maximum spatial standard deviation over mean inside the card slot.
/// **placeholder**
const double kGrayCardUniformityMax = 0.06;

/// Maximum pairwise CIEDE2000 between the card's four quadrants before the
/// scene counts as mixed lighting. **placeholder**
const double kGrayCardQuadrantDeltaEMax = 1.5;

/// Maximum share of clipped superpixels tolerated inside the card slot.
/// **decision**
const double kGrayCardMaxClippedFraction = 0.01;

/// Plausible correlated colour temperature range for the recommended light.
///
/// **decision** - the protocol asks for roughly 5500 K; far outside this window
/// the grey card correction is extrapolating away from the profile's D65 basis.
const double kIlluminantCctMin = 4000;
const double kIlluminantCctMax = 7000;

/// McCamy (1992) polynomial coefficients for correlated colour temperature.
/// **standard**
const double kMcCamyC3 = 437;
const double kMcCamyC2 = 3601;
const double kMcCamyC1 = 6861;
const double kMcCamyC0 = 5517;

/// Chromaticity pivot of the McCamy approximation. **standard**
const double kMcCamyPivotX = 0.3320;
const double kMcCamyPivotY = 0.1858;

/// Range over which the McCamy approximation is considered valid. **standard**
const double kMcCamyValidMinKelvin = 2856;
const double kMcCamyValidMaxKelvin = 6504;

// ---------------------------------------------------------------------------
// Device profile
// ---------------------------------------------------------------------------

/// Mean CIEDE2000 over the reference chart above which the user is sent back to
/// re-shoot the profile. **protocol**
const double kCcmMeanDeltaEGate = 2;

/// Minimum number of chart patches a fit accepts. **decision** - three would be
/// algebraically enough per row, which would fit noise rather than the sensor.
const int kMinChartPatches = 12;

/// Minimum number of neutral patches needed to derive channel gains.
/// **decision**
const int kMinNeutralPatches = 2;

/// Tolerance for the "matrix maps a neutral onto the white point" invariant.
/// **decision** - two orders above double rounding for a 3x3 fit.
const double kWhitePointPreservationTolerance = 1e-9;

// ---------------------------------------------------------------------------
// Robust region statistics
// ---------------------------------------------------------------------------

/// Upper rejection factor on the unscaled median absolute deviation.
///
/// **protocol**. Unscaled: for a normal distribution `MAD = 0.6745 sigma`, so
/// this is 1.686 sigma and discards about 4.6% of a clean region on its own.
const double kSpecularMadFactor = 2.5;

/// Lower rejection factor on the unscaled median absolute deviation.
///
/// **protocol**. 2.02 sigma, about 2.2% of a clean region. Together with the
/// upper factor the baseline rejection of a perfectly homogeneous region is
/// about 6.7%, which the confidence score must treat as normal rather than
/// alarming.
const double kShadowMadFactor = 3;

/// Trimmed mean bounds, as fractions of the surviving samples. **protocol**
const double kTrimLowFraction = 0.10;
const double kTrimHighFraction = 0.90;

/// Below this many surviving samples a region is rejected outright.
///
/// **decision** - the reason is representativeness, not standard error: the
/// median and MAD themselves become unstable, and if most of a region was
/// rejected then what is left is no longer the tooth.
const int kMinAcceptedSamples = 64;

/// Below this many surviving samples the measurement still stands but the
/// confidence score is lowered. **decision**
const int kLowConfidenceSampleCount = 256;

/// Rejected share above which a region is rejected outright. **decision**
const double kMaxRejectedFraction = 0.50;

// ---------------------------------------------------------------------------
// Relative mode
// ---------------------------------------------------------------------------

/// Per-channel clamp on the relative mode cone-space correction.
///
/// **decision** - plus or minus 10%, so a bad shade tab reading cannot wreck
/// the tooth measurement.
const double kRelativeModeGainMin = 0.90;
const double kRelativeModeGainMax = 1.111;

/// CIEDE2000 between the measured and library value of the shade tab above
/// which no correction is applied at all.
///
/// **decision** - a discrepancy this large on a known tab means the capture,
/// the library or the light is wrong; correcting by it would transfer that
/// error onto the tooth.
const double kRelativeModeTabDeltaEMax = 3;

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// 50:50 perceptibility threshold. **standard** - ISO/TR 28642, Paravina
/// et al. (2015).
const double kImperceptibleDeltaE = 0.8;

/// 50:50 acceptability threshold. **standard** - same source.
const double kAcceptableDeltaE = 1.8;

/// Number of candidates reported per region. **protocol**
const int kDefaultMatchCount = 3;

/// Library size above which brute force search would need revisiting.
/// **protocol** - the libraries that ship have 16 and 29 entries.
const int kMaxLibraryEntries = 50;

/// Magnitude bands for describing a single weighted deviation component.
///
/// **decision** - expressed in CIEDE2000 units, because the weighted components
/// are already divided by their S terms. That puts the 0.8 perceptibility
/// threshold inside the "slight" band, where it belongs.
const double kComponentSlightThreshold = 0.5;
const double kComponentModerateThreshold = 1;
const double kComponentPronouncedThreshold = 2;

// ---------------------------------------------------------------------------
// Mixing - consumed by the recipe engine
// ---------------------------------------------------------------------------

/// Grid step of the mixture search. **protocol** - 21 combinations for two
/// components, 231 per triple for three.
const double kMixGridStep = 0.05;

/// Step the published recipe is rounded to. **protocol**
const double kMixRoundingStep = 0.10;

/// Maximum number of components in a mixture. **protocol**
const int kMaxMixComponents = 3;

/// Minimum CIEDE2000 improvement the *rounded* mixture must deliver over the
/// best single shade before a mixture is offered at all. **protocol**
const double kMixImprovementMin = 0.3;

// ---------------------------------------------------------------------------
// Recipes
// ---------------------------------------------------------------------------

/// How much the dentin layer's target leans on the body rather than the
/// cervical measurement.
///
/// **decision** - a metal-ceramic dentin layer spans both thirds, so its target
/// is a blend of the two rather than either one. The body gets the larger share
/// because it is the larger area and the one a shade is normally read from.
const double kDentinBodyWeight = 0.60;

/// Extra weight the chroma term carries when a composite dentin is chosen.
///
/// **decision** - a dentin that is a step off in lightness disappears under the
/// enamel, while one that is a step off in chroma shows straight through it. So
/// the selection is not a plain nearest-neighbour search.
const double kCompositeDentinChromaWeight = 2;

/// Weighted chroma difference between cervical and body above which the
/// gradient is worth telling the technician about. **placeholder**
const double kGradientChromaThreshold = 1.5;

/// Weighted lightness difference between incisal and body above which the
/// gradient is worth mentioning. **placeholder**
const double kGradientLightnessThreshold = 2;

/// `b*(incisal) - b*(body)` below which the incisal third reads translucent.
///
/// **placeholder** - negative because translucency with nothing behind the edge
/// shifts the colour towards blue. The magnitude needs field data; it is a
/// heuristic standing in for a measurement this version does not make.
const double kTranslucencyBlueShiftThreshold = -1.5;
