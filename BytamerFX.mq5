//+------------------------------------------------------------------+
//|                                                   BytamerFX.mq5  |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX v4.7.0 - FIFO-Guard                                    |
//| M15 Timeframe | SL=YOK (MUTLAK) | Hibrit Sinyal + SPM Yonetimi  |
//| FIFO Kasa Persistence + Restart Koruma + Gece Modu               |
//| Hesap: 262230423 (Exness) | Dinamik Profil + Haber + Lisans      |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, By T@MER"
#property link        "https://www.bytamer.com"
#property version     "5.05"                     // !!! Config.mqh EA_VERSION_NUM ile senkron tut !!!
#property description "BytamerFX v5.0.5 - Min Profit $8 Guard + Dynamic Balance Scaling"  // !!! Config.mqh EA_VERSION_FULL ile senkron tut !!!
#property description "AntiSpam | FIFO-Guard | Kasa Persist | Gece Modu | Crypto 7/24"
#property description "SL=YOK | Lisans Sistemi | Haber Entegrasyonu"
#property description "Copyright 2026, By T@MER"
#property strict

//=================================================================
// TUM MODULLER
//=================================================================
#include "Config.mqh"
#include "LicenseManager.mqh"
#include "AccountSecurity.mqh"
#include "SymbolManager.mqh"
#include "SpreadFilter.mqh"
#include "CandleAnalyzer.mqh"
#include "LotCalculator.mqh"
#include "SignalEngine.mqh"
#include "TradeExecutor.mqh"
#include "PositionManager.mqh"
#include "TelegramMsg.mqh"
#include "DiscordMsg.mqh"
#include "NewsManager.mqh"
#include "ChartDashboard.mqh"
#include "DashboardSync.mqh"

//=================================================================
// GLOBAL NESNELER
//=================================================================
CAccountSecurity  g_security;
CSymbolManager    g_symMgr;
CSpreadFilter     g_spreadFilter;
CCandleAnalyzer   g_candle;
CLotCalculator    g_lotCalc;
CSignalEngine     g_signalEngine;
CTradeExecutor    g_executor;
CPositionManager  g_posMgr;
CTelegramMsg      g_telegram;
CDiscordMsg       g_discord;
CNewsManager      g_newsMgr;         // v2.2: Haber yonetici
CChartDashboard   g_dashboard;
CDashboardSync    g_dashSync;          // v4.7.8: Web dashboard senkronizasyonu

//--- Durum degiskenleri
bool              g_initialized = false;
ENUM_SYMBOL_CATEGORY g_category = CAT_UNKNOWN;
datetime          g_lastNewBarTime = 0;
datetime          g_lastSignalCheck = 0;
datetime          g_initTime = 0;           // v4.8.7: Baslangic zamani (30sn warmup)

