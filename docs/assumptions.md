# Varsayımlar

Brief'in "Sabit Kararlar" bölümünde bulunmayan ve kendi aldığım kararlar. Her satır tek
cümle gerekçelidir. Liste aşama aşama büyür; Aşama 7'de nihai hale gelir.

## Aşama 1 — Mimari

| # | Varsayım | Gerekçe |
|---|---|---|
| A1 | Mimari belgesi `docs/architecture/` altında tutuldu. | Global CLAUDE.md'nin docs haritasında mimari için bir yol tanımlı değil; PRD/spec/ADR yollarıyla tutarlı yeni bir klasör en az sürprizli seçim. |
| A2 | Native modüller ayrı bir Flutter plugin paketi değil, uygulamanın `ios/` ve `android/` ağaçlarında yaşıyor. | Brief'in istediği klasör yapısı bu; tek tüketici olduğu için paket sürümleme yükü gereksiz. |
| A3 | Paket kimliği `com.nuans.app` (iOS bundle id + Android applicationId). | Store kurulumu için bir yer tutucu gerekiyordu; gerçek sahip olunan alan adıyla değiştirilmeli — **placeholder, doğrulanmalı**. |
| A4 | Monorepo aracı (melos vb.) yok; `shade_core` düz `path` bağımlılığı. | İki paketlik ağaçta ek araç bakım yükü getirir, fayda getirmez. |
| A5 | Önizleme metrikleri Pigeon `@FlutterApi` ile ~10 Hz akıyor (`EventChannel` değil). | Tip güvenliği tek sözleşmede kalıyor; 10 Hz için Pigeon yeterli. |
| A6 | Cihaz eğimi Flutter tarafında `sensors_plus` ile okunuyor. | Jiroskop renk ölçümünün parçası değil; native sözleşmeyi şişirmemesi gerekir. |
| A7 | `captureId` Dart tarafında `uuid` ile üretiliyor. | Native bellek ömrünü Dart'ın sahipliğine bağlar; deterministik ve test edilebilir. |
| A8 | `maxSamplesPerRoi = 4096` (ColorChecker yamaları için 512). | ADR-0001'deki standart hata hesabı: ~0.03 L\*, karar eşiğinin bir buçuk mertebe altında. |
| A9 | Gri kartın mutlak Y değeri %18 yansıtma → Y = 18.0 (mükemmel difüzör = 100, L\* ≈ 49.5). | Fiziksel kartın veri sayfasındaki gerçek Y ile değiştirilmeli — **placeholder, doğrulanmalı**. |
| A10 | Bağıl mod düzeltmesi, doğrusal XYZ'de kanal başına oran olarak uygulanıyor (sönümleme katsayısı ve sınırlama ile). | Lab'da fark çıkarmaktan daha fiziksel; hatalı bir tab okuması ölçümü bozmasın diye sınırlandırılıyor. Formül Aşama 2'de kesinleşir. |
| A11 | Lint seti `very_good_analysis`. | Dart 3 null-safety ve immutability kurallarını brief'in istediği sıkılıkta zorlar. |
| A12 | Flutter/Dart/Pigeon sürümleri henüz pin edilmedi. | Makinede Flutter SDK kurulu değil; sürümler kurulumdan sonra `pubspec.yaml` ve CI'da sabitlenecek. |
| A13 | Aşama 1'de issue tracker'a kayıt açılmadı. | Projenin `./CLAUDE.md` dosyası yok, yani hangi tracker ve hangi dokümantasyon evi geçerli bilinmiyor; global CLAUDE.md bunu proje dosyasına bırakıyor. |

## Aşama 2 — Algoritma

