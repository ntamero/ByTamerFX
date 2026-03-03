# Changelog - BytamerFX EA

All notable changes to this project are documented in this file.

---

## [v4.7.5] - 2026-03-03

### PromotionFix — Terfi Sonrasi Grid Yon Guncelleme (KRITIK BUG FIX)

**KRITIK BUG FIX:** GBPUSD'de ANA SELL $9 karda kapandiktan sonra SPM1 BUY yeni ANA'ya terfi etti. Yeni ANA -$13 zararda olmasina ragmen SPM acilamadi. Sebep: `m_gridDirection` eski SELL yonunde kaldi, EA "trend donusu" sanarak `ManageTrendReversal()` cagirdi → `ManageMainInLoss()` hic cagirilmadi → SPM tetiklenemedi. Sonuc: 2 BUY pozisyon savunmasiz -$21'e kadar dustu.

#### 1. Terfi Sonrasi Grid Yon Guncelleme (KRITIK)
- **ESKi:** `PromoteOldestSPM()` grid yonunu (`m_gridDirection`) guncellemiyordu
- Eski ANA SELL kapanir → SPM1 BUY terfi eder → `m_gridDirection` hala SELL
- `ManageTrendGrid()`: mainDir(BUY) != gridDirection(SELL) → `ManageTrendReversal()` → return
- `ManageMainInLoss()` hic cagirilmaz → SPM tetiklenemez → ANA derin zararda kalir
- **YENI:** Terfi aninda `m_gridDirection` yeni ANA'nin yonune guncellenir
- `ManageTrendGrid()` normal akisa girer → ANA zarar esigi astiginda SPM hemen tetiklenir
- Log: `TERFI: Grid yon guncelleme SELL -> BUY (yeni ANA yonune)`

#### Dosyalar
- `Config.mqh`: Versiyon 4.7.5 PromotionFix
- `BytamerFX.mq5`: Versiyon 4.75
- `PositionManager.mqh`: `PromoteOldestSPM()` — grid yon guncelleme eklendi

---

## [v4.7.4] - 2026-03-02

### CryptoFreedom — Crypto Haber Blogu Muafiyeti + MIA Dashboard v7

**KRITIK IYILESTIRME:** BTC -$42'ye dustu ancak haber saati oldugu icin SPM/hedge acilamadi. Haber bittikten sonra -$35'te hala kurtarma islemleri baslayamadi. Crypto icin haber engeli kaldirildi.

#### 1. Crypto Haber Blogu Muafiyeti (KRITIK)
- **ESKi:** USD haberleri (NFP, FOMC, CPI vb.) TUM sembolleri blokluyordu — BTCUSD dahil
- **YENI:** Crypto semboller (`class: "crypto"`) haber saatlerinde trade engeline GIRMEZ
- `_CRYPTO_SYMBOLS` seti `config.SYMBOL_SPECS`'ten otomatik olusturulur
- `_refresh_blocks()`: Crypto semboller `_blocked_symbols`'e eklenmez
- Forex (EURUSD, GBPUSD, USDJPY, AUDUSD) ve metal (XAUUSD, XAGUSD) icin haber blogu aynen devam eder
- Grid genisleme (`get_grid_widen`) crypto icin hala aktif (volatilite koruma)
- Yeni crypto sembol eklendiginde `SYMBOL_SPECS`'te `class: "crypto"` tanimlamak yeterli

#### 2. MIA Telegram Zengin Emoji Formatlama
- Startup mesaji: Emoji basliklar (⚡🏦🔑🏢🖥💰💎⚖️🤖)
- Gunluk rapor: Emoji bolumleri (📊📈📉🏆🎯🟢🔴⚪) + P/L bar gorsellestirme
- Win rate emoji: >=70% 🏆, >=50% 🎯, <50% ⚠️

#### 3. PEAK_DROP Spam Dongusu Fix
- **Bug:** Executor `_refresh_all()` MT5'teki harici pozisyonlari yok sayiyordu
- GridManager pozisyonu goruyordu → PEAK_DROP uretiyordu → Executor bulamiyordu → sonsuz dongu
- **Fix:** Executor artik harici MT5 pozisyonlarini state'e alir (`_detect_role_from_comment()`)

#### 4. Canli Haber Ticker (RSS)
- SentimentEngine'den RSS haberleri dashboard alt ticker'a akar
- Yahoo Finance + CNBC RSS feed'leri eklendi
- 5 kategori: FINANS, SIYASI, DUNYA, EKONOMI, TEKNOLOJI
- Veri yokken 16 adet fallback haber basligi

#### 5. Kapananlar Tab Duzeltmeleri
- Kapanan islem adedi badge eklendi
- Backend `profit`, `close_time`, `open_price`, `close_price`, `volume` alanlari eklendi
- `open_price` acilis deal'den `position_id` eslesimiyle alinir

#### 6. Haftalik/Aylik P/L Cift Sayma Fix
- **Bug:** `calcPeriodPnL(7) + rapDaily` bugunun realize karini iki kez sayiyordu
- **Fix:** `+ rapDaily` yerine `+ floatingNow` (sadece acik pozisyon P/L eklenir)

#### 7. Pozisyon Karti Overflow Fix
- Sag sidebar (240px) icin compact layout: p-4→p-3, text-lg→text-sm
- Lot/Ticket ve Unrealized ayni satira tasindi

#### Dosyalar
- `Config.mqh`: Versiyon 4.7.4 CryptoFreedom
- `BytamerFX.mq5`: Versiyon 4.74
- `MIA/news_manager.py`: `_CRYPTO_SYMBOLS` seti + `_refresh_blocks()` crypto muafiyet
- `MIA/telegram_commander.py`: Zengin emoji startup + gunluk rapor
- `MIA/executor.py`: Harici pozisyon benimseme + `_detect_role_from_comment()`
- `MIA/sentiment_engine.py`: `get_rss_headlines()` RSS haber cekme
- `MIA/dashboard_api.py`: `update_rss_headlines()` + Cache-Control
- `MIA/main.py`: RSS thread entegrasyonu + kapanan islem veri alanlari
- `MIA/config.py`: Yahoo Finance + CNBC RSS feed'leri
- `MIA/dashboard_miav89.html`: Dashboard v7.0 — ticker, kapananlar, P/L fix, pozisyon karti

---

## [v4.7.3] - 2026-03-02

### AntiSpam — Global Trade Guard + Cooldown Sistemi

