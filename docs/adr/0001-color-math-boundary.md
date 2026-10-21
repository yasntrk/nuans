# ADR-0001: Renk matematiği Dart'ta kalır, native yalnızca indirgenmiş süperpiksel örneği döner

- Durum: kabul edildi
- Tarih: 2026-10-21
- Bağlam belgesi: [Aşama 1 mimari](../architecture/01-architecture.md)
- İlgili sözleşme: `pigeons/shade_camera_api.dart`

## Bağlam

İki kural çatışıyor:

1. **Piksel-yoğun iş native tarafta yapılır.** 12 MP bir Bayer karede ~2016 × 1512
   süperpiksel vardır; bunu Dart'a taşımak hem serileştirme hem döngü maliyeti demektir.
2. **Sağlam ROI istatistiği piksel başına L\* gerektirir.** Yansıma filtresi
   (medyan + 2.5·MAD) ve gölge filtresi (medyan − 3·MAD) süperpiksel başına L\* ister.
   L\* ise gri kart kazançları ve CCM uygulandıktan sonra hesaplanabilir.

Yani filtre, renk dönüşümünün *sonrasında* çalışmak zorundadır. Soru şu: dönüşüm nerede
yaşasın?

## Karar

Renk bilimi **yalnızca `packages/shade_core` içinde, saf Dart'ta** yaşar. Native katman
şunları yapar ve başka hiçbir şey yapmaz:

1. RAW okuma, siyah seviye çıkarma, beyaz seviyeye normalize etme,
2. Bayer 2×2 süperpiksel oluşturma — R, (G1+G2)/2, B,
3. kırpılmış süperpikselleri atma (eşik Dart'tan gelir),
4. kalan süperpikselleri **düzenli ızgara adımıyla (stride) seyreltip** döndürme —
   ortalama almadan,
5. tüm (seyreltilmemiş) kümenin kesin ortalama ve standart sapmasını ayrıca döndürme,
6. netlik (Laplacian varyansı), hareket ve histogram metriklerini ölçme.

Seyreltme formülü: `stride = max(1, ceil(sqrt(totalSuperpixels / maxSamplesPerRoi)))`.
Varsayılan `maxSamplesPerRoi = 4096`; ColorChecker yamalarında 512.

Stride **yalnızca ROI geometrisine** bağlıdır, hayatta kalan süperpiksel sayısına değil.
Aksi halde kırpılma sayısı karelere göre bir iki piksel oynadığında ızgara kayar ve burst
kareleri hizasız ortalanır. Kırpılma, ızgara noktalarını *maskeler*: kabul edilen
karelerden herhangi birinde kırpılmış bir nokta hepsinden düşer, böylece dönen her üçlü
aynı kare desteğine sahip olur.

## Gerekçe: sayısal bedel

**Veri hacmi.** 4096 örnek × 3 kanal × 8 bayt = 98 KB/ROI. Bir çekimde 5 ROI (3 diş bandı
+ gri kart + skala tabı) → ~0.5 MB. Cihaz profili çekiminde 24 yama × 512 örnek → ~295 KB.
Çekim başına tek seferlik bir aktarımdır; önizleme akışında hiç ham veri taşınmaz.

**Seyreltmenin ölçüm hatası.** Stride örnekleme yansız bir örneklemdir. ROI içi
σ(L\*) ≈ 2 kabul edilirse, N = 4096 örnekle kesilmiş ortalamanın standart hatası
≈ 2/√4096 ≈ 0.031 L\*; %10–90 kesilmiş ortalamanın verim katsayısı (~1.05) ile
≈ 0.033 L\*. Kabul edilebilirlik eşiği 0.8 ΔE00 olduğundan bu, karar eşiğinin bir buçuk
mertebe altındadır. (σ değeri tipik bir büyüklük tahminidir; gerçek dağılım saha
doğrulamasında ölçülecek — *placeholder, doğrulanmalı*.)

**Neden ortalama değil seyreltme.** Yansıma, ROI'nin küçük bir yüzdesinde çok parlak
piksellerdir. Hücre ortalaması alınırsa bu pikseller komşularına yayılır: aykırı değer
olmaktan çıkar, hücreyi hafifçe aydınlatır ve MAD filtresi onu yakalayamaz. Stride
örneklemede bir süperpiksel ya örnekte vardır ya yoktur; aykırı değer dağılımı korunur.

## Değerlendirilen alternatifler

| Alternatif | Neden reddedildi |
|---|---|
| Renk dönüşümünü native'de yapmak (CCM, Lab, ΔE00 Swift + Kotlin'de) | Aynı renk bilimi iki dilde iki kez yazılır; Sharma veri setiyle doğrulama iki kez kurulur; platformlar arası sapma riski doğar. Brief'in "renk matematiğinin tamamı shade_core'da yaşar ve %100 birim testlidir" kuralını ihlal eder. |
| Tüm ROI piksellerini Dart'a aktarmak | Tek kare için 2016×1512×3×8 ≈ 73 MB; Pigeon serileştirmesi ve Dart döngüsü kabul edilemez. |
| Native'de kaba hücre ızgarasına ortalamak (ör. 24×24 hücre) | Yansıma filtresinin dayandığı aykırı değer dağılımını yok eder (yukarıya bakın). |
| Kazanç ve CCM'yi native'e gönderip filtreyi native'de çalıştırmak | Renk kararı native'e taşınır, test yüzeyi ikiye katlanır, politika mekanizmayla karışır. |

## Sonuçlar

Olumlu:

- CIEDE2000, CCM uydurma, Lab dönüşümleri bir kez yazılır, saf Dart'ta, %100 testlenir ve
  Sharma/Wu/Dalal veri setiyle doğrulanır.
- Native yüzey deterministik ve sentetik tamponlarla test edilebilir hale gelir:
  seviye normalizasyonu, süperpiksel, kırpılma, ızgara örnekleme, Laplacian.
- Yansıma/gölge filtresi gerçek süperpiksel değerleri üzerinde çalışır, ortalama üzerinde değil.
- Çekim sonrası ROI sürüklendiğinde yeni çekim gerekmez: `resampleRoi` aynı kareden indirger.

Olumsuz / takip gerektiren:

- Çekim başına ~0.5 MB Pigeon yükü.
- Seyreltmenin yanlılık yaratmadığını kanıtlamak için sözleşme `decimationStride` ve
  seyreltilmemiş kümenin kesin `channelMean` değerini taşımak zorundadır; Aşama 3'te
  `roi_reducer_decimation_test.dart` sentetik ROI üzerinde tam küme ile seyreltilmiş
  kümenin kesilmiş ortalamalarını karşılaştırır.
- Dart, çekim başına ~20 bin üçlü işler (birkaç ms). v1'de isolate kullanılmaz, ancak
  indirgeme hattı saf fonksiyon olarak yazılır ki gerekirse isolate'a taşınabilsin.
