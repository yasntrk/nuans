# Nüans / Nuans — Aşama 2: Algoritma ve iş akışı

Durum: taslak (Aşama 2 çıktısı)
Kapsam: sensör pikselinden reçeteye kadar her adımın formülü, gerekçesi ve kaynağı.
Önceki aşama: [Aşama 1 mimari](01-architecture.md) · İlgili karar: [ADR-0001](../adr/0001-color-math-boundary.md)

Bu belge Aşama 3'te yazılacak `shade_core` kodunun spesifikasyonudur. Her sabit
§15'teki tabloda isimlendirilmiş ve kaynaklandırılmıştır; kodda çıplak sayı olmayacak.
Kaynağı literatür olmayan, benim seçtiğim değerler **(karar)** ve saha verisiyle
doğrulanması gereken değerler **(placeholder)** olarak işaretlidir.

---

## 1. Gösterim ve değişmezler

| Sembol | Anlam | Uzay |
|---|---|---|
| `v` | ham sensör değeri | tamsayı, 0..2^b−1 |
| `B`, `W` | siyah seviye, beyaz seviye | sensör birimi |
| `p` | normalize sensör sinyali | [0, 1] |
| `c = (c_R, c_G, c_B)` | süperpiksel, doğrusal kamera uzayı | [0, 1]³ |
| `k = (k_R, 1, k_B)` | gri kart von Kries kazançları | — |
| `M` | 3×3 renk düzeltme matrisi (CCM) | kamera → XYZ |
| `σ` | pozlama ölçek katsayısı | — |
| `T = σ · M · diag(k)` | **çekim dönüşümü** | kamera → XYZ |
| `XYZ` | tristimulus, mükemmel difüzör `Y = 1` | D65, 2° |
| `Lab` | CIELAB | D65, 2° |

**Değişmezler** (Aşama 3'te birim test olarak yazılacak):

1. `W > B`; `p = clamp((v − B) / (W − B), 0, 1)`.
2. `M · (1,1,1)ᵀ = (Xn, 1, Zn)` — CCM beyaz noktayı korur, bu bir kısıt değil bir
   tanımdır (§6.2). Sonucu: dengelenmiş nötr bir süperpiksel **tam olarak** `a* = b* = 0`
   verir.
3. `T` bir çekim boyunca sabittir; her ROI, her süperpiksel aynı `T` ile dönüştürülür.
   ROI'ler arası karşılaştırmanın anlamlı olmasının tek sebebi budur.
4. Ortalama **her zaman doğrusal XYZ'de** alınır, asla Lab'da.
5. Tüm iç hesap `double`; toplama sırası sabit (§14).

---

## 2. Uçtan uca iş akışı ve kapılar

```
N1  pozlama çözümü ve kilitler          (native)   → kapı G1
N2  3 karelik burst                     (native)
N3  kare seçimi                         (native)   → kapı G2
N4  seviye normalizasyonu               (native)
N5  Bayer 2×2 süperpiksel               (native)
N6  kırpılma maskesi                    (native)
N7  ızgara örnekleme + kare ortalaması  (native)
--- Pigeon sınırı: doğrusal kamera RGB üçlüleri ---
D1  doğrusallaştırma (yalnız işlenmiş yol)
D2  gri kart doğrulaması                           → kapı G3
D3  von Kries kazançları + mutlak Y çapası
D4  CCM → XYZ
D5  süperpiksel başına Lab
D6  yansıma/gölge filtresi
D7  %10–90 kesilmiş ortalama (XYZ) → Lab
D8  bağıl mod global düzeltmesi                    → uyarı W1
D9  eşleştirme: top-3 + bileşenler
D10 karışım: ızgara araması                        → kapı G4
D11 reçete üretimi (Aşama 5)
D12 güven skoru                                    → sert kapılar
D13 kalıcılaştırma + PDF
```

Kapılar (bunlardan biri kapalıysa akış ilerlemez):

| Kapı | Koşul | Davranış |
|---|---|---|
| G1 | ISO = ISO_min, enstantane çözüldü, AF/AE/AWB kilitli | kilit kurulamazsa `CameraErrorCode.*LockFailed`, çekim yok |
| G2 | en az 1 kare kabul edildi | hiçbiri değilse çekim tekrarı istenir |
| G3 | gri kart doğrulaması geçti (§5.1) | geçmezse **çekim butonu hiç aktif olmaz** |
| G4 | en iyi tek renk ΔE00 > 0.8 **ve** yuvarlanmış karışım ≥ 0.3 iyileştirme | sağlanmazsa karışım önerilmez |
| Sert | profil yok ∧ DNG yok · gri kart başarısız · atılan oran > 0.5 · örnek < 64 | güven zorla **Düşük** |

---

## 3. Native aşama (N1–N7)

### 3.1 Pozlama çözümü (N1)

Sensör doğrusaldır ve `p ∝ ISO · t`. ISO en düşük değere sabitlenir (okuma gürültüsü
en az, dinamik aralık en geniş). Enstantane `t`, gri kartın hedef sinyale oturacağı
şekilde çözülür:

```
t_{n+1} = clamp( t_n · (p_target / p̄_card,n), t_min, t_max )
```

`p̄_card,n` = gri kart ROI'sinin yeşil kanal medyanı, `p_target = 0.45` **(karar)**.
Kart %18 yansıtan bir yüzeydir; 0.45'e oturtmak dişin (yansıtması ~%60–70, artı yüzey
yansımaları) kırpılmadan ~1.3 stop başlık bırakması demektir.

En çok 3 iterasyon. Her iterasyondan sonra iki koşul denetlenir:

```
kırpılma(diş ROI)  ≤ 0.01   ve   p̄_card ∈ [0.20, 0.70]
```

Sağlanmazsa `t` tek yönlü düşürülür ve `limitationCodes` içine `exposureNotSolvable`
eklenir. Doğrusallık varsayımı CMOS sensörlerde bu aralıkta geçerlidir; kırpılmaya
yakın bölge dışlandığı için diz bölgesine girilmez.

