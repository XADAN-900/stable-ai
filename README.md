# Stable AI

Gerçek yapay zekâ ile sohbet eden, **ücretsiz ve anahtarsız** bir chatbot.
Flutter ile yazıldı; internet olmadığında bile çalışır ve **kendini günceller**.

Repo: **XADAN-900/stable-ai**

## Nasıl çalışıyor

Uygulama **önce interneti yoklar** (`lib/net.dart`, sonuç 30 sn önbelleklenir):

1. **İnternet var:** Mesaj ücretsiz, kayıt gerektirmeyen LLM uç noktasına
   gider (`text.pollinations.ai`, API anahtarı yok). İlk motor (OpenAI uyumlu
   POST) cevap vermezse **ikinci motor** (düz metin GET) denenir.
2. **İnternet yok / servis yok:** 25 sn beklemeden **cihazdaki son
   güncellenmiş motor** devreye girer. Bu motor niyet eşleme + yazım hatası
   toleransı + hesap makinesi + saat/tarih + fıkra + bilmece + rastgele
   karar içindir; "başka", "daha detaylı" gibi devam sorularını önceki
   mesajla birleştirerek cevaplar, kısmi eşleşmede konuyu geri sorar.

Sohbet ekranının üstündeki rozet hangi motorun konuştuğunu gösterir
(**Yapay zekâ açık** / **Yerel motor**). Ayarlar → Yapay zekâ bölümünden
LLM modunu tamamen kapatabilirsin.

## Kendini güncelleme

Kaynak: **GitHub Releases**. Depo iki yerden gelir:

- `lib/update.dart` içindeki **`defaultRepo`** = `XADAN-900/stable-ai`
  (uygulama kurulduğu gibi çalışır, kullanıcı bir şey ayarlamaz),
- isteğe bağlı olarak Ayarlar → Güncelleme alanına yazılan depo (bunu
  girersen gömülü olanın yerine geçer).

Hiçbir şey ayarlamadan çalışır.

- **Bilgi tabanı:** açılışta `stable_ai_kb.json` depodan çekilir ve cihaza
  kaydedilir. İnternet yoksa **en son kaydedilmiş (güncellenmiş) hali**
  kullanılır — `lib/knowledge.dart`.
- **Uygulama:** açılışta sessizce `releases/latest` çekilir; etiket kurulu
  sürümden yeniyse **bir kez** teklif edilir ve "İndir ve kur" ile sistem
  kurulum ekranı açılır (`lib/update_flow.dart` + `MainActivity.kt`).
  Android 8+ "Bu kaynaktan izin ver" ekranı çıkarsa uygulama seni oraya
  yönlendirir, izni verip tekrar dene. Ayarlar'dan "Sürümü kontrol et"
  ile de tetikleyebilirsin.

### Yeni sürüm yayınlama

1. `pubspec.yaml` içindeki `version:`'ı büyüt (örn. `1.1.0+2`).
2. Push et: CI APK'yı derleyip otomatik **GitHub Release** olarak yükler
   (`.github/workflows/build.yml`).
3. Kurulu uygulama yeni sürümü görür ve kurar.

> Not: Google Play üzerinden dağıtacaksan kendini güncelleme akışını
> kullanma; Play politikası APK'nın Play dışı güncellenmesini kısıtlar.
> Kendi dağıtımın (APK dosyası, GitHub Release) için uygundur.

## `stable_ai_kb.json` biçimi

```json
{
  "version": 1,
  "tr": [
    { "keys": ["anahtar kelime", "ikinci ifade"], "answers": ["Cevap metni"] }
  ],
  "en": [ ... ],
  "de": [ ... ]
}
```

Boşluklu `keys` ifade olarak, tek kelimeler token olarak eşleşir. Dosya
deponun `main` dalında durur.

## Animasyonlar

- Sayfa geçişleri: belirme + sağdan kayma + ölçek (`fadeSlide`)
- Ana menüde öğelerin sırayla belirmesi, logoda nefes alan vurgu
- Mesaj balonlarının aşağıdan yukarı belirmesi
- "Yazıyor" göstergesinde zıplayan noktalar
- İndirmede ilerleme çubuğu, sürüm diyaloğu

## Özellikler

- Dil: Türkçe / English / Deutsch
- Tema (sistem/açık/koyu), yazı boyutu, geçmişi kaydet, kullanıcı adı
- Yerel motor: niyet eşleme, hesap makinesi, saat/tarih, fıkra, zar, yazı tura

## APK almak (GitHub Actions)

1. **Actions** sekmesi → **Build APK** → bitince **Artifacts → StableAI-apk**.
2. Her push otomatik **GitHub Release** de açar (`v<pubspec sürümü>` etiketi);
   uygulama tam da buradan kendini günceller.

CI, eksik `android/` dosyalarını `flutter create` ile tamamlar, uygulama adını
"Stable AI" yapar, `INTERNET` + `REQUEST_INSTALL_PACKAGES` izinlerini ve
FileProvider'ı ekler, `flutter analyze` ve `flutter test` çalıştırır.

## Bota yeni cevap eklemek

- **Kalıcı (kodla):** `lib/bot.dart` içindeki `_kb` listesine
  `_I(id, [anahtar kelimeler], [cevaplar])` ekle.
- **Uzaktan (kodsuz):** `stable_ai_kb.json` dosyasını güncelle; uygulama
  açılışta çeker, internetsizken de son sürümü kullanır.

## Uyarı

LLM uç noktası bir topluluk servisidir: anahtarsızdır ama hız/erişim garantisi
vermez. Cevap gelmezse uygulama sessizce yerel motora döner; bu normaldir.