//--- v4.3: Seans istatistikleri (Telegram Shutdown + DailyReport)
datetime          g_sessionStartTime = 0;
double            g_sessionStartBalance = 0;
int               g_sessionClosedTrades = 0;
double            g_sessionProfit = 0;
int               g_dailyWins = 0;
int               g_dailyLosses = 0;
double            g_dailyWinAmount = 0;
double            g_dailyLossAmount = 0;
bool              g_dailyReportSent = false;
datetime          g_lastDailyReportDate = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 0. LISANS DOGRULAMA (EN ONCE)
   long accNo = AccountInfoInteger(ACCOUNT_LOGIN);
   if(!InitLicense(LicenseKey, accNo))
   {
      Print("!!! LISANS DOGRULANAMADI - EA DEVRE DISI !!!");
      Print("Lisans Durumu: ", GetLicenseStatus());
      Print("Lisans: ", GetLicenseKeyMasked());
      Print("Hesap: ", IntegerToString(accNo));

      // Lisans bos veya format hatali ise grafik uzerinde uyari goster
      // INIT_SUCCEEDED don ki EA grafikte kalsin (g_initialized=false, OnTick calisMAZ)
      // Kullanici sag tik > Ozellikler > Girisler ile lisans girince OnInit tekrar calisir
      ENUM_LICENSE_STATUS licStat = GetLicenseStatusEnum();
      if(licStat == LICENSE_EMPTY || licStat == LICENSE_INVALID)
      {
         Comment("\n\n",
                 "     ╔══════════════════════════════════════════╗\n",
                 "     ║      BYTAMERFX - LISANS GEREKLI          ║\n",
                 "     ╠══════════════════════════════════════════╣\n",
                 "     ║                                          ║\n",
                 "     ║  Lisans anahtari bos veya gecersiz!      ║\n",
                 "     ║                                          ║\n",
                 "     ║  Lisans girmek icin:                     ║\n",
                 "     ║  1. Grafige SAG TIKLAYIN                 ║\n",
                 "     ║  2. Uzman Danismanlar > Ozellikler       ║\n",
                 "     ║  3. Girisler sekmesi > LicenseKey        ║\n",
                 "     ║                                          ║\n",
                 "     ║  Format: BTAI-XXXXX-XXXXX-XXXXX-XXXXX   ║\n",
                 "     ║                                          ║\n",
                 "     ╚══════════════════════════════════════════╝\n");
         return INIT_SUCCEEDED;  // EA grafikte KALIR, OnTick calisMAZ (g_initialized=false)
      }

      // Diger hatalar (expired, revoked, baglanti vs.) icin de grafikte kal
      Comment("\n\n     BYTAMERFX: ", GetLicenseStatus(), "\n     Lisans girmek icin: Sag tik > Ozellikler > Girisler");
      return INIT_SUCCEEDED;
   }

   // Lisans suresi 7 gunden az ise uyari
   if(GetLicenseDaysRemaining() <= 7 && GetLicenseDaysRemaining() > 0)
   {
      Print("!!! UYARI: Lisans suresi ", GetLicenseDaysRemaining(), " gun sonra doluyor! !!!");
   }
   else if(GetLicenseDaysRemaining() == 0 && GetLicenseHoursRemaining() > 0)
   {
      Print("!!! UYARI: Lisans suresi ", GetLicenseHoursRemaining(), " saat sonra doluyor! !!!");
   }

   Print("Lisans: ", GetLicenseKeyMasked(), " | Musteri: ", GetLicenseCustomerName());
   Print("Bitis: ", GetLicenseEndDate(), " | Kalan: ", GetLicenseDaysRemaining(), " gun");

   //--- 1. HESAP GUVENLIK DOGRULAMASI
   g_security.Initialize(ExpectedAccountNumber);
   if(!g_security.IsVerified())
   {
      Print("!!! HESAP DOGRULANMADI - EA DEVRE DISI !!!");
      return INIT_FAILED;
   }

   string broker = g_security.GetBrokerName();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("================================================");
   Print(EA_VERSION_FULL);
   Print(StringFormat("Hesap: %d | Broker: %s", accNo, broker));
   Print(StringFormat("Bakiye: $%.2f | Sembol: %s", balance, _Symbol));
   Print("SL=YOK | Strateji: KAZAN-KAZAN | Net Hedef: $" + DoubleToString(SPM_NetTargetUSD, 2));
   Print(StringFormat("MinScore=%d | SPM Trigger=$%.1f | SPM Close=$%.1f",
         SignalMinScore, SPM_TriggerLoss, SPM_CloseProfit));
   Print(StringFormat("SPM LotBase=%.1f | LotIncrement=%.2f | MaxBuy=%d MaxSell=%d",
         SPM_LotBase, SPM_LotIncrement, SPM_MaxBuyLayers, SPM_MaxSellLayers));
   Print(StringFormat("v%s: BiDir=%s | TrendCheck=%dsn | Confirm=%d | LotReduce=%.0f%% | NewsWiden=%d%%",
         EA_VERSION, EnableReverseGrid ? "AKTIF" : "KAPALI", TrendCheckIntervalSec, TrendConfirmCount,
         LotReductionPerGrid * 100.0, NewsGridWidenPercent));
   Print(StringFormat("v%s: DCA=%d | Deadlock=%dsn | NewsFilter=%s",
         EA_VERSION, DCA_MaxPerPosition, Deadlock_TimeoutSec,
         EnableNewsFilter ? "AKTIF" : "KAPALI"));
   Print("Dinamik Profil: Sembol bazli TP/SPM/Hedge parametreleri");
   Print("================================================");

   //--- 2. SEMBOL KATEGORI TESPITI
   g_symMgr.Initialize(_Symbol);
   g_category = g_symMgr.GetCategory();

   string catName = GetCategoryStr(g_category);
   Print(StringFormat("Sembol Kategorisi: %s (%s)", _Symbol, catName));

   //--- 3. SPREAD FILTRESI (broker default + %15 tolerans - MUTLAK KURAL)
   double defaultSpread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   g_spreadFilter.Initialize(_Symbol, defaultSpread, MaxSpreadPercent);

   //--- 4. MUM ANALIZORU
   g_candle.Initialize(_Symbol, PERIOD_M15);

   //--- 5b. v2.1: DINAMIK PROFIL (erken yukle - lotcalc icin gerekli)
   SymbolProfile signalProfile = GetSymbolProfile(g_category, _Symbol);

   //--- 5. LOT HESAPLAYICI (v4.8.8: balance tier lot ile)
   g_lotCalc.Initialize(_Symbol, g_category, signalProfile.minLotOverride,
                        signalProfile.lotTier1, signalProfile.lotTier2,
                        signalProfile.lotTier3, signalProfile.lotTier4);

   //--- 6. SINYAL MOTORU
   if(!g_signalEngine.Initialize(_Symbol, g_category))
   {
      Print("!!! SINYAL MOTORU BASARISIZ - EA DEVRE DISI !!!");
      return INIT_FAILED;
   }

   //--- 6b. v2.1: DINAMIK PROFIL → SignalEngine'e aktar (pip bazli TP icin)
   g_signalEngine.SetProfile(signalProfile);

   //--- 7. ISLEM YURUTME
   g_executor.Initialize(_Symbol, g_category);

   //--- 8. BILDIRIMLER
   g_telegram.Initialize(TelegramToken, TelegramChatID, EnableTelegram);
   g_discord.Initialize(DiscordWebhookURL, EnableDiscord);

   //--- 9b. v2.2: HABER SISTEMI (Universal News Intelligence) - PosMgr'dan ONCE init et
   if(EnableNewsFilter)
   {
      g_newsMgr.Initialize(_Symbol, g_category);
      Print(StringFormat("Haber Filtresi: AKTIF | %d haber yuklendi | Blok: -%ddk / +%ddk",
            g_newsMgr.GetNewsCount(), NewsBlockBeforeMin, NewsBlockAfterMin));
   }
   else
   {
      Print("Haber Filtresi: DEVRE DISI");
   }

   //--- 9c. POZISYON YONETICI (SPM+FIFO) - v3.4.0: NewsManager referansi eklendi
   CNewsManager *newsMgrPtr = EnableNewsFilter ? GetPointer(g_newsMgr) : NULL;
   g_posMgr.Initialize(_Symbol, g_category, g_executor, g_signalEngine,
                        g_telegram, g_discord, newsMgrPtr);

   //--- 10. DASHBOARD (v2.2: News referansi eklendi)
   CNewsManager *newsPtr = EnableNewsFilter ? GetPointer(g_newsMgr) : NULL;
   g_dashboard.Initialize(_Symbol, g_category, g_signalEngine, g_posMgr,
                          g_spreadFilter, EnableDashboard, newsPtr);

   //--- 11. BASLANGIC MESAJLARI
   g_telegram.SendStartup(_Symbol, catName, accNo, broker, balance);
   g_discord.SendStartup(_Symbol, catName, accNo, broker, balance);

   if(EnablePushNotification)
      SendNotification(EA_VERSION_FULL + " BASLATILDI | " + _Symbol);

   //--- 12. TIMER (dashboard guncelleme icin)
   EventSetTimer(1);  // Her 1 saniye

   //--- v4.8.7: Baslangic zamani — 30sn warmup suresi
   g_initTime = TimeCurrent();

   //--- v4.3: Seans istatistikleri basla
   g_sessionStartTime    = TimeCurrent();
   g_sessionStartBalance = balance;
   g_sessionClosedTrades = 0;
   g_sessionProfit       = 0;
   g_dailyWins           = 0;
   g_dailyLosses         = 0;
   g_dailyWinAmount      = 0;
   g_dailyLossAmount     = 0;
   g_dailyReportSent     = false;
   g_lastDailyReportDate = 0;

   //--- 13. WEB DASHBOARD SENKRONIZASYONU
   if(EnableDashboardSync)
   {
      if(g_dashSync.Init(DashboardURL, LicenseKey, (int)accNo,
                          StateIntervalSec, TradeIntervalSec, SignalIntervalSec, LogIntervalSec))
      {
         Print("[DASHBOARD] Web senkronizasyonu AKTIF");
         g_dashSync.AddLog("INFO", "SYSTEM", EA_VERSION_FULL + " baslatildi - " + _Symbol);
      }
      else
      {
         Print("[DASHBOARD] Web senkronizasyonu basarisiz, arka planda yeniden denenecek");
      }
   }
   else
   {
      Print("[DASHBOARD] Web senkronizasyonu DEVRE DISI");
   }

   //--- MIA Advisor mode init
   g_activeMIAMode = MIA_Mode;
   if(MIA_EnableFileComm && g_activeMIAMode > 0)
   {
      PrintFormat("[MIA] Advisor entegrasyonu AKTIF | Mode=%d (%s) | Timeout=%dms",
                 g_activeMIAMode,
                 (g_activeMIAMode == 1) ? "ADVISOR" :
                 (g_activeMIAMode == 2) ? "COPILOT" :
                 (g_activeMIAMode == 3) ? "AUTOPILOT" : "OBSERVER",
                 MIA_TimeoutMs);
   }

   g_initialized = true;
   Print(EA_VERSION_FULL + " basariyla yuklendi.");

   //--- v5.0.3: Auto trading kontrol — kapaliysa UYAR (acilista)
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Alert("BytamerFX: Terminal AlgoTrading butonu KAPALI! Lutfen ust cubuktan AlgoTrading'i ACIN.");
      Print("!!! UYARI: Terminal AlgoTrading KAPALI — ust cubuktan yesil butona basin !!!");
   }
   else if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Alert("BytamerFX: EA trade izni KAPALI! Chart uzerinde EA'ya sag tikla → Properties → Common → 'Allow Algo Trading' isaretleyin.");
      Print("!!! UYARI: EA trade izni KAPALI — EA Properties → Allow Algo Trading !!!");
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Dashboard temizle
   g_dashboard.Destroy();

   //--- Timer kapat
   EventKillTimer();

   string reasonStr;
   switch(reason)
   {
      case REASON_PROGRAM:     reasonStr = "Program";       break;
      case REASON_REMOVE:      reasonStr = "Kaldirildi";    break;
      case REASON_RECOMPILE:   reasonStr = "Derleme";       break;
      case REASON_CHARTCHANGE: reasonStr = "Grafik Degisti";break;
      case REASON_CHARTCLOSE:  reasonStr = "Grafik Kapandi";break;
      case REASON_PARAMETERS:  reasonStr = "Parametre";     break;
      case REASON_ACCOUNT:     reasonStr = "Hesap";         break;
      case REASON_TEMPLATE:    reasonStr = "Sablon";        break;
      case REASON_INITFAILED:  reasonStr = "Init Hatasi";   break;
      case REASON_CLOSE:       reasonStr = "Terminal";      break;
      default:                 reasonStr = "Bilinmeyen";    break;
   }

   Print(StringFormat("%s DURDURULUYOR | Sebep: %s (%d)", EA_VERSION_FULL, reasonStr, reason));

   //--- Web Dashboard: Shutdown log
   if(EnableDashboardSync && g_dashSync.IsRegistered())
   {
      g_dashSync.AddLog("WARN", "SYSTEM",
         StringFormat("EA durduruluyor - Sebep: %s", reasonStr));
      g_dashSync.Shutdown();
   }

   //--- v4.3: Telegram Shutdown bildirimi
   if(g_initialized)
   {
      double shutdownBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      int runMinutes = (int)((TimeCurrent() - g_sessionStartTime) / 60);
      double sesProfit = shutdownBalance - g_sessionStartBalance;
      long accNo = AccountInfoInteger(ACCOUNT_LOGIN);

      g_telegram.SendShutdown(_Symbol, accNo, shutdownBalance,
                               reasonStr, g_sessionClosedTrades, sesProfit, runMinutes);
   }

   //--- Bildirim
   if(EnablePushNotification)
      SendNotification(EA_VERSION_FULL + " DURDURULDU | " + reasonStr);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;

   //--- v4.7.3: Auto trading kontrolu — kapaliysa trade deneme (spam onleme)
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      static datetime lastAutoTradingWarn = 0;
      if(TimeCurrent() - lastAutoTradingWarn > 300)  // 5dk'da bir uyari
      {
         Print("!!! AUTO TRADING KAPALI - Sadece izleme modu !!! AlgoTrading butonunu kontrol edin.");
         lastAutoTradingWarn = TimeCurrent();
      }
      //--- Pozisyon yoneticisini CALISTIRMA — trade denemelerine engel ol
      return;
   }

   //--- 0. LISANS PERIYODIK KONTROL (her 1 saatte bir)
   if(!CheckLicensePeriodically())
   {
      static datetime lastLicWarn = 0;
      if(TimeCurrent() - lastLicWarn > 60)
      {
         Print("!!! LISANS GECERSIZ - EA DURDURULDU !!! Durum: ", GetLicenseStatus());
         lastLicWarn = TimeCurrent();
      }
      return;
   }

   //--- 0b. MIA mode dosyasi kontrol (her 10 saniyede bir)
   if(MIA_EnableFileComm)
   {
      static datetime lastMIAModeCheck = 0;
      if(TimeCurrent() - lastMIAModeCheck > 10)
      {
         CheckMIAModeFile();
         lastMIAModeCheck = TimeCurrent();
      }
   }

   //--- 1. Hesap tekrar dogrula (her 5 dakikada bir)
   static datetime lastRecheck = 0;
   if(TimeCurrent() - lastRecheck > 300)
   {
      if(!g_security.Recheck())
      {
         Print("!!! HESAP DOGRULAMA BASARISIZ - ISLEM DURDURULDU !!!");
         return;
      }
      lastRecheck = TimeCurrent();
   }

   //--- 2. Min bakiye kontrolu
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade)
   {
      static datetime lastBalWarn = 0;
      if(TimeCurrent() - lastBalWarn > 60)
      {
         Print(StringFormat("!!! BAKIYE COK DUSUK: $%.2f < $%.2f - ISLEM YOK !!!",
               balance, MinBalanceToTrade));
         lastBalWarn = TimeCurrent();
      }
      //--- Yine de pozisyon yoneticisini calistir (korumalari aktif tutmak icin)
      g_posMgr.OnTick();
      return;
   }

   //--- 3. Pozisyon yoneticisi (SPM+FIFO + koruma)
   g_posMgr.OnTick();

   //--- 3b. v2.2: HABER KONTROLU
   if(EnableNewsFilter)
   {
      g_newsMgr.OnTick();

      //--- Haber bildirimi (30dk once)
      string alertMsg;
      if(g_newsMgr.CheckNewsAlert(alertMsg))
      {
         g_telegram.SendNewsAlert(alertMsg);

         //--- Discord icin ayri format
         string newsTitle, newsCurr;
         ENUM_NEWS_IMPACT newsImpact;
         datetime newsTime;
         int newsMin;
         if(g_newsMgr.GetActiveNewsInfo(newsTitle, newsCurr, newsImpact, newsTime, newsMin) ||
            g_newsMgr.GetNextNewsInfo(newsTitle, newsCurr, newsImpact, newsTime, newsMin))
         {
            NewsEvent ne;
            ne.eventTime = newsTime;
            ne.title = newsTitle;
            ne.currency = newsCurr;
            ne.impact = newsImpact;
            string discordDesc = CNewsManager::FormatDiscordNewsAlert(_Symbol, ne,
                                    AccountInfoDouble(ACCOUNT_BALANCE),
                                    AccountInfoDouble(ACCOUNT_EQUITY));
            g_discord.SendNewsAlert(discordDesc, CNewsManager::GetDiscordColor(newsImpact));
         }

         if(EnablePushNotification)
            SendNotification(StringFormat("HABER: %s | %s", _Symbol, alertMsg));
      }

      //--- Haber nedeniyle islem bloke mi? (v4.8.7: Crypto muaf)
      if(g_newsMgr.IsTradingBlocked() && g_category != CAT_CRYPTO)
      {
         static datetime lastNewsBlockLog = 0;
         if(TimeCurrent() - lastNewsBlockLog > 120)
         {
            PrintFormat("[NEWS-%s] Islem BLOKE: Haber suresi aktif (bitene kadar: %s)",
                        _Symbol, TimeToString(g_newsMgr.GetBlockUntil(), TIME_MINUTES));
            lastNewsBlockLog = TimeCurrent();
         }
         return;  // Yeni islem acma, sadece mevcut islemler yonetilir
      }
   }

   //--- 4. Trading paused ise yeni islem acma
   if(g_posMgr.IsTradingPaused())
      return;

   //--- 4b. v2.2.6: MarginKritik sonrasi toparlanma modu
   if(g_posMgr.IsInRecoveryMode())
      return;

   //--- 5. Yeni bar kontrolu
   bool isNewBar = g_candle.CheckNewBar();

   //--- 6. YENI SINYAL KONTROLU (sadece yeni barda + pozisyon yoksa)
   if(isNewBar && !g_posMgr.HasPosition())
   {
      CheckForNewSignal();
   }
}

