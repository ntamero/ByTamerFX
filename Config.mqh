//+------------------------------------------------------------------+
//|                                                      Config.mqh  |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX v2.0 - KAZAN-KAZAN Hedge Sistemi                      |
//| Merkezi Konfigurasyon                                            |
//| VERSIYON TEK KAYNAKTAN OKUNUR - Diger dosyalar buradan alir     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef CONFIG_MQH
#define CONFIG_MQH

//=================================================================
// MERKEZI VERSIYON - TEK KAYNAK
// BytamerFX.mq5 #property satirlari ELLE guncellenmeli (MQL5 kisiti)
//=================================================================
#define EA_VERSION        "4.5.0"
#define EA_VERSION_NUM    "4.50"
#define EA_VERSION_NAME   "SPM-Cycle"
#define EA_VERSION_FULL   "BytamerFX v4.5.0 - SPM Dongusu (Limit Yok + Saf SPM Yonetimi + MIA Entegrasyonu)"
#define EA_BUILD_DATE     __DATE__

//=================================================================
// LISANS + HESAP GUVENLIK
//=================================================================
input string   LicenseKey             = "";              // Lisans Anahtari (BTAI-XXXXX-XXXXX-XXXXX-XXXXX)
input long     ExpectedAccountNumber  = 262230423;               // Broker Hesap Numarasi (Exness)

//=================================================================
// TELEGRAM
//=================================================================
input string   TelegramToken          = "7682893549:AAFCRCMLRF8TQmw3U7NZvj1upqeIvSs5dMA";  // Telegram Bot Token (@BotFather)
input string   TelegramChatID         = "-1003212753244";                                  // Telegram Chat/Group ID

//=================================================================
// DISCORD
//=================================================================
input string   DiscordWebhookURL      = "";              // Discord Webhook URL

//=================================================================
// BILDIRIM
//=================================================================
input bool     EnableTelegram         = true;
input bool     EnableDiscord          = true;
input bool     EnablePushNotification = true;

//=================================================================
// ISLEM AYARLARI
//=================================================================
input int      MagicNumber            = 20260217;
input int      MaxSlippage            = 30;

//=================================================================
// RISK YONETIMI
//=================================================================
input double   BaseLotPer1000         = 0.01;
input double   InputMinLot            = 0.01;
input double   InputMaxLot            = 0.5;
input double   MaxSpreadPercent       = 15.0;
input double   MaxSpreadMultiplier    = 1.15;     // v3.5.0: Spread max %15 ustu = islem acma

//=================================================================
// SINYAL MOTORU
//=================================================================
input int      SignalMinScore         = 40;        // v3.4.0: firsat kacirilmasin (giris sonrasi mekanizma korur)
input int      SignalCooldownSec      = 120;

//=================================================================
// TREND-GRID + FIFO SISTEMI (v3.0.0)
//=================================================================
input double   SPM_TriggerLoss        = -3.0;     // v3.0.0: Grid tetik (fallback $) - artik ATR bazli
input double   SPM_CloseProfit        = 3.0;      // v3.0.0: Grid kar hedefi ($) - forex +3
input double   SPM_NetTargetUSD       = 5.0;      // FIFO net hedef ($) - toplam net >= +5$
input int      SPM_MaxBuyLayers       = 10;       // v3.0.0: Max BUY grid (10+10 yapi)
input int      SPM_MaxSellLayers      = 10;       // v3.0.0: Max SELL grid
input double   SPM_LotBase            = 1.0;      // Grid lot carpani (1.0x = ANA ile ayni)
input double   SPM_LotIncrement       = 0.1;      // Katman basi +0.1x artis
input double   SPM_LotCap             = 1.5;      // Max carpan 1.5x
input int      SPM_CooldownSec        = 30;       // v3.3.0: 60→30sn grid arasi bekleme (yakalama ↑%40)
input int      SPM_WaitMaxSec         = 180;      // ANA toparlanma bekleme suresi (sn)
input int      SPM_WarmupSec          = 45;       // v3.6.0: EA yuklendikten sonra SPM bekleme (sn)
input int      SPM_MinADX             = 40;        // v3.7.0: ADX 40 (eski 38)       // v3.6.0: SPM acmak icin min ADX degeri (guclu trend)

//=================================================================
// v4.2.0: GRID RESET + NET-EXPOSURE SPM
//=================================================================
input double   GridLossPercent        = 0.25;      // v4.2: Grid reset esigi (equity %)
input double   GridLossMinUSD         = 30.0;      // v4.2: Grid reset min $ esigi
input int      SPM_MaxLayers          = 3;         // v4.2: Max SPM katman (eski max 2)