**KRITIK BUG FIX:** Auto trading kapali veya trade hatasi oldugunda EA tum subsystemler (SPM/Hedge/DCA/FIFO) her tick'te islem deneyip basarisiz oluyordu. Bu her denemede log spam ve Telegram mesaji olusturuyordu (500+ mesaj/gece).

#### 1. Global Auto Trading Guard (OnTick)
- `!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)` veya `!MQLInfoInteger(MQL_TRADE_ALLOWED)` → tum trade mantigi atlaniyor
- 5dk'da bir uyari logu (spam onleme)
- Auto trading kapali iken hicbir subsystem trade denemez

#### 2. SPM Acilis Hatasi Cooldown
- `OpenSPM()` basarisiz olunca `m_lastSPMTime` guncellenir (adaptive cooldown devreye girer)
- 60sn GlobalVariable cooldown: `SPM_FailCooldown_{symbol}`
- `ManageMainInLoss` ve `ManageActiveSPMs` cooldown kontrol eder
- Basarili acilista cooldown temizlenir

#### 3. Hedge Acilis Hatasi Cooldown
- `OpenHedge()` basarisiz olunca `m_lastHedgeTime` guncellenir
- 60sn GlobalVariable cooldown: `HEDGE_FailCooldown_{symbol}`

#### 4. DCA Acilis Hatasi Cooldown
- `OpenDCA()` basarisiz olunca `m_lastDCATime` guncellenir
- Hata logu eklendi (onceden yoktu)

#### 5. v4.7.2 Spam Fix (onceki hotfix dahil)
- HEDGE KAYIP UYARI'dan Telegram/Discord kaldirildi
- `static datetime` → `GlobalVariable` (restart-safe cooldown)
- FIFO HEDEF bildirim: kapatma SONRASI gonderilir (oncesi degil)
- FIFO/NET SETTLE basarisiz kapatma → 60sn cooldown

#### 6. Dashboard Cache-Control
- `dashboard_api.py`: `Cache-Control: no-cache, no-store, must-revalidate` header eklendi
- Tarayici artik eski HTML cache'lemez

#### 7. Proje Yapilandirma Temizligi
- Eski `FXAGENT` dizini kaldirildi (153MB duplikat)
- Eski versiyonlar silindi (v4.0, v4.1_temp, backup)
- Kullanilmayan dashboard dosyalari silindi (v62, v88, v90, v91)
- 53MB log dosyasi temizlendi
- `start_mia.bat` / `start_mia_silent.vbs` → dogru dizine yonlendirildi
- Windows Startup shortcut guncellendi

#### 8. Dashboard v4.7.3 — Tam UI Yeniden Tasarimi

**7 buyuk gorsel degisiklik:**

1. **Logo**: Altin simsek ⚡ + ByTamerFX branding (gold gradient `#F4B23A`)
2. **Sidebar Tab Sistemi**: 5 tab — Dashboard / Pozisyonlar / BIDIR-GRID / Teknik Analiz / Raporlar
   - `switchSidebarTab()` fonksiyonu ile tab gecisi
   - Aktif tab: gold highlight (`bg-[#F4B23A]/10 text-[#F4B23A]`)
3. **BIDIR-GRID Tab**: Gunluk Kar, Acik Zarar, Toplam Islem, Basari Orani, Hedef Ilerleme, Grid Seviyesi
4. **Teknik Analiz Tab**: 6 indikatör — RSI, ADX, ATR, MACD, Stochastic, Bollinger Bands (canli, sembol bazli)
5. **Raporlar Tab**: Gunluk/Haftalik/Aylik P/L (yuzde + dolar + gradient bar) + Toplam Islem + Basari Orani
   - `calcPeriodPnL()` fonksiyonu ile trade_history bazli hesaplama
   - Pozitif = emerald gradient, Negatif = rose gradient
6. **System Logs**: Sidebar'dan chart altina tasindi (tam genislik, 180px, canli MT5 log akisi)
7. **Haber Ticker**: 8 fallback haber basligi aktif (veri yokken), dinamik hiz ayari