//+------------------------------------------------------------------+
//| Timer function (dashboard update)                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_initialized) return;

   //--- Dashboard guncelle (chart uzerindeki panel)
   g_dashboard.Update();

   //--- Web Dashboard senkronizasyonu
   if(EnableDashboardSync)
      g_dashSync.OnTimer();

   //--- v2.2: Haber kontrolu (timer ile de calistir - tick gelmese bile)
   if(EnableNewsFilter)
      g_newsMgr.OnTick();

   //--- v4.7.8: Gun sonu raporu (23:55 - her gun 1 kez, GlobalVariable ile tek chart gonderir)
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." +
                                  IntegerToString(dt.mon) + "." +
                                  IntegerToString(dt.day));

   if(dt.hour == 23 && dt.min >= 55 && today != g_lastDailyReportDate)
   {
      g_lastDailyReportDate = today;

      //--- v4.7.8: Sadece 1 chart rapor gondersin (GlobalVariable kilit)
      string gvName = "BytamerFX_DailyReport_" + IntegerToString((long)today);
      if(GlobalVariableCheck(gvName))
      {
         PrintFormat("[DAILY] Rapor zaten baska chart tarafindan gonderildi, atlaniyor");
      }
      else
      {
         GlobalVariableSet(gvName, (double)TimeCurrent());
         //--- Onceki gunlerin kilidini temizle
         string prevGV = "BytamerFX_DailyReport_" + IntegerToString((long)(today - 86400));
         GlobalVariableDel(prevGV);

         long   accNo   = AccountInfoInteger(ACCOUNT_LOGIN);
         string broker  = AccountInfoString(ACCOUNT_COMPANY);
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
         double floating = equity - balance;
         double dailyPL = balance - g_sessionStartBalance;
         double dailyPct = (g_sessionStartBalance > 0) ? (dailyPL / g_sessionStartBalance * 100.0) : 0;
         int    totalClosed = g_dailyWins + g_dailyLosses;

         g_telegram.SendDailyReport(accNo, broker, balance, equity,
                                     dailyPL, dailyPct, floating,
                                     totalClosed, g_dailyWins, g_dailyLosses,
                                     g_dailyWinAmount, g_dailyLossAmount,
                                     "", "");  // activePositions ve topPerformers opsiyonel

         PrintFormat("[DAILY] Gun sonu raporu gonderildi (%s): P/L=$%.2f (%.1f%%)", _Symbol, dailyPL, dailyPct);
      }
   }
}