| # | Varsayım | Gerekçe |
|---|---|---|
| B1 | "Düzeltme sonrası a\*, b\* ≈ 0" bir çalışma zamanı gri kart ölçütü değil, birim test değişmezi olarak yeniden sınıflandırıldı. | Kazançlar kartı tanım gereği nötr yapar ve CCM beyaz noktayı korur; bu kontrol kart yerine mavi bir kapak çekilse de geçer, yani ayrım gücü sıfırdır. Gerçek ayrım tekdüzelik, sinyal aralığı, çeyrekler arası ΔE00 ve CCT makullüğüdür. |
| B2 | İşlenmiş (HEIF/JPEG) yolda cihaz CCM'i değil standart sRGB→XYZ(D65) matrisi kullanılıyor. | Doğrusallaştırılmış değerler kamera-doğal değil sRGB primerlerine indirgenmiş durumda; cihaz CCM'ini uygulamak iki kez renk dönüşümü yapmak olur. |
| B3 | Beyaz nokta ASTM E308 (0.95047 / 1.08883), CIE 15:2004 değerleri değil. | İki kaynak ~%0.004 farklı, ΔE00 düzeyinde ölçülemez; önemli olan tek kaynağa bağlı kalmak. |
| B4 | Gri kart kazançları yeşil kanala çapalanıyor. | Bayer dizilimde yeşil örnek sayısı iki katı, yani en iyi SNR; ölçeği ona bağlamak gürültüyü en az büyütür. |
| B5 | CCM kazançları tek beyaz yama yerine tüm nötr satırdan en küçük karelerle çıkarılıyor; ağırlık matrisi varsayılan `I`. | Tek yamanın kırpılması veya tozlanması sonucu bozmasın; ifade parlak yamalara SNR ile orantılı ağırlık verir. |
| B6 | `rejectedFraction` yalnızca kırpılma + MAD filtresini sayar, %10–90 kesmeyi saymaz. | Kesme sabit oranlı bir kestirim yöntemi, red sinyali değil; dahil edilse oran her zaman ≥ %20 görünür ve bilgi taşımaz. |
| B7 | Bağıl mod düzeltmesi Bradford koni uzayında, kanal başına oran olarak, ±%10 sınırlı. | von Kries'in doğru formülasyonu koni uzayıdır ve Bradford matrisi zaten elde; sınır, hatalı tab okumasının ölçümü bozmasını engeller. |
| B8 | `ΔE00(tab_ölçülen, tab_kütüphane) > 3.0` ise düzeltme hiç uygulanmıyor, yalnızca uyarı veriliyor. | Bilinen bir tabda 3 ΔE00'ı aşan fark ölçüm/kütüphane/ışık hatası demektir; o farkla düzeltmek hatayı dişe taşır. |
| B9 | Bileşen açıklaması eşikleri ham `ΔL'/ΔC'/ΔH'` değil, `S_L/S_C/S_H` ile ağırlıklandırılmış bileşenler üzerinde (0.5 / 1.0 / 2.0). | Ağırlıklı bileşenler ΔE00 birimindedir, böylece 0.8 algılanabilirlik eşiği bileşen ölçeğinde de anlamlı olur. |
| B10 | Karışım gösterim kapısındaki 0.3 iyileştirme **yuvarlanmış** karışımdan ölçülüyor. | Hekimin eline geçen yuvarlanmış reçete; optimumla kapı açmak kazanılmamış bir iyileştirme vaat etmek olur. |
| B11 | Yuvarlama "en büyük kalan" yöntemiyle. | Ağırlık toplamının tam 1 kalmasını garanti eden tek basit yöntem. |
| B12 | Aileler arası karışım (A2 + B2) v1'de üretilmiyor — kabul edilen sınırlama. | Brief yapısal komşuluğu şart koşuyor; pratikte teknisyenler aileler arası karıştırır, bu v2 için açık iş. |
| B13 | 3D-MASTER'da ton komşuluğu yalnızca aynı kroma kodu iki kolonda da varsa tanımlı. | L/R kolonları 1.5 ve 2.5, M kolonu 1/2/3 taşır; örtüşmeyen kodlar arasında komşuluk kenarı uydurmak yapısal olmayan bir karışım üretir. |
| B14 | Güven skoru ağırlıkları 0.18/0.20/0.18/0.12/0.10/0.10/0.12 ve bantlar 0.80/0.60. | Göreli sıralama gerekçeli (sistematik hata > rastgele hata > çapraz kontrol); mutlak değerler saha doğrulamasına kadar **placeholder**. |
| B15 | Ağırlıklı toplamın yanında sert kapılar var. | Ağırlıklı toplam, iyi alt skorların ölümcül bir kusuru maskelemesine izin verir; sert kapı bunu engeller. |
| B16 | Pozlama hedefi `p_target = 0.45`, kare seçiminde bağıl netlik katsayısı 0.60, asgari örnek 64/256, maks atılma 0.50. | Hepsi §15'te isimlendirilmiş sabit; gerekçeleri ilgili bölümlerde, cihaz ölçümüyle kalibre edilecek olanlar **placeholder** işaretli. |
| B17 | Sharma veri setinin tamamı henüz koda girmedi; yalnızca brief'in verdiği satır var. | Hatırlayarak yazmak uydurmak olur; Aşama 3'te yayımlanmış tablodan birebir aktarılacak ve dosya `// SOURCE REQUIRED` ile işaretli kalacak. |
| B18 | `tools/spec_oracle/stage2_reference.py` referans oracle olarak depoda tutuluyor. | Spesifikasyonun formülleri çalıştırılabilir olsun ve Aşama 3'te Dart implementasyonu bağımsız bir transkripsiyonla çapraz kontrol edilebilsin. |

## Aşama 3 — shade_core kodu

