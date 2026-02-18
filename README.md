# ByTamerFX - Expert Advisor for MetaTrader 5

**BytamerFX v2.2.1** - Profesyonel hibrit sinyal motoru ile otomatik forex trading sistemi.

> **SL=YOK** | **Asla zararina satis yok** | **SPM+FIFO Strateji** | **Akilli Hedge**

---

## Ozellikler

### Sinyal Motoru - ByTamer Hybrid Signal System (BHSS)
- **12 indikator handle** (M15 + H1 + H4 multi-timeframe)
- **7 katmanli skor sistemi** (0-100 puan, min 35 giris)
- EMA Ribbon (8/21/50) + crossover tespiti
- MACD Momentum + Diverjans motoru (regular + hidden)
- ADX Trend Gucu + DI gap analizi + slope tespiti
- RSI Seviye + Multi-TF RSI + Diverjans
- Bollinger Bands + Squeeze tespiti + %B hesaplama
- Stochastic K/D + Overbought/Oversold zonlari
- ATR Volatilite + Percentile ranking
- Market Structure analizi (HH/HL/LH/LL)
- Mum formasyonu tespiti (Pin Bar, Engulfing, Doji)
- Momentum shift algilama
- H1 + H4 trend filtresi (multi-timeframe onay)

### Pozisyon Yonetimi - KAZAN-KAZAN Hedge Sistemi (v2.0+)
- **SPM** (Sub Position Management): 5+5 yapi (max 5 BUY + 5 SELL katman)
- **5-Oy Sistemi**: SPM yonu icin H1 Trend + Sinyal Skor + M15 Mum + MACD + DI
- **FIFO** (First In First Out): SPM karlari birikerek ana zarari karsilar (net >= +$5)
- **CheckSameDirectionBlock**: Asla zarardaki ANA yonunde SPM acmaz, ters yone zorlar
- **DCA**: Zarardaki SPM icin maliyet ortalama
- **Acil Hedge**: Lot oran > 2:1 dengesizliginde otomatik hedge
- **Kilitlenme Tespiti**: 5dk net degisim < $0.50 -> pozisyon kapatma

### Dinamik Profil Sistemi (v2.1+)
- **10 enstruman profili**: Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt, Indices, Energy, Metal, Default
- **Pip-Bazli TP**: Her profil icin ayri TP1/TP2/TP3 pip mesafeleri
- **Dinamik Min Lot**: Forex=0.06, BTC/XAG/XAU=0.01, Indices=0.03
- **Profil Bazli SPM**: Her enstruman icin ayri tetik, lot, cooldown parametreleri
- **3 Katli Eslestirme**: Sembol-spesifik > JPY grubu > Kategori onceligi

### Universal News Intelligence (v2.2+)
- **MQL5 Calendar API**: Ekonomik takvim entegrasyonu (CalendarValueHistory)
- **Impact Bazli Bloklama**: CRITICAL/HIGH haberlerde islem engelleme
- **Para Birimi Tespiti**: Otomatik sembol-para birimi eslestirme
- **Sembol Filtresi**: Haber sadece ilgili sembolun chart'inda gorunur
- **Tam Genislik Banner**: Chart ustunde canli haber bilgisi (impact renkleri, geri sayim)

### Akilli Margin Yonetimi (v2.2.1)
- **Kademeli Kapatma**: %150 altinda sadece en zarardaki pozisyon kapatilir
- **Kritik Acil**: %120 altinda tum pozisyonlar kapatilir
- **Hesap geneli degil**, enstruman bazli akilli yonetim

### Lot Hesaplama - 8 Faktorlu Dinamik Motor
- Bakiye bazli temel lot
- ATR volatilite faktor
- Risk faktor (0.5-1.5x)
- Margin kullanim limiti
- Drawdown azaltma
- Korelasyon riski
- Streak faktor (ardisik kayip/kazanc)
- Zaman faktor (dusuk volatilite saatleri)

### Dashboard
- Tam genislik haber banner'i (impact renginde zemin + cerceve)
- 4 panelli real-time chart dashboard (koyu tema)
- Panel 1: Hesap bilgileri, indikator degerleri, durum
- Panel 2: 7 katman sinyal skor detayi + progress bar
- Panel 3: TP1/TP2/TP3 hedefleri + trend gucu + indikatorler
- Panel 4: SPM+FIFO durumu + net ilerleme

### Bildirimler
- Telegram (HTML format + emoji + bakiye/equity bilgisi)
- Discord (Embed format + renk kodlu + bakiye/equity bilgisi)
- MT5 Push Notification