//+------------------------------------------------------------------+
//| MIA Advisor — Signal Request JSON yaz                             |
//| MQL5/Files/MIA/signal_request.json                                |
//+------------------------------------------------------------------+
int g_miaRequestId = 0;     // Global request sayaci
int g_activeMIAMode = 0;    // Runtime MIA modu (Telegram ile override)

void WriteMIASignalRequest(const SignalData &sig, double lot)
{
   g_miaRequestId++;

   string dirStr = (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL";
   string trendStr = (sig.trendStrength == TREND_STRONG) ? "STRONG" :
                     (sig.trendStrength == TREND_MODERATE) ? "MODERATE" : "WEAK";

   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   int    openPos     = PositionsTotal();

   // JSON dosya olustur
   string fileName = "MIA\\signal_request.json";
   int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      // Common olmadan dene
      handle = FileOpen(fileName, FILE_WRITE | FILE_TXT);
   }
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("[MIA] signal_request.json yazma hatasi: %d", GetLastError());
      return;
   }

   string json = "{";
   json += StringFormat("\"symbol\":\"%s\",", _Symbol);
   json += StringFormat("\"direction\":\"%s\",", dirStr);
   json += StringFormat("\"score\":%d,", sig.score);
   json += StringFormat("\"lot\":%.2f,", lot);
   json += StringFormat("\"atr\":%.5f,", sig.atr);
   json += StringFormat("\"rsi\":%.1f,", sig.rsi);
   json += StringFormat("\"adx\":%.1f,", sig.adx);
   json += StringFormat("\"plus_di\":%.1f,", sig.plusDI);
   json += StringFormat("\"minus_di\":%.1f,", sig.minusDI);
   json += StringFormat("\"trend_strength\":\"%s\",", trendStr);
   json += StringFormat("\"balance\":%.2f,", balance);
   json += StringFormat("\"equity\":%.2f,", equity);
   json += StringFormat("\"margin_level\":%.1f,", marginLevel);
   json += StringFormat("\"open_positions\":%d,", openPos);
   json += StringFormat("\"timestamp\":%d,", (int)TimeCurrent());
   json += StringFormat("\"request_id\":%d", g_miaRequestId);
   json += "}";

   FileWriteString(handle, json);
   FileClose(handle);

   PrintFormat("[MIA] Request #%d yazildi: %s %s score=%d lot=%.2f",
              g_miaRequestId, _Symbol, dirStr, sig.score, lot);
}

