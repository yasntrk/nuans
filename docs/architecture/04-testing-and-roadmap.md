# Nüans / Nuans — Aşama 7: Test, doğrulama ve yol haritası

Durum: taslak (Aşama 7 çıktısı)
Önceki aşamalar: [mimari](01-architecture.md) · [algoritma](02-algorithms.md) · [UX/l10n](03-ux-and-localisation.md)

---

## 1. Test stratejisi

### 1.1 Katman katman ne test edilir

| Katman | Araç | Neyi kanıtlar | Neyi kanıtlamaz |
|---|---|---|---|
| `shade_core` birim testleri | `dart test` | Renk matematiği, kalibrasyon, sağlam istatistik, eşleştirme, karışım, güven skoru | Hiçbir şeyin ekranda doğru göründüğünü |
| ARB eşitlik testi | `dart test` | İki dilin anahtar kümesi özdeş, yer tutucular eşleşiyor | Çevirinin *doğru* olduğunu |
| Durum makinesi testleri | `flutter test` | Histerezis, kilitler, bilinmeyen eğimin geçmemesi | Gerçek kameranın bu değerleri ürettiğini |
| Widget testleri | `flutter test` | Ekranların kurulduğunu, kilitlerin bağlandığını | Yerleşimin taşmadığını |
| Golden testler (TR + EN) | `flutter test` | Yerleşimin iki dilde de taşmadığını | Rengin doğru olduğunu |
| Native birim testleri | `xcodebuild test` / `gradle test` | Bayer indirgeme, kare kalitesi, pozlama çözücü — sentetik tamponlarla | Gerçek sensörün beklendiği gibi davrandığını |
| Entegrasyon testleri | `flutter test integration_test` | Akışın uçtan uca yürüdüğünü | Ölçümün doğru olduğunu |
| **Saha doğrulaması** | §2 | Ölçümün referans bir spektrofotometreye ne kadar yakın olduğunu | — |

Son satır önemlidir. Yukarıdaki her şey **tutarlılık** testidir: kodun kendi
spesifikasyonunu uyguladığını gösterir. Cihazın gerçekten dişin rengini ölçtüğünü
gösteren tek şey saha doğrulamasıdır ve o çalışana kadar hiçbir doğruluk iddiası
yapılmaz.

### 1.2 İki dilli golden testler

Kritik ekranlar (kamera overlay, sonuç, reçete, geçmiş) her iki yerelde render edilir.
Sebep yalnızca çeviri değil **taşma**: Türkçe klinik terimler İngilizce karşılıklarından
sistematik olarak uzundur ("Klinik olarak kabul edilebilir" / "Clinically acceptable",
"Belirgin şekilde daha az doygun" / "Markedly less saturated"). İngilizce'de sığan bir
rozet Türkçe'de kesilir ve bunu yalnızca iki dilde render eden bir test yakalar.

Golden testler ayrıca iki yazı tipi ölçeğinde çalışır (1.0 ve 1.3): klinikte gözlük
takan bir hekim sistem yazı tipini büyütmüş olabilir.

### 1.3 Referans oracle ile çapraz kontrol