### Guvenlik
- Hesap numarasi dogrulama (262230423)
- SL=0 MUTLAK kural (asla stop loss yok)
- 5 dakika aralikla hesap tekrar dogrulama

---

## Teknik Detaylar

| Ozellik | Deger |
|---------|-------|
| Platform | MetaTrader 5 (Build 5200+) |
| Dil | MQL5 |
| Timeframe | M15 (giris) + H1/H4 (filtre) |
| Min Bakiye | $10 |
| Min Sinyal Skor | 35/100 |
| SPM Max Katman | 5 BUY + 5 SELL |
| FIFO Net Hedef | $5 |
| Margin Uyari | <%150 (kademeli kapatma) |
| Margin Kritik | <%120 (tum kapat) |
| SPM Tetik | Forex: -$3, BTC/XAG/XAU: -$5 |
| Min Lot | Forex: 0.06, Metal/Crypto: 0.01, Indices: 0.03 |
| Profil Sayisi | 10 enstruman profili |

---

## Dosya Yapisi

```
BytamerFX/
├── BytamerFX.mq5          # Ana EA dosyasi (v2.2.1)
├── Config.mqh             # Merkezi konfigurasyon + 10 SymbolProfile
├── AccountSecurity.mqh    # Hesap dogrulama
├── SymbolManager.mqh      # Sembol kategorileme
├── SpreadFilter.mqh       # Spread kontrolu
├── CandleAnalyzer.mqh     # Mum analizi + formasyon tespiti
├── LotCalculator.mqh      # 8 faktorlu dinamik lot hesaplama
├── SignalEngine.mqh       # ByTamer Hybrid Signal System (BHSS)
├── TradeExecutor.mqh      # Islem yurutme (SL=0 MUTLAK)
├── PositionManager.mqh    # KAZAN-KAZAN Hedge + SPM+FIFO motoru
├── NewsManager.mqh        # Universal News Intelligence
├── TelegramMsg.mqh        # Telegram bildirimleri (emoji + bakiye)
├── DiscordMsg.mqh         # Discord bildirimleri (embed + bakiye)
├── ChartDashboard.mqh     # Haber banner + 4 panel dashboard
├── CHANGELOG.md           # Detayli versiyon gecmisi
├── compile.ps1            # PowerShell derleme scripti
└── .gitignore
```

---

## Versiyon Gecmisi

Detayli degisiklik listesi icin [CHANGELOG.md](CHANGELOG.md) dosyasina bakin.

| Versiyon | Tarih | Aciklama |
|----------|-------|----------|
| v2.2.1 | 2026-02-18 | SPM SAME-DIR BLOCK fix, Akilli Margin, Haber Filtresi |
| v2.2.0 | 2026-02-18 | Universal News Intelligence, Dinamik Lot, Emoji |
| v2.1.0 | 2026-02-17 | Dinamik Profil Sistemi, Pip-Bazli TP |
| v2.0.1 | 2026-02-17 | Hedge bug fix |
| v2.0.0 | 2026-02-17 | KAZAN-KAZAN Hedge Sistemi, 5+5 SPM, FIFO |
| v1.3.0 | 2026-02-17 | SmartSPM, Guclu Hedge |
| v1.2.0 | 2026-02-17 | SPM-FIFO Kar Odakli Sistem |
| v1.1.0 | 2026-02-17 | ByTamer Hybrid Signal System |
| v1.0.0 | 2026-02-17 | Ilk surum |

---

## Kurulum

1. Tum dosyalari `MQL5/Experts/BytamerFX/` klasorune kopyalayin
2. MetaEditor ile `BytamerFX.mq5` derleyin
3. MT5'te chart'a surukleyin (M15 timeframe)
4. **Ayarlar** > Tools > Options > Expert Advisors:
   - "Allow DLL imports" isaretli
   - "Allow WebRequest" aktif
   - URL listesine ekleyin:
     - `https://api.telegram.org`
     - `https://discordapp.com`
5. EA ayarlarindan Telegram/Discord bilgilerini girin

---

## Yasal Uyari

> **Bu yazilim yatirim tavsiyesi degildir.** Forex ve CFD ticareti yuksek risk icerir. Gecmis performans gelecek sonuclari garanti etmez. Yatirim kararlarinizi kendi arastirmaniza dayanarak verin.

---

**Copyright 2026, By T@MER** | [www.bytamer.com](https://www.bytamer.com)
