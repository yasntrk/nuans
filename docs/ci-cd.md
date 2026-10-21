# CI/CD — App Store ve Google Play

Üç iş akışı vardır: biri doğrular, ikisi yayınlar.

| Dosya | Tetik | Ne yapar |
|---|---|---|
| `.github/workflows/ci.yml` | `main`'e push, PR | Doğrular. Hiçbir şey yayınlamaz. |
| `.github/workflows/release-ios.yml` | `v*` etiketi, elle | TestFlight **dahili** test; App Store'a gönderim yalnızca elle |
| `.github/workflows/release-android.yml` | `v*` etiketi, elle | Play **internal** kanalına **taslak** olarak yükler |

---

## 1. Taşıyıcı karar: hiçbir şey otomatik olarak incelemeye gitmez

Etiket push'u TestFlight dahili testine ve Play internal kanalına **taslak** yükler.
İncelemeye gönderme (`appstore` lane'i) ve üretime yükseltme elle yapılır.

Gerekçesi: bu bir klinik karar destek aracıdır. Bir hekimin kurduğu sürümü, bir etiket
push'u değil, yayınlamayı *seçen* bir insan belirlemelidir. Otomatik yayın, hız kazandırdığı
yerde geri alınamaz bir şeyi hızlandırır.

---

## 2. Doğrulama hattı (`ci.yml`)

Beş iş, paralel:

**`colour-engine`** — `shade_core`, saf Dart. Format, analiz (`--fatal-infos
--fatal-warnings`), test ve **%90 satır kapsama tabanı**. Kapsama burada bir pano sayısı
değil yayın kapısıdır: renk motoru, bu uygulamanın ekrana bakarak denetlenemeyen parçasıdır.

**`generated-sources`** — üretilmiş her şeyin güncel olduğunu kanıtlar:

- ARB dosyaları `tools/l10n/strings.py` ile eşleşiyor (biri elle düzenlenmişse kırılır);
- Pigeon çıktısı sözleşmeyle eşleşiyor (commit'lenmiş olmasının tek faydası güncel olması);
- skala kütüphaneleri üreticileriyle eşleşiyor;
- spesifikasyon oracle'ı hâlâ spesifikasyonla aynı sonucu veriyor;
- **mağaza metni sınırlarını söylüyor** (§5).

**`app`** — Flutter: format, analiz, `gen-l10n`, **çevrilmemiş mesaj yok**, testler. Golden
başarısızlıklarında fark görüntüleri artefakt olarak yüklenir.

**`ios-build`** / **`android-build`** — imzasız derleme ve native birim testleri. PR'da
imzalama yoktur: derlemenin kanıtlaması gereken şey Swift/Kotlin'in üretilmiş Pigeon
bağlayıcılarıyla derlendiğidir — sözleşme ile implementasyon ayrıştığında gerçekten kırılan
kontrol budur.

**Flutter sürümü pinlenmiştir** (`stable` değil). Kendi kendine ilerleyen bir araç zinciri,
kimsenin koda dokunmadığı bir günde alakasız bir Flutter sürümünü kırık derlemeye çevirir;
ayrıca klinik bir uygulamada bir sürümü üreten araç zinciri geri bulunabilir olmalıdır.

---

## 3. iOS yayını

### Gerekli GitHub secret'ları

`ios-release` ortamında tanımlanır (ortam kullanmak, onay kuralı eklenebilmesi içindir):

| Secret | Nereden alınır |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `APP_STORE_CONNECT_ISSUER_ID` | Aynı sayfanın başındaki Issuer ID |
| `APP_STORE_CONNECT_KEY_BASE64` | İndirilen `AuthKey_XXXX.p8` → `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `IOS_CERTIFICATE_P12_BASE64` | Distribution sertifikası `.p12` olarak dışa aktarılır → base64 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` dışa aktarımında verilen şifre |
| `IOS_PROVISIONING_PROFILE_BASE64` | App Store dağıtım profili → base64 |

**Apple ID değil API anahtarı.** Apple ID, uygulamaya özel şifre ister ve etkileşimsiz bir
işte iki faktörlü istemlere yine takılır.

### İmzalama ve temizlik

İş, geçici bir keychain oluşturur, rastgele bir şifreyle açar, 900 saniye sonra kilitlenecek
şekilde ayarlar ve işin sonunda `if: always()` ile siler. Runner zaten tek kullanımlıktır;
bilinen şifreli adlandırılmış bir keychain yine de öğretilmesi yanlış bir alışkanlık olur.

### Sürüm numaralama

- **Pazarlama sürümü** `pubspec.yaml`'dan gelir — hekimin gördüğü numara sürüm kontrolünde durur.
- **Build numarası** `github.run_number`'dan gelir — monotoniktir ve tekrar kullanılamaz.
  App Store Connect tekrarlanan bir build numarasını reddeder ve yayın ortasında bunu elle
  toparlamak tatsızdır.
- Etiket `pubspec.yaml` sürümüyle uyuşmazsa iş kırılır.

---

## 4. Android yayını

### Gerekli GitHub secret'ları

`android-release` ortamında:

| Secret | Nereden alınır |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Upload keystore (`.jks`) → base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore şifresi |
| `ANDROID_KEY_ALIAS` | Anahtar takma adı |
| `ANDROID_KEY_PASSWORD` | Anahtar şifresi |
| `PLAY_SERVICE_ACCOUNT_JSON` | Google Cloud servis hesabı JSON'u, Play Console'da yetkilendirilmiş |

Servis hesabına Play Console'da verilmesi gereken izin: **Releases → yalnızca test
kanallarına yükleme.** Üretime yükseltme izni verilmez; §1'deki kararın teknik karşılığıdır.

### ProGuard eşleme dosyası

`mapping.txt` bundle ile birlikte yüklenir. Yüklenmezse sahadan gelen bir çökme raporu
okunamaz, ve bu fark edildiğinde çökmenin olduğu sürüm çoktan yayındadır.

---

## 5. Mağaza metninin otomatik denetimi

`tools/store/check_copy.py` CI'da çalışır ve şunları zorlar:

- aşırı iddia içeren ifadeler yok (`garanti`, `kusursuz`, `tıbbi cihaz`,
  `spectrophotometer-grade`, `clinically proven`, … — iki dilde, her yerde);
- her yerelin uzun açıklamasında **"spektrofotometre değildir" / "not a
  spectrophotometer"** geçiyor;
- her yerelin uzun açıklamasında sorumluluk uyarısı geçiyor;
- listeleme her iki dilde var.

Olumsuzlama penceresi kontrolü vardır: "does not diagnose" bir sorumluluk reddidir, iddia
değil. Gözden geçiren notları pazarlama metni olmadığı için taranmaz.

Bu kontrol mekanik olmak zorundadır. Telefon kamerasının ne ölçebildiğine dair dürüst
pozisyon spesifikasyonda, onboarding'de ve sonuç ekranında durur; mağaza listelemesi onu
sessizce düşürmenin en kolay olduğu yerdir — en son yazılır, pazarlama metnidir ve kimse
onu mimariye karşı okumaz.

---

## 6. Yayın kontrol listesi

```
[ ] pubspec.yaml sürümü güncellendi
[ ] CHANGELOG / release notes iki dilde yazıldı (commit mesajı değil)
[ ] docs/architecture/04-testing-and-roadmap.md §2 saha doğrulaması sonuçları güncel
[ ] com.nuans.app yerine gerçek sahip olunan alan adı kullanılıyor
[ ] privacy_url ve support_url gerçek adresleri gösteriyor
[ ] Ekran görüntüleri iki dilde, güven rozeti görünür şekilde
[ ] git tag -a vX.Y.Z -m "..." && git push --tags
[ ] TestFlight dahili test / Play internal taslak doğrulandı
[ ] İncelemeye gönderim elle tetiklendi
```

`com.nuans.app` ve `example.invalid` adresleri **yer tutucudur**; ilk gerçek yayından önce
değiştirilmelidir. Listede durmaları bunun unutulmaması içindir.