//+------------------------------------------------------------------+
//| MIA Advisor — Signal Response JSON oku                            |
//| MQL5/Files/MIA/signal_response.json                               |
//+------------------------------------------------------------------+
bool ReadMIASignalResponse(MIAResponse &resp)
{
   resp.Clear();

   string fileName = "MIA\\signal_response.json";
   int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      handle = FileOpen(fileName, FILE_READ | FILE_TXT);
   }
   if(handle == INVALID_HANDLE)
      return false;

   string content = "";
   while(!FileIsEnding(handle))
      content += FileReadString(handle);
   FileClose(handle);

   if(StringLen(content) < 10)
      return false;

   // Basit JSON parser (MQL5'te native JSON yok)
   resp.requestId    = (int)ExtractJsonInt(content, "request_id");
   resp.action       = ExtractJsonString(content, "action");
   resp.lotOverride  = ExtractJsonDouble(content, "lot_override");
   resp.lotMultiplier = ExtractJsonDouble(content, "lot_multiplier");
   resp.reason       = ExtractJsonString(content, "reason");
   resp.sentimentScore = ExtractJsonDouble(content, "sentiment_score");
   resp.newsBlackout = (ExtractJsonString(content, "news_blackout") == "true");
   resp.session      = ExtractJsonString(content, "session");
   resp.miaMode      = ExtractJsonString(content, "mia_mode");
   resp.timestamp    = (int)ExtractJsonInt(content, "timestamp");

   // Dosyayi sil (bir kere okundu)
   FileDelete(fileName, FILE_COMMON);
   FileDelete(fileName);

   return (resp.requestId > 0 && StringLen(resp.action) > 0);
}

