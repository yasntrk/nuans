# Nüans / Nuans — proje sözleşmeleri

Global `~/.claude/CLAUDE.md` üzerine bu projeye özgü eklemeler.

## Issue tracker

**Henüz tanımlanmadı.** Global sözleşme her projenin tracker'ını burada bildirmesini ister
ve bu depo için bir seçim yapılmamıştır. Tracker belirlenene kadar iş kalemi açılmaz;
kararlar [docs/assumptions.md](docs/assumptions.md) içinde ve ADR'lerde tutulur.

Tracker seçildiğinde bu bölüm şu biçime kavuşur ve ilgili fragment `@`-import edilir:

```markdown
## Issue tracker
<Tracker adı>, proje <kimlik>. @~/.claude/<tracker>.md
Hiyerarşi: <Epic / User Story veya Story / Sub-task>
```

## Documentation

**Henüz tanımlanmadı.** Özellik sayfalarının yayınlanacağı wiki belirlenmemiştir, bu
yüzden `document-feature` akışı çalıştırılamaz. Depo içi artefaktlar (`docs/`,
`CONTEXT.md`, ADR'ler) tek kayıt yeridir.

## Bu depoya özgü kurallar

**Üretilmiş dosyalar elle düzenlenmez.** Üç üretici vardır ve CI çıktılarının güncel
olduğunu doğrular:

| Üretici | Çıktı |
|---|---|
| `tools/l10n/generate.py` | `lib/l10n/app_tr.arb`, `app_en.arb` |
| `tools/shade_libraries/generate.py` | `assets/shade_libraries/*.json` |
| `dart run pigeon` | `*.g.dart`, `*.g.swift`, `*.g.kt` |

**`shade_core` hiç metin üretmez.** Kullanıcıya görünen her şey makine kodu olarak döner
ve `lib/core/l10n/clinical_strings.dart` tek köprüdür. Bu dosyaya eklenmeyen bir enum
değeri derlenmez — ekranda çevrilmemiş görünmez.

**Kullanıcıya görünen metne programatik harf dönüşümü uygulanmaz.** Türkçe'de Dart'ın
`toUpperCase`/`toLowerCase`'i yanlış sonuç verir. Büyük harf gereken metin ARB'de zaten
büyük harfle yazılır.

**Sabitler isimlendirilir ve kaynaklandırılır.** `packages/shade_core/lib/src/constants.dart`
her değeri **standard** / **protocol** / **decision** / **placeholder** olarak etiketler.
Çıplak sayı çekirdek mantıkta bulunmaz.

**Ölçüm olmayan sayı ölçüm gibi sunulmaz.** Skala değerleri `unverifiedPlaceholder`
işaretlidir, translüsensi "tahmini" etiketlidir, mağaza metni CI'da denetlenir. Hatırlanan
bir referans değeri yazmak yerine `SOURCE REQUIRED` bırakılır.

**Spesifikasyonun formülleri çalıştırılabilir.** `tools/spec_oracle/` altında bağımsız bir
Python transkripsiyonu durur; Dart testlerinin beklenen değerleri oradan üretilir,
hatırlanarak yazılmaz.

## Doğrulama komutları

```bash
cd packages/shade_core && dart analyze --fatal-infos && dart test
flutter analyze --fatal-infos && flutter test
python3 -I tools/l10n/generate.py --check
python3 -I tools/store/check_copy.py
```