| # | Varsayım | Gerekçe |
|---|---|---|
| C1 | sRGB→XYZ matrisi yayımlanmış 7 haneli matristen kopyalanmıyor, primerlerden türetiliyor. | Yayımlanmış matrisin satır toplamları beyaz noktaya tam eşit değil (`Y = 1.0000001`); kodlanmış beyaz `L* = 100.0000039` veriyor ve mutlak parlaklık zincirinin dayandığı değişmez yalnızca yaklaşık sağlanıyor. Türetilmiş matris 4.9e-08 içinde aynı, beyaz noktayı tam koruyor. |
| C2 | `CaptureTransform` değişmezi "kart kendi yansıtmasına geri döner" (`luminanceOf(card) == 0.18`) olarak tanımlandı; `matrix.rowSums.y` kullanılmıyor. | Satır toplamları `(1,1,1)` kamera üçlüsünün görüntüsüdür, von Kries kazançlarından sonra o üçlü artık nötr değil. Ölçüldü: `rowSums.y = 0.3967`, oysa σ = 0.4. Kamera uzayında mükemmel difüzör, kart ölçümünün yansıtmasına bölümüdür. |
| C3 | Bradford matrisinin tersi elle yazılmıyor, çalışma zamanında hesaplanıyor. | Transkripsiyon hatası sessizdir; `bradford * bradfordInverse == I` tek testle kapanır. |
| C4 | Gri kart ölçümü kanal başına **medyan** ile alınıyor (kesilmiş ortalama değil). | Toz, çizik ve tek tük parlama medyanı etkilemez; hesabı basit ve testlenebilir tutar. |
| C5 | `rejectedFraction = clipped + (1 − clipped) · örnek_red_oranı` olarak kestiriliyor. | Kırpılma tüm popülasyon üzerinde, MAD filtresi ise seyreltilmiş örnek üzerinde ölçülüyor; iki farklı popülasyonu toplamak yanlış olur, oranı taşımak yansız kestirimdir. |
| C6 | Kesme sıralamasının anahtarı `(L*, indeks)` ikilisi. | Dart'ın `List.sort` fonksiyonu kararlı değil; eşit `L*` değerlerinde kesme sınırları kayabilir. Tam sıra, algoritma kararlılığından bağımsız tekrarlanabilirlik sağlar. |
| C7 | Eşleştirmede eşitlik skala koduna göre bozuluyor. | Aynı ölçüm ve aynı kütüphane her zaman aynı sırayı vermeli. |
| C8 | Ton yönü, `h̄'` çeyreği ile `ΔH'` işaretinin birleşiminden adlandırılıyor. | `ΔH'` işareti tek başına adlandırılabilir bir şey söylemez: bir dönmedir, hangi renge doğru olduğu ton çemberindeki konuma bağlıdır. |
| C9 | `RoiSampleSet` kendisine verilen tamponu kopyalıyor. | Native tarafın tamponu yeniden kullanması, teslim edilmiş bir ölçümü sessizce değiştirebilirdi. |
| C10 | Sharma veri setinin 34 satırından yalnızca 1'i (brief'te verilen) kodda; dosya `SOURCE REQUIRED` ile işaretli ve eksik satır sayısını testte bildiriyor. | Hatırlayarak yazmak uydurmak olur: test geçer, hiçbir şey kanıtlanmaz. |
| C11 | `analysis_options.yaml` içinde `todo: error` ve `fixme: error`. | Brief'in "çekirdek mantıkta TODO bulunmasın" kuralını araçla zorlar, niyete bırakmaz. |
| C12 | Güven skoru motoru Aşama 3'te yazılmadı; alt skor getter'ları (`CcmQualityReport.score`, `DeviceProfile.confidenceScore`, `GrayCardVerdict.score`) veriyi tutan tiplerde duruyor. | Brief'in Aşama 3 kapsam listesi eşleştirmede bitiyor; ağırlıklı birleştirme karışım motoruyla birlikte Aşama 5'e ait. |
| C13 | Testler **çalıştırılamadı**: makinede Dart SDK yok. | Doğrulama statik: sembol çözümlemesi, ayraç dengesi, formül terim karşılaştırması ve beklenen değerlerin bağımsız Python oracle'dan üretilmesi. `dart test` çıktısı yok. |

## Aşama 4 — Native kamera kodu

