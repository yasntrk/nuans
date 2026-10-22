# Doğrulama günlüğü

Aşama 1–7 ve CI/CD, makinede Flutter SDK olmadan yazıldı; doğrulama statikti.
Bu belge araç zinciri kurulduktan sonra **gerçekten çalıştırıldığında** ne bulunduğunu
kaydeder. Amacı övünmek değil: statik doğrulamanın neyi yakalayıp neyi kaçırdığını
ölçmek.

Tarih: 2026-10-22 · Flutter 3.47.7 · Dart 3.13.5 · JDK 17.0.19 · AGP 9.1.0

---

## 1. Sonuç

| Kontrol | Sonuç |
|---|---|
| `dart analyze --fatal-infos` (shade_core) | **No issues found** |
| `flutter analyze --fatal-infos` (uygulama) | **No issues found** |
| `dart test` (shade_core) | **296/296 geçti**, satır kapsaması %93.0 |
| `flutter test` (uygulama) | **89/89 geçti** (33 mantık + 56 golden) |
| `flutter build apk --release` | üretildi |
| `dart run pigeon` | üretti; üç platform bağlayıcısı |
| `flutter gen-l10n` | üretti; çevrilmemiş mesaj: 0 |

İlk koşuşta 2 derleme hatası, 4 uyarı ve 4 test başarısızlığı çıktı. Hepsi aşağıda.

---

## 2. Statik doğrulamanın kaçırdıkları

Yani: yazdığım kontrollerin göremediği, yalnızca derleyici ve test koşucusunun
yakaladığı şeyler.

### 2.1 Gerçek kod hataları (4)

**`@visibleForTesting` iki yardımcıya yanlış konmuştu.** `XyzColor.labTransfer` ve
`inverseLabTransfer` yalnızca testten değil, `lab_color.dart` ve `roi_reducer.dart`
içinden de çağrılıyor. Analizör dört uyarı verdi. Anotasyon yanlıştı; kaldırıldı ve
üç çağrı yerinin neden var olduğu belgeye yazıldı. Statik tarayıcım anotasyon
semantiğini bilmiyor.

**`brandMapping`'teki `_comment` anahtarı emaye türü sanılıyordu.** JSON'daki
dokümantasyon anahtarının değeri `{tr, en}` nesnesi olduğu için `mappedBrands`
`{'tr', 'en'}` döndürüyordu — yani "marka eşlemesi boş" testi kırmızı. Düzeltme:
`brandMapping` anahtarları `EnamelKind` değerlerine karşı doğrulanıyor, `_` ile
başlayanlar atlanıyor, tanınmayan anahtar `FormatException`. Bu aynı zamanda bir
kliniğin kendi tablosundaki yazım hatasını da yakalar.

**PDF raporu profil kalitesinde ortalamayı iki kez gösteriyordu.**
`deviceProfileQuality(mean, max)` çağrısına `profileMeanDeltaE` iki kez geçiyordu, yani
"en kötü yama" kolonu ortalamayı basıyordu. `ReportData`'ya `profileMaxDeltaE` eklendi.
Bu satır 80 kolonu aştığı için lint sayesinde gözüme ilişti — uzun satır kuralının
beklenmedik faydası.

**Reçete kartının başlık satırı Türkçe'de taşıyordu.** İki dilli golden testler
yazılıp koşturulduğunda üç varyant kırmızı oldu ve hepsi aynı desendeydi:
`recipe_metalCeramic_tr_*`. İngilizce "Metal-ceramic" 360 piksel genişlikte sığıyor,
Türkçe "Metal destekli porselen" sığmıyor — varsayılan yazı tipi ölçeğinde **20 piksel**,
1.3 ölçeğinde **117 piksel** taşıma. Başlıktaki malzeme etiketi sarılamayan düz bir
`Text`'ti; `Flexible` + `TextAlign.end` ile sarılabilir yapıldı.

Bu, Aşama 6 ve 7 belgelerinde iki dilli golden testlerin *var olma sebebi* olarak
yazdığım hatanın birebir kendisi: "İngilizce'de sığan bir rozet Türkçe'de kesilir ve bunu
yalnızca iki dilde render eden bir test yakalar." Gerekçeyi yazmak hatayı önlemedi; testi
koşturmak önledi.

### 2.2 Yanlış test beklentileri (3)