//+------------------------------------------------------------------+
//| MIA Response bekle (polling, timeout)                              |
//+------------------------------------------------------------------+
bool WaitForMIAResponse(int timeoutMs, MIAResponse &resp)
{
   int waited = 0;
   int pollInterval = 100;  // 100ms arayla kontrol

   while(waited < timeoutMs)
   {
      if(ReadMIASignalResponse(resp))
      {
         // Dogru request_id kontrolu
         if(resp.requestId == g_miaRequestId)
         {
            PrintFormat("[MIA] Response #%d: %s lot=%.2f mult=%.2f | %s",
                       resp.requestId, resp.action, resp.lotOverride,
                       resp.lotMultiplier, resp.reason);
            return true;
         }
      }
      Sleep(pollInterval);
      waited += pollInterval;
   }

   PrintFormat("[MIA] Response TIMEOUT (%dms) — EA kendi karari ile devam", timeoutMs);
   return false;
}

//+------------------------------------------------------------------+
//| MIA Mode dosyasi oku (Telegram ile runtime degisim)                |
//+------------------------------------------------------------------+
void CheckMIAModeFile()
{
   string fileName = "MIA\\mia_mode.json";
   int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      handle = FileOpen(fileName, FILE_READ | FILE_TXT);
   }
   if(handle == INVALID_HANDLE)
      return;

   string content = "";
   while(!FileIsEnding(handle))
      content += FileReadString(handle);
   FileClose(handle);

   int modeId = (int)ExtractJsonInt(content, "mode_id");
   if(modeId != g_activeMIAMode && modeId >= 0 && modeId <= 3)
   {
      PrintFormat("[MIA] Mode degisti: %d → %d", g_activeMIAMode, modeId);
      g_activeMIAMode = modeId;
   }
}

//+------------------------------------------------------------------+
//| Basit JSON yardimci fonksiyonlari                                  |
//+------------------------------------------------------------------+
string ExtractJsonString(const string &json, const string &key)
{
   string searchKey = "\"" + key + "\":\"";
   int pos = StringFind(json, searchKey);
   if(pos < 0) return "";

   int start = pos + StringLen(searchKey);
   int end = StringFind(json, "\"", start);
   if(end < 0) return "";

   return StringSubstr(json, start, end - start);
}

double ExtractJsonDouble(const string &json, const string &key)
{
   string searchKey = "\"" + key + "\":";
   int pos = StringFind(json, searchKey);
   if(pos < 0) return 0.0;

   int start = pos + StringLen(searchKey);
   // Sayi sonunu bul (virgul, sunglu parantez, veya dosya sonu)
   string rest = StringSubstr(json, start, 20);
   // Tirnak isaretleri varsa (string olarak yazilmis sayi)
   StringReplace(rest, "\"", "");
   int endComma = StringFind(rest, ",");
   int endBrace = StringFind(rest, "}");
   int end = (endComma >= 0 && endBrace >= 0) ? MathMin(endComma, endBrace) :
             (endComma >= 0) ? endComma : endBrace;
   if(end > 0)
      rest = StringSubstr(rest, 0, end);

   return StringToDouble(rest);
}