| # | Varsayım | Gerekçe |
|---|---|---|
| D1 | `SignalEncoding` enum'u sözleşmeye eklendi; yalnızca Bayer RAW `linear`, önizleme ve işlenmiş çekim `displayReferredSrgb`. | Native tarafı yazarken ortaya çıktı: önizleme akışı hiçbir platformda doğrusal değil, dolayısıyla "doğrusal kamera RGB" alan açıklaması yanlıştı. Kodlamayı alan adına güvenerek değil, alanı okuyarak öğrenmek gerekiyor. |
| D2 | `RoiSample.linearRgbSamples` → `rgbSamples` olarak yeniden adlandırıldı. | Aynı sebep: işlenmiş yolda değerler doğrusal değil, ad yalan söylüyordu. |
| D3 | iOS önizlemesi BGRA; netlik, tekdüzelik ve kırpılma yeşil kanaldan ölçülüyor. | Yeşil parlaklığın büyük kısmını taşır, yani tüm kareyi dönüştürmeden elde edilebilecek en güçlü odak sinyali. |
| D4 | Android önizlemesi YUV_420_888; RGB'ye BT.601 kısıtlı aralık matrisiyle çevriliyor. | Kamera YUV çıktısı normalde bu; cihazın gerçek matrisinin yaklaşımı ama trafik ışığı için yeterli, çünkü ölçümün dayandığı gri kart doğrulaması ham burst üzerinde tekrar yapılıyor. |
| D5 | Android kamera seçimi: arka yüzlü → mantıksal olmayan → en büyük fiziksel sensör → en küçük id. | Android'de `builtInWideAngleCamera` karşılığı yok. Mantıksal kamera seans ortasında lens değiştirebilir ve profilin kurulduğu lensten farklı bir lensle alınan ölçüm karşılaştırılabilir değil. Seçilen id profil anahtarına yazılıyor; sistem güncellemesinden sonra farklı seçilirse profil eşleşmez ve kullanıcı yeniden kalibrasyona yönlendirilir — sessizce kalibre edilmemiş lensle ölçmek yerine. |
| D6 | Android önizleme boyutu 1080p ile sınırlı. | Oturumun ihtiyaç duyduğu üç akışlı kombinasyon (önizleme + YUV metrik + tam boy RAW) yalnızca doğrusal olmayan iki akış "preview" boyutundayken garanti ediliyor. |
| D7 | Gürültü azaltma ve kenar keskinleştirme kapalı; **sıcak piksel düzeltmesi açık**. | İlk ikisi komşu pikseller arasında enerji taşıyan uzamsal filtreler — ROI ortalaması alınmadan önce olmaması gereken tam olarak bu. Sıcak piksel ise kalıcı bir parlak aykırı değer; Dart'taki yansıma filtresi onu atardı ama sensörün kendi haritasıyla temizlemek o örnekleri kurtarır. |
| D8 | Android'de beyaz dengesi kazançları otomatik moddan okunup donduruluyor; okunamazsa birim kazanç. | Değerin kendisi ölçüme etkisiz (düzeltmeyi gri kart yapar) ama sabit kalması zorunlu. Gün ışığına benzeyen bir vektör uydurmak, kalibrasyon kılığına girmiş sihirli sayı olurdu. |
| D9 | iOS'ta siyah/beyaz seviyeler DNG'den `CGImageSource` ile okunuyor; yoksa 14-bit beyaz seviyesi varsayılıp `isFromMetadata = false` işaretlenir. | Seviyeler cihaza özgü; tahmin edilen değerle ölçüm yapılabilir ama bu güven skoruna yansımak zorunda. |
| D10 | Android'de dinamik siyah/beyaz seviye tercih ediliyor; burst'ün tamamı ilk karenin seviyelerini kullanıyor. | Pedestal sensör sıcaklığıyla kayar ve gölge eşiği tam o kaymanın göründüğü yerde. Aynı kilitli burst'ün kareleri birkaç yüz milisaniye arayla, aynı duyarlılıkta çekildiği için aralarındaki kayma bir en düşük anlamlı bitin altında. |
| D11 | `CaptureStore` kapasitesi 2 çekim, azami yaş 600 s. | 12 MP 16-bit bir kare ~24 MB, üç karelik burst ~72 MB. Ömrü Dart `releaseCapture` ile yönetiyor; sınır ve yaş yalnızca Dart tarafı çökerse diye var. |
| D12 | Burst kare seçimi yalnızca netliğe bakıyor; `FrameQuality.motionScore` burst'te 0 dönüyor. | Hareket ölçüsü ardışık ve karşılaştırılabilir kareler ister; burst kareleri arasında sahne zaten değişmiş olabilir. Hareket bulanıklığını netlik eşiği yakalıyor. Önizlemede hareket ölçülüyor ve çekim butonunu o kapatıyor. |
| D13 | Pigeon enum yazımı üreticiye göre: Swift camelCase, Kotlin UPPER_SNAKE. | Pigeon üreticilerinin kuralı; ilk kod üretiminde doğrulanacak. |
| D14 | Pigeon hata tipi tek bir yerde takma adla bağlandı (`PigeonError` / `FlutterError`). | Pigeon sürüm yükseltmesi tek satırlık değişiklik olsun, plugin'de tarama gerektirmesin. |
| D15 | `previewImagePath` ve `rawFilePath` şimdilik `null`. | Aşama 4'te dosya yazımı yok; PDF raporun görüntüsü Aşama 6'da, kabul edilen ilk kareden JPEG yazılarak doldurulacak. Sözleşmede alanlar var, henüz doldurulmuyor. |
| D16 | Apple ProRAW açıkça kapatıldı; sanal çoklu kamera cihazları seçilmiyor. | ProRAW zaten demosaic edilmiş ve ton eşlemesi uygulanmış; kalibre edilmeye değer olan sensörün okunduğu haldir. |
| D17 | Native kod **derlenmedi**. | Pigeon üretilmiş bağlayıcılar yok (Dart SDK yok), Xcode projesi ve Gradle yapılandırması henüz oluşturulmadı. Doğrulama statik: sözleşme uyum kontrolü, ayraç dengesi, platformlar arası algoritma eşitliği. |

## Aşama 5 — Karışım ve reçete

| # | Varsayım | Gerekçe |
|---|---|---|
| E1 | 3D-MASTER kroma komşuluğu **kolonun kendi** basılı dizisinden hesaplanıyor; ton komşuluğu ±0.5 kroma farkına izin veriyor. | Grafı kontrol edince bulundu: ortak bir kroma sıralamasıyla `2M1` ile `2M2` komşu çıkmıyordu (aradaki 1.5 M kolonunda yok) ve `0M3` tamamen izole kalıyordu. Yarım adımlar zaten `2L1.5`'in `2M1` ile `2M2` arasında durması için var. Düzeltmeden sonra: 62 kenar, izole kod yok. |
| E2 | Karışım yalnızca **ikili olarak** komşu şadelerden kurulur, zincirle bağlı olanlardan değil. | `A1 - A2 - A3` zinciri `A1` ile `A3`'ü aynı karışıma sokardı; o mesafe doğrusal modelin kapsamını aştığı yerdir. |
| E3 | Skala kütüphaneleri `unverifiedPlaceholder` olarak işaretli **yapısal iskelet** ile geliyor; üretici betik depoda. | Hatırlanan bir Lab tablosu yetkili görünür ve yanlış olur, aşağısındaki hiç kimse ayırt edemez. İskelet eşleştirme/karışım/rapor yollarının ilk açılıştan çalışmasını sağlar, provenance çalıştırılabilir, ve en yakın iki şade arası 1.18 ΔE00 (0.8 eşiğinin üstünde) olduğu için eşleştirme iyi tanımlıdır. |
| E4 | Marka eşleme tablosu **boş** geliyor. | Doldurmak üreticinin tablosundan ad kopyalamaktır; uydurmak, malzeme sipariş etmek üzere olan teknisyenin önüne uydurma ürün verisi koymaktır. |
| E5 | Kompozit dentini kroma ağırlıklı seçiliyor (`2·|ΔC| + |ΔL| + |ΔH|`). | Translüsent emayenin altında parlaklıkta bir adım sapan dentin maskelenir, kromada sapan dentin doğrudan görünür. Doğrulandı: aynı hedefte düz en yakın komşu `A2`, kroma öncelikli seçim `A3` veriyor. |
| E6 | Metal-porselen dentin hedefi gövde/servikal XYZ ortalaması, gövdeye %60 ağırlıkla. | Dentin katmanı iki üçlüyü de kaplıyor; yalnız gövdeyi hedefleyen bir yapı bitmiş kronadan açık çıkar. |
| E7 | Her `Recipe` türünde `requiresVerification` alanı var. | Doğrulama notunu dokümantasyon yerine alan yapmak, render eden kodu onu kabul etmeye zorlar. |
| E8 | Güven skoru normalize ediliyor (ağırlık toplamına bölünerek). | Çağıran özel ağırlık verdiğinde skorun sessizce 0..1 aralığından çıkmaması için. |