//=================================================================
// v3.4.0: BI-DIRECTIONAL GRID + AKILLI KAR SISTEMI
//=================================================================
input int      TrendCheckIntervalSec  = 120;      // v3.4.0: Trend kontrol araligi (5dk->2dk)
input int      TrendConfirmCount      = 2;        // v3.4.0: Trend onay sayisi (2 ardisik ayni yon)
input bool     EnableReverseGrid      = true;     // v3.4.0: Bi-directional mod (false=v3.0.0)
input double   LotReductionPerGrid    = 0.03;     // v3.3.0: %5→%3 grid basi lot azaltma (Grid10=%70 kalir)
input int      NewsGridWidenPercent   = 50;       // v3.4.0: Haber yakininda grid genisleme (%)

//=================================================================
// DCA (MALIYET ORTALAMA) SISTEMI - v2.0 YENI
//=================================================================
input int      DCA_CooldownSec        = 120;      // DCA acma arasi bekleme (sn)
input double   DCA_DistanceATR        = 2.0;      // DCA mesafesi (ATR carpani)
input int      DCA_MaxPerPosition     = 1;        // Pozisyon basi max DCA sayisi

//=================================================================
// ACIL HEDGE SISTEMI - v2.0 YENI
//=================================================================
input double   Hedge_RatioTrigger     = 2.0;      // Lot oran tetigi (BUY/SELL > bu)
input double   Hedge_FillPercent      = 0.70;     // Eksik lotun yuzde kaci hedge edilir
input int      Hedge_CooldownSec      = 120;      // Hedge acma arasi bekleme (sn)

//=================================================================
// KILITLENME TESPIT - v2.0 YENI
//=================================================================
input int      Deadlock_CheckSec      = 30;       // Kilitlenme kontrol araligi (sn)
input int      Deadlock_TimeoutSec    = 300;      // Kilitlenme tespit suresi (5dk)
input double   Deadlock_MinChange     = 0.50;     // Min net degisim ($) - altinda "degismedi"
input double   Deadlock_MaxLossRatio  = 0.15;     // Bakiye yuzde kaybinda kapat (%15)
input int      Deadlock_CooldownSec   = 120;      // Kilitlenme sonrasi bekleme (sn)

//=================================================================
// KORUMA SISTEMI
//=================================================================
input double   MaxDrawdownPercent     = 30.0;     // Max DD% - son care tum kapat
input double   MaxCycleLossUSD        = -15.0;    // Dongu max zarar ($)
input double   DailyProfitTarget      = 10.0;     // Gunluk kar hedefi ($)
input int      ProtectionCooldownSec  = 180;      // Koruma sonrasi bekleme (sn)
input double   MinBalanceToTrade      = 10.0;     // Min bakiye ($)
input double   MaxTotalVolume         = 2.0;      // Max toplam acik hacim (lot)
input double   MinMarginLevel         = 300.0;    // v2.4.3: Min margin seviyesi (%) - %300 altinda SPM kapat, %150 altinda herhangi kapat

//=================================================================
// v3.4.0: POST-ENTRY KARLILIK MOTORU
//=================================================================
input bool     EnablePartialClose     = true;      // v3.4.0: Kismi kapama (scale-out) ON/OFF
input double   PartialClosePercent    = 60.0;      // v3.4.0: Kismi kapama yuzde (%60 kapat, %40 devam)
input double   PartialCloseTriggerUSD = 5.0;       // v4.4.0: Kismi kapama tetik ($5 kar) (eski $3)
input bool     EnableBreakevenLock    = true;       // v3.4.0: Sanal breakeven kilidi ON/OFF
input double   BreakevenTriggerUSD    = 3.0;        // v4.4.0: Trailing Floor baslangic ($3 kar) (eski $2)

//=================================================================
// KAR YONETIMI
//=================================================================
input double   QuickProfitUSD         = 1.5;      // Hizli kar hedefi ($)
input double   TrailActivateUSD       = 1.0;      // Trailing aktif ($)
input double   TrailStepUSD           = 0.30;     // Trailing step ($)
input double   PeakDropPercent        = 45.0;     // v3.3.0: %50→%45 base (ANA=%35, SPM=%45, DCA=%55)
input double   PeakMinProfit          = 2.0;      // v4.4.0: Peak drop icin min kar ($) (eski $1)
input double   HedgePeakDropPercent   = 25.0;     // v3.6.4: HEDGE PeakDrop - tepe dusus yüzdesi (25%=tepeden %25 dusunce kapat)
input double   HedgePeakMinProfit     = 8.0;      // v3.6.4: HEDGE PeakDrop - minimum tepe kar ($) (peak >= $8 olmadan tetiklenmez)
input int      RescueHedgeMinScore    = 80;        // v3.6.5: Sinyal >= 80 + ANA yonu → HEDGE acma (guclu destek)

