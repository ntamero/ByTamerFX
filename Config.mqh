//+------------------------------------------------------------------+
//|                                                      Config.mqh  |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX - Merkezi Konfigurasyon                                |
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
#define EA_VERSION        "1.2.0"
#define EA_VERSION_NUM    "1.20"
#define EA_VERSION_NAME   "SPM-FIFO"
#define EA_VERSION_FULL   "BytamerFX v1.2.0 - SPM-FIFO"
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
input int      SignalMinScore         = 38;        // Daha guvenli sinyal esigi
input int      SignalCooldownSec      = 120;

//=================================================================
// SPM + FIFO SISTEMI
//=================================================================
input double   SPM_TriggerLoss        = -3.0;     // SPM tetik zarar ($) - ana veya spm -3$ olunca
input double   SPM_CloseProfit        = 4.0;      // SPM kar hedefi ($) - +4$ olunca kapat
input double   SPM_NetTargetUSD       = 5.0;      // FIFO net hedef ($) - spm toplami-ana >= +5$
input int      SPM_MaxLayers          = 6;        // Max SPM katmani (daha esnek)
input double   SPM_LotBase            = 1.0;      // SPM lot carpani (ana lot * bu)
input double   SPM_LotIncrement       = 0.1;      // Her katmanda lot artisi (1.0,1.1,1.2...)
input int      SPM_CooldownSec        = 45;       // SPM acma bekleme (sn)

//=================================================================
// KORUMA SISTEMI
//=================================================================
input double   MaxDrawdownPercent     = 30.0;     // Max DD% - equity duserse son care tum kapat
input double   MaxCycleLossUSD        = -15.0;    // Dongu max zarar ($)
input double   DailyProfitTarget      = 10.0;     // Gunluk kar hedefi ($)
input int      ProtectionCooldownSec  = 180;      // Koruma sonrasi bekleme (sn)
input double   MinBalanceToTrade      = 10.0;     // Min bakiye ($) - altinda islem yok
input double   MaxTotalVolume         = 2.0;      // Max toplam acik hacim (lot)
input double   MinMarginLevel         = 200.0;    // Min margin seviyesi (%) - altinda yeni islem yok

//=================================================================
// KAR YONETIMI
//=================================================================
input double   QuickProfitUSD         = 1.5;      // Hizli kar hedefi ($)
input double   TrailActivateUSD       = 1.0;      // Trailing aktif ($)
input double   TrailStepUSD           = 0.30;     // Trailing step ($)

//=================================================================
// GORSEL
//=================================================================
input bool     EnableDashboard        = true;
input int      ArrowSize              = 5;        // Buyuk ok (goze hitap eden)

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
   ROLE_MAIN = 0,
   ROLE_SPM  = 1
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
   int                spmLayerCount;      // Toplam SPM katman sayisi
   double             openSPMProfit;      // Acik SPM'lerin toplam P/L
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

#endif