## Aşama 6 — UX ve yerelleştirme

| # | Varsayım | Gerekçe |
|---|---|---|
| F1 | ARB dosyaları elle düzenlenmiyor; `tools/l10n/strings.py` tablosundan üretiliyor. | Elle tutulan iki dosya kayar; CI kontrolü bunu olaydan sonra yakalar, üretim ise baştan imkânsız kılar ve iki dili anlam uyuşmazlığının görülebileceği yere koyar. 210 mesaj, anahtarlar yapısal olarak özdeş. |
| F2 | Bileşen açıklaması için yön başına bir ARB anahtarı + madde sayısı başına bir cümle kalıbı. | Parçaları Dart'ta birleştirmek Türkçe cümleyi İngilizce söz dizimiyle çıkarmanın yoludur. ICU liste biçimlendirmesi yapmaz, bu yüzden 1/2/3 maddelik üç kalıp var. |
| F3 | Hekimin okuduğu metne programatik harf dönüşümü **hiç** uygulanmıyor. | Dart'ın `toUpperCase`/`toLowerCase`'i yerel duyarsız; `IK-14` yazılan hasta kodu `ık-14` kayıtlıyla asla eşleşmez. `TurkishText` yalnızca eşleştirme ve sıralama için. |
| F4 | Canlı kontrollerde histerezis: yeşile 4 kare, kırmızıya 2 kare. | 10 Hz'de kare kare değerlendirilen kontrol titrer ve titreyen trafik ışığı yoksayılmayı öğretir. Yanlış yeşil pahalı olan yön. |
| F5 | Bilinmeyen eğim geçer sayılmıyor. | Kullanılabilir hareket sensörü olmayan cihaz, görüntü analiziyle telafi edilemeyecek tek kontrolde bedava yeşil alırdı. |
| F6 | Overlay ölçüleri önizlemenin kesri; hiçbir yerde piksel yok. | Aynı model çizim, dokunma testi ve native ROI'leri besliyor; piksel üç kez dönüştürülür ve eninde sonunda kendisiyle çelişir. |
| F7 | Rapor dili uygulama dilinden bağımsız; rapor üreticisi yerelleştirmeyi `BuildContext`'ten değil kendisi çözüyor. | Türkçe arayüz kullanan hekim yurt dışına İngilizce rapor gönderir. |
| F8 | Güven rozeti sonuç ekranının ve raporun **en üstünde**, her renk adından önce. | "A3" okuyup üretime başlayan teknisyen, o adın ne kadar değerli olduğunu söyleyen tek bilgiyi kaybetmiştir. |
| F9 | Golden testler iki dil × iki yazı tipi ölçeği × iki cihaz boyutu (8 varyant/ekran). | Yakalanan hata çeviri değil **taşma**: Türkçe klinik terimler sistematik olarak daha uzun. Yazı tipi ölçeği, lup takan hekimin sistem fontunu büyütmüş olabileceği için. |

## CI/CD

