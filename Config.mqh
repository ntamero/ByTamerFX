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
#define EA_VERSION        "2.2.1"
#define EA_VERSION_NUM    "2.21"
#define EA_VERSION_NAME   "KazanKazan"
#define EA_VERSION_FULL   "BytamerFX v2.2.1 - KazanKazan Pro"
#define EA_BUILD_DATE     __DATE__

//=================================================================
// HESAP GUVENLIK
//=================================================================
input long     ExpectedAccountNumber  = 262230423;

//=================================================================
// TELEGRAM
//=================================================================
input string   TelegramToken          = "8477394899:AAF06Ik9u5tKxumHL2JB-wh64CU_nG9dDvI";
input string   TelegramChatID         = "-1003212753244";

//=================================================================
// DISCORD
//=================================================================
input string   DiscordWebhookURL      = "https://discordapp.com/api/webhooks/1471600739276034200/co3OJiOaXorrXfEn576Ak-Zpg0ZJxlQuunN3HZuLHmYkKh0C8rdUhp-W7Yc13HbEpIpq";

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

//=================================================================
// SINYAL MOTORU
//=================================================================
input int      SignalMinScore         = 40;        // v2.0: 38→40 guclu sinyal esigi
input int      SignalCooldownSec      = 120;

//=================================================================
// SPM + FIFO SISTEMI (v2.0 - KAZAN-KAZAN)
//=================================================================
input double   SPM_TriggerLoss        = -5.0;     // v2.0: -3→-5 SPM tetik ($)
input double   SPM_CloseProfit        = 4.0;      // SPM kar hedefi ($)
input double   SPM_NetTargetUSD       = 5.0;      // FIFO net hedef ($) - toplam net >= +5$
input int      SPM_MaxBuyLayers       = 5;        // v2.0: Max BUY katman (5+5 yapi)
input int      SPM_MaxSellLayers      = 5;        // v2.0: Max SELL katman
input double   SPM_LotBase            = 1.5;      // SPM lot carpani
input double   SPM_LotIncrement       = 0.2;      // v2.0: 0.3→0.2 daha yumusak artis
input double   SPM_LotCap             = 2.0;      // v2.0: 2.2→2.0 max carpan
input int      SPM_CooldownSec        = 60;       // v2.0: 45→60 SPM arasi bekleme (dropdown)
input int      SPM_WaitMaxSec         = 180;      // ANA toparlanma bekleme suresi (sn)

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
input double   MinMarginLevel         = 150.0;    // v2.2.1: Min margin seviyesi (%) - 200 cok yuksekti, 3 enstrumanda patliyordu

