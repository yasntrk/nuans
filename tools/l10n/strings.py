"""Single source of truth for every user-facing string.

WHY A GENERATOR

Two ARB files edited by hand drift: a key is added to one and forgotten in the
other, and the app then shows a raw key or falls back to the wrong language.
The CI check catches that after the fact. Defining both languages next to each
other and generating the files makes the drift impossible in the first place,
and it puts the Turkish and English wording side by side where a mismatch in
meaning - not just in keys - is visible while writing.

Each entry is `key: (tr, en, description, placeholders)`. Placeholders use the
ARB shape, so ICU select and plural work exactly as Flutter expects.

Run:  python3 -I tools/l10n/generate.py
"""

# A placeholder spec shorthand: name -> ARB placeholder object.
TEXT = {"type": "String"}
INT = {"type": "int"}
DECIMAL = {"type": "double", "format": "decimalPattern"}
DECIMAL_1 = {
    "type": "double",
    "format": "decimalPattern",
    "optionalParameters": {"minimumFractionDigits": 1, "maximumFractionDigits": 1},
}
DATE = {"type": "DateTime", "format": "yMMMd"}
DATETIME = {"type": "DateTime", "format": "yMMMd"}


def select(name, options):
    """An ICU select placeholder."""
    return {"type": "String"}


