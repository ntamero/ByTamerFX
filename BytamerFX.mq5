//+------------------------------------------------------------------+
//|                                                   BytamerFX.mq5  |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX v1.0.0 - SPM-FIFO                                     |
//| M15 Timeframe | SL=YOK (MUTLAK) | 7 Katman Hibrit Sinyal        |
//| Hesap: 262230423 (Exness)                                        |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, By T@MER"
#property link        "https://www.bytamer.com"
#property version     "1.00"
#property description "BytamerFX v1.0.0 - SPM-FIFO Strateji"
#property description "7 Katmanli Hibrit Sinyal Motoru"
#property description "SL=YOK | Asla Zararina Satis Yok"
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
   Print("SL=YOK | Strateji: SPM+FIFO | Net Hedef: $" + DoubleToString(SPM_NetTargetUSD, 2));
   Print("================================================");

   //--- 2. SEMBOL KATEGORI TESPITI
   g_symMgr.Initialize(_Symbol);
   g_category = g_symMgr.GetCategory();

   string catName;
   switch(g_category)
   {
      case CAT_FOREX:   catName = "FOREX";   break;
      case CAT_METAL:   catName = "METAL";   break;
      case CAT_CRYPTO:  catName = "CRYPTO";  break;
      case CAT_INDICES: catName = "INDEX";   break;
      case CAT_STOCKS:  catName = "STOCK";   break;
      case CAT_ENERGY:  catName = "ENERGY";  break;
      default:          catName = "UNKNOWN"; break;
   }
   Print(StringFormat("Sembol Kategorisi: %s (%s)", _Symbol, catName));

   //--- 3. SPREAD FILTRESI
   double defaultSpread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   g_spreadFilter.Initialize(_Symbol, defaultSpread, MaxSpreadPercent);

   //--- 4. MUM ANALIZORU
   g_candle.Initialize(_Symbol, PERIOD_M15);

   //--- 5. LOT HESAPLAYICI
   g_lotCalc.Initialize(_Symbol, g_category);

   //--- 6. SINYAL MOTORU
   if(!g_signalEngine.Initialize(_Symbol, g_category))
   {
      Print("!!! SINYAL MOTORU BASARISIZ - EA DEVRE DISI !!!");
      return INIT_FAILED;
   }

   //--- 7. ISLEM YURUTME
   g_executor.Initialize(_Symbol);

   //--- 8. BILDIRIMLER
   g_telegram.Initialize(TelegramToken, TelegramChatID, EnableTelegram);
   g_discord.Initialize(DiscordWebhookURL, EnableDiscord);

   //--- 9. POZISYON YONETICI (SPM+FIFO)
   g_posMgr.Initialize(_Symbol, g_category, g_executor, g_signalEngine,
                        g_telegram, g_discord);

   //--- 10. DASHBOARD
   g_dashboard.Initialize(_Symbol, g_category, g_signalEngine, g_posMgr,
                          g_spreadFilter, EnableDashboard);

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
}

//+------------------------------------------------------------------+
//| Yeni sinyal kontrolu ve islem acma                                |
//+------------------------------------------------------------------+
void CheckForNewSignal()
{
   //--- Cooldown kontrolu
   if(TimeCurrent() - g_lastSignalCheck < SignalCooldownSec)
      return;

   //--- Spread kontrolu
   if(!g_spreadFilter.IsSpreadOK())
      return;

   //--- Sinyal motoru degerlendir
   SignalData sig = g_signalEngine.Evaluate();

   if(sig.direction == SIGNAL_NONE)
      return;

   if(sig.score < SignalMinScore)
      return;

   g_lastSignalCheck = TimeCurrent();

   Print(StringFormat("=== YENI SINYAL: %s | Skor: %d/100 ===",
         (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL", sig.score));
   Print(StringFormat("  RSI=%.1f | ADX=%.1f | ATR=%.5f", sig.rsi, sig.adx, sig.atr));
   Print(StringFormat("  TP1=%.5f | TP2=%.5f | TP3=%.5f", sig.tp1, sig.tp2, sig.tp3));

   //--- Lot hesapla
   double lot = g_lotCalc.Calculate(AccountInfoDouble(ACCOUNT_BALANCE), sig.atr, sig.score);

   //--- TP hedefi belirle (TP1 default)
   double tp = sig.tp1;

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
      string catName;
      switch(g_category)
      {
         case CAT_FOREX:   catName = "FOREX";   break;
         case CAT_METAL:   catName = "METAL";   break;
         case CAT_CRYPTO:  catName = "CRYPTO";  break;
         case CAT_INDICES: catName = "INDEX";   break;
         case CAT_STOCKS:  catName = "STOCK";   break;
         case CAT_ENERGY:  catName = "ENERGY";  break;
         default:          catName = "UNKNOWN"; break;
      }

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

      //--- Chart uzerine ok ciz
      DrawSignalArrow(sig.direction, price);
   }
   else
   {
      Print(StringFormat("ISLEM ACMA HATASI: %s | %s | Lot=%.2f | Hata=%d",
            (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL", _Symbol, lot, GetLastError()));
   }
}

//+------------------------------------------------------------------+
//| Sinyal oku chart uzerine ciz                                      |
//+------------------------------------------------------------------+
void DrawSignalArrow(ENUM_SIGNAL_DIR dir, double price)
{
   string name = "BTFX_Arrow_" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   StringReplace(name, " ", "_");
   StringReplace(name, ":", "_");
   StringReplace(name, ".", "_");

   int arrowCode;
   color arrowClr;

   if(dir == SIGNAL_BUY)
   {
      arrowCode = 233;  // Up arrow
      arrowClr = clrLime;
   }
   else
   {
      arrowCode = 234;  // Down arrow
      arrowClr = clrRed;
   }

   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, arrowClr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, ArrowSize);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| ChartEvent handler (opsiyonel gelecek kullanim)                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Gelecekte dashboard etkilesimi icin
}

//+------------------------------------------------------------------+