//=================================================================
// KAR YONETIMI
//=================================================================
input double   QuickProfitUSD         = 1.5;      // Hizli kar hedefi ($)
input double   TrailActivateUSD       = 1.0;      // Trailing aktif ($)
input double   TrailStepUSD           = 0.30;     // Trailing step ($)
input double   PeakDropPercent        = 50.0;     // v2.0: %40→%50 SPM icin peak drop esigi
input double   PeakMinProfit          = 1.0;      // Peak drop icin min kar ($)

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
   double spmTriggerLoss;       // SPM tetik zarar esigi ($)
   double spmCloseProfit;       // SPM kar hedefi ($)
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

   //--- v2.2.1: Dinamik min lot (kategori bazli)
   double minLotOverride;          // 0 = broker default, >0 = profil override

   //--- v2.1: Profil adi (log icin)
   string profileName;

   //---------- PROFIL AYAR FONKSIYONLARI ----------

   //--- FOREX (EURUSD, GBPUSD vb. - JPY haric)
   void SetForex()
   {
      profileName       = "FOREX";
      minLotOverride    = 0.06;       // Forex: min 0.06 lot
      spmTriggerLoss    = -3.0;       // Forex: -$3 tetik
      spmCloseProfit    = 3.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.5;
      spmLotIncrement   = 0.2;
      spmLotCap         = 2.0;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;       // Forex: -$5 hedge esigi
      tp1Pips           = 30.0;       // Zayif trend: 30 pips
      tp2Pips           = 60.0;       // Orta trend: 60 pips
      tp3Pips           = 100.0;      // Guclu trend: 100 pips
   }

   //--- FOREX JPY pariteler (USDJPY, GBPJPY, EURJPY vb.)
   void SetForexJPY()
   {
      profileName       = "FOREX_JPY";
      minLotOverride    = 0.06;       // JPY: min 0.06 lot
      spmTriggerLoss    = -3.0;       // JPY: -$3 tetik
      spmCloseProfit    = 3.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.5;
      spmLotIncrement   = 0.2;
      spmLotCap         = 2.0;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 40.0;       // JPY daha genish: 40 pips
      tp2Pips           = 80.0;       // 80 pips
      tp3Pips           = 130.0;      // 130 pips
   }

   //--- GUMUS (XAG)
   void SetSilver()
   {
      profileName       = "SILVER_XAG";
      minLotOverride    = 0.01;       // XAG: min 0.01 lot
      spmTriggerLoss    = -5.0;       // XAG: -$5 tetik
      spmCloseProfit    = 4.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.5;
      spmLotIncrement   = 0.2;
      spmLotCap         = 2.0;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 20.0;       // Zayif trend: 20 pips
      tp2Pips           = 50.0;       // Orta trend: 50 pips
      tp3Pips           = 80.0;       // Guclu trend: 80 pips
   }

   //--- ALTIN (XAU)
   void SetGold()
   {
      profileName       = "GOLD_XAU";
      minLotOverride    = 0.01;       // XAU: min 0.01 lot
      spmTriggerLoss    = -5.0;       // XAU: -$5 tetik
      spmCloseProfit    = 4.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.4;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.9;
      spmCooldownSec    = 75;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.5;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 50.0;       // Zayif trend: 50 pips
      tp2Pips           = 120.0;      // Orta trend: 120 pips
      tp3Pips           = 200.0;      // Guclu trend: 200 pips
   }

   //--- BITCOIN (BTC)
   void SetCrypto()
   {
      profileName       = "CRYPTO_BTC";
      minLotOverride    = 0.01;       // BTC: min 0.01 lot
      spmTriggerLoss    = -5.0;       // BTC: -$5 tetik
      spmCloseProfit    = 5.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.3;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.8;
      spmCooldownSec    = 90;
      dcaDistanceATR    = 2.5;
      profitTargetPerPos = 3.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;       // BTC: -$5 hedge esigi
      tp1Pips           = 1500.0;     // Zayif trend: 1500 pips
      tp2Pips           = 2500.0;     // Orta trend: 2500 pips
      tp3Pips           = 3500.0;     // Guclu trend: 3500 pips
   }

   //--- DIGER KRIPTO (ETH, LTC, XRP vb.)
   void SetCryptoAlt()
   {
      profileName       = "CRYPTO_ALT";
      minLotOverride    = 0.01;       // Altcoin: min 0.01 lot
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 4.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.3;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.8;
      spmCooldownSec    = 90;
      dcaDistanceATR    = 2.5;
      profitTargetPerPos = 2.5;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 500.0;      // Altcoin: 500 pips
      tp2Pips           = 1000.0;     // 1000 pips
      tp3Pips           = 1800.0;     // 1800 pips
   }

   //--- ENDEKSLER (US30, NAS100, SPX500 vb.)
   void SetIndices()
   {
      profileName       = "INDICES";
      minLotOverride    = 0.03;       // Indices: min 0.03 lot
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 4.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.4;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.9;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.5;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 100.0;      // 100 pips
      tp2Pips           = 250.0;      // 250 pips
      tp3Pips           = 450.0;      // 450 pips
   }

   //--- ENERJI (USOIL, NGAS vb.)
   void SetEnergy()
   {
      profileName       = "ENERGY";
      minLotOverride    = 0.01;       // Energy: min 0.01 lot
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 4.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.4;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.9;
      spmCooldownSec    = 75;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.5;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 40.0;       // 40 pips
      tp2Pips           = 80.0;       // 80 pips
      tp3Pips           = 140.0;      // 140 pips
   }

   //--- VARSAYILAN (bilinmeyen enstrumanlar - ATR bazli fallback icin)
   void SetDefault()
   {
      profileName       = "DEFAULT";
      minLotOverride    = 0.0;        // Default: broker default kullan
      spmTriggerLoss    = SPM_TriggerLoss;
      spmCloseProfit    = SPM_CloseProfit;
      fifoNetTarget     = SPM_NetTargetUSD;
      spmMaxBuyLayers   = SPM_MaxBuyLayers;
      spmMaxSellLayers  = SPM_MaxSellLayers;
      spmLotBase        = SPM_LotBase;
      spmLotIncrement   = SPM_LotIncrement;
      spmLotCap         = SPM_LotCap;
      spmCooldownSec    = SPM_CooldownSec;
      dcaDistanceATR    = DCA_DistanceATR;
      profitTargetPerPos = SPM_CloseProfit;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 30.0;       // Varsayilan: 30 pips
      tp2Pips           = 60.0;       // 60 pips
      tp3Pips           = 100.0;      // 100 pips
   }

   //--- METAL (XPT, XPD gibi - XAU/XAG haric)
   void SetMetal()
   {
      profileName       = "METAL";
      minLotOverride    = 0.01;       // Metal: min 0.01 lot
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 4.0;
      fifoNetTarget     = 5.0;
      spmMaxBuyLayers   = 5;
      spmMaxSellLayers  = 5;
      spmLotBase        = 1.5;
      spmLotIncrement   = 0.2;
      spmLotCap         = 2.0;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -5.0;
      tp1Pips           = 30.0;       // 30 pips
      tp2Pips           = 70.0;       // 70 pips
      tp3Pips           = 120.0;      // 120 pips
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
#define MAX_POSITIONS  20

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