STRINGS = {
    # ---------------------------------------------------------------- app
    "appName": ("Nüans", "Nuans", "The application name. Never translated beyond these two forms.", None),
    "appTagline": (
        "Diş Renk Analizi",
        "Dental Shade Matching",
        "Shown under the app name on the launch and about screens.",
        None,
    ),
    "appLegalDisclaimer": (
        "Klinik karar destek aracıdır; nihai renk seçimi hekim/teknisyen sorumluluğundadır.",
        "A clinical decision support tool. The final shade choice remains the responsibility of the clinician or technician.",
        "Required disclaimer. Shown during onboarding, on the result screen and in every report.",
        None,
    ),

    # -------------------------------------------------------- common actions
    "actionContinue": ("Devam", "Continue", "Primary button.", None),
    "actionBack": ("Geri", "Back", "Secondary button.", None),
    "actionCancel": ("İptal", "Cancel", "Dismisses a dialog.", None),
    "actionRetake": ("Tekrar Çek", "Retake", "Discards the capture and returns to the camera.", None),
    "actionSave": ("Kaydet", "Save", "Persists the measurement.", None),
    "actionDelete": ("Sil", "Delete", "Destructive action.", None),
    "actionShare": ("Paylaş", "Share", "Opens the system share sheet.", None),
    "actionSendToLab": ("Laboratuvara Gönder", "Send to Laboratory", "Builds the report and opens the share sheet.", None),
    "actionStartCalibration": ("Kalibrasyonu Başlat", "Start Calibration", "Begins the device profile flow.", None),
    "actionNewMeasurement": ("Yeni Ölçüm", "New Measurement", "Starts the measurement flow.", None),

    # ------------------------------------------------------------ onboarding
    "onboardingWelcomeTitle": (
        "Telefonunuzu kolorimetre gibi kullanın",
        "Use your phone like a colorimeter",
        "Onboarding page 1 title.",
        None,
    ),
    "onboardingWelcomeBody": (
        "Nüans, dişin rengini standart skalalarla eşleştirir ve gerektiğinde karışım önerir. Doğru sonuç için kalibrasyon ve gri kart şarttır.",
        "Nuans matches a tooth against standard shade guides and suggests a mixture when one is needed. A calibration and a grey card are not optional for a correct result.",
        "Onboarding page 1 body.",
        None,
    ),
    "onboardingAccuracyTitle": (
        "Bir spektrofotometre değildir",
        "This is not a spectrophotometer",
        "Onboarding page 2 title. Deliberately blunt.",
        None,
    ),
    "onboardingAccuracyBody": (
        "Telefon kamerası üç kanalla ölçer, spektrum ölçmez. Metamerizmi göremez, translüsensiyi tahmin eder. Her ölçüm bir güven skoruyla gelir; skoru okumadan sonuca güvenmeyin.",
        "A phone camera measures three channels, not a spectrum. It cannot see metamerism and it estimates translucency. Every measurement carries a confidence score; do not trust a result without reading it.",
        "Onboarding page 2 body.",
        None,
    ),
    "onboardingLightingTitle": ("Işığınızı hazırlayın", "Prepare your light", "Onboarding page 3 title.", None),
    "onboardingLightingBody": (
        "CRI 95 ve üzeri, yaklaşık 5500K bir LED veya halka ışık kullanın. Pencere ışığı ve tavan lambası karışırsa ölçüm güvenilmez olur.",
        "Use an LED or ring light with CRI 95 or above at roughly 5500K. A measurement taken under mixed window and ceiling light is not reliable.",
        "Onboarding page 3 body.",
        None,
    ),
    "onboardingPrivacyTitle": ("Veriler cihazda kalır", "Your data stays on the device", "Onboarding page 4 title.", None),
    "onboardingPrivacyBody": (
        "Hasta görüntüleri şifreli olarak yalnızca bu cihazda saklanır. Bulut senkronu yoktur. Hasta adı değil hasta kodu kullanılır.",
        "Patient images are stored encrypted on this device only. There is no cloud sync. Records are keyed by a patient code, never by a name.",
        "Onboarding page 4 body.",
        None,
    ),

    # ------------------------------------------------------- device profile
    "deviceProfileTitle": ("Cihaz Profili", "Device Profile", "Screen title.", None),
    "deviceProfileIntro": (
        "Bu cihazın kamerasını bir kez kalibre edin. 24 yamalı renk referans kartını çerçeveye sığdırın ve çekin.",
        "Calibrate this device's camera once. Fit the 24-patch colour reference chart in the frame and capture.",
        "Explains the calibration step.",
        None,
    ),
    "deviceProfileMissing": (
        "Bu cihaz için profil yok",
        "No profile for this device",
        "Shown when no chart fit exists for the current device and lens.",
        None,
    ),
    "deviceProfileMissingBody": (
        "Profil olmadan ölçüm yapılabilir ama güven skoru düşük kalır: üretici matrisi tek bir numune cihazdan türetilmiştir, sizin cihazınızın sapmasını içermez.",
        "A measurement is possible without a profile, but the confidence score stays low: a manufacturer matrix comes from one sample device and does not include your unit's own deviation.",
        "Explains the fallback.",
        None,
    ),
    "deviceProfileQuality": (
        "Uyum kalitesi: ortalama ΔE00 {mean}, en kötü yama {max}",
        "Fit quality: mean ΔE00 {mean}, worst patch {max}",
        "Reports the chart fit residual.",
        {"mean": DECIMAL_1, "max": DECIMAL_1},
    ),
    "deviceProfileQualityExplained": (
        "Kamera duyarlılıkları gözlemci fonksiyonlarının doğrusal dönüşümü olmadığı için hiçbir 3x3 matris tam doğru olamaz. Bu sayı o temel sınırın bu cihazdaki büyüklüğüdür.",
        "No 3x3 matrix can be exact, because camera sensitivities are not a linear transform of the observer functions. This number is the size of that fundamental limit on this device.",
        "Explains what the residual means, so it is not read as a defect.",
        None,
    ),
    "deviceProfileGateFailed": (
        "Ortalama ΔE00 {mean}, kabul sınırı {limit} değerinin üzerinde. Işığı düzeltip tekrar çekin.",
        "Mean ΔE00 is {mean}, above the {limit} limit. Fix the lighting and capture again.",
        "Shown when the fit is too poor to use.",
        {"mean": DECIMAL_1, "limit": DECIMAL_1},
    ),
    "deviceProfileAcceptedOn": (
        "{date} tarihinde kalibre edildi",
        "Calibrated on {date}",
        "Shows when the active profile was created.",
        {"date": DATE},
    ),

    # ---------------------------------------------------- measurement setup
    "measurementSetupTitle": ("Yeni Ölçüm", "New Measurement", "Screen title.", None),
    "patientCodeLabel": ("Hasta kodu", "Patient code", "Form field label.", None),
    "patientCodeHint": (
        "Hasta adı yazmayın. Kendi kayıt sisteminizdeki kodu kullanın.",
        "Do not enter a patient name. Use the code from your own records.",
        "Form field helper text.",
        None,
    ),
    "patientCodeRequired": ("Hasta kodu zorunludur", "A patient code is required", "Validation error.", None),
    "toothNumberLabel": ("Diş numarası (FDI)", "Tooth number (FDI)", "Form field label.", None),
    "toothNumberInvalid": ("Geçerli bir FDI numarası girin", "Enter a valid FDI number", "Validation error.", None),
    "materialLabel": ("Malzeme", "Material", "Form field label.", None),
    "materialZirconia": ("Zirkonyum", "Zirconia", "Material option.", None),
    "materialMetalCeramic": ("Metal destekli porselen", "Metal-ceramic", "Material option.", None),
    "materialComposite": ("Kompozit", "Composite", "Material option.", None),
    "shadeSystemLabel": ("Renk skalası", "Shade guide", "Form field label.", None),
    "shadeSystemClassical": (
        "16 renkli klasik skala uyumlu",
        "16-shade classical guide compatible",
        "Shade system option. Brand names appear only in a compatibility statement.",
        None,
    ),
    "shadeSystemMaster": (
        "29 renkli üç boyutlu skala uyumlu",
        "29-shade three-dimensional guide compatible",
        "Shade system option.",
        None,
    ),
    "relativeModeLabel": ("Bağıl mod", "Relative mode", "Toggle label.", None),
    "relativeModeExplained": (
        "Fiziksel skala tabını dişin yanında aynı karede tutun. Önerilen klinik protokol budur: diş ile tab arasındaki fark hiçbir kütüphaneye güvenmeden ölçülür.",
        "Hold the physical shade tab next to the tooth in the same frame. This is the recommended clinical protocol: the difference between tooth and tab is then measured without relying on any library.",
        "Explains the relative protocol.",
        None,
    ),

    # ------------------------------------------------------------- camera
    "cameraTitle": ("Ölçüm", "Measurement", "Camera screen title.", None),
    "checkExposure": ("Pozlama", "Exposure", "Live check label.", None),
    "checkGrayCard": ("Gri kart", "Grey card", "Live check label.", None),
    "checkSharpness": ("Netlik", "Sharpness", "Live check label.", None),
    "checkMotion": ("Sabitlik", "Steadiness", "Live check label.", None),
    "checkMixedLight": ("Işık", "Lighting", "Live check label.", None),
    "checkTilt": ("Eğim", "Tilt", "Live check label.", None),
    "checkPending": ("Bekleniyor", "Waiting", "Live check state.", None),
    "checkExposureClipping": (
        "Parlak bölgeler kırpılıyor, ışığı azaltın",
        "Highlights are clipping, reduce the light",
        "Live check failure reason.",
        None,
    ),
    "checkExposureTooDark": ("Çok karanlık", "Too dark", "Live check failure reason.", None),
    "checkGrayCardNotFound": (
        "Gri kartı yuvaya yerleştirin",
        "Place the grey card in its slot",
        "Live check failure reason.",
        None,
    ),
    "checkGrayCardNonUniform": (
        "Kart yuvası düz değil: gölge veya kenar var",
        "The card slot is not flat: a shadow or an edge is in it",
        "Live check failure reason.",
        None,
    ),
    "checkMixedLightDetected": (
        "Karışık ışık: kart üzerinde renk farkı var",
        "Mixed lighting: the card's colour varies across it",
        "Live check failure reason.",
        None,
    ),
    "checkImplausibleLight": (
        "Işık rengi beklenen aralıkta değil (yaklaşık {kelvin} K)",
        "The light's colour is outside the expected range (about {kelvin} K)",
        "Live check failure reason.",
        {"kelvin": INT},
    ),
    "checkSharpnessLow": ("Odak net değil, dişe dokunun", "Not in focus, tap the tooth", "Live check failure reason.", None),
    "checkMotionHigh": ("Telefonu sabit tutun", "Hold the phone still", "Live check failure reason.", None),
    "checkTiltHigh": (
        "Yüzeye dik tutun (sapma {degrees}°)",
        "Hold it perpendicular to the surface (off by {degrees}°)",
        "Live check failure reason.",
        {"degrees": DECIMAL_1},
    ),
    "shutterBlocked": (
        "Tüm kontroller yeşil olmadan çekim yapılamaz",
        "Capture is disabled until every check is green",
        "Explains the disabled shutter.",
        None,
    ),
    "shutterReady": ("Çekime hazır", "Ready to capture", "Shutter enabled state.", None),
    # ------------------------------------------------------ live preview
    "liveCameraTitle": ("Canlı Önizleme", "Live Preview", "Live camera screen title.", None),
    "overlayWorkbenchTitle": (
        "Bindirme Tezgâhı",
        "Overlay Workbench",
        "Title of the screen that shows the overlay without a camera.",
        None,
    ),
    "overlayWorkbenchSubtitle": (
        "Kamerasız: yerleşimi ve trafik ışıklarını denemek için",
        "No camera: for trying the layout and the traffic lights",
        "Says plainly that this screen shows no camera image.",
        None,
    ),
    "liveCameraStarting": (
        "Kamera başlatılıyor…",
        "Starting the camera…",
        "Shown while the camera is being opened.",
        None,
    ),
    "liveCameraRetry": ("Tekrar dene", "Try again", "Retries opening the camera.", None),
    "liveCameraPermissionBody": (
        "Ayarlar ▸ Uygulamalar ▸ Nüans ▸ İzinler'den kamerayı açıp tekrar deneyin.",
        "Allow the camera in Settings ▸ Apps ▸ Nuans ▸ Permissions, then try again.",
        "Explains how to grant the camera permission.",
        None,
    ),
    "liveCameraUncalibrated": (
        "Bu cihazın profili yok. Önizleme ve hizalama çalışır; renge dayanan kontroller ve çekim kapalıdır.",
        "This device has no profile. The preview and the alignment work; the colour checks and capture are off.",
        "Explains what the live preview can and cannot do without a device profile.",
        None,
    ),
    "liveMetricsTitle": ("Canlı ölçümler", "Live measurements", "Section title.", None),
    "liveMetricNeedsProfile": (
        "profil gerekiyor",
        "needs a profile",
        "Shown instead of a value that cannot be computed without a device profile.",
        None,
    ),
    "liveMetricSharpness": ("Netlik (Laplace varyansı)", "Sharpness (Laplacian variance)", "Live metric label.", None),
    "liveMetricMotion": ("Hareket", "Motion", "Live metric label.", None),
    "liveMetricToothClipping": ("Dişte kırpılma", "Clipping on the tooth", "Live metric label.", None),
    "liveMetricCardUniformity": ("Kart düzgünlüğü", "Card uniformity", "Live metric label.", None),
    "liveMetricIso": ("ISO", "ISO", "Live metric label.", None),
    "liveMetricExposure": ("Pozlama", "Exposure", "Live metric label.", None),
    "liveMetricLocked": ("Kilitli", "Locked", "Live metric label for the lock state.", None),
    "liveMetricUnlocked": ("Otomatik", "Automatic", "Live metric label for the lock state.", None),
    "liveCameraNoFrames": (
        "Kamera açıldı ama kare gelmiyor.",
        "The camera opened but no frames are arriving.",
        "Shown when the preview starts but no metrics follow.",
        None,
    ),
    "clinicalTipHydration": (
        "Ölçümü seansın başında alın: dehidrasyon dişi olduğundan daha açık gösterir.",
        "Measure at the start of the appointment: dehydration makes a tooth read lighter than it is.",
        "Clinical hint on the camera screen.",
        None,
    ),
    "clinicalTipLipstick": (
        "Ruj, renkli örtü ve parlak giysiyi kadrajdan uzaklaştırın.",
        "Keep lipstick, coloured drapes and bright clothing out of the frame.",
        "Clinical hint on the camera screen.",
        None,
    ),
    "clinicalTipRetractor": (
        "Ekartör kullanın; dudak ve dil dişe renk yansıtır.",
        "Use a retractor; lips and tongue bounce colour onto the tooth.",
        "Clinical hint on the camera screen.",
        None,
    ),
    "capturingBurst": (
        "{captured} / {requested} kare",
        "{captured} of {requested} frames",
        "Burst progress.",
        {"captured": INT, "requested": INT},
    ),
    "capturePolarizerOn": ("Çapraz polarizasyon açık", "Cross polarisation on", "Mode badge.", None),

    # ------------------------------------------------------------ analysis
    "analysisTitle": ("Sonuç", "Result", "Screen title.", None),
    "regionCervical": ("Servikal", "Cervical", "Tooth region. Glossary term.", None),
    "regionBody": ("Gövde", "Body", "Tooth region. Glossary term.", None),
    "regionIncisal": ("İnsizal", "Incisal", "Tooth region. Glossary term.", None),
    "deltaEValue": ("ΔE00 {value}", "ΔE00 {value}", "Formats a colour difference. The locale decides the decimal separator.", {"value": DECIMAL_1}),
    "bandImperceptible": ("Fark edilemez", "Imperceptible", "Acceptability band.", None),
    "bandAcceptable": ("Klinik olarak kabul edilebilir", "Clinically acceptable", "Acceptability band.", None),
    "bandUnacceptable": ("Kabul edilemez", "Unacceptable", "Acceptability band.", None),
    "bandImperceptibleExplained": (
        "Fark 0,8 ΔE00 eşiğinin altında: gözlemcilerin yarısı bile ayırt edemez.",
        "The difference is below the 0.8 ΔE00 threshold: not even half of observers would tell them apart.",
        "Explains the green band.",
        None,
    ),
    "bandAcceptableExplained": (
        "Fark görülebilir ama klinik olarak kabul edilebilir sınırın içinde.",
        "The difference is visible but inside the clinically acceptable limit.",
        "Explains the amber band.",
        None,
    ),
    "bandUnacceptableExplained": (
        "Fark kabul sınırının üzerinde: karışım veya özel reçete gerekir.",
        "The difference is past the acceptable limit: a mixture or a custom recipe is needed.",
        "Explains the red band.",
        None,
    ),
    "bestMatchLabel": ("En yakın renk", "Closest shade", "Section heading.", None),
    "alternativesLabel": ("Diğer seçenekler", "Other options", "Section heading.", None),
    "shadeToothVsTab": (
        "Diş ile elinizdeki tab arasındaki ölçülen fark",
        "Measured difference between the tooth and the tab in your hand",
        "Label for the relative-mode result, which depends on no library.",
        None,
    ),

    # the three deviation phrases, one key per direction, magnitude by select
    "deviationLighter": (
        "{magnitude, select, slight{biraz daha açık} moderate{daha açık} pronounced{belirgin şekilde daha açık} other{daha açık}}",
        "{magnitude, select, slight{slightly lighter} moderate{lighter} pronounced{markedly lighter} other{lighter}}",
        "A lightness deviation phrase. Composed into a sentence by the comparison keys.",
        {"magnitude": TEXT},
    ),
    "deviationDarker": (
        "{magnitude, select, slight{biraz daha koyu} moderate{daha koyu} pronounced{belirgin şekilde daha koyu} other{daha koyu}}",
        "{magnitude, select, slight{slightly darker} moderate{darker} pronounced{markedly darker} other{darker}}",
        "A lightness deviation phrase.",
        {"magnitude": TEXT},
    ),
    "deviationMoreChromatic": (
        "{magnitude, select, slight{biraz daha doygun} moderate{daha doygun} pronounced{belirgin şekilde daha doygun} other{daha doygun}}",
        "{magnitude, select, slight{slightly more saturated} moderate{more saturated} pronounced{markedly more saturated} other{more saturated}}",
        "A chroma deviation phrase.",
        {"magnitude": TEXT},
    ),
    "deviationLessChromatic": (
        "{magnitude, select, slight{biraz daha az doygun} moderate{daha az doygun} pronounced{belirgin şekilde daha az doygun} other{daha az doygun}}",
        "{magnitude, select, slight{slightly less saturated} moderate{less saturated} pronounced{markedly less saturated} other{less saturated}}",
        "A chroma deviation phrase.",
        {"magnitude": TEXT},
    ),
    "deviationTowardRed": (
        "{magnitude, select, slight{biraz kırmızıya kaymış} moderate{kırmızıya kaymış} pronounced{belirgin şekilde kırmızıya kaymış} other{kırmızıya kaymış}}",
        "{magnitude, select, slight{shifted slightly towards red} moderate{shifted towards red} pronounced{shifted markedly towards red} other{shifted towards red}}",
        "A hue deviation phrase.",
        {"magnitude": TEXT},
    ),
    "deviationTowardYellow": (
        "{magnitude, select, slight{biraz sarıya kaymış} moderate{sarıya kaymış} pronounced{belirgin şekilde sarıya kaymış} other{sarıya kaymış}}",
        "{magnitude, select, slight{shifted slightly towards yellow} moderate{shifted towards yellow} pronounced{shifted markedly towards yellow} other{shifted towards yellow}}",
        "A hue deviation phrase.",
        {"magnitude": TEXT},
    ),
    "deviationTowardGreen": (
        "{magnitude, select, slight{biraz yeşile kaymış} moderate{yeşile kaymış} pronounced{belirgin şekilde yeşile kaymış} other{yeşile kaymış}}",
        "{magnitude, select, slight{shifted slightly towards green} moderate{shifted towards green} pronounced{shifted markedly towards green} other{shifted towards green}}",
        "A hue deviation phrase.",
        {"magnitude": TEXT},
    ),
    "deviationTowardBlue": (
        "{magnitude, select, slight{biraz maviye kaymış} moderate{maviye kaymış} pronounced{belirgin şekilde maviye kaymış} other{maviye kaymış}}",
        "{magnitude, select, slight{shifted slightly towards blue} moderate{shifted towards blue} pronounced{shifted markedly towards blue} other{shifted towards blue}}",
        "A hue deviation phrase.",
        {"magnitude": TEXT},
    ),

    # sentence frames: one per count, so nothing is ever concatenated in Dart
    "comparisonNone": (
        "Hedef diş {shade} renginden ayırt edilemiyor.",
        "The target tooth is indistinguishable from {shade}.",
        "Comparison sentence when no component is worth mentioning.",
        {"shade": TEXT},
    ),
    "comparisonOne": (
        "Hedef diş, {shade} renginden {first}.",
        "The target tooth is {first} than {shade}.",
        "Comparison sentence with one notable component.",
        {"shade": TEXT, "first": TEXT},
    ),
    "comparisonTwo": (
        "Hedef diş, {shade} renginden {first} ve {second}.",
        "The target tooth is {first} and {second} than {shade}.",
        "Comparison sentence with two notable components.",
        {"shade": TEXT, "first": TEXT, "second": TEXT},
    ),
    "comparisonThree": (
        "Hedef diş, {shade} renginden {first}, {second} ve {third}.",
        "The target tooth is {first}, {second} and {third} than {shade}.",
        "Comparison sentence with all three components notable.",
        {"shade": TEXT, "first": TEXT, "second": TEXT, "third": TEXT},
    ),

    # ---------------------------------------------------------- confidence
    "confidenceLabel": ("Güven skoru", "Confidence score", "Glossary term.", None),
    "confidenceHigh": ("Yüksek", "High", "Confidence band.", None),
    "confidenceMedium": ("Orta", "Medium", "Confidence band.", None),
    "confidenceLow": ("Düşük", "Low", "Confidence band.", None),
    "confidenceWeakestTerm": (
        "En zayıf halka: {term}",
        "Weakest link: {term}",
        "Points the user at what to improve.",
        {"term": TEXT},
    ),
    "termCaptureMode": ("Yakalama modu", "Capture mode", "Confidence term name.", None),
    "termDeviceProfile": ("Cihaz profili", "Device profile", "Confidence term name.", None),
    "termGrayCard": ("Gri kart", "Grey card", "Confidence term name.", None),
    "termRejectedFraction": ("Atılan piksel oranı", "Discarded pixel share", "Confidence term name.", None),
    "termRegionHomogeneity": ("Bölge homojenliği", "Region homogeneity", "Confidence term name.", None),
    "termRelativeMode": ("Bağıl mod", "Relative mode", "Confidence term name.", None),
    "termMatchResidual": ("Eşleşme artığı", "Match residual", "Confidence term name.", None),
    "overrideNoColorProfile": (
        "Renk profili yok: ölçüm izlenebilir değil",
        "No colour profile: the measurement is not traceable",
        "Hard override reason.",
        None,
    ),
    "overrideGrayCardInvalid": (
        "Gri kart doğrulanamadı: beyaz nokta ve mutlak parlaklık çapasız",
        "The grey card did not validate: nothing anchors the white point or the absolute lightness",
        "Hard override reason.",
        None,
    ),
    "overrideExcessiveRejection": (
        "Bölgenin yarısından fazlası atıldı",
        "More than half of the region was discarded",
        "Hard override reason.",
        None,
    ),
    "overrideTooFewSamples": (
        "Sağlam istatistik için yeterli örnek kalmadı",
        "Too few samples survived for the robust statistics",
        "Hard override reason.",
        None,
    ),
    "overrideNoAcceptedFrames": (
        "Hiçbir kare kabul edilmedi",
        "No frame of the burst was accepted",
        "Hard override reason.",
        None,
    ),
    "placeholderLibraryWarning": (
        "Bu kütüphanenin değerleri ölçüm değil, yapısal bir iskelettir. Kendi skalanızı ölçene kadar renk adları yalnızca yön göstericidir.",
        "This library's values are a structural scaffold, not measurements. Until you measure your own guide, the shade names are indicative only.",
        "Shown whenever a result rests on unverified library values.",
        None,
    ),
    "clinicalCoverage": (
        "Kütüphanenin {percent} kadarı bu klinikte ölçüldü",
        "{percent} of the library was measured in this clinic",
        "Reports how much of the guide has been calibrated.",
        {"percent": {"type": "double", "format": "percentPattern"}},
    ),

    # -------------------------------------------------------------- recipe
    "recipeTitle": ("Reçete", "Recipe", "Screen title.", None),
    "recipeDisclaimer": (
        "Başlangıç önerisidir, şahit numune veya test fırınlaması ile doğrulayın.",
        "A starting point. Confirm it with a shade sample or a trial firing.",
        "Mandatory note on every recipe.",
        None,
    ),
    "recipeMixingModelNote": (
        "Karışım oranları doğrusal bir yaklaşımla hesaplanır ve kütlece orandır. Gerçek porselen karışımı doğrusal değildir.",
        "Mixture proportions come from a linear approximation and are ratios by mass. Real ceramic mixing is not linear.",
        "Explains the model's limit next to the proportions.",
        None,
    ),
    "layerOpaque": ("Opak", "Opaque", "Ceramic layer. Glossary term.", None),
    "layerDentin": ("Dentin", "Dentin", "Ceramic layer. Glossary term.", None),
    "layerIncisal": ("İnsizal", "Incisal", "Ceramic layer. Glossary term.", None),
    "layerSingleShade": ("{shade}", "{shade}", "A layer made of one powder.", {"shade": TEXT}),
    "layerMixTwo": (
        "{firstShade} %{firstPercent} + {secondShade} %{secondPercent}",
        "{firstShade} {firstPercent}% + {secondShade} {secondPercent}%",
        "A two-powder mixture.",
        {"firstShade": TEXT, "firstPercent": INT, "secondShade": TEXT, "secondPercent": INT},
    ),
    "layerMixThree": (
        "{firstShade} %{firstPercent} + {secondShade} %{secondPercent} + {thirdShade} %{thirdPercent}",
        "{firstShade} {firstPercent}% + {secondShade} {secondPercent}% + {thirdShade} {thirdPercent}%",
        "A three-powder mixture.",
        {
            "firstShade": TEXT, "firstPercent": INT,
            "secondShade": TEXT, "secondPercent": INT,
            "thirdShade": TEXT, "thirdPercent": INT,
        },
    ),
    "mixImprovement": (
        "Karışım, en iyi tek renge göre ΔE00 {improvement} iyileştirme sağlıyor",
        "The mixture improves on the best single shade by ΔE00 {improvement}",
        "Shows the gain the mixture delivers, measured on the rounded proportions.",
        {"improvement": DECIMAL_1},
    ),
    "mixDeclinedGoodEnough": (
        "Tek renk yeterli: karışım önerilmiyor",
        "A single shade is enough; no mixture is suggested",
        "Explains why no mixture is shown.",
        None,
    ),
    "mixDeclinedNoGain": (
        "Hiçbir karışım kayda değer iyileştirme sağlamıyor",
        "No mixture delivers a worthwhile improvement",
        "Explains why no mixture is shown.",
        None,
    ),
    "mixDeclinedNoNeighbours": (
        "Yapısal komşu bulunmadığı için karışım üretilemiyor",
        "No structural neighbour is available, so no mixture can be formed",
        "Explains why no mixture is shown.",
        None,
    ),
    "zirconiaBlockLabel": ("Blok veya ön-renklendirilmiş renk", "Block or pre-shaded blank", "Zirconia recipe field.", None),
    "zirconiaStainLabel": ("Servikal boyama hedefi", "Cervical staining target", "Zirconia recipe field.", None),
    "compositeDentinLabel": ("Dentin", "Dentin", "Composite recipe field.", None),
    "compositeEnamelLabel": ("Emaye", "Enamel", "Composite recipe field. Glossary term.", None),
    "enamelMatchingShade": ("Dentinle aynı aileden emaye", "Enamel from the dentin's family", "Enamel kind.", None),
    "enamelUniversal": ("Genel amaçlı emaye", "Universal enamel", "Enamel kind.", None),
    "enamelTranslucent": ("Translüsent emaye", "Translucent enamel", "Enamel kind.", None),
    "enamelOpalescent": ("Opalesan emaye", "Opalescent enamel", "Enamel kind.", None),
    "enamelBleach": ("Yüksek parlaklıkta emaye", "High-value enamel", "Enamel kind.", None),
    "enamelBrandUnmapped": (
        "Marka eşlemesi boş: kendi ürün adınızı Ayarlar'dan tanımlayın",
        "No brand mapping: define your own product name in Settings",
        "Shown when the brand mapping table has no entry.",
        None,
    ),
    "translucencyEstimated": (
        "Translüsensi tahminidir: siyah/beyaz zemin ölçümü yapılmıyor.",
        "Translucency is an estimate: no black and white backing measurement is taken.",
        "Mandatory label next to any translucency statement.",
        None,
    ),
    "gradientCervicalMoreChromatic": (
        "Servikal üçlü gövdeden daha kromalı",
        "The cervical third is more chromatic than the body",
        "Gradient note.",
        None,
    ),
    "gradientIncisalLighter": (
        "İnsizal üçlü gövdeden daha açık",
        "The incisal third is lighter than the body",
        "Gradient note.",
        None,
    ),
    "gradientIncisalMoreTranslucent": (
        "İnsizal üçlü daha translüsent görünüyor (tahmini)",
        "The incisal third reads more translucent (estimated)",
        "Gradient note.",
        None,
    ),
    "gradientUniform": (
        "Bölgeler arasında kayda değer gradyan yok",
        "No gradient worth mentioning between the regions",
        "Gradient note.",
        None,
    ),

    # -------------------------------------------------------------- report
    "reportTitle": ("Rapor", "Report", "Screen title.", None),
    "reportLanguageLabel": ("Rapor dili", "Report language", "Lets the report language differ from the interface language.", None),
    "reportLanguageExplained": (
        "Arayüz dilinden bağımsız seçilebilir: yurt dışındaki bir laboratuvara İngilizce rapor gönderebilirsiniz.",
        "Chosen independently of the interface language, so a report for a laboratory abroad can go out in English.",
        "Explains the report language selector.",
        None,
    ),
    "reportHeaderMeasurement": ("Ölçüm", "Measurement", "PDF section heading.", None),
    "reportHeaderRegions": ("Bölgeler", "Regions", "PDF section heading.", None),
    "reportHeaderRecipe": ("Reçete", "Recipe", "PDF section heading.", None),
    "reportHeaderCalibration": ("Kalibrasyon", "Calibration", "PDF section heading.", None),
    "reportFieldPatientCode": ("Hasta kodu", "Patient code", "PDF field label.", None),
    "reportFieldTooth": ("Diş", "Tooth", "PDF field label.", None),
    "reportFieldMaterial": ("Malzeme", "Material", "PDF field label.", None),
    "reportFieldShadeSystem": ("Skala", "Guide", "PDF field label.", None),
    "reportFieldCapturedAt": ("Çekim zamanı", "Captured at", "PDF field label.", None),
    "reportFieldDevice": ("Cihaz", "Device", "PDF field label.", None),
    "reportFieldCaptureMode": ("Yakalama modu", "Capture mode", "PDF field label.", None),
    "reportCaptureModeRaw": ("Bayer RAW", "Bayer RAW", "Capture mode value. Not translated.", None),
    "reportCaptureModeProcessed": ("İşlenmiş (sınırlı mod)", "Processed (limited mode)", "Capture mode value.", None),
    "reportFieldLabValues": ("L* a* b* (D65, 2°)", "L* a* b* (D65, 2°)", "PDF column heading. Not translated.", None),
    "reportGeneratedBy": (
        "{appName} ile oluşturuldu · {date}",
        "Generated with {appName} · {date}",
        "PDF footer.",
        {"appName": TEXT, "date": DATETIME},
    ),
    "reportPageOf": ("{page} / {total}", "{page} of {total}", "PDF page number.", {"page": INT, "total": INT}),

    # ------------------------------------------------------------- history
    "historyTitle": ("Geçmiş", "History", "Screen title.", None),
    "historySearchHint": ("Hasta kodu ara", "Search patient code", "Search field hint.", None),
    "historyEmpty": ("Henüz ölçüm yok", "No measurements yet", "Empty state.", None),
    "historyCount": (
        "{count, plural, =0{Ölçüm yok} =1{1 ölçüm} other{{count} ölçüm}}",
        "{count, plural, =0{No measurements} =1{1 measurement} other{{count} measurements}}",
        "Measurement count.",
        {"count": INT},
    ),
    "feedbackTitle": ("Sonuç geri bildirimi", "Outcome feedback", "Section heading.", None),
    "feedbackPrompt": (
        "Nihai restorasyon uydu mu? Girdiğiniz sonuç, malzeme başına sapma öğrenmek için saklanır; bu sürümde otomatik düzeltme yapılmaz.",
        "Did the finished restoration match? What you enter is stored so that a per-material deviation can be learned; this version applies no automatic correction.",
        "Explains the feedback loop honestly.",
        None,
    ),
    "feedbackMatched": ("Uydu", "It matched", "Feedback option.", None),
    "feedbackDidNotMatch": ("Uymadı", "It did not match", "Feedback option.", None),
    "feedbackMeasuredDeltaE": ("Ölçülen ΔE00", "Measured ΔE00", "Feedback field.", None),

    # ------------------------------------------------------------ settings
    "settingsTitle": ("Ayarlar", "Settings", "Screen title.", None),
    "settingsLanguage": ("Dil", "Language", "Setting label.", None),
    "settingsLanguageSystem": ("Cihaz dili", "System language", "Language option.", None),
    "settingsLanguageTurkish": ("Türkçe", "Türkçe", "Language option. Shown in its own language.", None),
    "settingsLanguageEnglish": ("English", "English", "Language option. Shown in its own language.", None),
    "settingsThresholds": ("Klinik eşikler", "Clinical thresholds", "Setting group.", None),
    "settingsShadeLibraries": ("Skala kütüphaneleri", "Shade guides", "Setting group.", None),
    "settingsCalibrateLibrary": ("Kendi skalanı ölç", "Measure your own guide", "Opens the per-tab calibration flow.", None),
    "settingsBrandMapping": ("Marka eşlemesi", "Brand mapping", "Setting group.", None),
    "settingsExportData": ("Verileri dışa aktar", "Export data", "KVKK and GDPR right.", None),
    "settingsDeleteAllData": ("Tüm verileri sil", "Delete all data", "KVKK and GDPR right.", None),
    "settingsDeleteConfirm": (
        "Tüm ölçümler ve görüntüler kalıcı olarak silinecek. Bu işlem geri alınamaz.",
        "Every measurement and image will be permanently deleted. This cannot be undone.",
        "Destructive confirmation.",
        None,
    ),
    "settingsAbout": ("Hakkında", "About", "Setting group.", None),
    "settingsRegulatoryNote": (
        "Bu yazılımın tıbbi cihaz statüsü yayından önce ilgili mevzuata göre değerlendirilmelidir.",
        "This software's medical device status must be assessed against the applicable regulations before release.",
        "Regulatory note on the about screen.",
        None,
    ),

    # -------------------------------------------------------------- errors
    "errorPermissionDenied": (
        "Kamera izni verilmedi",
        "Camera access has not been granted",
        "Camera error. Mapped from a native error code.",
        None,
    ),
    "errorDeviceUnavailable": ("Kamera kullanılamıyor", "The camera is unavailable", "Camera error.", None),
    "errorConfigurationFailed": ("Kamera yapılandırılamadı", "The camera could not be configured", "Camera error.", None),
    "errorFocusLockFailed": ("Odak kilitlenemedi", "Focus could not be locked", "Camera error.", None),
    "errorExposureLockFailed": ("Pozlama kilitlenemedi", "Exposure could not be locked", "Camera error.", None),
    "errorWhiteBalanceLockFailed": (
        "Beyaz dengesi kilitlenemedi",
        "White balance could not be locked",
        "Camera error.",
        None,
    ),
    "errorRawUnavailable": (
        "Bu cihazda RAW yakalama yok: sınırlı modda ölçüm yapılacak",
        "This device has no RAW capture: the measurement will run in limited mode",
        "Camera error.",
        None,
    ),
    "errorCaptureFailed": ("Çekim başarısız", "The capture failed", "Camera error.", None),
    "errorRoiOutOfBounds": ("Bölge kadrajın dışında", "A region is outside the frame", "Camera error.", None),
    "errorUnknownCaptureId": ("Çekim artık bellekte değil", "That capture is no longer in memory", "Camera error.", None),
    "errorCaptureExpired": ("Çekim zaman aşımına uğradı", "The capture expired", "Camera error.", None),
    "errorPreviewNotRunning": ("Önizleme çalışmıyor", "The preview is not running", "Camera error.", None),
    "errorInterrupted": ("Kamera oturumu kesildi", "The camera session was interrupted", "Camera error.", None),
    "errorLimitedModeBadge": ("Sınırlı mod", "Limited mode", "Badge shown when the device cannot run the full protocol.", None),
    "limitationNoManualSensor": (
        "Manuel sensör kontrolü yok",
        "No manual sensor control",
        "Device limitation code.",
        None,
    ),
    "limitationNoRawSupport": ("RAW desteği yok", "No RAW support", "Device limitation code.", None),
    "limitationWhiteBalanceNotLockable": (
        "Beyaz dengesi kilitlenemiyor",
        "White balance cannot be locked",
        "Device limitation code.",
        None,
    ),
    "limitationFocusNotLockable": ("Odak kilitlenemiyor", "Focus cannot be locked", "Device limitation code.", None),
    "limitationLogicalMultiCamera": (
        "Mantıksal çoklu kamera: lens kendi kendine değişebilir",
        "Logical multi-camera: the lens can switch on its own",
        "Device limitation code.",
        None,
    ),
    "limitationExposureNotSolvable": (
        "Pozlama bu sahne için çözülemedi",
        "The exposure could not be solved for this scene",
        "Device limitation code.",
        None,
    ),

    # ------------------------------------------------------------ glossary
    "glossaryTitle": ("Terimler", "Glossary", "Screen title.", None),
    "glossaryHue": ("Ton", "Hue", "Glossary term.", None),
    "glossaryChroma": ("Kroma", "Chroma", "Glossary term.", None),
    "glossaryValue": ("Parlaklık", "Value", "Glossary term.", None),
    "glossaryTranslucency": ("Translüsensi", "Translucency", "Glossary term.", None),
    "glossaryShadeGuide": ("Renk skalası", "Shade guide", "Glossary term.", None),
    "glossaryTestFiring": ("Test fırınlaması", "Test firing", "Glossary term.", None),
}