//=================================================================
// v2.2: HABER SISTEMI (UNIVERSAL NEWS INTELLIGENCE)
//=================================================================
input bool     EnableNewsFilter       = true;       // Haber filtresi aktif
input int      NewsBlockBeforeMin     = 20;         // Haber oncesi blok (dakika)
input int      NewsBlockAfterMin      = 5;          // Haber sonrasi blok (dakika)
input int      NewsAlertBeforeMin     = 30;         // Haber oncesi bildirim (dakika)

//=================================================================
// GORSEL
//=================================================================
input bool     EnableDashboard        = true;
input int      ArrowSize              = 5;

//=================================================================
// ENUM TANIMLARI
//=================================================================

enum ENUM_SYMBOL_CATEGORY
{
   CAT_FOREX   = 0,
   CAT_METAL   = 1,
   CAT_CRYPTO  = 2,
   CAT_INDICES = 3,
   CAT_STOCKS  = 4,
   CAT_ENERGY  = 5,
   CAT_UNKNOWN = 6
};

enum ENUM_SIGNAL_DIR
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

enum ENUM_POS_ROLE
{
   ROLE_MAIN  = 0,
   ROLE_SPM   = 1,
   ROLE_DCA   = 2,    // v2.0: Maliyet ortalama pozisyonu
   ROLE_HEDGE = 3     // v2.0: Acil hedge pozisyonu
};

enum ENUM_TREND_STRENGTH
{
   TREND_WEAK     = 0,    // ADX < 25
   TREND_MODERATE = 1,    // 25 <= ADX < 35
   TREND_STRONG   = 2     // ADX >= 35
};

//--- v3.4.0: Volatilite rejimi
enum ENUM_VOLATILITY_REGIME
{
   VOL_LOW      = 0,    // ATR < 0.8x ortalama
   VOL_NORMAL   = 1,    // 0.8-1.5x ortalama
   VOL_HIGH     = 2,    // 1.5-2.5x ortalama
   VOL_EXTREME  = 3     // > 2.5x ortalama → grid ACILMAZ
};

//=================================================================
// STRUCT TANIMLARI
//=================================================================

struct SignalData
{
   ENUM_SIGNAL_DIR    direction;
   int                score;
   double             atr;
   double             rsi;
   double             adx;
   double             plusDI;
   double             minusDI;
   double             macd_main;
   double             macd_signal;
   double             macd_hist;
   double             bb_upper;
   double             bb_lower;
   double             bb_middle;
   double             ema_fast;
   double             ema_mid;
   double             ema_slow;
   double             stoch_k;
   double             stoch_d;
   double             tp;
   double             sl;
   double             tp1;
   double             tp2;
   double             tp3;
   ENUM_TREND_STRENGTH trendStrength;
   datetime           time;
   string             reason;

   void Clear()
   {
      direction = SIGNAL_NONE; score = 0;
      atr = 0; rsi = 0; adx = 0; plusDI = 0; minusDI = 0;
      macd_main = 0; macd_signal = 0; macd_hist = 0;
      bb_upper = 0; bb_lower = 0; bb_middle = 0;
      ema_fast = 0; ema_mid = 0; ema_slow = 0;
      stoch_k = 0; stoch_d = 0;
      tp = 0; sl = 0; tp1 = 0; tp2 = 0; tp3 = 0;
      trendStrength = TREND_WEAK; time = 0; reason = "";
   }
};

struct PositionInfo
{
   ulong              ticket;
   string             symbol;
   ENUM_POSITION_TYPE type;
   ENUM_POS_ROLE      role;
   int                spmLayer;
   ulong              parentTicket;   // v2.0: DCA icin orijinal pozisyon bileti
   double             volume;
   double             openPrice;
   double             profit;
   double             sl;
   double             tp;
   datetime           openTime;
   string             comment;
};

struct SPMLayerInfo
{
   ulong              ticket;
   int                layer;
   ENUM_SIGNAL_DIR    direction;
   double             lots;
   double             openPrice;
   double             profit;
   double             closedProfit;
   bool               isClosed;
   datetime           openTime;
   datetime           closeTime;
};

