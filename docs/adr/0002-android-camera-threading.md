# ADR-0002: Android kamera katmanı üç thread kullanır

- Durum: kabul edildi
- Tarih: 2026-10-22
- Bağlam: kullanıcı APK'yı kurdu, kamera hiç açılmadı

## Karar

`Camera2SessionController` üç `HandlerThread` kullanır:

| Thread | İşi | Bloklanabilir mi |
|---|---|---|
| `nuans-camera` | Kontrol. Her host çağrısı buraya seri hale getirilir. | **Evet** |
| `nuans-camera-callbacks` | Cihaz, oturum ve çekim durumu geri çağrıları. | Hayır |
| `nuans-camera-frames` | `ImageReader` dinleyicileri: kare kopyalama. | Hayır |

Dart'a gönderilen olaylar ayrıca ana thread'e aktarılır.

## Sebep

Hepsi tek thread'deydi ve bu üç ayrı yolla kırıyordu.

**1. Kilitlenme.** `openCamera`, `manager.openCamera(id, callback, cameraHandler)`
çağırıp aynı `cameraHandler` üzerinde `latch.await()` ile bekliyordu. Bekleyen
thread, beklediği şeyi teslim etmesi gereken thread'in kendisiydi. Kamera asla
açılmadı, `initialize()` hiç dönmedi, Dart hiç cevap almadı.
`configureSession` birebir aynı desendeydi.

**2. Kare açlığı.** Pozlama çözücüsü `startRepeating()` sonrası
`Thread.sleep(150)` ile bekleyip `latestPreview`'ı okuyordu. Kareyi yazan
`ImageReader` dinleyicisi de aynı handler'daydı: uyku boyunca mesaj kuyrukta
bekliyor, uykudan sonra okuma hâlâ aynı mesajın içinde olduğu için yeni kare
*henüz işlenmemiş* oluyordu. Her tur önceki turun karesini ölçüyordu.

**3. Olaylar hiç gitmiyordu.** `events?.onPreviewMetrics(...)` arka plan
thread'inden çağrılıyordu. `DartMessenger.send`, `FlutterJNI`'nin
`dispatchPlatformMessage` metodunu doğrudan çağıran thread üzerinde çalıştırır ve
o metodun ilk komutu `ensureRunningOnMainThread()`. Yani trafik ışıklarını besleyen
her olay istisna fırlatırdı. (Bu, makinede `javap` olmadığı için sınıf dosyası
ayrıştırılarak doğrulandı; aynı incelemede
`invokePlatformMessageResponseCallback`'in okuma kilidi aldığı ve thread şartı
koymadığı görüldü — bu yüzden host çağrılarının cevapları aktarılmıyor.)

## Neden iki değil üç

Kilitlenme ve açlık, tek bir ek thread ile de çözülürdü. Üçüncüsü başka bir
sebeple var: kare kopyalamak bu thread'lerin üzerindeki tek pahalı iş. Durum
geri çağrılarıyla aynı thread'i paylaşsa, bir seri çekim sırasındaki tam boy
RAW kopyaları (her biri ~24 MB) oturum geri çağrılarını geciktirebilir; ham
okuyucunun tamponu seri çekim uzunluğu + 1 olduğu için de ters yönde kare
düşürme riski doğar. Ayırmak bedava, kuplajı kaldırıyor.

## Sonuçları

- Thread'ler arası geçen her alan `@Volatile` ya da `frameLock` ile korunuyor.
- Önizleme kareleri `frameLock` altında; `previewFrameCount` sayacı sayesinde
  kontrol thread'i *yeni* bir kare bekleyebiliyor (bkz. varsayım I6).
- Seri çekimin indirgemesi kontrol thread'ine geri atılıyor: son kare kare
  thread'inde gelir, megapiksellik indirgemeyi orada yapmak kare teslimini
  indirgeme boyunca durdururdu.
- Bekleyişlerin hepsi zaman aşımlı (I5); cevapsız bir cihaz artık süresiz
  beklemek yerine hata veriyor.
- `dispose` üç thread'i de durduruyor ve `frameLock`'u uyandırıyor.

## Doğrulanmadı

Bu makinede bağlı Android cihaz yok. Kod derleniyor, sözleşmeye uyuyor ve
kilitlenmenin sebebi kesin; ama hiçbir karenin gerçekten aktığı görülmedi.
Ekranın "Kamera açıldı ama kare gelmiyor." mesajı tam bu belirsizliği ayırt
etmek için var.
