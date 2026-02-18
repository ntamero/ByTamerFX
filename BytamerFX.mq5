//+------------------------------------------------------------------+
//|                                                   BytamerFX.mq5  |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX v2.2.1 - KAZAN-KAZAN Pro                                |
//| M15 Timeframe | SL=YOK (MUTLAK) | 7 Katman Hibrit Sinyal        |
//| FIFO +$5 Net | DCA | Acil Hedge | Universal News Intelligence    |
//| Hesap: 262230423 (Exness) | Dinamik Profil + Haber Kontrol       |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, By T@MER"
#property link        "https://www.bytamer.com"
#property version     "2.21"
#property description "BytamerFX v2.2.1 - KazanKazan Pro"
#property description "FIFO +$5 | DCA | Hedge | News Intelligence"
#property description "SL=YOK | Dinamik Profil | Pip-TP"
#property description "Copyright 2026, By T@MER"
#property strict

//=================================================================
// TUM MODULLER
//=================================================================
#include "Config.mqh"
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

//--- Durum degiskenleri
bool              g_initialized = false;
ENUM_SYMBOL_CATEGORY g_category = CAT_UNKNOWN;
datetime          g_lastNewBarTime = 0;
datetime          g_lastSignalCheck = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- 1. HESAP GUVENLIK DOGRULAMASI
   g_security.Initialize(ExpectedAccountNumber);
   if(!g_security.IsVerified())
   {
      Print("!!! HESAP DOGRULANMADI - EA DEVRE DISI !!!");
      return INIT_FAILED;
   }

   long accNo    = g_security.GetAccountNumber();
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
   Print(StringFormat("v2.2: DCA=%d | Hedge=%.0f%% | Deadlock=%dsn | NewsFilter=%s",
         DCA_MaxPerPosition, Hedge_FillPercent * 100.0, Deadlock_TimeoutSec,
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

   //--- 5. LOT HESAPLAYICI (v2.2.1: profil min lot ile)
   g_lotCalc.Initialize(_Symbol, g_category, signalProfile.minLotOverride);

   //--- 6. SINYAL MOTORU
   if(!g_signalEngine.Initialize(_Symbol, g_category))
   {
      Print("!!! SINYAL MOTORU BASARISIZ - EA DEVRE DISI !!!");
      return INIT_FAILED;
   }

   //--- 6b. v2.1: DINAMIK PROFIL → SignalEngine'e aktar (pip bazli TP icin)
   g_signalEngine.SetProfile(signalProfile);

   //--- 7. ISLEM YURUTME
   g_executor.Initialize(_Symbol);

   //--- 8. BILDIRIMLER
   g_telegram.Initialize(TelegramToken, TelegramChatID, EnableTelegram);
   g_discord.Initialize(DiscordWebhookURL, EnableDiscord);

   //--- 9. POZISYON YONETICI (SPM+FIFO)
   g_posMgr.Initialize(_Symbol, g_category, g_executor, g_signalEngine,
                        g_telegram, g_discord);

   //--- 9b. v2.2: HABER SISTEMI (Universal News Intelligence)
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

   g_initialized = true;
   Print(EA_VERSION_FULL + " basariyla yuklendi.");

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

      //--- Haber nedeniyle islem bloke mi?
      if(g_newsMgr.IsTradingBlocked())
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

   //--- Dashboard guncelle
   g_dashboard.Update();

   //--- v2.2: Haber kontrolu (timer ile de calistir - tick gelmese bile)
   if(EnableNewsFilter)
      g_newsMgr.OnTick();
}

//+------------------------------------------------------------------+
//| Yeni sinyal kontrolu ve islem acma                                |
//+------------------------------------------------------------------+
void CheckForNewSignal()
{
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

   //--- v2.1: TP hedefi trend gucune gore (sig.tp zaten profil bazli ayarli)
   double tp = sig.tp;   // Trend: WEAK→TP1, MODERATE→TP2, STRONG→TP3

   //--- Islem ac (SL=YOK - MUTLAK)
   string comment = StringFormat("BTFX_%s_%d", _Symbol, sig.score);
   if(StringLen(comment) > 25) comment = StringSubstr(comment, 0, 25);

   ulong ticket = g_executor.OpenPosition(sig.direction, lot, tp, 0, comment);

   if(ticket > 0)
   {
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

   //--- TOOLTIP: Mouse ile ok uzerine gelince islem bilgileri goster
   string dirStr = (sig.direction == SIGNAL_BUY) ? "ALIS (BUY)" : "SATIS (SELL)";
   string trendStr;
   switch(sig.trendStrength)
   {
      case TREND_STRONG:   trendStr = "GUCLU";  break;
      case TREND_MODERATE: trendStr = "ORTA";   break;
      default:             trendStr = "ZAYIF";  break;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   string tooltip = StringFormat(
      "BytamerFX %s\n"
      "Yon: %s\n"
      "Skor: %d/100\n"
      "Lot: %.2f\n"
      "Fiyat: %s\n"
      "TP1: %s\n"
      "TP2: %s\n"
      "TP3: %s\n"
      "SL: YOK (MUTLAK)\n"
      "ATR: %s\n"
      "ADX: %.1f\n"
      "RSI: %.1f\n"
      "+DI/−DI: %.1f/%.1f\n"
      "Trend: %s\n"
      "MACD: %.6f\n"
      "Stoch: %.1f/%.1f\n"
      "Zaman: %s",
      EA_VERSION,
      dirStr,
      sig.score,
      lot,
      DoubleToString(price, digits),
      DoubleToString(sig.tp1, digits),
      DoubleToString(sig.tp2, digits),
      DoubleToString(sig.tp3, digits),
      DoubleToString(sig.atr, digits),
      sig.adx,
      sig.rsi,
      sig.plusDI, sig.minusDI,
      trendStr,
      sig.macd_main,
      sig.stoch_k, sig.stoch_d,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));

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