| # | Varsayım | Gerekçe |
|---|---|---|
| G1 | Etiket push'u TestFlight **dahili** testine ve Play **internal taslağına** gider; incelemeye gönderim ve üretime yükseltme elle. | Klinik karar destek aracı: hekimin kurduğu sürümü, etiket değil yayınlamayı seçen bir insan belirlemeli. |
| G2 | Flutter sürümü pinli, `stable` değil. | Kendi kendine ilerleyen araç zinciri alakasız bir sürümü kırık derlemeye çevirir; ayrıca bir sürümü üreten araç zinciri geri bulunabilir olmalı. |
| G3 | `shade_core` için %90 satır kapsama tabanı yayın kapısı. | Renk motoru bu uygulamanın ekrana bakarak denetlenemeyen parçası. |
| G4 | Mağaza metni CI'da otomatik denetleniyor (aşırı iddia yok, sınır ifadesi ve sorumluluk uyarısı zorunlu). | Dürüst pozisyonun sessizce düşmesi en kolay yer mağaza listelemesi: en son yazılır, pazarlama metnidir, kimse mimariye karşı okumaz. |
| G5 | iOS'ta App Store Connect API anahtarı, Apple ID değil. | Apple ID uygulamaya özel şifre ister ve etkileşimsiz işte iki faktöre takılır. |
| G6 | Build numarası `github.run_number`; pazarlama sürümü `pubspec.yaml`. Etiket uyuşmazlığı işi kırar. | Build numarası monotonik ve tekrar kullanılamaz olmalı; hekimin gördüğü numara sürüm kontrolünde durmalı. |
| G7 | Pigeon çıktısı, ARB dosyaları ve skala kütüphaneleri commit'li; CI güncel olduklarını doğruluyor. | Commit'li olmalarının tek faydası, codegen çalıştırmadan okunup derlenebilmeleri — bu da ancak güncelse geçerli. |
| G8 | Play servis hesabına yalnızca test kanallarına yükleme izni verilir. | G1'in teknik karşılığı: izin yoksa kaza olamaz. |
| G9 | `com.nuans.app` ve `example.invalid` adresleri yer tutucu; yayın kontrol listesinde duruyorlar. | Unutulmaması için listede. |

## Araç zinciri kurulduktan sonra (2026-10-22)

Ayrıntılı döküm: [doğrulama günlüğü](verification-log.md).

| # | Varsayım | Gerekçe |
|---|---|---|
| H1 | Flutter 3.47.7 / Dart 3.13.5 pinlendi (önceki tahmin 3.24.5 / 3.5.4 idi). | Gerçek kararlı sürüm; CI'daki üç iş akışının pin'i de hizalandı. |
| H2 | `intl: ^0.20.3`. | `flutter_localizations` bunu şart koşuyor; `^0.19.0` ile çözüm başarısız. |
| H3 | Pigeon sözleşmesinde `dart:typed_data` import edilmiyor. | Pigeon yalnızca kendi import'una izin veriyor; `Float64List` onun export'undan geliyor. |
| H4 | ARB kesme işaretleri üreticide `''` olarak kaçırılıyor. | `use-escaping: true` ICU için doğru ayar (süslü parantez kaçışı gerekiyor) ama kesme işaretini kaçış karakteri yapıyor. Kaçışı üreticiye koymak kaynak tabloyu okunabilir bırakıyor ve kuralı hatırlamak gerekmiyor. |
| H5 | `public_member_api_docs` kapatıldı, gerekçesi `analysis_options.yaml` içinde. | Kural yayımlanan paketler için; buradaki ikisi `publish_to: none`. İstediği 708 yorumun çoğu alan adını tekrar ederdi ve argüman taşıyan yorumları gömerdi. |
| H6 | `lib/` içindeki 71 göreli import paket import'una çevrildi. | very_good_analysis `always_use_package_imports` kullanıyor; ben `prefer_relative_imports` varsaymıştım. |
| H7 | Kullanılmayan 11 bağımlılık park edildi, hangi aşamada geri geleceği yazılı. | Her biri native kod getiriyor: özellik getirmeyen derleme riski. Bu arada `sqlcipher_flutter_libs` 0.6 discontinued, 0.7 `+eol` — şifreleme katmanı karar bekliyor. |
| H8 | `very_good_analysis` 6.0.0'da bırakıldı (11.0.0 mevcut). | Mevcut kural setiyle iki paket temiz; 11'e geçiş ayrı iş kalemi. |
| H9 | Android `applicationId` ve `namespace` = `com.nuans.app`, `minSdk` = 29. | A3'teki karar; `minSdk` 29 çünkü protokol MANUAL_SENSOR + RAW_SENSOR istiyor ve pozlama çözücünün okuduğu dinamik siyah seviye bu seviyeden itibaren güvenilir. |
| H10 | `ShadeCameraPlugin` `MainActivity.configureFlutterEngine` içinde elle kaydediliyor. | Plugin yayımlanmış bir paket değil, uygulamanın kendi kaynağında; üretilen plugin registrant onu bilmiyor. Paket yapmak tek tüketici için sürümleme yükü olurdu. |
| H11 | `CAMERA` izni zorunlu, `manual_sensor` ve `raw` yetenekleri `required="false"`. | Ölçüm uygulamanın kendisi, kamerasız gösterilecek bir şey yok. Yetenekleri zorunlu işaretlemek sınırlı modda ölçebilecek cihazları kurulumdan dışlardı. |
| H12 | `RadioGroup` kullanılıyor, `RadioListTile.groupValue`/`onChanged` değil. | Flutter 3.32'den beri deprecated; yepyeni kodda deprecated API kullanmak tercih değil hata. |
| H13 | `XyzColor.weightedMean` statik metot yerine factory constructor. | Lint haklıydı ve çağrı sözdizimi değişmedi. |
| H14 | Release derlemesi, `android/key.properties` gelene kadar debug anahtarıyla imzalanıyor. | Telefona kurulur, Play'e yüklenemez — gözden geçirilmemiş bir derleme için doğru olan yön bu. |

## APK telefona kurulduktan sonra (2026-10-22)

Kullanıcının bildirdiği iki hata — "kameraya bağlanmıyor, görüntü gelmedi" ve
"herhangi bir menüye tıklayınca geri dönemiyorum, uygulamadan çıkıyor" — bu
bölümün tamamının sebebi. İkisi de statik incelemeyle görülmemişti; biri
uygulamayı çalıştırmakla, diğeri o hatayı ararken kodu okumakla bulundu.

