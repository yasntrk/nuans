# Nüans / Nuans

Diş hekimleri ve diş teknisyenleri için, telefon kamerasını kalibre edilmiş bir renk
ölçüm aracı gibi kullanan iOS + Android uygulaması. Baştan iki dilli (TR + EN).

**Telefon kamerası spektrofotometre değildir.** Üç kanalla ölçer, spektrum ölçmez;
metamerizmi göremez ve translüsensiyi tahmin eder. Bu depoda doğruluk iddiası yoktur;
belirsizlik mimaride (güven skoru), arayüzde ve raporda açıkça taşınır.

## Durum

Flutter 3.47.7 / Dart 3.13.5 ile kuruldu ve koşturuldu.

| Kontrol | Sonuç |
|---|---|
| `dart analyze --fatal-infos` · shade_core | **No issues found** |
| `flutter analyze --fatal-infos` · uygulama | **No issues found** |
| `dart test` · shade_core | **296 / 296**, satır kapsaması %93.0 |
| `flutter test` · uygulama | **89 / 89** (33 mantık + 56 golden) |
| `dart run pigeon` | Dart + Swift + Kotlin bağlayıcıları üretildi |
| `flutter gen-l10n` | üretildi, çevrilmemiş mesaj: 0 |
| `flutter build apk --release` | **55 MB**, `com.nuans.app`, minSdk 29, debug anahtarıyla imzalı |
| Swift ↔ Pigeon uyumu | 11 host metodu, 15 struct, 9 enum: tam eşleşme |

| Aşama | Çıktı |
|---|---|
| 1 Mimari | Katman diyagramı, Pigeon sözleşmesi, ADR-0001 |
| 2 Algoritma | Pikselden reçeteye formüller, sabitler tablosu |
| 3 Renk çekirdeği | `packages/shade_core` — 296 test |
| 4 Native kamera | Swift/AVFoundation + Kotlin/Camera2 |
| 5 Karışım ve reçete | Komşuluk grafı, ızgara araması, kural motoru |
| 6 UX ve l10n | Overlay, durum makinesi, 210 ARB mesajı, PDF, ekranlar |
| 7 Test ve yol haritası | Strateji, saha protokolü, yol haritası |
| CI/CD | Üç iş akışı, fastlane, mağaza metni denetimi |

**Derlenmeyen tek taraf iOS.** Xcode projesi yok, bu yüzden Swift kodu yalnızca üretilmiş
Pigeon bağlayıcılarına karşı denetlendi (11 host metodu, 15 struct, 9 enum: tam eşleşme).
Android tarafı Kotlin kamera katmanıyla birlikte derlendi ve APK üretildi; hiçbir kamera
kodu gerçek bir cihazda çalıştırılmadı.

Araç zincirini çalıştırmak **üç gerçek kod hatası ve üç yanlış test beklentisi** ortaya
çıkardı; hepsi [doğrulama günlüğünde](docs/verification-log.md) kayıtlı.

## Belgeler

- [Mimari](docs/architecture/01-architecture.md) — katmanlar, modüller, veri akışı
- [Algoritma](docs/architecture/02-algorithms.md) — her adımın formülü, kaynağı ve sınırı
- [UX ve yerelleştirme](docs/architecture/03-ux-and-localisation.md)
- [Test ve yol haritası](docs/architecture/04-testing-and-roadmap.md)
- [CI/CD](docs/ci-cd.md) — gereken secret'lar, yayın kontrol listesi
- [ADR-0001](docs/adr/0001-color-math-boundary.md) — renk matematiğinin platform sınırı
- [CONTEXT.md](CONTEXT.md) — iki dilli terim sözlüğü ve kullanılmayan kelimeler
- [Varsayımlar](docs/assumptions.md) — 87 karar, gerekçeleriyle

## Yapı

```
packages/shade_core/   saf Dart renk motoru: Flutter yok, I/O yok, metin yok
lib/                   Flutter uygulaması
ios/Runner/Camera/     Swift + AVFoundation
android/.../camera/    Kotlin + Camera2
pigeons/               tek platform sözleşmesi
assets/                skala kütüphaneleri, kompozit kuralları, fontlar
tools/                 üreticiler ve spesifikasyon oracle'ı
docs/                  yukarıdaki belgeler
```

## Çalıştırma

```bash
# renk motoru, Flutter gerektirmez
cd packages/shade_core && dart pub get && dart test

# uygulama
flutter pub get
dart run pigeon --input pigeons/shade_camera_api.dart
flutter gen-l10n
flutter test
flutter run

# üretilmiş dosyaları yenile
python3 -I tools/l10n/generate.py
python3 -I tools/shade_libraries/generate.py

# spesifikasyonun formüllerini doğrula
python3 -I tools/spec_oracle/stage2_reference.py
python3 -I tools/store/check_copy.py
```

## Eksikler

- Sharma/Wu/Dalal (2005) CIEDE2000 veri setinin 34 satırından 1'i kodda; kalanı
  yayımlanmış tablodan aktarılmalı
- Skala kütüphaneleri yapısal iskelet; klinik kendi skalasını ölçmeli
- Marka eşleme tablosu boş
- Cihaz başına netlik/hareket eşikleri ölçülmemiş
- Gri kartın gerçek `Y` değeri veri sayfasından okunmamış
- Güven skoru ağırlıkları saha verisiyle kalibre edilmemiş
- `assets/fonts/NotoSans-*.ttf` eklenmeli (lisansı Open Font License)
- `com.nuans.app` ve `example.invalid` adresleri yer tutucu

## Lisans

Belirlenmedi.