**Gri kart kazancı 11. hanede sapıyordu.** Beklenen değeri Python fikstür üreticisinin
*yuvarlanmamış* ara değerinden almışım; test ise 10 ondalığa yuvarlanmış literal
besliyor. Doğrusu literalden hesaplanmalı: `0.8939984596048943`. Kod doğruydu.

**"Temiz ölçüm 1.0 skorlar" varsayımı yanlıştı.** Fikstürün `L*` yayılımı 1.85, yani
homojenlik teriminin 1.5 eşiğinin üstünde — skor 0.9922. Kod doğru, beklenti yanlış:
gerçek bir dişte gerçek bir gradyan vardır, tam 1.0 skorlayan bir fikstür dişi değil
başka bir şeyi temsil ediyor olurdu. İki test bu yüzden kırmızıydı.

### 2.3 Derleme hataları (2)

`[1.0, 2, 3, 4, 5]` Dart'ta `List<num>` çıkarıyor, `List<double>` beklenen parametreye
atanamıyor. Ayraç dengesi kontrolü tip çıkarımı yapmaz.

---

## 3. Araç zincirinin kendi gerçekleri

Bunlar hata değil, bilgi eksikliğiydi: kodu yazarken bilemediğim gerçek sürüm ve API
davranışları.

| Bulduğum | Varsaydığım | Gerçek |
|---|---|---|
| Flutter kararlı sürümü | 3.24.5 / Dart 3.5.4 | **3.47.7 / Dart 3.13.5** — CI pin'leri hizalandı |
| `intl` kısıtı | `^0.19.0` | `flutter_localizations` `^0.20.3` istiyor |
| Pigeon import kuralı | `dart:typed_data` import edilebilir | **Yalnızca `package:pigeon/pigeon.dart`**; `Float64List` pigeon'un kendi export'undan gelir |
| ICU kaçışı | ARB'de kesme işareti düz yazılır | `use-escaping: true` ile `'` kaçış karakteri; her kesme işareti `''` olmalı. Üreticiye konuldu, kaynak tablo okunabilir kaldı |
| `RadioListTile` | `groupValue` + `onChanged` | v3.32'den beri deprecated; `RadioGroup` ataya taşındı |
| vga import kuralı | `prefer_relative_imports` | **`always_use_package_imports`** — lib/ içindeki 71 göreli import çevrildi |

### Pigeon varsayımlarının tamamı tuttu

ADR ve varsayım listesinde yazdığım dört şey, üretilen koda bakılarak doğrulandı:

| Varsayım (D13, D14) | Üretilen |
|---|---|
| Swift hata tipi `PigeonError` | `final class PigeonError: Error` ✓ |
| Swift enum camelCase | `enum CaptureTier: Int { case full = 0 ...}` ✓ |
| Swift `Float64List` → `FlutterStandardTypedData` | ✓ |
| Kotlin hata sınıfı `FlutterError(code, message, details)` | ✓ |
| Kotlin enum UPPER_SNAKE | `enum class CaptureTier(val raw: Int) { FULL(0) ... }` ✓ |
| Kotlin `Float64List` → `DoubleArray` | ✓ |
| Swift host protokolü + `...Setup.setUp` | `protocol ShadeCameraHostApi` + `class ShadeCameraHostApiSetup` ✓ |

Yazdığım `typealias ShadeCameraBridgeError = PigeonError` tek satırlık sürüm bağı olarak
doğru yerde durdu.

---

## 4. Alınan kararlar

**`public_member_api_docs` kapatıldı.** Kural yayımlanan bir paketin dartdoc'u *onun
arayüzü olduğu* için vardır; buradaki iki paket `publish_to: none` ve tek tüketicisi var.
Pratikte istediği şey `final String patchId;` üstüne `/// The patch id.` yazmaktı — 708
tanesi, argüman taşıyan yorumları gömerdi. Gerekçe `analysis_options.yaml` içinde yazılı.
Projenin tuttuğu standart yerinde: her tip, adından anlaşılmayan her enum değeri ve
davranışı şaşırtıcı her üye *neden*ini anlatan bir yorum taşır.