| # | Varsayım | Gerekçe |
|---|---|---|
| I1 | Alt ekranlara `context.push`, asla `context.go` ile gidilir; kural `app_router.dart`'ın başında yazılı. | `go` üst düzey bir rota için yığını **değiştirir**; geri gidilecek sayfa kalmaz ve sistem geri tuşu uygulamayı kapatır. Bildirilen hata tam buydu. `push` ayrıca AppBar'a geri okunu hiçbir şey bağlamadan kazandırır. |
| I2 | `createAppRouter()` fonksiyon, tek bir global `GoRouter` değil. | Paylaşılan router, bir testin bıraktığı rotayı sonrakine taşır — navigasyon regresyonunun saklanma yolu tam olarak budur. |
| I3 | Android kamera katmanı üç thread kullanır: kontrol, çerçeve geri çağrıları, kare kopyalama. | [ADR-0002](adr/0002-android-camera-threading.md). Tek thread kilitleniyordu. |
| I4 | Platform kanalına gönderilen olaylar ana thread'e aktarılır; host çağrılarının cevapları aktarılmaz. | `FlutterJNI.dispatchPlatformMessage` ilk iş olarak `ensureRunningOnMainThread()` çağırıyor (sınıf dosyası ayrıştırılarak doğrulandı); `invokePlatformMessageResponseCallback` ise okuma kilidi alıyor ve thread şartı koymuyor. Yani olaylar istisna fırlatırdı, cevaplar fırlatmaz. |
| I5 | Kameranın açılması 5 s, oturum yapılandırması 5 s, bir ayarın kareye yansıması 1,5 s ile sınırlı. | Camera2 bu çağrılar için üst sınır vermiyor; başka bir uygulamanın tuttuğu cihaz geri çağrıyı hiç cevaplamayabilir. Sağlıklı bir açılış bunların çok altında kalır, dolayısıyla aşılması bir arızadır ve kullanıcıya söylenmesi beklemekten iyidir. |
| I6 | Pozlama çözücüsü sabit bir uyku yerine **iki** yeni kare bekler. | İlk gelen kare yeni istek yola çıktığında zaten pozlanmış olabilir; yalnızca ikincisi yeni ayarları kesin taşır. Eski kod `Thread.sleep(150)` sonrası son kareyi okuyordu ve o kare her turda öncekiydi — çözücü hiçbir şeye yakınsıyordu. |
| I7 | Kamera izni `initialize()` içinde istenir, sözleşmeye ayrı bir metot eklenmez. | Dart tarafı tek bir "bana kamera ver" çağrısı görür ve her platform kendi usulüyle sorar. Eklenti bu yüzden `ActivityAware`: Android izni başka hiçbir yerden isteyemez. |
| I8 | İzin diyaloğu için `androidx` değil çerçeve API'leri (`Context.checkSelfPermission`, `Activity.requestPermissions`) kullanılır. | `minSdk` 29; bu API'ler API 23'ten beri var. Bir bağımlılık eklememek için yeterli sebep. |
| I9 | `PreviewSession` sözleşmeye eklendi: doku kimliği, kare boyutu ve dönüş. | Sözleşmedeki her `NormalizedRect` **kareye** göre normalize; bindirme ise **ekrana** göre. Kamera kareyi sensör yöneliminde yazar. Boyut ve dönüş bilinmezse bindirme, native'in ölçtüğü yerden başka bir yere düşer — hekimin göremeyeceği ve düzeltemeyeceği tek hizalama hatası bu. |
| I10 | iOS dönüşü 90 derece olarak bildiriliyor. | AVFoundation, bağlantıya aksi söylenmedikçe tamponları sensör yöneliminde verir ve bu kodda söylenmiyor; iPhone arka kamerasında o yönelim landscape-right. **Cihazda doğrulanmadı.** |
| I11 | ROI'ler önizleme başladıktan sonra bir kez daha gönderilir. | Kare biçimi `startPreview` cevaplayana kadar bilinmiyor, yani ilk yapılandırma zorunlu olarak ekran koordinatlarında gidiyor. İkinci gönderim onu kare koordinatlarına çeviriyor. Bu güncelleme başarısız olursa önizleme düşürülür: yanlış bölgenin sayılarını göstermek, hata göstermekten kötüdür. |
| I12 | Canlı önizleme ekranında çekim düğmesi **yok**. | Cihaz profili olmadan kamera değerlerini renge çeviren matris yok; alınan ölçüm gösterilebilir ama güvenilemez. Profil gerektirmeyen okumalar (netlik, hareket, kırpılma, kart düzgünlüğü, ISO, pozlama) gösteriliyor; renge dayananlar "profil gerekiyor" diye işaretli — sahte yeşil vermemek için `LiveCheckMachine` bu ekranda hiç kullanılmıyor, çünkü renk kararlarını `issues` kümesinden alıyor ve profilsiz o küme boş kalır. |
| I13 | Kamerasız bindirme ekranı kaldı ama adı "Bindirme Tezgâhı" oldu. | Faydası var: yerleşimi ve trafik ışıklarını kamerasız denemeye yarıyor. Ama ana menüde "Ölçüm" diye durması, kullanıcının kamera sanıp açtığı ve hiçbir şey görmediği ekran olmasının sebebiydi. |
| I14 | Telif sahibi `NOTICE` içinde "the Nüans authors" olarak yazılı. | Deponun git kimliğinde tam ad yok; hukuki bir metne tahmin ettiğim bir adı yazmam doğru olmaz. Dağıtımdan önce değiştirilmeli, dosya bunu söylüyor. |
| I15 | Lisans Apache-2.0, yanında `NOTICE`. | Gerekçesi README'nin Lisans bölümünde: 4(d) maddesi, skala değerlerinin ölçüm olmadığı uyarısını forklara taşımaya zorluyor. MIT'te bir fork bu uyarıyı sessizce atabilirdi. |
| I16 | Doku, motorun `registerTexture`/`unregisterTexture` çağrıları gibi ana thread'de oluşturulup bırakılır. | `FlutterJNI`'nin bu metotlarının ilk komutu `ensureRunningOnMainThread()`. Kamera thread'inden çağrılınca istisna fırlıyor ve bir `HandlerThread`'den kaçan istisna süreci öldürüyor — test eden kişide uygulamanın "ses gelip atması" buydu. |
| I17 | Kontrol thread'indeki her posta bloğu `Throwable` yakalar. | Beklenmedik bir istisnanın uygulamayı sessizce yok etmesi, hata olarak bildirilmesinden kötü. Eklentinin `bridge` yorumundaki kuralın aynısı. |
| I18 | `tools/native/check_platform_thread.py` CI'da; korunan sembol yalnızca kendi yardımcısının içinde geçebilir. | Bu hata sınıfı iki kez ısırdı ve native birim testi yok. Nöbetçi, iki hata örneğinde de yakaladığı doğrulanarak eklendi. |

