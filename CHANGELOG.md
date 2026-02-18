# Changelog - BytamerFX EA

Tum onemli degisiklikler bu dosyada belgelenir.

---

## [v2.2.1] - 2026-02-18

### Kritik Duzeltmeler
- **SPM SAME-DIR BLOCK Sonsuz Dongu Fix**: ANA zarardayken 5-oy ayni yonu gosterince SPM hic acilmiyordu. Override sonrasi `ShouldWaitForANARecovery` artik atlanir, SPM hemen ters yonde acilir.
- **Margin Acil Durum Akilli Yonetim**: `MinMarginLevel` 200% -> 150% dusuruldu. %150 altinda sadece en zarardaki 1 pozisyon kapatilir (kademeli). %120 altinda tum pozisyonlar kapatilir (gercek acil).
- **SPM Log Spam Onleme**: 30 saniyelik cooldown eklendi. Tick basina tekrarlanan SPM loglari artik 30sn aralikla yazilir.

### Yeni Ozellikler
- **Haber Banner Sembol Filtresi**: Haber artik sadece ilgili sembolun chart'inda gorunur (GBP haberi XAG'da gozukmez).
- **Haber Banner Renkleri**: Zemin renkleri cok daha parlak ve belirgin yapildi (KRITIK=kirmizi, YUKSEK=turuncu, ORTA=sari). Cerceve kalinligi 2px.
- **Dinamik Min Lot**: Kategori bazli minimum lot: Forex=0.06, BTC/XAG/XAU=0.01, Indices=0.03.
- **Haber Bazli Islem Bloklama**: Sadece ilgili sembolu etkileyen haberler islem bloklama yapar.

### Degisiklikler
- `Config.mqh`: SymbolProfile'a `minLotOverride` alani eklendi, 10 profil guncellendi
- `LotCalculator.mqh`: `Initialize()` fonksiyonuna `profileMinLot` parametresi eklendi
- `PositionManager.mqh`: `m_lastSPMLogTime` ve `m_spmDirOverridden` alanlari eklendi
- `NewsManager.mqh`: `GetActiveNewsInfo/GetNextNewsInfo`'ya `onlyRelevant` filtresi eklendi
- `ChartDashboard.mqh`: Panel 5 yerine tam genislik ust haber banner'i (24px, dinamik genislik)

---

## [v2.2.0] - 2026-02-18

### Yeni Ozellikler
- **Universal News Intelligence**: MQL5 CalendarValueHistory API ile ekonomik takvim entegrasyonu
- **Dinamik Lot Hesaplama**: 8 faktorlu lot motoru (bakiye, volatilite, risk, margin, DD, korelasyon, streak, zaman)
- **Emoji Bildirimler**: Telegram + Discord mesajlarinda otomatik emoji ve bakiye/equity bilgisi
- **Dashboard Haber Paneli**: Chart uzerinde canli haber bilgisi (impact renkleri, geri sayim)

### Degisiklikler
- `NewsManager.mqh` eklendi: Haber yukleyici, para birimi tespiti, impact bazli bloklama
- `ChartDashboard.mqh`: 5 panelli dashboard (haber paneli eklendi)
- `TelegramMsg.mqh` / `DiscordMsg.mqh`: Emoji + bakiye/equity bilgisi

---

## [v2.1.0] - 2026-02-17

### Yeni Ozellikler
- **Dinamik Profil Sistemi**: 10 enstruman profili (Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt, Indices, Energy, Metal, Default)
- **Pip-Bazli TP**: Her profil icin ayri TP1/TP2/TP3 pip mesafeleri
- **3 Katli Sembol Eslestirme**: Sembol-spesifik > JPY grubu > Kategori onceligi

### Degisiklikler
- `Config.mqh`: SymbolProfile struct + 10 profil metodu + GetSymbolProfile()
- `PositionManager.mqh`: Profil bazli SPM tetik, lot, cooldown parametreleri

---

## [v2.0.1] - 2026-02-17

### Duzeltmeler
- **Hedge Bug Fix**: Hedge pozisyonunun aninda kapanma hatasi duzeltildi
- Hedge acildiginda SPM sistemi bir sonraki check'e kadar bekler

---

## [v2.0.0] - 2026-02-17

### Buyuk Degisiklik - KAZAN-KAZAN Hedge Sistemi
- **5+5 SPM Yapi**: Max 5 BUY + 5 SELL ayri katman limiti
- **5-Oy Sistemi**: SPM yonu icin H1 Trend + Sinyal Skor + M15 Mum + MACD Histogram + DI Crossover
- **FIFO Net Hedef**: kasaKar + acikSPMKar + acikSPMZarar + anaP/L >= +$5 -> TUM KAPAT
- **DCA Mekanizmasi**: Zarardaki SPM icin maliyet ortalama (max 1 per pozisyon)
- **Acil Hedge**: Lot oran > 2:1 + zarardaki taraf buyukse hedge
- **Kilitlenme Tespiti**: 5dk net degisim < $0.50 -> tum kapat
- **CheckSameDirectionBlock**: Asla zarardaki ANA yonunde SPM acma

### Kaldirilanlar
- Terfi (SPM->ANA) sistemi kaldirildi (kara delik yaratiyordu)
- DD-bazli equity koruma kaldirildi (kullanici istegi)

---

## [v1.3.0] - 2026-02-17

### Yeni Ozellikler
- **SmartSPM**: Akilli SPM yon belirleme
- **Guclu Hedge**: Tek tarafli risk tespiti + otomatik hedge

---

## [v1.2.0] - 2026-02-17

### Yeni Ozellikler
- **SPM-FIFO Kar Odakli Sistem**: Kucuk karlari biriktirme stratejisi
- PeakDrop sadece SPM'lere uygulanir (ANA'ya degil)

---

## [v1.1.0] - 2026-02-17

### Yeni Ozellikler
- **ByTamer Hybrid Signal System**: 7 katmanli gelismis sinyal motoru
- MACD + RSI diverjans motoru (regular + hidden)
- Market structure analizi (HH/HL/LH/LL)
- Bollinger squeeze tespiti
- Mum formasyonu puanlama
- Multi-timeframe onay (H1 + H4)
- ATR percentile ranking

### Duzeltmeler
- Discord embed description JSON escape
- Telegram SendMessage public erisim

---

## [v1.0.0] - 2026-02-17

### Ilk Surum
- 7 katmanli temel sinyal motoru (EMA+MACD+ADX+RSI+BB+Stoch+ATR)
- SPM+FIFO pozisyon yonetim sistemi
- Eskale eden koruma sistemi
- 4 panelli chart dashboard
- Telegram + Discord bildirim sistemi
- Hesap guvenlik dogrulama
- Dinamik lot hesaplama