long ExtractJsonInt(const string &json, const string &key)
{
   return (long)ExtractJsonDouble(json, key);
}

//+------------------------------------------------------------------+
//| Yeni sinyal kontrolu ve islem acma                                |
//+------------------------------------------------------------------+
void CheckForNewSignal()
{
   //--- v4.8.7: 30sn warmup — sistem acilisinda kor dalis yapma
   if(TimeCurrent() - g_initTime < 30)
   {
      static bool warmupLogged = false;
      if(!warmupLogged)
      {
         PrintFormat("[WARMUP-%s] 30sn bekleniyor (sinyal kalitesi icin)", _Symbol);
         warmupLogged = true;
      }
      return;
   }

   //--- v4.6.0: Gece modu ek guvenlik (TradeExecutor'da da var)
   if(NightModeEnabled && g_category != CAT_CRYPTO)
   {
      MqlDateTime lt;
      TimeToStruct(TimeLocal(), lt);
      if(lt.hour >= NightModeStartHour)
         return;
   }

   //--- Cooldown kontrolu
   if(TimeCurrent() - g_lastSignalCheck < SignalCooldownSec)
      return;

   //--- Spread kontrolu (MUTLAK KURAL: default + %15 uzerinde islem yok)
   if(!g_spreadFilter.IsSpreadOK())
      return;

   //--- Margin kontrolu (yeni islem icin min margin seviyesi)
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel)
   {
      static datetime lastMarginWarn = 0;
      if(TimeCurrent() - lastMarginWarn > 120)
      {
         Print(StringFormat("MARGIN YETERSIZ: %.1f%% < %.1f%% - Yeni islem yok",
               marginLevel, MinMarginLevel));
         lastMarginWarn = TimeCurrent();
      }
      return;
   }

   //--- Toplam acik hacim kontrolu
   double totalVolume = GetTotalOpenVolume();
   if(totalVolume >= MaxTotalVolume)
   {
      static datetime lastVolWarn = 0;
      if(TimeCurrent() - lastVolWarn > 120)
      {
         Print(StringFormat("MAX HACIM: %.2f >= %.2f lot - Yeni islem yok",
               totalVolume, MaxTotalVolume));
         lastVolWarn = TimeCurrent();
      }
      return;
   }

   //--- Sinyal motoru degerlendir
   SignalData sig = g_signalEngine.Evaluate();

   if(sig.direction == SIGNAL_NONE)
      return;

   if(sig.score < SignalMinScore)
      return;

   g_lastSignalCheck = TimeCurrent();

   Print(StringFormat("=== YENI SINYAL: %s | Skor: %d/100 ===",
         (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL", sig.score));
   string trendName = (sig.trendStrength == TREND_STRONG) ? "GUCLU" :
                      (sig.trendStrength == TREND_MODERATE) ? "ORTA" : "ZAYIF";
   Print(StringFormat("  RSI=%.1f | ADX=%.1f | ATR=%.5f | Trend=%s", sig.rsi, sig.adx, sig.atr, trendName));
   Print(StringFormat("  TP=%.5f (Ana) | TP1=%.5f | TP2=%.5f | TP3=%.5f", sig.tp, sig.tp1, sig.tp2, sig.tp3));

   //--- v2.2: Dinamik lot hesapla (8 faktor: balance + atr + score + trend + margin + toplam lot)
   ENUM_TREND_STRENGTH trendStr = g_signalEngine.GetTrendStrength();
   double lot = g_lotCalc.CalculateDynamic(
      AccountInfoDouble(ACCOUNT_BALANCE), sig.atr, sig.score, trendStr, marginLevel, totalVolume);

   //--- v4.9.0: MIA Advisor kontrolu
   if(MIA_EnableFileComm && g_activeMIAMode >= MIA_ADVISOR)
   {
      // Signal request yaz
      WriteMIASignalRequest(sig, lot);

      // Response bekle (max timeout ms)
      MIAResponse miaResp;
      bool gotResponse = WaitForMIAResponse(MIA_TimeoutMs, miaResp);

      if(gotResponse)
      {
         if(miaResp.action == "REJECT")
         {
            PrintFormat("[MIA] REJECT: %s — Islem ACILMAYACAK", miaResp.reason);
            g_telegram.SendMessage(StringFormat(
               "MIA REJECT: %s %s\n%s",
               _Symbol, (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL",
               miaResp.reason));
            return;  // Islem acma
         }

         if(miaResp.action == "ADJUST" && miaResp.lotOverride > 0)
         {
            PrintFormat("[MIA] ADJUST: lot %.2f → %.2f | %s", lot, miaResp.lotOverride, miaResp.reason);
            lot = miaResp.lotOverride;
         }

         // APPROVE → devam et (lot degismez)
         PrintFormat("[MIA] %s: %s | sentiment=%.0f session=%s",
                    miaResp.action, miaResp.reason,
                    miaResp.sentimentScore, miaResp.session);
      }
      else
      {
         // Timeout → EA kendi karari ile devam (guvenli fallback)
         PrintFormat("[MIA] Timeout — EA kendi karari ile devam (lot=%.2f)", lot);
      }
   }

   //--- v2.2.2: ANA pozisyona BROKER TP KONMAZ
   //--- ANA SADECE FIFO ile kapanir (net >= +$5)
   //--- Broker TP koymak -> broker otomatik kapatir -> FIFO bozulur
   //--- TP tracking internal olarak ManageTPLevels ile yapilir (sadece log)
   double tp = 0;   // v2.2.2: ANA icin broker TP = YOK

   //--- Islem ac (SL=YOK - MUTLAK, TP=YOK - FIFO ILE KAPANIR)
   string comment = StringFormat("BTFX_%s_%d", _Symbol, sig.score);
   if(StringLen(comment) > 25) comment = StringSubstr(comment, 0, 25);

   ulong ticket = g_executor.OpenPosition(sig.direction, lot, tp, 0, comment);

   if(ticket > 0)
   {
      //--- v4.8.5: Brier Score icin sinyal kaydi
      g_signalEngine.RecordSignal(sig, ticket);

      string dirStr = (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL";
      double price = (sig.direction == SIGNAL_BUY)
                     ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      Print(StringFormat("ISLEM ACILDI: %s | %s | Lot=%.2f | Fiyat=%.5f | TP=%.5f | Ticket=%d",
            dirStr, _Symbol, lot, price, tp, ticket));

      //--- Kategori ismi
      string catName = GetCategoryStr(g_category);

      //--- Bildirimler
      long accNo = g_security.GetAccountNumber();
      string broker = g_security.GetBrokerName();
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);

      g_telegram.SendTradeOpen(_Symbol, catName, sig.direction,
                               lot, price, tp, 0,
                               sig.atr, sig.rsi, sig.adx, sig.score,
                               accNo, broker, bal);

      g_discord.SendTradeOpen(_Symbol, catName, sig.direction,
                              lot, price, tp, 0,
                              sig.atr, sig.rsi, sig.adx, sig.score,
                              accNo, broker, bal);

      if(EnablePushNotification)
         SendNotification(StringFormat("ISLEM: %s %s Lot=%.2f Skor=%d", dirStr, _Symbol, lot, sig.score));

      //--- TP Tracking ayarla
      g_posMgr.SetTPTracking(sig.tp1, sig.tp2, sig.tp3, sig.trendStrength);

      //--- Chart uzerine ok ciz (buyuk ok + tooltip)
      DrawSignalArrow(sig, lot, price);
   }
   else
   {
      Print(StringFormat("ISLEM ACMA HATASI: %s | %s | Lot=%.2f | Hata=%d",
            (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL", _Symbol, lot, GetLastError()));
   }
}

//+------------------------------------------------------------------+
//| Sinyal oku chart uzerine ciz - Buyuk ok + Tooltip                 |
//+------------------------------------------------------------------+
void DrawSignalArrow(const SignalData &sig, double lot, double price)
{
   string name = "BTFX_Arrow_" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   StringReplace(name, " ", "_");
   StringReplace(name, ":", "_");
   StringReplace(name, ".", "_");

   int arrowCode;
   color arrowClr;
   double arrowPrice;

   if(sig.direction == SIGNAL_BUY)
   {
      arrowCode = 233;  // Up arrow
      arrowClr = clrLime;
      arrowPrice = price - g_signalEngine.GetATR() * 0.5;  // Mumun altina yerlestir
   }
   else
   {
      arrowCode = 234;  // Down arrow
      arrowClr = clrRed;
      arrowPrice = price + g_signalEngine.GetATR() * 0.5;  // Mumun ustune yerlestir
   }

   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), arrowPrice);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, arrowClr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, ArrowSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);  // Gorunur (tooltip icin)

   //--- TOOLTIP: v2.2.2 - Kompakt, BMP Unicode
   string dirMark = (sig.direction == SIGNAL_BUY) ? "\x25B2" : "\x25BC";
   string dirStr  = (sig.direction == SIGNAL_BUY) ? "ALIS (BUY)" : "SATIS (SELL)";
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   string tooltip = StringFormat(
      "%s  %s  %s\n"
      "\x25CF  %s | Lot: %.2f\n"
      "\x2714  TP1: %s\n"
      "\x2714  TP2: %s\n"
      "\x2605  Skor: %d/100\n"
      "%s",
      dirMark, _Symbol, dirStr,
      DoubleToString(price, digits), lot,
      DoubleToString(sig.tp1, digits),
      DoubleToString(sig.tp2, digits),
      sig.score,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));

   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}

//+------------------------------------------------------------------+
//| Toplam acik hacim hesapla                                         |
//+------------------------------------------------------------------+
double GetTotalOpenVolume()
{
   double total = 0.0;
   int totalPos = PositionsTotal();

   for(int i = 0; i < totalPos; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MAGIC) continue;

      total += PositionGetDouble(POSITION_VOLUME);
   }

   return total;
}

//+------------------------------------------------------------------+
//| Kategori string helper                                             |
//+------------------------------------------------------------------+
string GetCategoryStr(ENUM_SYMBOL_CATEGORY cat)
{
   switch(cat)
   {
      case CAT_FOREX:   return "FOREX";
      case CAT_METAL:   return "METAL";
      case CAT_CRYPTO:  return "CRYPTO";
      case CAT_INDICES: return "INDEX";
      case CAT_STOCKS:  return "STOCK";
      case CAT_ENERGY:  return "ENERGY";
      default:          return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| ChartEvent handler                                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   //--- Gelecekte dashboard etkilesimi icin
}

//+------------------------------------------------------------------+