## Kimlik (2026-10-22)

| # | Varsayım | Gerekçe |
|---|---|---|
| J1 | Simge: bir tutacağa asılı üç renk skalası sekmesi. | Uygulamanın yerini tuttuğu nesne bu. Önce çizilmiş bir diş denendi ve bırakıldı: 48 px'te dolu ve bantlı bir diş siluetine değil teneke kutuya benziyor, konikliği ayarlamak da kurtarmadı. Kamera simgesi "fotoğraf uygulaması", renk çarkı ise üç kanalın veremeyeceği bir gam vaat ederdi. |
| J2 | Ortadaki sekme en uzun. | Ritim için değil: tek renk eşleşmesi gövde üçte birinden okunur (`ToothRegion.body`), yani gözün gitmesi gereken yer orası. |
| J3 | Zemin `#37474F`, klinik temanın seed rengi; soğuk ve nötr. | Renk, nötr bir çevreye karşı değerlendirilir, başka bir renge karşı değil. Çekim ekranını gri tutan gerekçenin aynısı simgenin zeminini de seçiyor. |
| J4 | Sekme tonları dekoratif; **skala değeri değil.** | Sıcak, birbirine yakın ve 48 px'te ayrışacak kadar uzak seçildiler — tipografik bir kısıt, kolorimetrik değil. Gerçek skala kütüphaneleri `assets/shade_libraries` içinde ve onlar da doğrulanmamış iskelet olarak işaretli. |
| J5 | Asıl simge adaptive icon; eski bitmap yalnızca yedek. | `minSdk` 29, yani kurulduğu her cihaz simgeyi kendisi maskeliyor. |
| J6 | İşaret adaptive tuvalin %72'sine sığdırılıyor ve bu bir testle kanıtlanıyor. | 108 dp'lik tuvalin yalnızca ortadaki 72 dp'si kesin görünür; yuvarlak maske onu daire olarak içine alır. Göz kararı yetmez: %75'te işaret merkezden 36,3 dp uzanıyordu, sınır 36,0. Test bunu yakaladı. |
| J7 | Açılış ekranı aynı zemin ve aynı işaret, gece için ayrı dosya yok. | Zemin zaten koyu nötr; açık bir açılış, Flutter çizmeden önce ekranın beyaz parlaması demek olurdu. |
| J8 | Varlıklar `tools/branding/generate_icons.dart` ile üretiliyor, elle çizilmiyor. | Deponun diğer üretilmiş dosyalarıyla aynı gerekçe: işaret kod olarak incelenebilir, bir oran değişince hiçbir yoğunluk geride kalmaz ve depoda olmayan bir tasarım dosyasını kimsenin saklaması gerekmez. Tazelik kontrolü macOS işinde, çünkü çıktı rasterize görüntü. |
| J10 | İşaret uygulama içinde yalnızca ana ekranın başlığında, kendi koyu zeminini taşıyan bir rozet olarak kullanılıyor. | Sekme tonları simgenin koyu zemini için seçildi; klinik temanın açık yüzeyinde kaybolurlardı. Rozet ayrıca uygulamanın kendi işareti gibi okunuyor, serbest duran sekmeler ise bir şeyin çizimi gibi okunurdu. |
| J11 | **Çekim ekranında rozet yok.** | O ekran hastanın karşısındaki ikinci en parlak yüzey ve yüzeyleri kasten sıfır doygunlukta; sıcak bir işaret dişten yansıyıp ölçüme girerdi. Gri temayı seçen kural rozeti dışarıda tutuyor. |
| J9 | iOS simgesi yok. | `ios/Runner` altında Xcode projesi, Info.plist ve varlık kataloğu yok; koyacak yer yok. |
