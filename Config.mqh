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
#define EA_VERSION        "2.0.0"
#define EA_VERSION_NUM    "2.00"
#define EA_VERSION_NAME   "KazanKazan"
#define EA_VERSION_FULL   "BytamerFX v2.0.0 - KazanKazan Hedge"
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
input double   MinMarginLevel         = 200.0;    // Min margin seviyesi (%)

//=================================================================
// KAR YONETIMI
//=================================================================
input double   QuickProfitUSD         = 1.5;      // Hizli kar hedefi ($)
input double   TrailActivateUSD       = 1.0;      // Trailing aktif ($)
input double   TrailStepUSD           = 0.30;     // Trailing step ($)
input double   PeakDropPercent        = 50.0;     // v2.0: %40→%50 SPM icin peak drop esigi
input double   PeakMinProfit          = 1.0;      // Peak drop icin min kar ($)

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
   double spmTriggerLoss;
   double spmCloseProfit;
   double fifoNetTarget;
   int    spmMaxBuyLayers;
   int    spmMaxSellLayers;
   double spmLotBase;
   double spmLotIncrement;
   double spmLotCap;
   int    spmCooldownSec;
   double dcaDistanceATR;
   double profitTargetPerPos;
   int    hedgeMinSPMCount;    // v2.0.1: Hedge icin minimum SPM sayisi
   double hedgeMinLossUSD;     // v2.0.1: Hedge icin minimum toplam zarar ($)

   void SetDefault()
   {
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
      hedgeMinSPMCount  = 2;          // En az 2 SPM olsun
      hedgeMinLossUSD   = -8.0;       // Min $8 zarar biriksin
   }

   void SetMetal()
   {
      SetDefault();
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 4.0;
      spmLotBase        = 1.5;
      spmLotIncrement   = 0.2;
      spmLotCap         = 2.0;
      spmCooldownSec    = 60;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -8.0;
   }

   void SetCrypto()
   {
      SetDefault();
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 5.0;
      spmLotBase        = 1.3;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.8;
      spmCooldownSec    = 90;
      dcaDistanceATR    = 2.5;
      profitTargetPerPos = 3.0;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -10.0;     // Crypto daha volatil, daha yuksek esik
   }

   void SetGold()
   {
      SetDefault();
      spmTriggerLoss    = -5.0;
      spmCloseProfit    = 4.0;
      spmLotBase        = 1.4;
      spmLotIncrement   = 0.2;
      spmLotCap         = 1.9;
      spmCooldownSec    = 75;
      dcaDistanceATR    = 2.0;
      profitTargetPerPos = 2.5;
      hedgeMinSPMCount  = 2;
      hedgeMinLossUSD   = -8.0;
   }
};

//=================================================================
// PROFIL SECIM FONKSIYONU
//=================================================================
SymbolProfile GetSymbolProfile(ENUM_SYMBOL_CATEGORY cat, string sym)
{
   SymbolProfile p;

   // Oncelik: Sembol bazli ozel profil
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
   {
      p.SetGold();
      return p;
   }

   // Kategori bazli profil
   switch(cat)
   {
      case CAT_METAL:
         p.SetMetal();
         break;
      case CAT_CRYPTO:
         p.SetCrypto();
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