struct TPLevelInfo
{
   int                currentLevel;
   double             tp1Price;
   double             tp2Price;
   double             tp3Price;
   bool               tp1Hit;
   bool               tp2Hit;
   bool               tpExtended;
   ENUM_TREND_STRENGTH trendStrength;
};

struct FIFOSummary
{
   double             closedProfitTotal;  // Toplam kapatilan SPM kari
   int                closedCount;        // Kapatilan SPM sayisi
   int                activeSPMCount;     // Aktif SPM sayisi
   int                activeDCACount;     // v2.0: Aktif DCA sayisi
   int                activeHedgeCount;   // v2.0: Aktif Hedge sayisi
   int                buyLayerCount;      // v2.0: BUY katman sayisi
   int                sellLayerCount;     // v2.0: SELL katman sayisi
   double             openSPMProfit;      // Acik SPM P/L (pozitifler)
   double             openSPMLoss;        // v2.0: Acik SPM P/L (negatifler)
   double             mainLoss;           // Ana pozisyon P/L
   double             netResult;          // Net sonuc
   double             targetUSD;          // Hedef ($)
   bool               isProfitable;       // Hedef ulasildi mi?

   //--- v2.3.0: Dashboard istatistikleri
   double             dailyProfit;        // Gunluk realize kar
   double             dailyProfitPct;     // Gunluk kar yuzdesi
   int                totalBuyTrades;     // Toplam BUY islem adedi
   int                totalSellTrades;    // Toplam SELL islem adedi
   int                dailyTradeCount;    // Bugun acilan islem adedi

   //--- v3.4.0: Bi-Directional Grid istatistikleri
   bool               biDirectionalMode;  // Bi-dir mod aktif mi
   string             activeGridDirStr;   // Aktif grid yonu (BUY/SELL)
   string             legacyGridDirStr;   // Eski grid yonu
   int                activeGridCount;    // Aktif yon grid sayisi
   int                legacyGridCount;    // Eski yon grid sayisi
   string             volatilityRegime;   // Volatilite rejimi ("LOW","NORMAL","HIGH","EXTREME")
   double             adaptiveSpacing;    // Adaptif grid mesafesi (pips)
};

struct ScoreBreakdown
{
   int emaTrend;
   int macdMomentum;
   int adxStrength;
   int rsiLevel;
   int bbPosition;
   int stochSignal;
   int atrVolatility;
   int totalScore;

   void Clear()
   {
      emaTrend = 0; macdMomentum = 0; adxStrength = 0;
      rsiLevel = 0; bbPosition = 0; stochSignal = 0;
      atrVolatility = 0; totalScore = 0;
   }
};

//=================================================================
// v2.0: ENSTRUMAN PROFILI
//=================================================================
struct SymbolProfile
{
   //--- SPM / FIFO parametreleri
   double spmTriggerLoss;       // v3.7.0: ANA zarar → SPM1 tetik ($)
   double spm2TriggerLoss;      // v3.7.0: SPM1 zarar → SPM2 tetik ($)
   double spmCloseProfit;       // SPM kar hedefi ($) — TP1
   double fifoNetTarget;        // FIFO net hedef ($)
   int    spmMaxBuyLayers;      // Max BUY katman
   int    spmMaxSellLayers;     // Max SELL katman
   double spmLotBase;           // SPM lot carpani
   double spmLotIncrement;      // Katman basi lot artisi
   double spmLotCap;            // Max carpan
   int    spmCooldownSec;       // SPM arasi bekleme (sn)
   double dcaDistanceATR;       // DCA mesafesi (ATR carpani)
   double profitTargetPerPos;   // Pozisyon basi kar hedefi ($)
   int    hedgeMinSPMCount;     // Hedge icin minimum SPM sayisi
   double hedgeMinLossUSD;      // Hedge icin minimum toplam zarar ($)

   //--- v2.1: DINAMIK TP DEGERLERI (PIPS olarak)
   //--- Trend gucune gore: WEAK→TP1, MODERATE→TP2, STRONG→TP3
   double tp1Pips;              // Zayif trend TP (pips)
   double tp2Pips;              // Orta trend TP (pips)
   double tp3Pips;              // Guclu trend TP (pips)

   //--- v2.3.0: ANA kar hedefi (SPM yokken ANA kapat esigi)
   double anaCloseProfit;          // ANA tek basina karda iken bu hedefe ulasinca kapat ($)

   //--- v2.2.2: Min kar esigi (maliyeti kurtarmayan islem KAPATMAZ)
   double minCloseProfit;          // Min kapatma kari ($) - bunun altinda SPM/DCA/HEDGE kapatilmaz