- Tum deger gecislerinde TextScramble animasyonu tutarli
- Merkez alandan eski Teknik Analiz + BIDIR-GRID bloklari kaldirildi (tab'lara tasindi)

#### Dosyalar
- `BytamerFX.mq5`: Global auto trading guard + versiyon 4.73
- `PositionManager.mqh`: SPM/Hedge/DCA fail cooldown + FIFO/SETTLE spam fix
- `Config.mqh`: Versiyon 4.7.3 AntiSpam
- `MIA/dashboard_miav89.html`: Tam UI yeniden tasarimi (7 degisiklik)
- `MIA/dashboard_api.py`: Cache-Control header
- `MIA/start_mia.bat`: Dogru dizin yonlendirme
- `MIA/start_mia_silent.vbs`: Dogru dizin yonlendirme

---

## [v4.7.1] - 2026-03-01

### HEDGE-Safe — Hedge Zararina Satis Yasagi

**KRITIK BUG FIX:** HEDGE TIMEOUT mekanizmasi (Durum 5) hedge pozisyonlari zararina kapatiyordu. Kural: ZARARINA SATIS SADECE FIFO SISTEMINDE YAPILABILIR.

#### 1. HEDGE Timeout Durum 5 Revizyonu
- **ESKi:** 10dk acik + zarar > $1.0 → ZARARINA KAPAT ❌
- **YENI:** 10dk acik + KARDA → kar al, ZARARDA → dokunma (FIFO halledecek) ✅
- Zarardaki hedge artik asla kapatilmaz, sadece uyari logu yazilir (2dk arayla)

#### 2. MaxKayip Koruma Revizyonu
- **ESKi:** Kayip > %20 bakiye → HEMEN ZARARINA KAPAT ❌
- **YENI:** Kayip > %20 bakiye → sadece UYARI (Telegram/Discord), pozisyon ACIK kalir ✅
- FIFO sistemi uzerinden kapanmasini bekler

#### 3. MIA Dashboard v90 Guncelleme
- Charts alti Teknik Analiz Detaylari artik live (firstTech → activeTech)
- 6 gosterge: RSI, ADX, ATR, MACD, Stochastic, Bollinger Bands
- Aktif sembol ismi gosteriliyor (sembol degisince tum degerler guncellenir)
- Sinyal Analiz paneli (sol sidebar) 7 animasyonlu bar
- Header: Bakiye + Equity + Daily P/L + Borsa Saatleri + Saat
- Ust ticker: Tum semboller scrolling, borsa aciksa yesil / kapaliysa kirmizi
- Alt ticker: Ekonomik takvim haberleri, kategori ikonlari
- Pozisyonlar 2 tab: Acik / Kapananlar + TP1 eklendi
- Win/Loss gradient bar
- pollCandles 15s → 5s hizlandirildi

#### Dosyalar
- `PositionManager.mqh`: Durum 5 HEDGE TIMEOUT — zararina satis kaldirild
- `Config.mqh`: Versiyon 4.7.1 HEDGE-Safe
- `BytamerFX.mq5`: Versiyon 4.71
- `MIA/dashboard_miav89.html`: Dashboard v90 tum guncellemeler

---

## [v4.7.0] - 2026-03-01

### FIFO-Guard — Kasa Persistence + Restart Koruma

**KRITIK BUG FIX:** EA restart olduğunda FIFO kasası ($30.05) sıfırlanıyordu. Tüm birikmiş SPM karları kayboluyordu.

#### 1. FIFO Kasa Persistence (GlobalVariable)
- `SaveFIFOState()`: Her tick sonunda FIFO kasasını GlobalVariable'a kaydeder
- `LoadFIFOState()`: EA restart sonrası kasayı geri yükler
- Kaydedilen veriler: kasaProfit, kasaCount, totalCashed, mainTicket
- Pozisyon yoksa GlobalVariable otomatik temizlenir

#### 2. BI-DIR State Persistence
- BiDirectionalMode, activeGridDir, legacyGridDir de GlobalVariable'da saklanır
- EA restart sonrası bi-directional mod doğru devam eder

#### 3. mainFound Kasa Koruma
- ESKİ: ANA bulunamazsa ResetFIFO() → kasa $0'a düşer
- YENİ: Kalan pozisyon varsa en eski'yi ANA olarak terfi et, kasayı KORU
- Sadece hiç pozisyon kalmazsa ResetFIFO çağrılır

#### Dosyalar
- `PositionManager.mqh`: SaveFIFOState, LoadFIFOState, mainFound fix, OnTick persist
- `Config.mqh`: Versiyon 4.7.0 FIFO-Guard
- `BytamerFX.mq5`: Versiyon 4.70

---

## [v4.6.1] - 2026-02-27

### HEDGE Minimum Kar Esigi

- FIX: HEDGE trend kapatma esigi $0.00 → $1.50 (QuickProfitUSD)
- ManageHedgePositions Durum 3: hedgeProfit >= 0.0 → hedgeProfit >= $1.50
- HEDGE koruma pozisyonudur, komik karlarda ($0.27) kapatmak korumayi yok eder
- v4.4.0 iyilestirmeleri ManageKarliPozisyonlar'a uygulanmisti, HEDGE ayri fonksiyonu atlanmisti

---

## [v4.6.0] - 2026-02-27

### NightGuard — Gece Modu (Night Session Protection)

**Amac:** Bolgesel borsa acilislarindaki yuksek volatilite ve ters spread riskine karsi koruma.

#### 1. Yeni Islem Engeli (20:00+)
- Crypto HARIC tum semboller: 20:00'den sonra yeni islem acilmaz
- ANA, SPM, DCA, HEDGE dahil — hicbir yeni pozisyon acilmaz
- TradeExecutor tek bogaz noktasinda engellenir (6 farkli acilis noktasi korunur)
- Mevcut pozisyonlar normal yonetilir (kapanis mekanizmalari calisir)

#### 2. Zorla Kapanis (23:00+)
- Crypto HARIC: +$1.00 karli tum pozisyonlar kapatilir
- Zarardaki pozisyonlar dokunulmaz — sadece karlilar kapanir
- Kapanis nedeni: "GeceModu_HH:MM_$X.XX" formatinda loglanir

#### 3. Crypto Istisna
- Crypto semboller (BTC, ETH vb.) 7/24 aktif kalir
- Gece modu Crypto'yu HICBIR sekilde etkilemez

#### 4. Input Parametreleri
- `NightModeEnabled` (true) — Gece modu aktif/pasif
- `NightModeStartHour` (20) — Yeni islem engel saati (yerel)
- `NightModeCloseHour` (23) — Karli pozisyon kapatma saati (yerel)
- `NightModeMinProfit` ($1.0) — Kapatma icin minimum kar

---

## [v4.5.0] - 2026-02-27

### SPM Dongusu — Limit Yok + Saf SPM Yonetimi

**Hedef:** Tum zorla kapatma mekanizmalari kaldirildi. Sadece SPM dongusu calisir.

#### 1. Zorla Kapatma Mekanizmalari KALDIRILDI
- **STOP-LOSS**: Tamamen devre disi — SPM sistemi pozisyon yonetimini yapar
- **EQUITY_EMERGENCY**: Devre disi — sadece margin call seviyesinde (1%)
- **PEAK_DROP**: Devre disi — kar buyurken zorla kapatma yok
- **DD_EMERGENCY**: Devre disi — SPM dongusu zarari yonetir
- **MARGIN_EMERGENCY**: Sadece broker seviyesi (20%) — bilgilendirme logu

#### 2. SPM Dongusu (Tek Yonetim Mekanizmasi)
- ANA pozisyon zarar >= $3-4 → SPM ters yonde acilir
- SPM toplam kar - ANA zarar >= +$5 → grup kapanir
- Geride kalan SPM yeni ANA olur → dongu tekrar baslar
- Zarina satis YOK — mumlar terse donene kadar beklenir

#### 3. MIA v5.2.0 Entegrasyonu
- MIA Dashboard tum zorla kapatma limitleri kaldirildi (config.py + agents.py)
- RiskAgent/SpeedAgent sadece loglama yapar, kapatma YAPMAZ
- Telegram/Discord bildirim sistemi aktif

#### 4. Versiyon Senkronizasyonu
- EA: v4.5.0 SPM-Cycle
- MIA: v5.2.0 SPM-Only Position Management
- Tum dashboard HTML dosyalari v5.2.0 guncellendi

---

## [v4.4.0] - 2026-02-26

### Hayatta Kalma Icgudusu + Kazanma Hirsi

**Hedef:** SPM ortalama kapanis kari $1.50-$2.00 → $3.50-$5.00 artisi.
FIFO kasa birikimi realistik, Grid Reset tetiklenmesi azalacak.

#### 1. SPM Hizli Kapanis Esigi Yukseltildi
- **Eski**: `minCloseThreshold = minCloseProfit * 0.5` → SPM $1-2'de kapaniyordu
- **Yeni**: `minCloseThreshold = spmCloseProfit` (Forex=$4, BTC=$6)
- SPM'ler artik daha buyuk kar hedefinde kapatilir

#### 2. Cift Mum Teyit Sistemi (MUM_DONUS)
- **Eski**: 1 ters mum = aninda kapanis
- **Yeni**: 2 ardisik ters mum gerekli (teyit sistemi)
- **Istisna**: Guclu engulfing (body > ATR × 1.2) tek mumda kapatir
- Tek mum ters donusu → "teyit bekleniyor" logu

#### 3. Momentum Koruma (Buyuyen Kar Korumasi)
- Kar son tick'e gore $0.10+ artiyorsa → kapatma mekanizmalari engellenir
- Buyuyen kar = pozisyon korunur, peak tracking devam eder
- Grid Reset haric tum kapatma mekanizmalari atlanir

#### 4. Dinamik Trailing Floor (BE Lock Yerine)
- **Eski BE Lock**: $2'de tetiklenir → $0.80'e dusunce kapatir → $1.20 kayip
- **Yeni Trailing Floor**: Kademeli koruma tabani
  - Peak >= $3: Floor = $1.50 (%50 koruma)
  - Peak >= $5: Floor = $3.00 (%60 koruma)
  - Peak >= $8: Floor = $5.50 (%69 koruma)
- Floor ASLA dusmez, sadece yukari gider

#### 5. TREND_DONUS Guclendirme
- **Eski**: Herhangi trend sinyali SPM'yi kapatiyordu
- **Yeni**: Sadece guclu trend (sinyal skoru >= 55) SPM kapatabilir
- Zayif trend donusu → loglanir ama kapatilmaz

#### 6. Zaman Korumasi (Grace Period)
- < 2 dakikalik yeni pozisyonlar Grid Reset haric kapatilmaz
- Yeni acilan pozisyonlarin erken kapatilmasi engellenir

#### 7. Profil Esikleri Yukseltme (Tum Profiller)
- **Forex**: candleClose W=$3/M=$4.50/S=$7, spmClose=$4, minClose=$2.50
- **BTC**: candleClose W=$5/M=$7/S=$10, spmClose=$6
- **JPY**: candleClose W=$3/M=$4.50/S=$7, spmClose=$4, minClose=$2.50
- **XAG/XAU/Metal/CryptoAlt/Indices**: candleClose +$1.50 artis
- **Energy/Default**: candleClose %100 artis
- **Global**: PeakMinProfit $1→$2, PartialClose $3→$5, BE_Trigger $2→$3

#### 8. PeakDrop Minimum Yukseltme
- **Eski**: PeakMinProfit = $1.00 → $1.10 peak'te bile %45 drop tetikleniyordu
- **Yeni**: PeakMinProfit = $2.00 → anlamli peak birikimi gerektirir

### Yeni Mekanizma Ozeti
```
1. Pozisyon acilir → 2 dk Grace Period (kapatma yok)
2. Kar artiyorsa → Momentum Koruma (kapatma engellenir)
3. Mum ters donerse → 1. ters mum = teyit bekle, 2. ters mum = kapat
4. Peak >= $3 → Trailing Floor baslar ($1.50 min koruma)
5. Trend donusu → skor >= 55 gerekli (zayif donus = kapatma yok)
6. SPM kari → spmCloseProfit esigine ulasinca MumDonus_TP kapatir
```

### Files Changed
- `Config.mqh`: Tum profil esikleri + global input degerleri
- `PositionManager.mqh`: 6 yeni mekanizma + m_candleAgainstCount[] + m_lastProfit[]
- `CandleAnalyzer.mqh`: GetLastBody() + GetATR() eklendi
- `BytamerFX.mq5`: Version 4.40
- `TelegramMsg.mqh`: Header v4.4.0

---

## [v4.3.2] - 2026-02-26

### FIFO Kasa Fix + BE Lock Fix + Min Profit Threshold

#### 1. FIFO Kasa Negatif Bug Fix (KRITIK)
- **Bug**: FIFO Yol A (`CloseWorstSPM`) en zarardaki SPM'yi kapatiyordu
- SPM'nin negatif P/L'si kasaya ekleniyordu → kasa = $-8.64
- Kasa negatif → FIFO calisamaz → Grid Reset tetiklenir → buyuk zarar
- **Fix 1**: FIFO Yol A tamamen DEVRE DISI birakildi
  - SPM'ler ASLA zararda kapatilmaz
  - FIFO sadece Yol B uzerinden calisir: kasa + anaLoss >= +$5 → ANA kapat
- **Fix 2**: `SmartClosePosition` kasaya sadece pozitif kar ekler
  - `if(profit > 0)` koruması eklendi
  - Zarardaki kapanislar kasayi etkilemez (guvenlik agi)

#### 2. BE Lock Miras Bug Fix (KRITIK)
- **Bug**: `RefreshPositions()` icinde pozisyon array indexi yeniden kullanildiginda `m_breakevenLocked[]` sifirlanmiyordu
- Eski SPM'nin BE lock durumu yeni SPM'ye miras kaliyordu → yeni SPM aninda $0.00'da kapaniyordu
- **Fix**: `RefreshPositions()` icinde ticket degistiginde BE lock + BE price sifirlama eklendi

#### 3. Minimum BE Kapanis Kari: $0.80
- **Eski**: `profit >= 0.0` → $0.00, $0.02 gibi spread maliyetini karsilamayan kapanislar
- **Yeni**: `profit >= 0.80` → Spread maliyetini karsilayan minimum kar esigi

#### 4. Dashboard MIA v5.1 Gorsel Iyilestirme
- Signal gauge, pozisyon haritasi, ticker, glow efektleri, indicator mini-bars

#### 5. Telegram Bot Guncelleme
- Yeni bot token (ByTamerEA_bot) ile mesaj gonderimi OK
- HTTP 401 hatasi cozuldu

### FIFO Mantik Ozeti (v4.3.1)
```
1. ANA acilir → zarara girer
2. SPM'ler ters yonde acilir (koruma)
3. SPM'ler SADECE KARDA kapanir (MumDonus/TrendDonus/PeakDrop)
4. Karli SPM kapanislari → kasaya eklenir
5. Kasa + ANA_zarar >= +$5 → ANA kapatilir (FIFO Yol B)
6. En eski zarardaki SPM → yeni ANA olur
7. Dongu tekrar baslar
```

### Files Changed
- `PositionManager.mqh`: FIFO Yol A devre disi + kasa koruma + BE lock fix + minBEProfit $0.80
- `Config.mqh`: v4.3.1 + yeni Telegram token
- `BytamerFX.mq5`: v4.31 surum guncelleme
- `dashboard_api.py`: MIA v5.1 gorsel yeniden tasarim

---

## [v4.3.0] - 2026-02-26

### Telegram Rich Messages + Daily Report + Token Validation

#### 1. Telegram Mesaj Sistemi Tam Yeniden Yazim
- **10 Mesaj Tipi**: Startup, Shutdown, TradeOpen, TradeClose, SPM, Hedge, FIFO, GridReset, DailyReport, Generic
- Her mesajda: Hesap No, Bakiye, Equity, Surum, Tarih/Saat
- Zengin format: Emoji + cerceve + bolumler + HTML
- Progress bar (FIFO ilerleme gostergesi)
- Otomatik icon secimi (mesaj icerigine gore)

#### 2. Token Dogrulama (v4.3 NEW)
- `ValidateToken()`: Initialize sirasinda `/getMe` API ile token dogrulama
- HTTP 401 → "TOKEN GECERSIZ" uyarisi + BotFather yonlendirmesi
- WebRequest hatasi → URL listesi uyarisi
- Detayli hata loglama: Response body dahil

#### 3. EA Kapanis Bildirimi (SendShutdown - NEW)
- `OnDeinit()` icinde: Seans ozeti mesaji gonderilir
- Kapatilan islem sayisi, seans kari, calisma suresi, kapanis sebebi

#### 4. Gun Sonu Raporu (SendDailyReport - NEW)
- Her gun 23:55'te otomatik gonderilir
- Finansal ozet, islem istatistikleri, sistem sagligi
- Karli/zararda islem sayisi, win rate yuzdeleri

#### 5. Pozisyon Haritasi (GetPositionMapHTML - NEW)
- SPM, FIFO, Hedge mesajlarinda tam pozisyon haritasi
- Her pozisyon: Rol + Yon + Lot + P/L

#### 6. Zengin Olay Mesajlari
- `SendSPMEvent()`: SPM acilis/kapanis + pozisyon haritasi + FIFO ilerleme cubugu
- `SendHedgeEvent()`: Rescue hedge + pozisyon haritasi
- `SendFIFOEvent()`: ANA kapanis + SPM kasa + net sonuc + terfi bilgisi
- `SendGridReset()`: Floating loss + esik + kapatilan pozisyonlar

### Files Changed
- `TelegramMsg.mqh`: Tamamen yeniden yazildi (10 mesaj tipi + token dogrulama + format helpers)
- `PositionManager.mqh`: GetPositionMapHTML(), GetCategoryName(), 4 key SendMessage→zengin method
- `BytamerFX.mq5`: v4.30, SendShutdown, DailyReport timer, seans istatistikleri
- `Config.mqh`: v4.3.0

---

## [v4.2.0] - 2026-02-26

### Net-Exposure SPM + Grid Reset + FIFO Enhance

**Backtester sonuclari:** BTC +$93 (+93%), GBP +$18 (+18%), Toplam +$111

#### 1. Net-Exposure SPM Dengeleme (KRITIK)
- **Eski**: SPM1 = ANA yonunde DCA, SPM2 = SPM1 tersi
- **Yeni**: SPM yonu = BUY/SELL DENGESI (fazla olan tarafin tersi acilir)
- `GetNetExposureDirection()`: Tum acik pozisyonlarin BUY/SELL sayisini hesaplar
- 3+ SPM ayni yonde birikmesi IMKANSIZ → tek yonlu batma onlendi
- SPM acilislarinda BUY/SELL zigzag pattern olusur

#### 2. Grid Reset Mekanizmasi (YENi)
- `CheckGridHealth()`: Toplam floating loss esik asarsa tum grid sifirlanir
- Esik: `-max(GridLossMinUSD, equity * GridLossPercent)` (default: -max($30, %25))
- Islem: Karli SPM'ler once kapatilir (kasa koruma), sonra kalan kapatilir
- Cooldown + Telegram/Discord bildirim
- Yeni inputlar: `GridLossPercent=0.25`, `GridLossMinUSD=30.0`
- ManageTrendGrid() baslangicinda cagirilir (warmup sonrasi)

#### 3. EQUITY_ACIL Recovery Mode Fix (KRITIK BUG FIX)
- **Bug**: EQUITY_ACIL tetiklendikten sonra `peak_balance` sifirlanmiyordu
- `equity/peak_balance < 30%` her tick'te true → EA surekli EQUITY_ACIL → sonsuz kilit
- **Fix**: EQUITY_ACIL sonrasi `m_recoveryMode = true` aktif edilir
- Recovery mode: 24 saat veya bakiye %50 toparlaninca cikis
- Olum spirali onlendi (eski: $100 → $36 → $13 → $1.18)

#### 4. SPM Max 3 Katman
- **Eski**: Sabit max 2 SPM (SPM1 + SPM2)
- **Yeni**: Profil bazli `spmMaxLayers = 3` (Config input: `SPM_MaxLayers`)
- SPM2 tetik: ANA zarar bazli (eski: SPM1 zarar bazli)
- SPM3 tetik: ANA zarar * 1.5 (daha derin zarar gerekli)

#### 5. SPM Hizli Kasa Birikimi
- SPM/DCA icin min close threshold %50 dusuruldu
- `minCloseThreshold = max(0.5, minCloseProfit * 0.5)`
- Daha hizli kasa dolumu → FIFO daha erken tetiklenir

### Tasarim Felsefesi
- **SL = YOK (MUTLAK)** — Hicbir pozisyona Stop Loss konulmaz
- **Zararina satis YOK** — Normal operasyonda pozisyon zararda kapatilmaz
- **SPM/FIFO ile zarar yonetimi** — Zarar SPM birikimi + FIFO ile telafi edilir
- Grid Reset ve EQUITY_ACIL sadece asiri durumlarda son care guvenlik agidir

### Files Changed
- `Config.mqh`: v4.2.0, 3 yeni input, SymbolProfile 3 yeni alan, 10 profil guncelleme
- `PositionManager.mqh`: GetNetExposureDirection(), CheckGridHealth(), ManageMainInLoss net-exposure, ManageActiveSPMs max 3 + net-exposure, CheckMarginEmergency recovery, ManageKarliPozisyonlar %50 esik
- `BytamerFX.mq5`: v4.20

---

## [v4.1.0] - 2026-02-24

### BiDir Fix + Forex 0.03 + FIFO Fix + SPM Enhance

#### Degisiklikler
- FIFO sadece ANA kapatir (SPM'ler acik kalir, terfi devam)
- Sonraki mum bekleme: FIFO tamamlandiktan sonra yeni islem bekler
- Forex min lot 0.03 (kucuk hesap uyumu)
- BiDir Legacy tracking fix
- SPM Warmup 45sn

---

## [v4.0.0] - 2026-02-23

### Major: KazanKazan-Pro Signal Redesign

#### Degisiklikler
- SignalEngine: 7→12 indicator (SuperTrend, Ichimoku, Keltner, MFI, SAR eklendi)
- CandleAnalyzer: Bagimsiz modul (Pin Bar, Engulfing, Doji, Inside Bar, Three Soldiers/Crows)
- BytamerFX combo scoring (tum 12 indikatoru birlestiren ozel skor)
- v3.7.1 Tepe/Dip koruma: ADX>=45 trend yonu, ADX<=40 30sn cooldown
- v3.7.0 Kademeli Kurtarma: SPM1=DCA, SPM2=SPM1 tersi, ADX>=20 filtre
- v3.8.0 Gercek equity+margin koruma (3 seviye: %30/%150/%300)
- Rescue Hedge: SPM2 -$7 → ANA * 1.3 lot hedge
- HEDGE PeakDrop: peak >= $8 + %25 dusus → kapat

---

## [v3.5.0] - 2026-02-21

### Net Settlement + Zigzag Grid Engine

#### Degisiklikler
- Net Settlement: kasa + worstLoss >= $5 → worst pozisyon kapat
- Zigzag SPM: ANA→SPM1(ayni)→SPM2(ters)→SPM3(ayni)...
- ADX 25+ grid filtresi (ADX<25 → grid acilmaz)
- Spread kontrolu: ATR normalize * MaxSpreadMultiplier
- Trend Hold: ADX>=25 + trend yonunde → PeakDrop YAPMA
- Adaptif grid mesafesi (volatilite bazli)
- Bi-Directional Grid: trend degisince iki yon aktif
- Post-Entry Karlilik: Kismi kapama (%60) + Sanal BE kilidi

---

## [v3.3.0] - 2026-02-21

### Grid Performans Iyilestirmeleri

#### Degisiklikler
- SPM cooldown 60→30sn (yakalama +%40)
- Lot azaltma grid basi %5→%3 (Grid10 = %70 kalir)
- Kategori bazli SPM kar hedefleri ayarlandi
- Min close profit arttirildi (spread sonrasi yetersiz kapatma onlendi)

---

## [v3.2.0] - 2026-02-20

### Lisans Sistemi Iyilestirmeleri

#### 1. Lisans Input Penceresi
- Lisans bos/gecersiz ise MessageBox ile uyari gosterilir
- EA otomatik grafikten kaldirilir (ExpertRemove)
- Kullanici tekrar surukleyince MT5 input penceresi acilir - lisans koda dokunmadan girilebilir
- LicenseKey ve ExpectedAccountNumber default deger bos (musteriye dagitim icin)

#### 2. Cache Invalidation Duzeltmlesi
- Init() baslangicinda tum state sifirlaniyor (m_isValid, m_status, m_daysRemaining vb.)
- Lisans anahtari degistiginde eski cache gecersiz (DJB2 hash eslesmez → cache siliniyor)
- Global nesne eski deger tasima bug'i giderildi

#### 3. Periyodik Lisans Kontrolu
- m_checkInterval = 300 saniye (5 dakika)
- Tum lisans tipleri icin ayni aralık

#### 4. API Uyumlulugu
- EA artik hem "active" hem "valid" status kabul eder
- Flat ve nested JSON yanit destegi
- hours_remaining/license_type yoksa end_date'den hesaplama
- Minimum key uzunlugu 28 karakter (sunucu 28 char uretir)

---

## [v2.3.0] - 2026-02-19

### Major: Smart Recovery Sistemi

#### 1. Smart SPM Yon Mantigi
- **SPM1**: DAIMA ANA tersine (5-oy sistemi KULLANILMAZ)
- **SPM2**: DAIMA SPM1 tersine (ANA ile ayni yon)
- **SPM3+**: 5-oy sistemi (Trend, Sinyal, Mum, MACD, DI)
- DetermineSPMDirection, CheckSameDirectionBlock, ShouldWaitForANARecovery SPM1 icin kaldirildi

#### 2. Yeni FIFO Hesaplama
- **Eski**: net = kasa + acikKar + acikZarar + anaP/L (acik SPM zararlari FIFO'yu kilitliyordu)
- **Yeni**: net = kasa - ANA zarar (acik SPM P/L DAHIL DEGIL)
- ANA karda ise: net = kasa → kasa >= $5 ise ANA kapanir
- ANA zararda ise: net = kasa - |zarar| → SPM karlari ANA zarari telafi edince kapanir
- v2.2.7 ANA Kar Koruma blogu KALDIRILDI (yeni FIFO ile gereksiz)

#### 3. SPM Terfi (AKTIF)
- ANA FIFO ile kapandiktan sonra SADECE ANA kapanir (SPM'ler ACIK KALIR)
- En eski SPM → yeni ANA olur (PromoteOldestSPM)
- Kalan SPM katmanlari openTime sirasina gore yeniden numaralanir (RenumberSPMLayers)
- Dongü devam eder: yeni ANA zararda ise yeni SPM'ler acilir

#### 4. Acil Hedge Yeniden Yazildi
- **Eski**: Lot oran > 2:1 + iki tarafta pozisyon + zarardaki taraf buyuk
- **Yeni**: Grup toplam P/L <= -$40 tetiklenir
- Yon: 5-oy sistemi (trend bazli)
- Lot: zarardaki toplam lot * 1.2
- SPM katman limiti BYPASS

#### 5. SPM Kar Hedefi
- XAG, XAU, INDICES, CRYPTO_ALT, METAL: spmCloseProfit $4 → $5
- BTC: $5 (degismedi), FOREX: $3 (degismedi)

#### 6. Dashboard Gunluk Istatistikler
- Panel 4'e 3 yeni satir: Gunluk Kar ($+%), Toplam Islem (B:X/S:Y), Bugun (X islem)
- Trade sayaclari: OpenNewMainTrade, OpenSPM, OpenDCA, OpenHedge
- Gunluk sayac midnight reset

### Files Changed
- `Config.mqh`: FIFOSummary (5 yeni alan), profil kar hedefleri, versiyon 2.3.0
- `PositionManager.mqh`: 6 degisiklik (yon, FIFO, terfi, hedge, sayaclar, header)
- `ChartDashboard.mqh`: Panel 4 (3 yeni satir, h=220), versiyon header
- `BytamerFX.mq5`: Versiyon 2.30

---

## [v2.2.7] - 2026-02-19

### Critical Fixes
- **ANA Kar Koruma Mekanizmasi**: FIFO deadlock durumunda ANA pozisyonun karini korur. ANA >= $10 karda + FIFO net < -$10 + kilitlenme 300sn+ + ANA peak'ten %30 dusmüs → tum pozisyonlari kapatir, ANA karini realize eder.
- Onceki sorun: ANA +$16 karda iken SPM'ler -$44 zararda → FIFO ASLA tetiklenemiyordu → ANA kari realize edilemeden eriyebiliyordu.

### Changes
- `PositionManager.mqh`: CheckFIFOTarget icinde ANA Kar Koruma blogu eklendi
- Versiyon 2.2.6 → 2.2.7

---

## [v2.2.6] - 2026-02-19

### Critical Fixes
- **HEDGE PeakDrop Muafiyeti**: HEDGE pozisyonlari artik PeakDrop ile KAPATILMIYOR. PeakDrop sadece SPM/DCA icin gecerli. HEDGE margin korumasi sagladigi icin erken kapatilmasi margin cokusu yaratiyordu.
- **SPM Katman Limiti 5→3**: Tum profillerde maxSpmLayers 5→3 dusuruldu. 5 SPM yigilmasi kucuk hesaplarda margin patlamasina neden oluyordu.
- **MarginKritik Sonrasi Toparlanma Modu**: MarginKritik tetiklendikten sonra EA yeni islem ACMIYOR. Bakiye crash oncesinin %50'sine ulasana veya 24 saat gecene kadar bekler. $13 ile islem devam edip $1'e dusme onlendi.

### Root Cause
- 19 Subat 06:34: XAGUSDm'de 5 SPM SELL yigildi, HEDGE BUY PeakDrop ile erken kapandi, margin korumasi kalkti, 7 saniyede $105→$13 dustu. EA $13 ile devam etti→$1.18.

### Changes
- `PositionManager.mqh`: PeakDrop role kosulu (HEDGE muaf), IsInRecoveryMode(), CheckMarginEmergency recovery
- `Config.mqh`: maxSpmLayers 5→3 (tum profiller), versiyon 2.2.6
- `BytamerFX.mq5`: IsInRecoveryMode() kontrolu, versiyon 2.26
- `ChartDashboard.mqh`: Versiyon header 2.2.6

---

## [v2.2.5] - 2026-02-18

### Critical Fixes
- **SPM Lot Carpanlari Duzeltildi**: Tum profillerde spmLotBase 1.5→1.0, spmLotIncrement 0.2→0.1, spmLotCap 2.0→1.5
- SPM artik: 1.0x, 1.1x, 1.2x, 1.3x, 1.4x, 1.5x seklinde gidiyor (onceki: 1.5x, 1.7x, 1.9x - COKLU MARGIN RISKI)
- Ornek: ANA 0.06 lot ise SPM1=0.06, SPM2=0.07, SPM3=0.07 (onceki: 0.09, 0.10, 0.11)

### Changes
- `Config.mqh`: 10 profilin hepsi guncellendi + input default degerleri

---

## [v2.2.4] - 2026-02-18

### Critical Fixes
- **Deadlock Kapatma Kaldirildi**: CheckDeadlock artik pozisyon KAPATMIYOR. Sadece log + Telegram/Discord uyari gonderiyor. Kilitlenme durumunda pozisyon korunur, yeniden izleme baslar.
- **LOT DENGE Limiti Genisletildi**: Oran limiti 2.5:1 → 4.0:1. Daha fazla SPM katmani acilabilir, kilitlenmeye girme riski azalir.
- **EmergencyHedge Kosulu Gevsedi**: `zarar_taraf_buyuk` sarti kaldirildi. Artik toplam net zarar < 0 VE lot orani > 2.0 ise hedge tetiklenir. ANA kucuk lot ile zarardayken bile hedge acilir.
- **LOT DENGE Log Spam Giderildi**: CheckLotBalance fonksiyonundan PrintFormat kaldirildi.

### Changes
- `PositionManager.mqh`: CheckDeadlock sadece uyari, CheckLotBalance 4.0 limit, ManageEmergencyHedge basitlestirildi
- `Config.mqh`: Versiyon 2.2.3 → 2.2.4
- `BytamerFX.mq5`: Versiyon 2.23 → 2.24
- `ChartDashboard.mqh`: Header guncelleme

---

## [v2.2.3] - 2026-02-18

### Fixes
- **Emoji-Yazi Bosluk**: Tum dashboard panellerinde emoji ile yazi arasina cift bosluk eklendi
- **BMP Unicode**: Dashboard simgeleri BMP Unicode araligi (U+0000-U+FFFF) ile degistirildi

### Changes
- `ChartDashboard.mqh`: Tum panel etiketleri ve deger stringlerinde cift bosluk
- `BytamerFX.mq5`: Tooltip BMP Unicode guncelleme

---

## [v2.2.2] - 2026-02-18

### Critical Fixes
- **Minimum Profit Threshold**: Added `minCloseProfit` to SymbolProfile. No SPM/DCA/HEDGE position closes below the minimum profit. Prevents trades closing at $0.26-$0.80 that don't cover spread+commission costs. Forex/XAG/XAU=$1.0, BTC=$1.5.
- **SPM Emergency Cooldown Skip**: When SPM loss exceeds 2x the trigger threshold (e.g., -$10 when trigger is -$5), the cooldown for next SPM layer is skipped entirely. Prevents situations where SPM1 reaches -$10.45 but SPM2 can't open for 60 seconds.
- **ANA Position Broker TP Removed**: Broker-side TP is no longer set for main (ANA) positions. ANA ONLY closes via FIFO (net >= +$5). Previously, broker would auto-close ANA at TP price, bypassing FIFO logic and resulting in tiny $0.26 profits.
- **ANA Ticket Detection Fix**: When broker closes ANA via TP/SL, `m_mainTicket` now properly resets. New positions are correctly identified as ANA instead of being misassigned as SPM1.
- **BTC TP Pips Increased 10x**: BTC TP1: 1500→15000, TP2: 2500→30000, TP3: 3500→50000 pips. At 0.01 lot, old values only yielded ~$0.35 profit. New values yield $1.50/$3.00/$5.00+.
- **CryptoAlt TP Pips Increased 10x**: Similar adjustment for altcoins: 500→5000, 1000→10000, 1800→18000 pips.

### Changes
- `Config.mqh`: Added `minCloseProfit` field to SymbolProfile, updated all 10 profiles. Version 2.2.1→2.2.2
- `PositionManager.mqh`: All 5 profit-close rules now respect `minCloseProfit`. Emergency SPM cooldown skip when loss >= 2x trigger. ANA ticket existence check in `RefreshPositions()`. Role assignment fix when `m_mainTicket == 0`.
- `BytamerFX.mq5`: ANA broker TP set to 0 (FIFO-only close). Version 2.21→2.22

---

## [v2.2.1] - 2026-02-18

### Critical Fixes
- **SPM SAME-DIR BLOCK Infinite Loop Fix**: When main position was losing and 5-vote returned same direction, SPM never opened. After override to opposite direction, `ShouldWaitForANARecovery` is now skipped, SPM opens immediately in opposite direction.
- **Smart Margin Management**: `MinMarginLevel` reduced from 200% to 150%. Below 150% only the worst-performing position is closed (gradual). Below 120% all positions are closed (true emergency).
- **SPM Log Spam Prevention**: 30-second cooldown added. Repeated SPM log messages now write at 30s intervals instead of every tick.

### New Features
- **News Banner Symbol Filter**: News now only appears on the chart of the affected symbol (e.g., GBP news won't show on XAG chart).
- **News Banner Colors**: Background colors made much brighter and more visible (CRITICAL=red, HIGH=orange, MEDIUM=yellow). Border width set to 2px.
- **Dynamic Min Lot**: Category-based minimum lot: Forex=0.06, BTC/XAG/XAU=0.01, Indices=0.03.
- **Symbol-Based Trade Blocking**: Only news affecting the current symbol will block trading.

### Changes
- `Config.mqh`: Added `minLotOverride` field to SymbolProfile, updated all 10 profiles
- `LotCalculator.mqh`: Added `profileMinLot` parameter to `Initialize()`
- `PositionManager.mqh`: Added `m_lastSPMLogTime` and `m_spmDirOverridden` fields
- `NewsManager.mqh`: Added `onlyRelevant` filter to `GetActiveNewsInfo/GetNextNewsInfo`
- `ChartDashboard.mqh`: Replaced Panel 5 with full-width top news banner (24px, dynamic width)

---

## [v2.2.0] - 2026-02-18

### New Features
- **Universal News Intelligence**: MQL5 CalendarValueHistory API integration for economic calendar
- **Dynamic Lot Calculation**: 8-factor lot engine (balance, volatility, risk, margin, DD, correlation, streak, time)
- **Emoji Notifications**: Automatic emoji and balance/equity info in Telegram + Discord messages
- **Dashboard News Panel**: Live news info on chart (impact colors, countdown timer)

### Changes
- Added `NewsManager.mqh`: News loader, currency detection, impact-based trade blocking
- `ChartDashboard.mqh`: 5-panel dashboard (news panel added)
- `TelegramMsg.mqh` / `DiscordMsg.mqh`: Emoji + balance/equity info

---

## [v2.1.0] - 2026-02-17

### New Features
- **Dynamic Profile System**: 10 instrument profiles (Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt, Indices, Energy, Metal, Default)
- **Pip-Based TP**: Separate TP1/TP2/TP3 pip distances per profile
- **3-Tier Symbol Matching**: Symbol-specific > JPY group > Category priority

### Changes
- `Config.mqh`: SymbolProfile struct + 10 profile methods + GetSymbolProfile()
- `PositionManager.mqh`: Profile-based SPM trigger, lot, cooldown parameters

---

## [v2.0.1] - 2026-02-17

### Fixes
- **Hedge Bug Fix**: Fixed hedge position being closed immediately after opening
- Hedge system now waits until next SPM check cycle after opening

---

## [v2.0.0] - 2026-02-17

### Major Release - WIN-WIN Hedge System
- **5+5 SPM Structure**: Max 5 BUY + 5 SELL separate layer limits
- **5-Vote System**: SPM direction via H1 Trend + Signal Score + M15 Candle + MACD Histogram + DI Crossover
- **FIFO Net Target**: closedProfit + openSPMProfit + openSPMLoss + mainP/L >= +$5 triggers full close
- **DCA Mechanism**: Dollar cost averaging for losing SPM positions (max 1 per position)
- **Emergency Hedge**: Auto-hedge when lot ratio > 2:1 and losing side is larger
- **Deadlock Detection**: 5min net change < $0.50 triggers full position closure
- **CheckSameDirectionBlock**: Never opens SPM in same direction as losing main position

### Removed
- Promotion (SPM->MAIN) system removed (was creating black hole effect)
- DD-based equity protection removed (per user request)

---

## [v1.3.0] - 2026-02-17

### New Features
- **SmartSPM**: Intelligent SPM direction determination
- **Strong Hedge**: One-sided risk detection + automatic hedge

---

## [v1.2.0] - 2026-02-17

### New Features
- **SPM-FIFO Profit-Focused System**: Small profit accumulation strategy
- PeakDrop now applies only to SPM positions (not to main)

---

## [v1.1.0] - 2026-02-17

### New Features
- **ByTamer Hybrid Signal System**: 7-layer advanced signal engine
- MACD + RSI divergence engine (regular + hidden)
- Market structure analysis (HH/HL/LH/LL)
- Bollinger squeeze detection
- Candlestick pattern scoring
- Multi-timeframe confirmation (H1 + H4)
- ATR percentile ranking

### Fixes
- Discord embed description JSON escape fix
- Telegram SendMessage public access fix

---

## [v1.0.0] - 2026-02-17

### Initial Release
- 7-layer base signal engine (EMA+MACD+ADX+RSI+BB+Stoch+ATR)
- SPM+FIFO position management system
- Escalating protection system
- 4-panel chart dashboard
- Telegram + Discord notification system
- Account security verification
- Dynamic lot calculation