### 3.2 Kare seçimi (N3)

Netlik ölçüsü, diş ROI'si üzerinde Laplacian varyansı:

```
L(x,y) = p(x−1,y) + p(x+1,y) + p(x,y−1) + p(x,y+1) − 4·p(x,y)
sharpness = Var[L]  (ROI içinde)
```

Hareket ölçüsü, art arda karelerin normalize ortalama mutlak farkı:

```
motion = mean |p_i(x,y) − p_{i−1}(x,y)| / mean p_i(x,y)
```

Kabul kuralı **hem mutlak hem bağıl** eşik kullanır:

```
accept(i) ⇔ sharpness_i ≥ max(S_min, 0.6 · max_j sharpness_j)
            ∧ motion_i ≤ M_max
            ∧ clipped_i ≤ 0.01
```

Bağıl terimin gerekçesi: `S_min` cihazdan cihaza (lens, çözünürlük, gürültü) değişir;
burst içindeki en iyi kareye göre %60 kuralı cihazdan bağımsızdır ve burst'ün tamamı
bulanıksa yine mutlak eşik devreye girer. `S_min` ve `M_max` **placeholder**: cihaz
başına kalibrasyon sırasında ölçülecek.

### 3.3 Normalizasyon, süperpiksel, kırpılma (N4–N6)

```
p = clamp((v − B) / (W − B), 0, 1)
```

2×2 Bayer bloğu (RGGB düzeni; diğer düzenlerde kanal eşlemesi değişir, matematik aynı):

```
c_R = p_R
c_G = (p_G1 + p_G2) / 2
c_B = p_B
```

Kırpılma, **ortalama almadan önce, dört ham örnek üzerinde** denetlenir:

```
clipped ⇔ max(p_R, p_G1, p_G2, p_B) > τ_clip     (τ_clip = 0.95)
```

Yeşilleri ortalayıp sonra bakmak, kırpılmış tek bir G örneğini gizler; bu yüzden sıra
önemlidir.

Demosaic **yapılmaz**. Gerekçe: demosaic komşu pikselleri karıştıran bir interpolasyon
kestirimidir; 2×2 süperpiksel ise gerçekten ölçülmüş üç kanalın aynı uzamsal konumdaki
değeridir. Bedeli uzamsal çözünürlüğün yarıya düşmesi, ki ROI ortalaması alındığı için
önemsizdir.

### 3.4 Izgara örnekleme ve kare ortalaması (N7)

```
stride = max(1, ceil( sqrt(totalSuperpixels / maxSamplesPerRoi) ))
lattice = { (i, j) : i ≡ 0, j ≡ 0  (mod stride) }        # yalnız geometriye bağlı
mask    = { ızgara noktaları : kabul edilen HİÇBİR karede kırpılmamış }
c̄(i,j) = (1/|F|) · Σ_{f ∈ F} c_f(i,j)                     # kabul edilen kareler
```

`stride`'ın yalnız geometriye bağlı olması zorunludur: hayatta kalan piksel sayısına
bağlanırsa gürültü yüzünden ızgara kareden kareye kayar ve ortalama hizasız olur
(ADR-0001).

Native ayrıca **seyreltilmemiş** kümenin kesin ortalama ve standart sapmasını döner.
Dart bu ikisini karşılaştırarak seyreltmenin yanlılık yaratmadığını denetler:

```
|mean(örnek) − channelMean| ≤ 3 · channelStdDev / sqrt(sampleCount)   ⇒ yanlılık yok
```

---

## 4. Doğrusallaştırma (D1) — yalnızca işlenmiş yol

RAW yolunda değerler zaten doğrusaldır; bu adım atlanır. İşlenmiş (HEIF/JPEG) yolda
8-bit kodlanmış değer `V` için ters sRGB EOTF (IEC 61966-2-1):

```
s = V / 255
p = s / 12.92                        ,  s ≤ 0.04045
p = ((s + 0.055) / 1.055)^2.4        ,  s > 0.04045
```

**Bilimsel dürüstlük notu.** Bu dönüşüm işlenmiş yolu RAW yoluna eşitlemez:

- Telefon ISP'si global bir gamma değil, *yerel* ton eşlemesi uygular; tek bir eğriyle
  tersi alınamaz.
- Doğrusallaştırılmış değerler kamera-doğal değil, sRGB primerlerine indirgenmiştir;
  dolayısıyla bu yolda cihaz CCM'i **kullanılmaz**, standart sRGB→XYZ(D65) matrisi
  kullanılır:

```
M_sRGB = [ 0.4124564  0.3575761  0.1804375
           0.2126729  0.7151522  0.0721750
           0.0193339  0.1191920  0.9503041 ]
```

- Gri kart kazançları ve mutlak Y çapası yine uygulanır; beyaz dengesi ve pozlama hatası
  düzeltilir, ton eşlemesi hatası düzeltilemez.

Sonuç: işlenmiş yol ölçer ama kalibre etmez. Güven skorunda `s_mode = 0.45` ile
cezalandırılır (§13) ve arayüzde "Sınırlı mod" rozeti gösterilir.

---

## 5. Gri kart: doğrulama, von Kries, mutlak çapa (D2–D3)

### 5.1 Doğrulama (kapı G3)

Kart ölçümü kanal başına **medyan** ile alınır (kesilmiş ortalama değil): toz, çizik
ve tek tük parlama medyanı etkilemez, hesabı basit ve testlenebilir tutar.

Çalışan dört ayrım ölçütü:

| # | Ölçüt | Formül | Eşik |
|---|---|---|---|
| V1 | uzamsal tekdüzelik | `σ_spatial(c_G) / mean(c_G)` | ≤ 0.06 **(placeholder)** |
| V2 | sinyal aralığı | `median(c_G)` | ∈ [0.20, 0.70] **(karar)** |
| V3 | karışık ışık | çeyrekler arası maks ikili ΔE00 | ≤ 1.5 **(placeholder)** |
| V4 | ışık kaynağı makullüğü | McCamy CCT | ∈ [4000, 7000] K **(karar)** |