   //--- v2.2.1: Dinamik min lot (kategori bazli)
   double minLotOverride;          // 0 = broker default, >0 = profil override

   //--- v2.1: Profil adi (log icin)
   string profileName;

   //--- v3.4.0: Bi-Directional Grid parametreleri
   double gridATRMultLow;          // Dusuk vol grid ATR carpani
   double gridATRMultNormal;       // Normal vol grid ATR carpani
   double gridATRMultHigh;         // Yuksek vol grid ATR carpani
   double candleCloseWeak;         // Zayif trend mum donus min kari ($)
   double candleCloseModerate;     // Orta trend mum donus min kari ($)
   double candleCloseStrong;       // Guclu trend mum donus min kari ($)
   double trendCloseMultModerate;  // Orta trend kar carpani
   double trendCloseMultStrong;    // Guclu trend kar carpani
   int    trendConfirmBars;        // Trend degisimi onay bar sayisi

   //--- v3.5.7: Rescue Hedge parametreleri
   double rescueHedgeThreshold;    // ANA zarar esigi ($) - bu deger asilinca rescue hedge acar
   double rescueHedgeLotMult;      // Rescue hedge lot carpani (zarardaki toplam lot * bu)

   //--- v4.2.0: Grid Reset + Net-Exposure SPM
   double gridLossPercent;         // v4.2: Grid reset esigi (equity %)
   double gridLossMinUSD;          // v4.2: Grid reset min $ esigi
   int    spmMaxLayers;            // v4.2: Max SPM katman (eski max 2)

   //---------- PROFIL AYAR FONKSIYONLARI ----------

   //--- FOREX (EURUSD, GBPUSD vb. - JPY haric)
   void SetForex()
   {
      profileName       = "FOREX";
      minLotOverride    = 0.03;       // Forex: min 0.03 lot (v4.0: $100 bakiye uyumu)
      minCloseProfit    = 2.5;        // v4.4.0: $2.5 min (eski $2)
      anaCloseProfit    = 5.0;        // v3.5.3: ANA +$5 → kapat (eski $4)
      spmTriggerLoss    = -4.0;       // v3.7.0: ANA -$4 → SPM1 (Forex)
      spm2TriggerLoss   = -5.0;       // v3.7.0: SPM1 -$5 → SPM2 (Forex)
      spmCloseProfit    = 4.0;        // v4.4.0: TP1 $4 (eski $3)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;
      spmLotIncrement   = 0.1;
      spmLotCap         = 1.5;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 3.0;
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 30.0;
      tp2Pips           = 60.0;
      tp3Pips           = 100.0;
      //--- v3.5.0: Bi-Dir Grid
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.00;       // v4.4.0: (eski $1.50)
      candleCloseModerate = 4.50;     // v4.4.0: (eski $3.00)
      candleCloseStrong = 7.00;       // v4.4.0: (eski $5.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (Forex)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;      // v4.2: Grid reset esigi (%25 equity)
      gridLossMinUSD    = 30.0;      // v4.2: Grid reset min $30
      spmMaxLayers      = 3;         // v4.2: Max 3 SPM katman
   }