**11 bağımlılık park edildi.** Hiçbiri `lib/` içinde import edilmiyordu; her biri native
kod getiriyor, yani özellik getirmeyen derleme riski. Hangi aşamada geri geleceği
`pubspec.yaml` içinde yazılı. Bu arada bir bulgu: **`sqlcipher_flutter_libs` 0.6 hattı
discontinued, 0.7 `+eol` olarak yayımlanmış** — şifreleme katmanı üzerine inşa edilmeden
önce karar gerektiriyor.

**`very_good_analysis` 6.0.0'da bırakıldı** (11.0.0 mevcut). Mevcut kural setiyle iki
paket temiz; 11'e geçiş ayrı bir iş kalemi ve kendi lint selini getirir.

**`XyzColor.weightedMean` statik metottan factory constructor'a çevrildi.** Lint haklıydı
ve çağrı sözdizimi aynı kaldı.

---

## 5. Ölçmeden koyduğum bir CI kapısı tutmuyordu

CI'daki `shade_core` için **%90 satır kapsama tabanı** bir iddiaydı; ilk kez ölçüldüğünde
**%88.4** çıktı, yani kapı kendi derlemesini kırardı.

Cevap eşiği düşürmek değildi. En büyük boşluk gerçek bir test eksiğiydi:
`model/tooth_region.dart` **%0** — `FdiToothNumber`'ın doğrulama mantığı hiç test
edilmemiş, oysa gerçek kenar durumları var (süt dişi çeyreklerinde beşinci pozisyondan
sonrası yok, kalıcı çeyreklerde dokuzuncu yok, sıfır çeyrek, sıfır pozisyon). Raporun
yanlış dişi adlandırması, hiç adlandırmamasından kötüdür.

Yazılan testler: FDI numaralandırma, beyaz nokta kromatikliği, `CameraRgb` kanal
uçları, değer tiplerinin eşitlik ve yazdırma yolları. **268 → 296 test, %88.4 → %93.0.**
Kapı artık tutuyor ve `dart analyze --fatal-infos` temiz.

Bir yan not: dört yerde `use_named_constants` lint'ini gerekçeli `ignore` ile kapattım.
Testin kastı yapıcıyla kurulan değeri adlandırılmış sabitle karşılaştırmak — lint ikisini
aynı yapmamı isterse test totolojiye dönüşür.

## 6. Yol üstünde çıkan iki araç ayarı

**Gradle sarmalayıcısı `-all` yerine `-bin` dağıtımına çevrildi.** `flutter create`
`gradle-9.3.1-all.zip` yazıyor; o paket Gradle'ın kaynak kodunu ve dokümantasyonunu da
taşır, derleme hiçbirini okumaz. Soğuk önbellekte ilk Kotlin satırı derlenmeden önce
çeyrek gigabayt indiriyordu (gözlenen hız ~42 KB/s). `-bin` zaten önbellekteydi.
Gerekçe `gradle-wrapper.properties` içinde yazılı ki kimse geri "yükseltmesin".

**`flutter create` bir boilerplate test bıraktı.** `test/widget_test.dart` var olmayan
bir `MyApp` sınıfına atıfta bulunuyordu ve analizi kırıyordu; silindi.

## 7. Android APK

`flutter build apk --release` → **55 MB**, exit 0. İlk derleme 1493 s sürdü ve bunun
büyük kısmı NDK r28c indirmesiydi; ikinci derleme çok daha hızlı olur.

Üretilen APK üzerinde doğrulananlar (`aapt2 dump badging`, `apksigner`, `unzip -l`):

| Kontrol | Sonuç |
|---|---|
| Paket | `com.nuans.app`, versionName 0.1.0, versionCode 1 |
| SDK | minSdk 29, targetSdk 36 |
| İzin | `android.permission.CAMERA` |
| Yetenekler | `manual_sensor` ve `raw` → **not-required** (sınırlı mod kurulabilsin) |
| Uygulama adı | `Nuans`, **`application-label-tr: 'Nüans'`** — iki dilli ad çalışıyor |
| İmza | `CN=Android Debug` — telefona kurulur, Play'e yüklenemez |
| ABI | arm64-v8a 16.2 MB + armeabi-v7a 13.8 MB + x86_64 17.6 MB |
| Varlıklar | üç Noto Sans, iki skala kütüphanesi, kural tablosu, referans kartı |
| Native kod | `com/nuans/app/camera/*` sınıflarının tamamı dex içinde derlenmiş |