V3 için kartın dört çeyreği, kartın bütününden türetilen kazançlarla düzeltilir ve
Lab'a çevrilir; çeyrekler arasında renk farkı varsa sahnede iki farklı ışık vardır.

V4'te korele renk sıcaklığı McCamy (1992) yaklaşımıyla:

```
n   = (x − 0.3320) / (0.1858 − y)
CCT = 437 n³ + 3601 n² + 6861 n + 5517
```

`x, y` düzeltilmemiş kart ölçümünün profil üzerinden hesaplanan kromatiklik
koordinatlarıdır. Yaklaşım ~2856–6504 K arasında geçerlidir; dışında yalnızca uyarı
üretilir, sayı kullanılmaz.

**Kaldırılan ölçüt ve sebebi.** Brief "düzeltme sonrası a\*, b\* ≈ 0 olmalı" diyor.
Bu çalışma zamanında bir ayrım ölçütü **olamaz**: kazançlar kartı tam olarak nötr yapar
ve CCM beyaz noktayı koruduğu için sonuç yapısal olarak `a* = b* = 0` çıkar — kart
yerine mavi bir kapak çekilse de çıkar. Bu bir *değişmezdir*; Aşama 3'te birim test
olarak doğrulanır (`|a*| < 1e-9 ∧ |b*| < 1e-9`), çalışma zamanı kontrolü olarak değil.
Gerçek ayrım V1–V4'tedir.

### 5.2 von Kries kazançları

```
k_R = c̄_G / c̄_R ,   k_G = 1 ,   k_B = c̄_G / c̄_B
c' = diag(k) · c
```

Yeşili çapa almanın sebebi: Bayer dizilimde yeşil örnek sayısı iki katıdır, yani en iyi
SNR'a sahiptir; ölçeği ona bağlamak gürültüyü en az büyütür.

### 5.3 Mutlak L\* çapası

Değişmez 2 gereği `M · (1,1,1)ᵀ = (Xn, 1, Zn)`, yani dengelenmiş kart `c̄_G · (Xn, 1, Zn)`
değerine gider ve `Y = c̄_G` olur. Kartın bilinen yansıtması `Y_card` ise:

```
σ = Y_card / c̄_G                      (Y_card = 0.18)
T = σ · M · diag(k)
XYZ = T · c
```

Böylece `L*_card = 116·(0.18)^{1/3} − 16 = 49.50` olur ve **mutlak parlaklık sabitlenir**:
aynı diş, iki farklı ışıkta, iki farklı pozlamada aynı `L*` verir. Pozlama hatası
`σ` içinde yutulur.

`Y_card = 0.18` **placeholder**: "%18 gri" kartların gerçek `Y` değeri 0.17–0.19
arasında değişir ve spektral olarak tam düz değildir; fiziksel kartın veri sayfasından
okunup profile yazılmalıdır.

---

## 6. Cihaz profili: CCM uydurma (D4)

### 6.1 Nötr yamalardan kazanç

24 yamalı tablonun nötr satırındaki `J` yama (White 9.5 … Black 2) kullanılır. Her nötr
yamada `R = G = B` olması gerektiğinden, kanal başına en küçük kareler:

```
k_c = ( Σ_{j∈J} c_{j,c} · c_{j,G} ) / ( Σ_{j∈J} c_{j,c}² )
```

Tek bir beyaz yama yerine tüm nötr satır kullanılır; ifade parlak yamalara doğal olarak
daha çok ağırlık verir (SNR ile orantılı), ayrıca tek bir yamanın kırpılması veya
tozlanması sonucu bozmaz. Kırpılmış yamalar kümeden çıkarılır.

Ölçek: beyaz yamanın referans `Y_w` değeri üzerinden `ĉ_i = (Y_w / c'_{w,G}) · c'_i`,
yani mükemmel difüzör `(1,1,1)` okur.

### 6.2 Beyaz noktayı koruyan kısıtlı en küçük kareler

`X` = (N×3) ölçülen `ĉ_i` satırları, `y_r` = referans XYZ'nin `r`. bileşeni,
`w = (Xn, 1, Zn)`. Her satır bağımsız çözülür:

```
minimize ‖X a − y_r‖²    s.t.   1ᵀa = w_r
```

Tek eşitlik kısıtı olduğu için kapalı çözüm vardır (KKT):

```
G    = XᵀX
a_u  = G⁻¹ Xᵀ y_r                                  # kısıtsız çözüm
a    = a_u + G⁻¹1 · (w_r − 1ᵀa_u) / (1ᵀ G⁻¹ 1)     # kısıtlı düzeltme
```

Yalnızca 3×3 bir ters alma gerekir; iteratif çözücü, öğrenme oranı, yakınsama kontrolü
yok — tamamen deterministik ve tek testle kapatılabilir. `M`'in satırları `aᵀ`'lerdir.

Ağırlıklı varyant `W` köşegen matrisiyle `G = XᵀWX`, `Xᵀy → XᵀWy` olarak desteklenir;
varsayılan `W = I` **(karar)**. `1/max(Y, Y_floor)` ağırlığı koyu yamaların etkisini
eşitler ama gürültüyü de büyütür; varsayılan kapalı, sabit olarak tanımlı.

### 6.3 Uyum kalitesi ve kapı

Her yama için `Lab(M ĉ_i)` ile referans `Lab_i` arasında ΔE00; ortalama ve maksimum
raporlanır ve profile yazılır.

```
mean ΔE00 > 2.0  ⇒  kullanıcı tekrar çekime yönlendirilir
```

### 6.4 D50 → D65 (Bradford)

Referans değerler D50 ise:

```
M_BFD = [ 0.8951  0.2664 −0.1614
         −0.7502  1.7135  0.0367
          0.0389 −0.0685  1.0296 ]

(ρ,γ,β)_src = M_BFD · w_D50 ,  (ρ,γ,β)_dst = M_BFD · w_D65
M_CAT = M_BFD⁻¹ · diag( ρ_dst/ρ_src, γ_dst/γ_src, β_dst/β_src ) · M_BFD
XYZ_D65 = M_CAT · XYZ_D50
```

`M_BFD⁻¹` **kodda sayısal olarak hesaplanır**, elle yazılmaz: transkripsiyon hatası
riski yok ve `M_BFD · M_BFD⁻¹ = I` tek testle doğrulanır.

### 6.5 Profil yoksa: DNG yedeği

`ForwardMatrix1` varsa doğrudan kamera→XYZ(D50) olarak kullanılır, Bradford ile D65'e
uyarlanır. Yoksa `ColorMatrix1` tersi alınır. Her iki durumda `s_profile = 0.3` (§13)
ve arayüzde düşük güven rozeti. Üretici matrisleri tek bir numune cihazdan türetilmiş
ortalamalardır; bireysel cihaz sapmasını içermez, bu yüzden yedektir, eş değer değil.

---

## 7. XYZ ↔ Lab ↔ LCh (D5)

CIE 15:2004, D65 2° gözlemci. Beyaz nokta `Xn = 0.95047, Yn = 1.0, Zn = 1.08883`
(ASTM E308 / sRGB spesifikasyonu). CIE 15:2004'ün `0.95043 / 1.08890` değerleri ~%0.004
farklıdır, yani ΔE00 düzeyinde ölçülemez; tek bir kaynak seçip her yerde ona bağlı
kalmak önemlidir — bu projede ASTM E308.

```
ε = 216/24389 ≈ 0.008856     κ = 24389/27 ≈ 903.2963

f(t) = t^{1/3}                      , t > ε
f(t) = (κ t + 16) / 116             , t ≤ ε

L* = 116 f(Y/Yn) − 16
a* = 500 ( f(X/Xn) − f(Y/Yn) )
b* = 200 ( f(Y/Yn) − f(Z/Zn) )
```

Rasyonel sabitler (`216/24389`, `24389/27`) ondalık yuvarlamalar yerine kullanılır;
yoksa `L*` eşiğinde küçük bir süreksizlik oluşur.

Ters dönüşüm (karışımda ve yuvarlama testlerinde gerekir):

```
fy = (L* + 16)/116 ,  fx = fy + a*/500 ,  fz = fy − b*/200
t³ > ε  ⇒  t_i³   ;   aksi halde  (116 t_i − 16)/κ
```

LCh:

```
C* = sqrt(a*² + b*²)
h  = atan2(b*, a*) · 180/π   (mod 360)
```

Gidiş-dönüş testi: `Lab → XYZ → Lab` farkı `< 1e-10`.

---

## 8. Sağlam ROI istatistiği (D6–D7)

Girdi: ROI'nin `n` süperpiksel üçlüsü. Çıktı: tek bir `Lab` + kalite ölçüleri.

```
1.  XYZ_i = T · c_i                     her örnek, aynı çekim dönüşümü
2.  L*_i  = 116 f(Y_i / Yn) − 16        yalnız L* gerekir, tam Lab değil
3.  med   = median(L*)
    MAD   = median( |L*_i − med| )      ÖLÇEKLENMEMİŞ
4.  S = { i :  med − 3.0·MAD ≤ L*_i ≤ med + 2.5·MAD }
5.  S'yi (L*_i, i) ikilisine göre artan sırala              → deterministik sıra
    m = |S| ,  lo = floor(0.10 m) ,  hi = ceil(0.90 m)
    XYZ̄ = (1/(hi−lo)) · Σ_{rank ∈ [lo, hi)} XYZ_i           aritmetik ortalama, XYZ'de
6.  Lab = toLab(XYZ̄)
7.  sakla: rejectedFraction , σ(L*|S) , |S|
```

### 8.1 MAD ölçeklenmemiştir — ve bunun sonucu

Yaygın kullanımda MAD, `σ` kestirimi olması için 1.4826 ile çarpılır. Brief'in 2.5 ve 3.0
çarpanları **ham MAD** birimindedir, bu belgede ve kodda öyle kalıyor. Normal dağılım
için `MAD ≈ 0.6745 σ` olduğundan eşikler gerçekte şu demektir:

```
üst eşik : med + 2.5·MAD = med + 1.686 σ   →  üst kuyruk  %4.6
alt eşik : med − 3.0·MAD = med − 2.024 σ   →  alt kuyruk  %2.2
toplam atılan (yansıma hiç yoksa)          ≈  %6.7
```