`tools/spec_oracle/` altında spesifikasyonun formüllerinin bağımsız bir Python
transkripsiyonu durur. Dart implementasyonunun beklenen değerleri oradan üretilmiştir —
hatırlanarak yazılmış değil, hesaplanmış. Bu, Aşama 3'te dört hatalı test iddiasını ve iki
gerçek kod hatasını yakaladı (yayımlanmış sRGB matrisinin beyaz noktayı tam korumaması;
`rowSums.y`'nin kazançlardan sonra mükemmel difüzör olmaması).

### 1.4 CIEDE2000 doğrulamasının eksik kısmı

Sharma/Wu/Dalal (2005) veri setinin 34 satırından **1'i** koddadır — brief'te verilen
satır. Kalanı yayımlanmış tablodan birebir aktarılmalıdır; test eksik satır sayısını
bildirir. Hatırlayarak yazmak uydurmak olur: test geçer, hiçbir şey kanıtlanmaz.

### 1.5 Test edilemeyenlerin listesi

Dürüstlük gereği açık tutulur:

- **Gerçek sensör davranışı.** Bayer indirgeme sentetik tamponla test edilir; gerçek bir
  sensörün siyah seviye kayması, sıcak pikseli ve satır gürültüsü yoktur orada.
- **Platform API imzaları.** Pigeon üretilmiş bağlayıcılar ve proje iskeletleri olmadan
  Swift/Kotlin kodu derlenmedi.
- **Metamerizm.** Üç kanalla ölçüm yapıldığı için test edilemez; ancak spektrofotometreyle
  saha karşılaştırması dolaylı bir sınır verir.
- **Çeviri kalitesi.** Anahtar eşitliği otomatiktir, anlam eşitliği değil. İki dili
  yan yana tanımlamak bunu kolaylaştırır ama bir dil uzmanının gözden geçirmesi gerekir.

---

## 2. Saha doğrulama protokolü

### 2.1 Tasarım

| Parametre | Değer | Gerekçe |
|---|---|---|
| Örneklem | ≥ 30 diş, ≥ 10 hasta | Brief'in asgarisi; diş başına değil hasta başına çeşitlilik gerekir |
| Referans | Temas tipi klinik spektrofotometre (ör. VITA Easyshade sınıfı) | Tek erişilebilir altın standart |
| Hedef diş | Üst santral kesici (FDI 11/21) | Protokolün varsayılanı |
| Bölge | Gövde üçlüsü | Referans cihazın ölçtüğü bölge |
| Tekrar | Her diş için 3 ölçüm, her iki cihazla | Tekrarlanabilirliği ayırmak için |
| Sıra | Randomize, önce Nüans veya önce referans | Dehidrasyon sistematik hata yaratır |
| Zamanlama | Ekartör takıldıktan sonra ilk 60 saniye | Dehidrasyon `L*`'ı dakikalar içinde yükseltir |
| Işık | CRI ≥ 95, ~5500K, sabit | Protokolün önerisi |

### 2.2 Raporlanacak metrikler

```
1. Ortalama ΔE00 farkı (Nüans vs referans) ve standart sapması
2. Bland-Altman grafiği: fark vs ortalama, sistematik sapmayı ayırmak için
3. Tekrarlanabilirlik: her cihazın kendi 3 ölçümü arasındaki ortalama ΔE00
4. Skala uyum oranı: iki cihazın aynı skala kodunu verdiği diş yüzdesi
5. Komşu-skala uyum oranı: kodlar aynı değilse yapısal komşu mu?
6. Güven skoru ile hatanın korelasyonu
```

Altıncısı en önemlisidir ve çoğu zaman atlanır. Güven skoru, hatayı öngörmüyorsa işe
yaramaz bir süstür. Doğrulamanın asıl çıktısı "ortalama ΔE00 şu kadar" değil, **"güven
skoru Yüksek olduğunda hata şu kadar, Düşük olduğunda şu kadar"**dır.

### 2.3 Başlangıç hedefleri

```
ortalama ΔE00 farkı  < 2.0
tek renk uyumu       ≥ %70
komşu-skala uyumu    ≥ %95
tekrarlanabilirlik   < 1.0 ΔE00
```

**Bunlar hedeftir, iddia değildir.** Yayın öncesi karşılanmazsa yapılacak şey hedefi
düşürmek değil, arayüzdeki dili sıkmaktır.

### 2.4 Protokolün kendi sınırı

Referans cihaz da bir ölçüm hatası taşır. Ölçülen fark iki cihazın hatalarının
birleşimidir; Nüans'ın hatası tek başına bu çalışmayla ayrılamaz. Ayırmak için üçüncü bir
yöntem (laboratuvar spektrofotometresi, düz numune) gerekir ve bu v2 kapsamındadır.

---

## 3. MVP → v2 yol haritası

### MVP (bu aşamalar)

Renk çekirdeği, native yakalama, kalibrasyon, eşleştirme, karışım, reçete, iki dilli
arayüz ve rapor. iOS önce.

### v1.1 — ürünleşme

- Android yayını (aynı kod tabanı, `CapabilityProbe` sezgiselinin saha doğrulaması)
- Cihaz başına netlik/hareket eşiklerinin ölçülmesi (şimdi placeholder)
- Sharma veri setinin tamamının aktarılması
- Gri kart `Y` değerinin fiziksel karttan okunması
- Güven skoru ağırlıklarının saha verisiyle kalibrasyonu

### v2 — ölçüm yeteneğinin genişlemesi

| İş | Neden şimdi değil | Neyi açar |
|---|---|---|
| **ML diş segmentasyonu** (Core ML / TFLite) | MVP'de sabit ROI geometrisi karşılaştırılabilirlik sağlıyor; segmentasyon doğruluk getirir ama tutarlılığı riske atar | Eğri dişler, aşınmış kenarlar, serbest ROI |
| **Translüsensi ölçümü** | Siyah/beyaz zemin gerektirir: yeni bir fiziksel aksesuar ve yeni bir protokol | Sezgiselin yerine gerçek ölçüm; "tahmini" etiketi kalkar |
| **Kubelka–Munk karışım modeli** | Spektral veri ister; üç kanalla beslenemez | Doğrusal yaklaşımın yerine fiziksel model; aileler arası karışım |
| **Spektral ek donanım** | Maliyet ve kalibrasyon yükü | Metamerizmin görünür olması — bugünün en büyük kör noktası |
| **Bulut üzerinden laboratuvar paylaşımı** | Offline-first ve KVKK/GDPR gerekçesi; açık rıza akışı tasarlanmalı | Raporun PDF yerine canlı bağlantı olması, geri bildirim döngüsünün kapanması |
| **Geri bildirim döngüsünün otomatik düzeltmesi** | v1 yalnızca kayıt tutuyor; düzeltme uygulamak için istatistiksel güç gerekir | Malzeme başına öğrenilmiş sapma ofseti |
| **Aileler arası karışım** | Yapısal komşuluk kuralı doğrusal modeli geçerli tutuyor | Teknisyenin pratikte yaptığı karışımlar |

### Yayın öncesi zorunlu kontroller

- [ ] Tıbbi cihaz yazılımı statüsü değerlendirmesi (TİTCK / AB MDR)
- [ ] Saha doğrulaması (§2) tamamlandı ve sonuçları arayüzdeki dile yansıtıldı
- [ ] Sharma veri setinin tamamı aktarıldı
- [ ] Paket kimliği gerçek sahip olunan alan adıyla değiştirildi
- [ ] SQLCipher anahtar yönetimi güvenlik gözden geçirmesinden geçti
- [ ] KVKK/GDPR: silme ve dışa aktarma hakları uçtan uca test edildi
- [ ] Mağaza metinleri iki dilde hazır ve doğruluk iddiası içermiyor
