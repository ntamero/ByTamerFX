# ByTamerFX - Expert Advisor for MetaTrader 5

**BytamerFX** - Profesyonel hibrit sinyal motoru ile otomatik forex trading sistemi.

> **SL=YOK** | **Asla zararina satis yok** | **SPM+FIFO Strateji**

---

## Ozellikler

### Sinyal Motoru - ByTamer Hybrid Signal System
- **12 indikator handle** (M15 + H1 + H4 multi-timeframe)
- **7 katmanli skor sistemi** (0-100 puan, min 35 giriş)
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

### Pozisyon Yonetimi - SPM+FIFO
- **SPM** (Sub Position Management): Zarardaki ana pozisyon icin ters yon hedge katmanlari
- **FIFO** (First In First Out): SPM karlari birikerek ana zarari karsilar
- Net hedef: SPM toplam kar - Ana zarar >= +$5
- Max 4 SPM katmani
- Otomatik yeni ana pozisyon acma (sinyal > trend > mum > hint onceligi)

### Koruma Sistemi
- Equity koruma: Max %25 drawdown -> tum pozisyonlar kapanir
- Dongu zarar limiti: -$10 max -> tum pozisyonlar kapanir
- Marjin acil durum: Level < %150 -> tum pozisyonlar kapanir
- Eskale eden cooldown: Her tetiklemede +5dk (max 30dk)
- Min bakiye kontrolu: $10 altinda islem yok

### Dashboard
- 4 panelli real-time chart dashboard (koyu tema)
- Panel 1: Hesap bilgileri, indikator degerleri, durum
- Panel 2: 7 katman sinyal skor detayi + progress bar
- Panel 3: TP1/TP2/TP3 hedefleri + trend gucu
- Panel 4: SPM+FIFO durumu + net ilerleme

### Bildirimler
- Telegram (HTML format + emoji + cerceve)
- Discord (Embed format + renk kodlu)
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
| SPM Max Katman | 4 |
| Net Hedef | $5 |
| Cooldown | 120sn (sinyal) / 60sn (SPM) |

---

## Dosya Yapisi

```
BytamerFX/
├── BytamerFX.mq5          # Ana EA dosyasi
├── Config.mqh             # Merkezi konfigurasyon
├── AccountSecurity.mqh    # Hesap dogrulama
├── SymbolManager.mqh      # Sembol kategorileme
├── SpreadFilter.mqh       # Spread kontrolu
├── CandleAnalyzer.mqh     # Mum analizi
├── LotCalculator.mqh      # Dinamik lot hesaplama
├── SignalEngine.mqh       # ByTamer Hybrid Signal System
├── TradeExecutor.mqh      # Islem yurutme (SL=0)
├── PositionManager.mqh    # SPM+FIFO motoru
├── TelegramMsg.mqh        # Telegram bildirimleri
├── DiscordMsg.mqh         # Discord bildirimleri
├── ChartDashboard.mqh     # 4 panel dashboard
└── .gitignore
```

---

## Guncelleme Gecmisi

### v1.1.0 (2026-02-17)
- **YENI**: ByTamer Hybrid Signal System - gelismis sinyal motoru
  - MACD + RSI diverjans motoru (regular + hidden)
  - Market structure analizi (HH/HL/LH/LL tepe/dip tespiti)
  - Bollinger squeeze tespiti (breakout ongorusu)
  - Mum formasyonu puanlama (Pin Bar, Engulfing, Doji)
  - Momentum shift algilama (ani hareket tespiti)
  - Multi-timeframe onay: H1 + H4 trend filtresi
  - ATR percentile ranking (volatilite rejimi)
  - RSI multi-TF: M15 + H1 uyum bonusu
- **IYILESTIRME**: Dashboard font +1, satir araligi +1, genislik +10
- **DUZELTME**: Discord embed description JSON escape
- **DUZELTME**: Telegram SendMessage public erisim
- Telegram token guncellendi

### v1.0.0 (2026-02-17)
- Ilk surum
- 7 katmanli temel sinyal motoru (EMA+MACD+ADX+RSI+BB+Stoch+ATR)
- SPM+FIFO pozisyon yonetim sistemi
- Eskale eden koruma sistemi
- 4 panelli chart dashboard
- Telegram + Discord bildirim sistemi
- Hesap guvenlik dogrulama
- Dinamik lot hesaplama

---

## Kurulum

1. Tum dosyalari `MQL5/Experts/BytamerFX/` klasorune kopyalayin
2. MetaEditor ile `BytamerFX.mq5` derleyin
3. MT5'te chart'a surukleyin
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

**Copyright 2026, By T@MER** | [www.bytamer.com](https://www.bytamer.com) | @ByT@MER