Yani **tamamen homojen bir ROI'de dahi örneklerin ~%7'si atılır.** Bu bir hata değil,
eşiklerin agresifliğinin doğal sonucudur: yansımayı kaçırmamak için biraz sağlam veri
feda edilir. Önemli sonuç, güven skorunun bunu bilmesi gerektiğidir — %7 atılma oranı
alarm değildir, taban çizgisidir (§13, `s_rejected` eşiği 0.12'den başlar).

`rejectedFraction` tanımı **(karar)**: kırpılma + MAD filtresi. Kesme (%10–90) hesaba
katılmaz, çünkü kesme bir *red sinyali* değil sabit oranlı bir kestirim yöntemidir;
dahil edilse oran her zaman ≥ %20 görünür ve bilgi taşımaz. Temiz bir Gauss ROI'sinde
zincirin tamamı örneklerin ~%75'ini ortalamaya alır.

### 8.2 Sıralama ve asgari örnek

Kesme bir sıra istatistiğidir, dolayısıyla sıralama deterministik olmalıdır. Dart'ın
`List.sort` fonksiyonu **kararlı değildir**; eşit `L*` değerlerinde sıra değişebilir.
Bu yüzden karşılaştırma anahtarı `(L*, latticeIndex)` ikilisidir: sıra tamdır, algoritma
kararlılığından bağımsız olarak tekrarlanabilir.

```
|S| < 64            ⇒ ROI geçersiz, ölçüm reddedilir
rejectedFraction > 0.5 ⇒ ROI geçersiz (yanlış yerleşim / aşırı yansıma şüphesi)
|S| < 256           ⇒ güven düşürülür
```

64 sınırının gerekçesi standart hata değil temsiliyettir: medyan ve MAD'in kendisi 64
örneğin altında kararsızlaşır ve ROI'nin yarısı atılmışsa ölçülen şey artık diş değildir.

---

## 9. Bağıl mod global düzeltmesi (D8)

Hekim fiziksel skala tabını aynı karede tutar. Tabın ölçülen değeri `XYZ_t`, klinik
kütüphanedeki değeri `XYZ_ℓ`. Fark, çekimin tamamını etkileyen global bir sapmadır
(kalan ışık kayması, profil hatası, pozlama hatası).

Düzeltme **Bradford koni uzayında** uygulanır, doğrudan XYZ'de değil:

```
ρ_t = M_BFD · XYZ_t ,  ρ_ℓ = M_BFD · XYZ_ℓ
r_c = clamp( ρ_ℓ,c / ρ_t,c , 0.90 , 1.111 )       c ∈ {ρ, γ, β}
XYZ_corrected = M_BFD⁻¹ · diag(r) · M_BFD · XYZ
```

Gerekçeler:

- **Çarpımsal, Lab'da çıkarmalı değil:** baskın global hata modu ışık/pozlama hatasıdır
  ve o fiziksel olarak çarpımsaldır. Lab'da fark çıkarmak hiçbir fiziksel hataya
  karşılık gelmeyen bir ton kayması üretir.
- **Koni uzayında, XYZ'de değil:** von Kries uyarlamasının doğru formülasyonu konidir;
  XYZ oranı birinci derece bir basitleştirmedir ve Bradford matrisi elimizde olduğu için
  bedava olarak doğrusu yapılabilir.
- **Sınırlama ±%10:** hatalı bir tab okuması ölçümü bozamaz.

Uygulama kararı tabın kendi hatasına bağlıdır **(karar)**:

| `ΔE00(t, ℓ)` | Davranış |
|---|---|
| ≤ 3.0 | düzeltme uygulanır, `s_relative = 1.0` |
| > 3.0 | **uygulanmaz**, `relativeModeTabMismatch` uyarısı (W1), `s_relative = 0.3` |

3 ΔE00'ı aşan bir fark bilinen bir tabda ölçüm, kütüphane veya ışık tarafında bir hata
demektir; o farkla "düzeltmek" hatayı dişe taşımak olur.

Bağıl modun ikinci çıktısı doğrudan klinik değere sahiptir: diş ile tab arasındaki ΔE00
hiçbir kütüphaneye, profile veya CCM'e güvenmeden raporlanır — aynı karede, aynı ışıkta,
aynı dönüşümle ölçülmüş iki yüzeyin farkıdır.

---

## 10. CIEDE2000 (D9 çekirdeği)

CIE 2001 / ISO 11664-6, `kL = kC = kH = 1`. Referans (standart) = aday renk,
numune = ölçülen diş; bileşen işaretleri bu yüzden "diş, adaydan şu kadar ..." diye
okunur.

```
C1*  = sqrt(a1² + b1²) ,  C2* = sqrt(a2² + b2²) ,  C̄* = (C1* + C2*)/2
G    = 0.5 · ( 1 − sqrt( C̄*⁷ / (C̄*⁷ + 25⁷) ) )
a1'  = (1 + G) a1 ,  a2' = (1 + G) a2
C1'  = sqrt(a1'² + b1²) ,  C2' = sqrt(a2'² + b2²)
h1'  = atan2(b1, a1') mod 360        (a1' = b1 = 0 ise h1' = 0)
h2'  = atan2(b2, a2') mod 360

ΔL'  = L2 − L1
ΔC'  = C2' − C1'
Δh'  = 0                       , C1'C2' = 0
     = h2' − h1'               , |h2' − h1'| ≤ 180
     = h2' − h1' − 360         , h2' − h1' >  180
     = h2' − h1' + 360         , h2' − h1' < −180
ΔH'  = 2 sqrt(C1' C2') sin(Δh'/2)

L̄'   = (L1 + L2)/2 ,  C̄' = (C1' + C2')/2
h̄'   = h1' + h2'                     , C1'C2' = 0
     = (h1' + h2')/2                  , |h1' − h2'| ≤ 180
     = (h1' + h2' + 360)/2            , |h1' − h2'| > 180 ∧ h1' + h2' <  360
     = (h1' + h2' − 360)/2            , |h1' − h2'| > 180 ∧ h1' + h2' ≥ 360

T    = 1 − 0.17 cos(h̄' − 30°) + 0.24 cos(2h̄')
         + 0.32 cos(3h̄' + 6°) − 0.20 cos(4h̄' − 63°)
Δθ   = 30 · exp( −((h̄' − 275°)/25)² )
R_C  = 2 sqrt( C̄'⁷ / (C̄'⁷ + 25⁷) )
S_L  = 1 + 0.015 (L̄' − 50)² / sqrt( 20 + (L̄' − 50)² )
S_C  = 1 + 0.045 C̄'
S_H  = 1 + 0.015 C̄' T
R_T  = − sin(2Δθ) · R_C

ℓ = ΔL'/(kL S_L) ,  c = ΔC'/(kC S_C) ,  h = ΔH'/(kH S_H)
ΔE00 = sqrt( ℓ² + c² + h² + R_T · c · h )
```

Dikkat edilecek üç tuzak — Sharma/Wu/Dalal (2005) veri setinin özellikle sınadığı yerler:

1. `h̄'` ortalaması 0°/360° sınırını geçerken; yukarıdaki dört kollu tanım zorunludur.
2. `C1'C2' = 0` durumları (nötr renkler): `Δh' = 0` ve `h̄' = h1' + h2'`.
3. `C̄*⁷` ve `25⁷` büyük sayılardır; `25⁷ = 6103515625` olarak önceden hesaplanmış sabit
   kullanılır, `pow` çağrısı tekrarlanmaz.

Doğrulama: Sharma veri seti 1e-4 toleransla test edilir. Brief'in verdiği tek satır
`(50, 2.6772, −79.7751)` ↔ `(50, 0, −82.7485)` → `2.0425` koda gömülü başlangıç
vektörüdür. **Veri setinin tamamı uydurulmayacak**; Aşama 3'te test dosyası, Sharma'nın
yayımladığı tablodan (Rochester Üniversitesi, CIEDE2000 ek verisi) birebir aktarılacak
ve dosya başında kaynak künyesi bulunacak. Aktarım yapılana kadar test dosyası
`// SOURCE REQUIRED` işaretiyle tek satırla çalışır.

---

## 11. Eşleştirme ve bileşenlerin insan diline çevrilmesi (D9)

Kütüphane ≤ 50 girdi olduğu için arama kaba kuvvettir: her girdi için ΔE00, artan sırala,
ilk 3'ü al. Maliyet 50 × ~40 kayan nokta işlemi; optimize edilecek bir şey yok.

Her sonuç `(kod, ΔE00, ℓ, c, h)` taşır. `ℓ, c, h` **ağırlıklandırılmış** bileşenlerdir
(§10 sonu), yani hepsi ΔE00 birimindedir ve doğrudan karşılaştırılabilir — ham `ΔL'`,
`ΔC'`, `ΔH'` değil. Böylece 0.8 algılanabilirlik eşiği bileşen ölçeğinde de anlamlıdır.

Baskın bileşen `argmax(|ℓ|, |c|, |h|)`. Sözcük seçimi eşikleri **(karar)**:

| `|bileşen|` | Nitelik | Örnek |
|---|---|---|
| < 0.5 | anılmaz | — |
| 0.5 – 1.0 | "biraz" | "biraz daha açık" |
| 1.0 – 2.0 | "daha" | "daha az doygun" |
| > 2.0 | "belirgin şekilde" | "belirgin şekilde daha sarı" |

Yön sözlüğü: `ℓ > 0` açık / `< 0` koyu · `c > 0` daha doygun / `< 0` daha az doygun ·
`h` işareti ton yönünü tek başına belirlemez, bu yüzden ton farkı `h̄'` çeyreğine göre
ifade edilir (sarıya/kırmızıya kayma). Cümleler ICU şablonlarıyla kurulur (Aşama 6);
Dart'ta string birleştirme yapılmaz.

Kabul edilebilirlik eşikleri (ISO/TR 28642 + Paravina ve ark. 2015, %50:%50):

```
ΔE00 ≤ 0.8        : fark edilemez     (yeşil)
0.8 < ΔE00 ≤ 1.8  : kabul edilebilir  (sarı)
ΔE00 > 1.8        : kabul edilemez    (kırmızı)
```

---

## 12. Karışım (D10)

### 12.1 Aday kümesi ve komşuluk

En yakın 4 renk ve **yalnızca** onların yapısal komşuları. En çok 3 bileşen.

Classical (16 renk: A1 A2 A3 A3.5 A4 · B1 B2 B3 B4 · C1 C2 C3 C4 · D2 D3 D4):
komşu = aynı ton ailesi içinde kroma sıralamasında bitişik. `A3 ↔ A3.5` komşudur,
`A3 ↔ B3` **değildir**.

3D-MASTER (29 renk: 0M1–3, 1M1–2, 2/3/4 gruplarında L1.5 L2.5 M1 M2 M3 R1.5 R2.5,
5M1–3): komşu = üç eksenden **tam birinde** bitişik olmak —

```
value  : 2M2 ↔ 3M2        (aynı hue, aynı chroma, bitişik grup)
chroma : 2M1 ↔ 2M2        (aynı value, aynı hue, bitişik kroma)
hue    : 2L1.5 ↔ 2M1.5?   → 3D-MASTER'da M kolonunda 1.5 yok; eşleşme yoksa komşu yok
```

Hue ekseninde `L ↔ M ↔ R` bitişiktir ama kroma kodları kolonlar arasında birebir
örtüşmez (L/R kolonları 1.5 ve 2.5, M kolonu 1, 2, 3 taşır). Bu yüzden hue komşuluğu
**yalnızca aynı kroma kodu her iki kolonda da varsa** tanımlıdır; yoksa kenar yoktur.
Graf, kütüphane JSON'unda açık kenar listesi olarak değil, kod yapısından türetilir ve
Aşama 3'te tam komşuluk tablosu testle sabitlenir.

**Sonuç olarak kabul edilen sınırlama:** aileler arası karışım (A2 + B2) üretilmez.
Pratikte teknisyenler bunu yapar; brief'in kuralı yapısal komşuluğu şart koştuğu için
v1'de dışarıda. Varsayım listesine limitasyon olarak eklendi.

### 12.2 Izgara araması

```
2 bileşen: w ∈ {0, 0.05, ..., 1.00}                        → 21 kombinasyon
3 bileşen: 20 birimin 3 parçaya tüm bölüşümleri, C(22,2)   → 231 kombinasyon / üçlü
XYZ_mix = Σ w_i · XYZ_i          (doğrusal XYZ'de, Lab'da DEĞİL)
ΔE00_mix = ΔE00( toLab(XYZ_mix) , Lab_target )
en küçüğü seç
```

### 12.3 Pratik yuvarlama

%5 adımlı optimum, tartımda uygulanamaz; %10'a yuvarlanır. Yuvarlama **en büyük kalan**
yöntemiyle yapılır ki toplam tam olarak 1 kalsın:

```
u_i = 10 · w_i ;  f_i = floor(u_i) ;  eksik = 10 − Σ f_i
eksik birim, en büyük kesirli parçaya sahip bileşenlere birer birer dağıtılır
```

Yuvarlama bir bileşeni sıfırlayabilir (0.05 → 0.0); o zaman reçete kendiliğinden 2
bileşene düşer. Hem optimum hem yuvarlanmış karışımın ΔE00'ı gösterilir.

### 12.4 Gösterim kapısı (G4)

```
göster ⇔ ΔE00(en iyi tek renk) > 0.8
         ∧ ΔE00(en iyi tek renk) − ΔE00(YUVARLANMIŞ karışım) ≥ 0.3
```

İyileştirme **yuvarlanmış** karışımdan ölçülür **(karar)**: hekimin eline geçecek olan
odur. Optimumla kapı açıp yuvarlanmışla tezgaha çıkmak, kazanılmamış bir iyileştirme
vaat etmek olur.

### 12.5 Modelin dürüst sınırı

Doğrusal XYZ karışımı, yansıma karışımına **birinci derece** bir yaklaşımdır. Gerçek
porselen/kompozit karışımı soğurucu-saçıcı bir ortamda toplanır, çarpımsal ve doğrusal
değildir (Kubelka–Munk, v2). Ayrıca ağırlıklar kütlece oranlardır; kütle oranı ile
yansıma katkısı arasındaki ilişki de doğrusal değildir. Yaklaşımın kabul edilebilir
olmasının tek sebebi bileşenlerin yapısal komşu, yani birbirine çok yakın olmasıdır.
Her reçete bu yüzden "başlangıç önerisidir, şahit numune/test fırınlaması ile
doğrulayın" notuyla çıkar.

---

## 13. Güven skoru (D12)

Yedi alt skor, her biri [0, 1], ağırlıklı toplam. Tüm katsayılar `ConfidenceWeights`
içinde isimlendirilmiş sabitlerdir.

| Alt skor | Formül | Ağırlık | Gerekçe |
|---|---|---|---|
| `s_mode` | RAW = 1.0 · işlenmiş = 0.45 | **0.18** | İşlenmiş yolda ISP'nin yerel ton eşlemesi tersinir değil (§4); bu düzeltilemeyen sistematik bir hatadır. |
| `s_profile` | `clamp(1 − (ΔE̅_ccm − 0.5)/1.5, 0, 1)`; DNG = 0.3; yok = 0 | **0.20** | Profil hatası tüm ölçümlere aynı yönde biner; hiçbir sonraki adım geri alamaz. En yüksek ağırlık. |
| `s_graycard` | `min(s_uniform, s_mixedLight)`, V1/V3 marjlarından | **0.18** | Çekim başına tek mutlak çapa budur; bozulursa `L*` ve beyaz dengesi birlikte kayar. |
| `s_rejected` | `clamp((0.45 − ρ)/(0.45 − 0.12), 0, 1)` | **0.12** | ρ ≤ 0.12 ceza yok (§8.1'deki ~%7 taban çizgisi + marj); 0.45'te sıfır. |
| `s_homogeneity` | `clamp((6.0 − σ_L)/(6.0 − 1.5), 0, 1)` | **0.10** | Dişte gerçek bir gradyan vardır, σ saf gürültü değil; bu yüzden düşük ağırlık. Eşikler **placeholder**. |
| `s_relative` | kullanıldı+uyumlu 1.0 · uyumsuz 0.3 · kullanılmadı 0.5 | **0.10** | Kullanmamak hata değil, bağımsız çapraz kontrolden vazgeçmektir. |
| `s_match` | `clamp((4.0 − ΔE00_best)/(4.0 − 0.8), 0, 1)` | **0.12** | Büyük artık, modelin göremediği bir şeyin varlığına işaret eder (dehidrasyon, translüsensi, yanlış kütüphane). |

```
score = Σ w_i s_i          Σ w_i = 1.00
```

Ağırlık grupları ve mantığı:

- **Ölçümün izlenebilir olup olmadığı** (`mode + profile + graycard = 0.56`): buradaki
  hata sistematik sapmadır, ortalama alarak yok edilemez.
- **ROI rastgele hatası** (`rejected + homogeneity = 0.22`): zaten binlerce örneğin
  ortalamasıyla bastırılıyor, bu yüzden daha az ağırlık.
- **Çapraz kontroller** (`relative + match = 0.22`): ilk iki grubun göremediği hataları
  yakalayan tek mekanizma.

Bantlar: `≥ 0.80` Yüksek · `≥ 0.60` Orta · aksi halde Düşük.

**Sert kapılar.** Ağırlıklı toplamın yapısal zayıflığı, iyi alt skorların ölümcül bir
kusuru maskeleyebilmesidir. Bu yüzden şu koşullardan herhangi biri skoru hesaba
bakılmaksızın **Düşük**'e çeker:

```
profil yok ∧ DNG yok   ·   gri kart doğrulaması başarısız   ·
rejectedFraction > 0.5 ·   |S| < 64                          ·
kabul edilen kare yok
```

İlk ikisi ayrıca çekimi tamamen engeller (G1/G3). Tüm ağırlıklar ve eşikler klinik
olarak ayarlanabilir sabitlerdir ve saha doğrulamasından (Aşama 7) önce **placeholder**
sayılmalıdır: ağırlıkların göreli sıralaması gerekçeli, mutlak değerleri kalibre
edilmemiştir.

---

## 14. Sayısal determinizm

- Tüm aritmetik `double` (IEEE 754 binary64). `num` kullanılmaz.
- Toplama sırası sabit ve tek iş parçacıklı. 4096 terimli saf toplamanın bağıl hatası
  `≲ n·ε ≈ 4096 × 2.2e−16 ≈ 1e−12`; ΔE00 kararına etkisi yok, bu yüzden Kahan
  toplaması kullanılmaz (gerekmeyen karmaşıklık eklenmez).
- Sıralama anahtarı her yerde tam sıra üretir (`(değer, indeks)`), çünkü `List.sort`
  kararlı değildir.
- `atan2`, `pow`, `exp` platform kütüphanesinden gelir; Sharma testi 1e-4 toleransla
  bunların yeterli olduğunu doğrular.
- Rastgelelik yok, zaman bağımlılığı yok, I/O yok: `shade_core`'un tamamı saf
  fonksiyonlardan oluşur ve aynı girdi her zaman aynı çıktıyı verir.

---

## 15. Sabitler tablosu

Kodda isimlendirilmiş sabit olarak tanımlanacak her değer. "Kaynak" sütunu brief'in
5. kuralının gereğidir.

| Sabit | Değer | Kaynak |
|---|---|---|
| `kBayerClippingThreshold` | 0.95 | protokol (brief) |
| `kBurstFrameCount` | 3 | protokol (brief) |
| `kFrameRelativeSharpnessFactor` | 0.60 | **karar** — cihazdan bağımsız kare seçimi |
| `kMinSharpness`, `kMaxMotionScore` | — | **placeholder** — cihaz başına ölçülecek |
| `kExposureTargetGrayLuma` | 0.45 | **karar** — dişe ~1.3 stop başlık |
| `kExposureGrayRange` | [0.20, 0.70] | **karar** |
| `kMaxSamplesPerRoi` | 4096 | ADR-0001 (standart hata hesabı) |
| `kMaxSamplesPerChartPatch` | 512 | ADR-0001 |
| `kGrayCardReflectanceY` | 0.18 | **placeholder** — kart veri sayfasından |
| `kGrayCardUniformityMax` | 0.06 | **placeholder** |
| `kGrayCardQuadrantDeltaEMax` | 1.5 | **placeholder** |
| `kGrayCardCctRange` | [4000, 7000] K | **karar** — önerilen 5500K ışığın etrafı |
| `kMcCamyCoefficients` | 437, 3601, 6861, 5517 | McCamy (1992) |
| `kD65WhitePoint` | (0.95047, 1.0, 1.08883) | ASTM E308 / sRGB spesifikasyonu |
| `kLabEpsilon` | 216/24389 | CIE 15:2004 |
| `kLabKappa` | 24389/27 | CIE 15:2004 |
| `kSrgbToXyzD65` | 3×3 (§4) | IEC 61966-2-1 |
| `kSrgbGammaBreakpoint` | 0.04045 / 12.92 / 0.055 / 2.4 | IEC 61966-2-1 |
| `kBradfordMatrix` | 3×3 (§6.4) | Bradford / Lindbloom; tersi sayısal |
| `kCcmMeanDeltaEGate` | 2.0 | protokol (brief) |
| `kSpecularMadFactor` | 2.5 | protokol (brief), ham MAD |
| `kShadowMadFactor` | 3.0 | protokol (brief), ham MAD |
| `kTrimLowFraction` / `kTrimHighFraction` | 0.10 / 0.90 | protokol (brief) |
| `kMinAcceptedSamples` | 64 | **karar** — medyan/MAD kararlılığı |
| `kLowConfidenceSampleCount` | 256 | **karar** |
| `kMaxRejectedFraction` | 0.50 | **karar** |
| `kRelativeModeClamp` | [0.90, 1.111] | **karar** — ±%10 |
| `kRelativeModeTabDeltaEMax` | 3.0 | **karar** |
| `kImperceptibleDeltaE` | 0.8 | ISO/TR 28642, Paravina 2015 |
| `kAcceptableDeltaE` | 1.8 | ISO/TR 28642, Paravina 2015 |
| `kMixImprovementMin` | 0.3 | protokol (brief) |
| `kMixGridStep` | 0.05 | protokol (brief) |
| `kMixRoundingStep` | 0.10 | protokol (brief) |
| `kMaxMixComponents` | 3 | protokol (brief) |
| `kComponentWordingThresholds` | 0.5 / 1.0 / 2.0 | **karar** — ΔE00 biriminde |
| `kConfidenceWeights` | 0.18/0.20/0.18/0.12/0.10/0.10/0.12 | **placeholder** — §13 gerekçeli, kalibre edilmemiş |
| `kConfidenceBands` | 0.80 / 0.60 | **placeholder** |
| `kCiede2000Pow25_7` | 6103515625 | 25⁷, önceden hesaplanmış |

---

## 16. Matematiğin yapamadıkları

Bunlar çözülecek açık işler değil, modelin yapısal sınırlarıdır; arayüzde ve raporda
gizlenmezler.

1. **Metamerizm görünmez.** Üç kanalla ölçüm yapılıyor, spektrum ölçülmüyor. 5500K
   LED altında eşleşen iki yüzey gün ışığında ayrışabilir ve uygulama bunu öngöremez.
2. **Luther koşulu sağlanmıyor.** Kamera spektral duyarlılıkları, CIE gözlemci
   fonksiyonlarının doğrusal bir dönüşümü değildir; dolayısıyla *hiçbir* 3×3 matris
   tam doğru olamaz. 24 yamalık ortalama ΔE00 tam olarak bu artığı ölçer — CCM'in
   kalite raporu bir "uyum iyiliği" değil, bu temel sınırın niceliğidir.
3. **Translüsensi ölçülmüyor.** Siyah/beyaz zemin ölçümü yapılmadığı için insizal
   translüsensi sezgiseldir ve arayüzde "tahmini" etiketlidir.
4. **Diş Lambertian değil.** CIELAB opak difüz yansıtıcı varsayar; diş yarı saydamdır,
   kenar kaybı (edge loss) nedeniyle ölçülen `L*` ROI boyutuna bağlıdır. Sabit ROI
   geometrisi doğruluk değil **karşılaştırılabilirlik** sağlar.
5. **Gri kart dişin düzleminde değil.** Işık kartın bulunduğu yerde ölçülür; dişin
   eğriliği ve yönelimi farklıdır. Overlay'in merkez kısıtı ve ±5° eğim koşulu bunu
   azaltır, sıfırlamaz.
6. **Dehidrasyon zaman bağımlıdır.** Ekartörden sonra dakikalar içinde `L*` yükselir.
   Bunun algoritmik çözümü yok; çözüm prosedüreldir (seans başında ölç) ve arayüz
   bunu hatırlatır.