   //--- FOREX JPY pariteler (USDJPY, GBPJPY, EURJPY vb.)
   void SetForexJPY()
   {
      profileName       = "FOREX_JPY";
      minLotOverride    = 0.03;       // JPY: min 0.03 lot (v4.0: $100 bakiye uyumu)
      minCloseProfit    = 2.5;        // v4.4.0: $2.5 min (eski $2)
      anaCloseProfit    = 5.0;        // v3.5.3: ANA +$5 (eski $4)
      spmTriggerLoss    = -4.0;       // v3.7.0: ANA -$4 → SPM1 (Forex JPY)
      spm2TriggerLoss   = -5.0;       // v3.7.0: SPM1 -$5 → SPM2
      spmCloseProfit    = 4.0;        // v4.4.0: TP1 $4 (eski $3)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;
      spmLotIncrement   = 0.1;
      spmLotCap         = 1.5;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 3.0;
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 40.0;
      tp2Pips           = 80.0;
      tp3Pips           = 130.0;
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.00;       // v4.4.0: (eski $1.50)
      candleCloseModerate = 4.50;     // v4.4.0: (eski $3.00)
      candleCloseStrong = 7.00;       // v4.4.0: (eski $5.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- GUMUS (XAG)
   void SetSilver()
   {
      profileName       = "SILVER_XAG";
      minLotOverride    = 0.01;       // XAG: min 0.01 lot
      minCloseProfit    = 2.5;        // v3.5.3: $2.5 min (eski $1 XAG spread yuksek)
      anaCloseProfit    = 7.0;        // v3.5.3: ANA +$7 (eski $5)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (XAG)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (XAG)
      spmCloseProfit    = 5.0;        // v3.7.0: SPM TP +$5 (XAG)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (XAG)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 4.0;       // v3.5.3: $4 (eski $2)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 20.0;       // Zayif trend: 20 pips
      tp2Pips           = 50.0;       // Orta trend: 50 pips
      tp3Pips           = 80.0;       // Guclu trend: 80 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.50;       // v4.4.0: (eski $2.00)
      candleCloseModerate = 5.50;     // v4.4.0: (eski $4.00)
      candleCloseStrong = 8.00;       // v4.4.0: (eski $6.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (XAG)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (XAG)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- ALTIN (XAU)
   void SetGold()
   {
      profileName       = "GOLD_XAU";
      minLotOverride    = 0.01;       // XAU: min 0.01 lot
      minCloseProfit    = 2.5;        // v3.5.3: $2.5 min (eski $1 XAU spread yuksek)
      anaCloseProfit    = 7.0;        // v3.5.3: ANA +$7 (eski $5)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (XAU)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (XAU)
      spmCloseProfit    = 5.0;        // v3.7.0: SPM TP +$5 (XAU)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (XAU)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 75;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 4.0;       // v3.5.3: $4 (eski $2.5)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 50.0;       // Zayif trend: 50 pips
      tp2Pips           = 120.0;      // Orta trend: 120 pips
      tp3Pips           = 200.0;      // Guclu trend: 200 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.50;       // v4.4.0: (eski $2.00)
      candleCloseModerate = 5.50;     // v4.4.0: (eski $4.00)
      candleCloseStrong = 9.00;       // v4.4.0: (eski $7.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (XAU)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (XAU)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- BITCOIN (BTC)
   void SetCrypto()
   {
      profileName       = "CRYPTO_BTC";
      minLotOverride    = 0.01;       // BTC: min 0.01 lot
      minCloseProfit    = 3.0;        // v3.5.2: $3 altinda kapatma (BTC spread ~$0.18/trade, min anlamli kar)
      anaCloseProfit    = 8.0;        // v3.5.2: ANA +$8 → kapat (eski $5 yetersizdi)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (BTC)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (BTC)
      spmCloseProfit    = 6.0;        // v4.4.0: SPM TP +$6 (eski $5)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (BTC)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 90;
      dcaDistanceATR    = 2.5;
      profitTargetPerPos = 5.0;       // v3.5.2: $5 (eski $3 yetersizdi)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;       // BTC: -$5 hedge esigi
      tp1Pips           = 15000.0;    // v2.2.2: Zayif trend: 15000 pips ($1.5+ at 0.01 lot)
      tp2Pips           = 30000.0;    // v2.2.2: Orta trend: 30000 pips ($3+ at 0.01 lot)
      tp3Pips           = 50000.0;    // v2.2.2: Guclu trend: 50000 pips ($5+ at 0.01 lot)
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 5.00;       // v4.4.0: (eski $3.00)
      candleCloseModerate = 7.00;     // v4.4.0: (eski $5.00)
      candleCloseStrong = 10.00;      // v4.4.0: (eski $8.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (BTC)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (BTC)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- DIGER KRIPTO (ETH, LTC, XRP vb.)
   void SetCryptoAlt()
   {
      profileName       = "CRYPTO_ALT";
      minLotOverride    = 0.01;       // Altcoin: min 0.01 lot
      minCloseProfit    = 2.5;        // v3.5.3: $2.5 min (eski $1 altcoin spread yuksek)
      anaCloseProfit    = 7.0;        // v3.5.3: ANA +$7 (eski $5)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (CryptoAlt)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (CryptoAlt)
      spmCloseProfit    = 5.0;        // v3.7.0: SPM TP +$5 (CryptoAlt)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (CryptoAlt)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 90;
      dcaDistanceATR    = 2.5;
      profitTargetPerPos = 4.0;       // v3.5.3: $4 (eski $2.5)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 5000.0;     // v2.2.2: Altcoin: 5000 pips (daha genis)
      tp2Pips           = 10000.0;    // 10000 pips
      tp3Pips           = 18000.0;    // 18000 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.50;       // v4.4.0: (eski $2.00)
      candleCloseModerate = 5.50;     // v4.4.0: (eski $4.00)
      candleCloseStrong = 8.00;       // v4.4.0: (eski $6.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (CryptoAlt)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (CryptoAlt)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- ENDEKSLER (US30, NAS100, SPX500 vb.)
   void SetIndices()
   {
      profileName       = "INDICES";
      minLotOverride    = 0.03;       // Indices: min 0.03 lot
      minCloseProfit    = 2.5;        // v3.5.3: $2.5 min (eski $1 indeks spread yuksek)
      anaCloseProfit    = 7.0;        // v3.5.3: ANA +$7 (eski $5)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (Indices)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (Indices)
      spmCloseProfit    = 5.0;        // v3.7.0: SPM TP +$5 (Indices)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (Indices)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 4.0;       // v3.5.3: $4 (eski $2.5)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 100.0;      // 100 pips
      tp2Pips           = 250.0;      // 250 pips
      tp3Pips           = 450.0;      // 450 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.50;       // v4.4.0: (eski $2.00)
      candleCloseModerate = 5.50;     // v4.4.0: (eski $4.00)
      candleCloseStrong = 8.00;       // v4.4.0: (eski $6.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (Indices)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (Indices)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- ENERJI (USOIL, NGAS vb.)
   void SetEnergy()
   {
      profileName       = "ENERGY";
      minLotOverride    = 0.01;       // Energy: min 0.01 lot
      minCloseProfit    = 2.0;        // v3.5.3: $2 min (eski $1 enerji spread yuksek)
      anaCloseProfit    = 6.0;        // v3.5.3: ANA +$6 (eski $5)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (Energy)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (Energy)
      spmCloseProfit    = 5.0;        // v3.7.0: SPM TP +$5 (Energy)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (Energy)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 75;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 4.0;       // v3.5.3: $4 (eski $2.5)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 40.0;       // 40 pips
      tp2Pips           = 80.0;       // 80 pips
      tp3Pips           = 140.0;      // 140 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.00;       // v4.4.0: (eski $1.50)
      candleCloseModerate = 4.50;     // v4.4.0: (eski $3.00)
      candleCloseStrong = 7.00;       // v4.4.0: (eski $5.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (Energy)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (Energy)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- VARSAYILAN (bilinmeyen enstrumanlar - ATR bazli fallback icin)
   void SetDefault()
   {
      profileName       = "DEFAULT";
      minLotOverride    = 0.0;        // Default: broker default kullan
      minCloseProfit    = 2.0;        // v3.5.3: $2 min (eski $1 spread sonrasi yetersiz)
      anaCloseProfit    = 6.0;        // v3.5.3: ANA +$6 (eski $5)
      spmTriggerLoss    = SPM_TriggerLoss;
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (Default)
      spmCloseProfit    = SPM_CloseProfit;
      fifoNetTarget     = SPM_NetTargetUSD;
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = SPM_LotBase;
      spmLotIncrement   = SPM_LotIncrement;
      spmLotCap         = SPM_LotCap;
      spmCooldownSec    = SPM_CooldownSec;
      dcaDistanceATR    = DCA_DistanceATR;
      profitTargetPerPos = SPM_CloseProfit;
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 30.0;       // Varsayilan: 30 pips
      tp2Pips           = 60.0;       // 60 pips
      tp3Pips           = 100.0;      // 100 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.00;       // v4.4.0: (eski $1.50)
      candleCloseModerate = 4.50;     // v4.4.0: (eski $3.00)
      candleCloseStrong = 7.00;       // v4.4.0: (eski $5.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (Default)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (Default)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }

   //--- METAL (XPT, XPD gibi - XAU/XAG haric)
   void SetMetal()
   {
      profileName       = "METAL";
      minLotOverride    = 0.01;       // Metal: min 0.01 lot
      minCloseProfit    = 2.5;        // v3.5.3: $2.5 min (eski $1 metal spread yuksek)
      anaCloseProfit    = 7.0;        // v3.5.3: ANA +$7 (eski $5)
      spmTriggerLoss    = -7.0;       // v3.7.0: ANA -$7 → SPM1 (Metal)
      spm2TriggerLoss   = -7.0;       // v3.7.0: SPM1 -$7 → SPM2 (Metal)
      spmCloseProfit    = 5.0;        // v3.7.0: SPM TP +$5 (Metal)
      fifoNetTarget     = 5.0;        // v3.7.0: FIFO net $5 (Metal)
      spmMaxBuyLayers   = 1;          // v3.7.0: max 1 SPM per side
      spmMaxSellLayers  = 1;          // v3.7.0: max 1 SPM per side
      spmLotBase        = 1.0;        // v2.2.5: 1.0x
      spmLotIncrement   = 0.1;        // v2.2.5: +0.1x
      spmLotCap         = 1.5;        // v2.2.5: max 1.5x
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 4.0;       // v3.5.3: $4 (eski $2)
      hedgeMinSPMCount  = 1;          // v3.7.0: 1 SPM yeterli
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 30.0;       // 30 pips
      tp2Pips           = 70.0;       // 70 pips
      tp3Pips           = 120.0;      // 120 pips
      gridATRMultLow    = 1.0;
      gridATRMultNormal = 1.5;
      gridATRMultHigh   = 2.0;
      candleCloseWeak   = 3.50;       // v4.4.0: (eski $2.00)
      candleCloseModerate = 5.50;     // v4.4.0: (eski $4.00)
      candleCloseStrong = 8.00;       // v4.4.0: (eski $6.00)
      trendCloseMultModerate = 1.3;
      trendCloseMultStrong = 1.8;
      trendConfirmBars  = 2;
      rescueHedgeThreshold = -7.0;    // v3.7.0: SPM2 -$7 → HEDGE (Metal)
      rescueHedgeLotMult   = 1.3;    // v3.7.0: HEDGE = ANA × 1.3 (Metal)
      //--- v4.2.0: Grid Reset + Net-Exposure
      gridLossPercent   = 0.25;
      gridLossMinUSD    = 30.0;
      spmMaxLayers      = 3;
   }
};

//=================================================================
// PROFIL SECIM FONKSIYONU - v2.1 DINAMIK
// Oncelik: Sembol bazli > Grup bazli > Kategori bazli > Varsayilan
//=================================================================
SymbolProfile GetSymbolProfile(ENUM_SYMBOL_CATEGORY cat, string sym)
{
   SymbolProfile p;
   string symUpper = sym;
   StringToUpper(symUpper);

   //--- ONCELIK 1: Sembol bazli ozel profil (tam eslesme)

   // ALTIN (XAU)
   if(StringFind(symUpper, "XAU") >= 0 || StringFind(symUpper, "GOLD") >= 0)
   {
      p.SetGold();
      return p;
   }

   // GUMUS (XAG)
   if(StringFind(symUpper, "XAG") >= 0 || StringFind(symUpper, "SILVER") >= 0)
   {
      p.SetSilver();
      return p;
   }

   // BITCOIN (BTC)
   if(StringFind(symUpper, "BTC") >= 0)
   {
      p.SetCrypto();
      return p;
   }

   // DIGER KRIPTO (ETH, LTC, XRP, DOGE, SOL, ADA, DOT, BNB)
   if(StringFind(symUpper, "ETH") >= 0 || StringFind(symUpper, "LTC") >= 0 ||
      StringFind(symUpper, "XRP") >= 0 || StringFind(symUpper, "DOGE") >= 0 ||
      StringFind(symUpper, "SOL") >= 0 || StringFind(symUpper, "ADA") >= 0 ||
      StringFind(symUpper, "DOT") >= 0 || StringFind(symUpper, "BNB") >= 0)
   {
      p.SetCryptoAlt();
      return p;
   }

   //--- ONCELIK 2: JPY ciftleri (ozel pip yapisi)
   if(StringFind(symUpper, "JPY") >= 0 && cat == CAT_FOREX)
   {
      p.SetForexJPY();
      return p;
   }

   //--- ONCELIK 3: Kategori bazli profil
   switch(cat)
   {
      case CAT_FOREX:
         p.SetForex();
         break;
      case CAT_METAL:
         p.SetMetal();     // XPT, XPD gibi diger metaller
         break;
      case CAT_CRYPTO:
         p.SetCryptoAlt(); // Tanimlanmamis kripto
         break;
      case CAT_INDICES:
         p.SetIndices();
         break;
      case CAT_ENERGY:
         p.SetEnergy();
         break;
      default:
         p.SetDefault();
         break;
   }
   return p;
}

//=================================================================
// SABIT DEGERLER
//=================================================================
#define MAX_POSITIONS  25       // v2.5.0: 10+10 SPM + ANA + DCA + yedek

//=================================================================
// ALIAS TANIMLARI (PositionManager uyumu)
//=================================================================
#define EA_MAGIC              MagicNumber
#define SPM_TriggerLossUSD    SPM_TriggerLoss
#define SPM_CloseProfitUSD    SPM_CloseProfit
#define SPM_CooldownSeconds   SPM_CooldownSec
#define SPM_LotMultiplier     SPM_LotBase
#define SPM_WaitMaxSeconds    SPM_WaitMaxSec

#endif