Yani Kotlin kamera katmanı **gerçekten derleniyor** — Aşama 4'ün doğrulanmamış tek büyük
parçası buydu. Hâlâ bir cihazda çalıştırılmadı.

İki küçük not:

- **55 MB'ın 47.6'sı native kütüphaneler** ve üç ABI'nin hepsi tek dosyada.
  `--split-per-abi` ile arm64 sürümü ~25 MB olur; evrensel APK her telefonda
  çalıştığı için bu derleme öyle bırakıldı.
- Derleme `cupertino_icons` font ailesini bulamadığına dair uyarı verdi. Uygulama
  hiçbir Cupertino ikonu kullanmıyor (uyarı `GlobalCupertinoLocalizations`
  üzerinden geliyor), bu yüzden etkisi yok; bağımlılığı eklemek uyarıyı susturur.

## 8. iOS tarafı: derleyici yerine sözleşme kontrolü

Xcode projesi olmadığı için Swift derlenemiyor. Pigeon artık gerçek bağlayıcıları ürettiği
için elle yazılmış Swift'i onlara karşı denetleyen bir araç yazıldı
(`tools/native/check_swift_against_pigeon.py`, CI'da koşuyor): 11 host metodu imzası, 15
struct alanı ve 9 enum case'i karşılaştırılıyor. Sonuç: **tam eşleşme**.

Bu bir derleyici değil — tip çözümlemesi yapmıyor, nokta kısayollu enum'ları veya
AVFoundation'ı bilmiyor. Yakaladığı şey, elle yazılmış bir platform
implementasyonunun gerçekten yaptığı hata: sözleşme kaydı, implementasyon kalmadı.

Yazarken bu kontrolün kendisi iki kez yanlış alarm verdi (Pigeon struct'ları Swift'in
örtük memberwise init'ini kullanıyor, benim regex `init(` arıyordu; ve protokol uyumu
plugin'de, controller'ın kendi içsel imzasında değil). İkisi de düzeltildi — bir
kontrolün kendi yanlış pozitifini "bulgu" diye raporlamak, hiç kontrol etmemekten kötüdür.

## 9. Push etmek iki CI kusuru ortaya çıkardı

Depoyu GitHub'a gönderdikten sonra, yazdığım iş akışının iki yerde kendi derlemesini
kıracağı görüldü. İkisi de koşmasını beklemeden, sadece ne yaptığına bakarak bulundu.

**`ios-build` var olmayan bir projeyi derlemeye çalışıyordu.** `flutter build ios` ve
`xcodebuild test -scheme Runner` çağırıyor, ama depoda `ios/Runner.xcodeproj` ve
`Podfile` yok — Swift kodu yazıldı, onu derleyen Xcode projesi hiç oluşturulmadı. İş
artık projenin varlığını kontrol ediyor: yoksa bir `::notice::` bırakıp geçiyor ve proje
eklendiği anda derlemeye başlıyor. Yoklukta Swift'i kapsayan şey, aynı iş akışındaki
sözleşme uyum kontrolü.

**Golden görüntüler Ubuntu'da karşılaştırılacaktı.** 56 referans görüntü bu makinede,
macOS'ta üretildi; `app` işi `ubuntu-latest` üzerinde koşuyordu. Flutter golden'ları
platforma bağlıdır — metin rasterizasyonu ve kenar yumuşatma farklı olduğu için aynı
widget Linux'ta farklı bir görüntü verir ve her karşılaştırma, kodla hiç ilgisi olmayan
bir sebepten kırmızıya düşerdi.

Golden testler artık `@Tags(['golden'])` ile etiketli: Linux işi onları hariç tutuyor
(33 test), macOS'ta kendi işinde koşuyorlar (56 test). macOS koşucusunu hak ettiren şey
görüntü karşılaştırması değil, harness'ın diğer iddiası: hiçbir `RenderFlex`'in taşmadığı
— iki dilde, iki yazı tipi ölçeğinde. Bu testlerin var olma sebebi o ve reçete kartının
taşması öyle bulundu.

## 10. Hâlâ doğrulanmayanlar

- **Swift kodu derlenmedi.** Xcode projesi yok; iOS tarafı yalnızca üretilmiş Pigeon
  bağlayıcılarına karşı okundu, derleyiciden geçmedi.
- **Golden testler koşuyor** (56 varyant: 7 bileşen × 2 dil × 2 yazı tipi ölçeği × 2
  cihaz genişliği) ve referans görüntüler `test/golden/images/` altında. Harness
  uygulamanın gerçek Noto Sans fontlarını yüklüyor — yer tutucu fontla yakalanan
  görüntü, bu testlerin var olma sebebi olan taşmayı gösteremez. Henüz golden'ı
  olmayan ekranlar: kamera overlay'i, geçmiş, ayarlar.
- **Native birim testleri yok.** Bayer indirgeme ve pozlama çözücü sentetik tamponlarla
  test edilebilir ama o testler yazılmadı. Kotlin tarafı artık derleniyor, yani bu
  testler yazılır yazılmaz koşabilir.
- **Gerçek cihazda ölçüm yapılmadı.** Kamera yolu derlenir ama bir telefonda
  çalıştırılmadı; saha doğrulaması (Aşama 7 §2) hiç başlamadı.

---

## Üçüncü tur: APK telefona kuruldu (2026-10-22)

Önceki iki tur "araç zincirini kurup koşturmak" turlarıydı. Bu tur farklı: kod
bir telefona kuruldu ve **kullanıcı denedi**. İki hata bildirdi ve ikisi de
gerçekti.

### Bildirilen 1: "herhangi bi menüye tıkladığım zaman geri ana menüye dönemiyorum"

Sebep: her navigasyon çağrısı `context.go()` kullanıyordu. `go`, üst düzey bir
rota için navigasyon yığınını **değiştirir**; geriye gidilecek sayfa kalmaz,
sistem geri tuşu boş yığın bulur ve uygulamayı kapatır.

Düzeltme: beşi `home_screen.dart`'ta, biri `onboarding_screen.dart`'ta olmak
üzere hepsi `push`/`pop` oldu; kural `app_router.dart`'ın doküman yorumuna
yazıldı.

Nöbetçi: `test/navigation/back_navigation_test.dart`. Kritik iddia
`Navigator.canPop` — `go` ile `false`, `push` ile `true`. Yalnızca "ekran
açıldı mı" diye bakan bir test hatanın tamamı boyunca geçerdi. Test ayrıca
gerçek sistem geri tuşunu kullanıyor (`flutter/navigation` kanalına `popRoute`),
AppBar okunu değil, çünkü kullanıcı ona basmıştı.

Doğrulandı: düzeltme geri alınıp test koşturuldu — 7 testin 6'sı "nothing to go
back to" diyerek düştü; düzeltmeyle hepsi geçti.

### Bu düzeltmeyi yaparken kendi soktuğum regresyon

`push()` değişimini kabuk heredoc'u ile yaparken `'/result/${material.name}'`
içindeki dolar kaçtı ve `'/result/\${material.name}'` oldu — Dart'ta geçerli bir
kaçış, yani derleniyor, ama rota literal `${material.name}` metni oluyor ve üç
analiz kartı da çöküyordu. HEAD'deki hali doğruydu, kıran bendim. `git show
HEAD:dosya` ile karşılaştırınca görüldü. Dersi: tırnaksız heredoc'a Dart
dizgesi yazılmaz; ve her metin değişiminin uygulandığı iddia edilmeden önce
doğrulanmalı (bu turda iki değişim sessizce uygulanmamıştı, çünkü aradığım metni
`dart format` araya girip değiştirmişti).

### Bildirilen 2: "kameraya bağlanmıyor görüntü gelmedi"

Burada **üç** ayrı hata vardı; hepsinin kökü kamera katmanının her şeyi tek bir
thread'de yapmasıydı. Ayrıntısı
[ADR-0002](adr/0002-android-camera-threading.md)'de; özeti:

1. **Kilitlenme.** `openCamera` ve `configureSession`, geri çağrıyı teslim
   etmesi gereken thread üzerinde `latch.await()` ile bekliyordu. Kamera asla
   açılmadı. Bu, kullanıcının gördüğü belirtinin doğrudan sebebi.
2. **Her turda eski kare.** Pozlama çözücüsü `Thread.sleep(150)` sonrası son
   kareyi okuyordu; kareyi yazan dinleyici aynı thread'deydi, dolayısıyla yeni
   kare o okuma sırasında henüz işlenmemişti.
3. **Olaylar istisna fırlatırdı.** Dart'a gönderilen her olay arka plan
   thread'indendi; `FlutterJNI.dispatchPlatformMessage` ilk iş olarak
   `ensureRunningOnMainThread()` çağırıyor.

(3) iddiası ezberden söylenmedi. Makinede `javap` yok, Flutter gömülü jar'ında
kaynak yok; bu yüzden sınıf dosyasını ayrıştıran küçük bir Python okuyucu
yazıldı ve `dispatchPlatformMessage`'ın çağrı listesi okundu. İlk çağrı
`ensureRunningOnMainThread`. Aynı okuma `invokePlatformMessageResponseCallback`
için yapıldı: orada böyle bir çağrı yok, bir `ReentrantReadWriteLock` okuma
kilidi var — bu yüzden host çağrılarının **cevapları** ana thread'e aktarılmıyor,
yalnızca olaylar aktarılıyor. Ayrımı ölçmek, hepsini aktarmaktan iyiydi.

### Kullanıcının asıl şikâyetinin kalan yarısı

Kilitlenme düzeltildikten sonra bile Flutter tarafı kamerayı **hiç**
başlatmıyordu: ana menüdeki "Ölçüm" girişi, doküman yorumunda "without a camera
behind it" yazan bir maket ekrana gidiyordu. Yani kullanıcı kamera sanıp açtı ve
hiçbir şey görmedi — haklıydı.

Eklenen: gerçek bir canlı önizleme ekranı, bir izin akışı ve sözleşmede eksik
olan iki şey.

- `ShadeCameraPlugin` artık `ActivityAware`; `initialize()` gerekirse izin
  diyaloğunu açıyor. İzin hiç istenmiyordu.
- `PreviewSession` sözleşmeye eklendi: doku kimliği, kare boyutu, dönüş.
  Boyut gerekliydi çünkü önizleme 16:9 seçilebilirken sensör 4:3 olabiliyor;
  dönüş gerekliydi çünkü kamera kareyi sensör yöneliminde yazıyor. İkisi de
  bindirmenin, native'in ölçtüğü bölgenin üstüne düşüp düşmediğini belirliyor.
- `PreviewGeometry`, ekran ve kare koordinatları arasındaki dönüşümü saf
  aritmetik olarak taşıyor ve **cihazsız test edilebiliyor**: yedi test, dört
  dönüş için tersinirlik ve birim kare içinde kalma dahil.

Bu sırada kendi doküman yorumumun uygulanmamış olduğu test tarafından yakalandı:
"ilk yapılandırma, önizleme biçimini bildirir bildirmez değiştirilir" yazmıştım
ama değiştiren kodu yazmamıştım. ROI'ler ekran koordinatlarında kalıyordu, yani
native yanlış bölgeyi ölçerdi. Test `host.configs`'un iki eleman olmasını ve
ikincisinin birincisinin devriği olmasını istiyor.

### Sayılar

| | Önce | Sonra |
|---|---|---|
| Uygulama testleri | 89 | 111 |
| shade_core testleri | 296 | 296 |
| `flutter analyze --fatal-infos` | temiz | temiz |
| `dart analyze --fatal-infos` (shade_core) | temiz | temiz |
| Pigeon↔Kotlin, Pigeon↔Swift denetleyicileri | geçiyor | geçiyor |
| Release APK | 55 MB | 55 MB |

### Hâlâ doğrulanmadı

`adb devices` boş: bu makinede bağlı Android cihaz yok. Dolayısıyla **kamera
kodunun hiçbir satırı bir cihazda koşmadı.** Kilitlenmenin sebebi kesin ve
düzeltmesi derleniyor; ama "telefonda görüntü geliyor" iddiası yapılamaz.
Cihazda sınanması gerekenler:

- önizlemenin dönüşü (sensör yönelimi kullanılıyor; çoğu telefonda 90 derece,
  hepsinde değil)
- iOS'un bildirdiği sabit 90 derece (varsayım I10) — iOS ayrıca hiç
  derlenmedi, Xcode projesi yok
- izin diyaloğunun akışı ve reddedildiğinde dönen hata
- kare akışının gerçekten başlaması; ekranın "Kamera açıldı ama kare gelmiyor."
  mesajı tam bu durumu ayırt etmek için var
- `lockCaptureParameters`'ın iki kare beklemesinin gerçek bir pozlama çözümünde
  yakınsaması
