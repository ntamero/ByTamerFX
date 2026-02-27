//+------------------------------------------------------------------+
//|                                              TelegramMsg.mqh     |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| Telegram Mesaj Sistemi v4.4.0 - Zengin Format + Token Dogrulama  |
//| 10 Mesaj Tipi: Startup, Shutdown, TradeOpen, TradeClose,         |
//|   SPM, Hedge, FIFO, GridReset, DailyReport, Generic              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef TELEGRAM_MSG_MQH
#define TELEGRAM_MSG_MQH

#include "Config.mqh"

class CTelegramMsg
{
private:
   string m_token;
   string m_chatId;
   bool   m_enabled;
   bool   m_tokenValid;           // v4.3: Token dogrulama sonucu

   //--- v3.5.3: Rate limiting
   datetime m_msgTimestamps[];
   int      m_msgCount;
   datetime m_rateLimitReset;
   string   m_lastMsgHash;
   datetime m_lastMsgTime;
   int      m_retryAfter;
   datetime m_retryUntil;

   //--- Emoji cache — Supplementary Plane (surrogat pair)
   string m_rocket, m_chart, m_money, m_dollar, m_target;
   string m_shield, m_fire, m_muscle, m_gem, m_bank, m_pc;
   string m_moneybag, m_greenCircle, m_redCircle;
   string m_upArrow, m_downArrow, m_sparkle;
   string m_office, m_cycle, m_blueCircle, m_yellowCircle;
   string m_wave, m_clipboard, m_medal1, m_medal2, m_medal3;

   //--- Emoji cache — BMP (tek karakter)
   string m_star, m_warning, m_bolt, m_line, m_check, m_cross;
   string m_clock, m_stopwatch, m_gear;
   string m_barFull, m_barEmpty;  // Progress bar icin

public:
   CTelegramMsg() : m_enabled(false), m_tokenValid(false), m_msgCount(0),
                    m_rateLimitReset(0), m_lastMsgTime(0), m_retryAfter(0), m_retryUntil(0)
   {
      m_lastMsgHash = "";
      ArrayResize(m_msgTimestamps, 0);
   }

   void Initialize(string token, string chatId, bool enabled)
   {
      m_token      = token;
      m_chatId     = chatId;
      m_enabled    = enabled;
      m_tokenValid = false;
      CacheEmojis();

      if(m_enabled)
      {
         Print("Telegram Mesaj: AKTIF (Rate limit: 15 msg/dk)");
         //--- v4.3: Token dogrulama
         ValidateToken();
      }
   }

   //================================================================
   // 1. EA BASLADI
   //================================================================
   void SendStartup(string symbol, string category, long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
      double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

      string msg = "";
      msg += FmtHeader(m_sparkle, "KazanKazan Pro AKTIF");

      //--- Hesap
      msg += m_bank   + " <b>Hesap:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_office + " <b>Broker:</b> <code>" + broker + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>" + FmtMoney(balance) + "</code>\n";
      msg += m_gem    + " <b>Equity:</b> <code>" + FmtMoney(equity) + "</code>\n";
      if(marginLevel > 0)
         msg += m_chart + " <b>Margin:</b> <code>%" + DoubleToString(marginLevel, 0) + "</code>\n";
      msg += "\n";

      //--- Sistem Ayarlari
      msg += FmtSection(m_gear, "Sistem Ayarlari");
      msg += m_clipboard + " <b>Strateji:</b> SPM + FIFO\n";
      msg += m_shield    + " <b>SL:</b> YOK (MUTLAK)\n";
      msg += m_star      + " <b>Min Skor:</b> " + IntegerToString(SignalMinScore) + "/100\n";
      msg += m_cycle     + " <b>SPM Max:</b> " + IntegerToString(SPM_MaxLayers) + " Katman\n";
      msg += m_bolt      + " <b>Grid Reset:</b> -%" + IntegerToString((int)(GridLossPercent * 100)) + " equity\n\n";

      //--- Aktif Sembol
      msg += FmtSection(m_chart, "Aktif Sembol");
      msg += m_check + " " + symbol + " (" + category + ")\n\n";

      msg += FmtFooter();
      SendMsg(msg);
   }

   //================================================================
   // 2. EA KAPANDI (v4.3 NEW)
   //================================================================
   void SendShutdown(string symbol, long accNo, double balance,
                     string reason, int closedTrades, double sessionProfit,
                     int runMinutes)
   {
      if(!m_enabled) return;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);

      string msg = "";
      msg += FmtHeader(m_redCircle, "SISTEM KAPANDI");

      msg += m_bank     + " <b>Hesap:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>" + FmtMoney(balance) + "</code>\n";
      msg += m_gem      + " <b>Equity:</b> <code>" + FmtMoney(equity) + "</code>\n\n";

      msg += FmtSection(m_chart, "Seans Ozeti");
      msg += m_check  + " <b>Kapatilan:</b> " + IntegerToString(closedTrades) + " islem\n";
      msg += m_dollar + " <b>Seans Kar:</b> <code>" + FmtMoneyPL(sessionProfit) + "</code>\n";
      msg += m_bolt   + " <b>Sebep:</b> " + reason + "\n";

      int hours = runMinutes / 60;
      int mins  = runMinutes % 60;
      msg += m_clock + " <b>Calisma:</b> " + IntegerToString(hours) + "s " + IntegerToString(mins) + "dk\n\n";

      msg += FmtFooter();
      SendMsg(msg);
   }

   //================================================================
   // 3. ISLEM ACILDI
   //================================================================
   void SendTradeOpen(string symbol, string category, ENUM_SIGNAL_DIR dir,
                      double lot, double price, double tp, double sl,
                      double atr, double rsi, double adx, int score,
                      long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
      double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      bool   isBuy       = (dir == SIGNAL_BUY);
      string dirEmoji    = isBuy ? m_greenCircle : m_redCircle;
      string dirText     = isBuy ? "BUY" : "SELL";
      string arrow       = isBuy ? m_upArrow : m_downArrow;

      string msg = "";
      msg += FmtHeader(dirEmoji, "YENI ISLEM ACILDI");

      msg += arrow + " <b>" + dirText + " " + symbol + "</b> (" + category + ")\n\n";

      //--- Islem Detay
      msg += FmtSection(m_money, "Islem Detay");
      msg += m_chart  + " <b>Lot:</b> <code>" + DoubleToString(lot, 2) + "</code>\n";
      msg += m_dollar + " <b>Fiyat:</b> <code>" + FmtPrice(price, symbol) + "</code>\n";
      if(tp > 0)
         msg += m_target + " <b>TP:</b> <code>" + FmtPrice(tp, symbol) + "</code>\n";
      msg += m_shield + " <b>SL:</b> <code>YOK</code>\n\n";

      //--- Sinyal Motoru
      msg += FmtSection(m_chart, "Sinyal Motoru");
      msg += m_star   + " <b>Skor:</b> <code>" + IntegerToString(score) + "/100</code>\n";
      msg += m_chart  + " <b>RSI:</b> <code>" + DoubleToString(rsi, 1) + "</code> | <b>ADX:</b> <code>" + DoubleToString(adx, 1) + "</code>\n";
      msg += m_fire   + " <b>ATR:</b> <code>" + DoubleToString(atr, 5) + "</code>\n\n";

      //--- Hesap
      msg += FmtSection(m_bank, "Hesap");
      msg += m_pc       + " <b>No:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>" + FmtMoney(balance) + "</code>\n";
      msg += m_gem      + " <b>Equity:</b> <code>" + FmtMoney(equity) + "</code>\n";
      if(marginLevel > 0)
         msg += m_chart + " <b>Margin:</b> <code>%" + DoubleToString(marginLevel, 0) + "</code>\n";
      msg += "\n";

      msg += FmtFooter();
      SendMsg(msg);
   }

   //================================================================
   // 4. ISLEM KAPANDI
   //================================================================
   void SendTradeClose(string symbol, string category, ENUM_SIGNAL_DIR dir,
                       double lot, double openPrice, double closePrice,
                       double netProfit, double pctProfit,
                       long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      bool   isProfit = (netProfit >= 0);
      string resEmoji = isProfit ? m_check : m_cross;
      string dirText  = (dir == SIGNAL_BUY) ? "BUY" : "SELL";
      string resLabel = isProfit ? "KAR" : "ZARAR";

      string msg = "";
      msg += FmtHeader(resEmoji, "ISLEM KAPANDI");

      msg += (isProfit ? m_greenCircle : m_redCircle);
      msg += " <b>" + dirText + " " + symbol + "</b> (" + category + ") " + resLabel + "\n\n";

      //--- Islem Sonucu
      msg += FmtSection(m_money, "Islem Sonucu");
      msg += m_chart     + " <b>Lot:</b> <code>" + DoubleToString(lot, 2) + "</code>\n";
      msg += m_upArrow   + " <b>Giris:</b> <code>" + FmtPrice(openPrice, symbol) + "</code>\n";
      msg += m_downArrow + " <b>Cikis:</b> <code>" + FmtPrice(closePrice, symbol) + "</code>\n";
      msg += resEmoji    + " <b>P/L:</b> <code>" + FmtMoneyPL(netProfit);
      msg += " (" + FmtPercentPL(pctProfit) + ")</code>\n\n";

      //--- Hesap
      msg += FmtSection(m_bank, "Hesap");
      msg += m_pc       + " <b>No:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>" + FmtMoney(balance) + "</code>\n";
      msg += m_gem      + " <b>Equity:</b> <code>" + FmtMoney(equity) + "</code>\n\n";

      msg += FmtFooter();
      SendMsg(msg);
   }

   //================================================================
   // 5. SPM OLAYI (v4.3 NEW)
   // positionMap: HTML formatted position list (PM tarafindan olusturulur)
   //================================================================
   void SendSPMEvent(string symbol, string category, int spmLayer,
                     string action, string positionMap,
                     double kasaTotal, double fifoTarget)
   {
      if(!m_enabled) return;

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      long   accNo   = AccountInfoInteger(ACCOUNT_LOGIN);

      string emoji = (action == "ACILDI") ? m_cycle : m_check;
      string title = "SPM #" + IntegerToString(spmLayer) + " " + action;

      string msg = "";
      msg += FmtHeader(emoji, title);
      msg += m_money + " <b>" + symbol + "</b> (" + category + ")\n\n";

      //--- SPM Durumu
      msg += FmtSection(m_chart, "Pozisyon Haritasi");
      msg += positionMap + "\n";

      //--- FIFO Hedef
      if(fifoTarget > 0 && kasaTotal >= 0)
      {
         msg += FmtSection(m_target, "FIFO Hedef");
         msg += m_moneybag + " <b>Kasa:</b> <code>" + FmtMoney(kasaTotal) + "</code>\n";
         msg += m_target   + " <b>Hedef:</b> <code>" + FmtMoney(fifoTarget) + "</code>\n";
         double pct = (fifoTarget > 0) ? MathMin(100.0, (kasaTotal / fifoTarget) * 100.0) : 0;
         msg += m_chart + " <b>Ilerleme:</b> " + FmtProgressBar(pct) + " " + DoubleToString(pct, 0) + "%\n\n";
      }
      else
         msg += "\n";

      //--- Hesap
      msg += m_pc + " <code>" + IntegerToString(accNo) + "</code> | ";
      msg += m_moneybag + " <code>" + FmtMoney(balance) + "</code> | ";
      msg += m_gem + " <code>" + FmtMoney(equity) + "</code>\n\n";

      msg += FmtFooterShort();
      SendMsg(msg);
   }

   //================================================================
   // 6. HEDGE OLAYI (v4.3 NEW)
   //================================================================
   void SendHedgeEvent(string symbol, string category, string action,
                       string hedgeDir, double hedgeLot, string positionMap)
   {
      if(!m_enabled) return;

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      long   accNo   = AccountInfoInteger(ACCOUNT_LOGIN);

      string emoji = (action == "ACILDI") ? m_shield : m_check;

      string msg = "";
      msg += FmtHeader(emoji, "RESCUE HEDGE " + action);
      msg += m_money  + " <b>" + symbol + "</b> (" + category + ")\n";
      msg += m_shield + " <b>HEDGE:</b> " + hedgeDir + " " + DoubleToString(hedgeLot, 2) + " lot\n\n";

      //--- Pozisyon Haritasi
      msg += FmtSection(m_chart, "Pozisyon Haritasi");
      msg += positionMap + "\n\n";

      //--- Hesap
      msg += m_pc + " <code>" + IntegerToString(accNo) + "</code> | ";
      msg += m_moneybag + " <code>" + FmtMoney(balance) + "</code> | ";
      msg += m_gem + " <code>" + FmtMoney(equity) + "</code>\n\n";

      msg += FmtFooterShort();
      SendMsg(msg);
   }

   //================================================================
   // 7. FIFO ANA KAPATMA (v4.3 NEW)
   //================================================================
   void SendFIFOEvent(string symbol, string category, double mainLoss,
                      double spmKasa, double netProfit, string promotionInfo)
   {
      if(!m_enabled) return;

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      long   accNo   = AccountInfoInteger(ACCOUNT_LOGIN);

      string msg = "";
      msg += FmtHeader(m_target, "FIFO: ANA KAPATILDI!");
      msg += m_money + " <b>" + symbol + "</b> (" + category + ")\n\n";

      //--- FIFO Sonuc
      msg += FmtSection(m_chart, "FIFO Sonuc");
      msg += m_downArrow + " <b>ANA Zarar:</b> <code>" + FmtMoney(mainLoss) + "</code>\n";
      msg += m_moneybag  + " <b>SPM Kasa:</b> <code>" + FmtMoneyPL(spmKasa) + "</code>\n";
      string netEmoji = (netProfit >= 0) ? m_check : m_cross;
      msg += netEmoji + " <b>Net:</b> <code>" + FmtMoneyPL(netProfit) + "</code>\n\n";

      //--- Terfi
      if(StringLen(promotionInfo) > 0)
         msg += m_cycle + " " + promotionInfo + "\n\n";

      //--- Hesap
      msg += m_pc + " <code>" + IntegerToString(accNo) + "</code> | ";
      msg += m_moneybag + " <code>" + FmtMoney(balance) + "</code> | ";
      msg += m_gem + " <code>" + FmtMoney(equity) + "</code>\n\n";

      msg += FmtFooterShort();
      SendMsg(msg);
   }

   //================================================================
   // 8. GUN SONU RAPORU (v4.3 NEW)
   //================================================================
   void SendDailyReport(long accNo, string broker, double balance,
                        double equity, double dailyProfit, double dailyProfitPct,
                        double floating, int totalClosed, int wins, int losses,
                        double totalWinAmt, double totalLossAmt,
                        string activePositionsStr, string topPerformersStr)
   {
      if(!m_enabled) return;

      double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

      //--- Tarih
      MqlDateTime dt;
      TimeCurrent(dt);
      string aylar[] = {"", "Ocak", "Subat", "Mart", "Nisan", "Mayis", "Haziran",
                         "Temmuz", "Agustos", "Eylul", "Ekim", "Kasim", "Aralik"};
      string dateStr = IntegerToString(dt.day) + " " + aylar[dt.mon] + " " + IntegerToString(dt.year);

      string msg = "";
      msg += FmtHeader(m_chart, "GUN SONU RAPORU\n" + dateStr);

      msg += m_bank   + " <b>Hesap:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_office + " <b>Broker:</b> <code>" + broker + "</code>\n\n";

      //--- Finansal Ozet
      msg += FmtSection(m_moneybag, "Finansal Ozet");
      msg += m_moneybag + " <b>Bakiye:</b> <code>" + FmtMoney(balance) + "</code>\n";
      msg += m_gem      + " <b>Equity:</b> <code>" + FmtMoney(equity) + "</code>\n";
      string plArrow = (dailyProfit >= 0) ? m_upArrow : m_downArrow;
      msg += plArrow + " <b>Gunluk:</b> <code>" + FmtMoneyPL(dailyProfit);
      msg += " (" + FmtPercentPL(dailyProfitPct) + ")</code>\n";
      msg += m_chart + " <b>Floating:</b> <code>" + FmtMoney(floating) + "</code>\n\n";

      //--- Islem Istatistik
      msg += FmtSection(m_chart, "Islem Istatistik");
      msg += m_check + " <b>Kapatilan:</b> " + IntegerToString(totalClosed) + " islem\n";
      if(totalClosed > 0)
      {
         double winRate = ((double)wins / (double)totalClosed) * 100.0;
         msg += m_greenCircle + " <b>Karli:</b> " + IntegerToString(wins) + " (%" + DoubleToString(winRate, 0) + ")\n";
         msg += m_redCircle   + " <b>Zararda:</b> " + IntegerToString(losses) + "\n";
         msg += m_dollar + " <b>Kar:</b> <code>" + FmtMoneyPL(totalWinAmt) + "</code>\n";
         msg += m_dollar + " <b>Zarar:</b> <code>" + FmtMoney(totalLossAmt) + "</code>\n";
         msg += m_chart  + " <b>Net:</b> <code>" + FmtMoneyPL(dailyProfit) + "</code>\n";
      }
      msg += "\n";

      //--- Aktif Pozisyonlar
      if(StringLen(activePositionsStr) > 0)
      {
         msg += FmtSection(m_cycle, "Aktif Pozisyonlar");
         msg += activePositionsStr + "\n\n";
      }

      //--- En Iyi Performans
      if(StringLen(topPerformersStr) > 0)
      {
         msg += FmtSection(m_upArrow, "En Iyi Performans");
         msg += topPerformersStr + "\n\n";
      }

      //--- Sistem Saglik
      msg += FmtSection(m_gear, "Sistem Saglik");
      msg += m_check + " <b>EA:</b> Aktif\n";
      msg += m_check + " <b>Sinyal Motoru:</b> OK\n";
      msg += m_check + " <b>SPM/FIFO:</b> Normal\n";
      if(marginLevel > 0)
         msg += m_check + " <b>Margin:</b> %" + DoubleToString(marginLevel, 0) + "\n";
      msg += "\n";

      msg += FmtFooter();
      SendMsg(msg);
   }

   //================================================================
   // 9. GRID RESET BILDIRIMI (v4.3 NEW)
   //================================================================
   void SendGridReset(string symbol, string category, double floatingLoss,
                      double gridLimit, string positionMap)
   {
      if(!m_enabled) return;

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      long   accNo   = AccountInfoInteger(ACCOUNT_LOGIN);

      string msg = "";
      msg += FmtHeader(m_fire, "GRID RESET!");
      msg += m_money + " <b>" + symbol + "</b> (" + category + ")\n\n";

      msg += m_warning + " <b>Floating:</b> <code>" + FmtMoney(floatingLoss) + "</code>\n";
      msg += m_shield  + " <b>Esik:</b> <code>" + FmtMoney(gridLimit) + "</code>\n\n";

      if(StringLen(positionMap) > 0)
      {
         msg += FmtSection(m_chart, "Kapatilan Pozisyonlar");
         msg += positionMap + "\n\n";
      }

      msg += m_pc + " <code>" + IntegerToString(accNo) + "</code> | ";
      msg += m_moneybag + " <code>" + FmtMoney(balance) + "</code> | ";
      msg += m_gem + " <code>" + FmtMoney(equity) + "</code>\n\n";

      msg += FmtFooterShort();
      SendMsg(msg);
   }

   //================================================================
   // 10. GENEL MESAJ (generic fallback — PositionManager icin)
   // v4.3: Otomatik emoji + hesap bilgisi + cerceve
   //================================================================
   void SendMessage(string text)
   {
      if(!m_enabled) return;

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      long   accNo   = AccountInfoInteger(ACCOUNT_LOGIN);

      //--- Otomatik icon secimi
      string icon = m_bolt;
      if(StringFind(text, "KAPAT") >= 0)
      {
         if(StringFind(text, "$-") >= 0 || StringFind(text, "ZARAR") >= 0)
            icon = m_redCircle;
         else
            icon = m_greenCircle;
      }
      else if(StringFind(text, "SPM") >= 0 || StringFind(text, "ANA") >= 0)
         icon = m_chart;
      else if(StringFind(text, "DCA") >= 0)
         icon = m_money;
      else if(StringFind(text, "HEDGE") >= 0)
         icon = m_shield;
      else if(StringFind(text, "TP") >= 0)
         icon = m_target;
      else if(StringFind(text, "TERFI") >= 0)
         icon = m_sparkle;
      else if(StringFind(text, "FIFO") >= 0)
         icon = m_star;
      else if(StringFind(text, "MARGIN") >= 0 || StringFind(text, "KILITLENME") >= 0 || StringFind(text, "ACIL") >= 0)
         icon = m_warning + " " + m_fire;
      else if(StringFind(text, "TREND") >= 0)
         icon = m_wave;

      string msg = "";
      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      msg += icon + " " + text + "\n";
      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      msg += m_pc + " <code>" + IntegerToString(accNo) + "</code> | ";
      msg += m_moneybag + " <code>" + FmtMoney(balance) + "</code> | ";
      msg += m_gem + " <code>" + FmtMoney(equity) + "</code>";

      SendMsg(msg);
   }

   //================================================================
   // HABER UYARI MESAJI (NewsManager formatli — degismedi)
   //================================================================
   void SendNewsAlert(string formattedMsg)
   {
      SendMsg(formattedMsg);
   }

   //================================================================
   // TOKEN DURUMU
   //================================================================
   bool IsTokenValid() const { return m_tokenValid; }

private:
   //================================================================
   // TOKEN DOGRULAMA (v4.3)
   //================================================================
   void ValidateToken()
   {
      if(StringLen(m_token) < 10)
      {
         Print("TELEGRAM TOKEN HATALI: Token cok kisa!");
         m_tokenValid = false;
         return;
      }

      string url = "https://api.telegram.org/bot" + m_token + "/getMe";
      char   data[];
      char   result[];
      string headers     = "";
      string resHeaders;

      ArrayResize(data, 0);
      int res = WebRequest("GET", url, headers, 5000, data, result, resHeaders);

      if(res == 200)
      {
         m_tokenValid = true;
         string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
         Print("Telegram Token: GECERLI | ", body);
      }
      else if(res == 401)
      {
         m_tokenValid = false;
         Print("!!! TELEGRAM TOKEN GECERSIZ (HTTP 401) !!!");
         Print("!!! BotFather'dan yeni token alin: https://t.me/BotFather !!!");
      }
      else if(res == -1)
      {
         //--- WebRequest izni yok veya URL eklenmemis
         m_tokenValid = false;  // Bilinmiyor
         int err = GetLastError();
         PrintFormat("Telegram Token dogrulama basarisiz: WebRequest err=%d", err);
         Print("MT5 > Tools > Options > Expert Advisors > Allow WebRequest URL:");
         Print("  https://api.telegram.org eklenmeli!");
      }
      else
      {
         m_tokenValid = false;
         string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
         PrintFormat("Telegram Token dogrulama: HTTP %d | %s", res, body);
      }
   }

   //================================================================
   // EMOJI CACHE
   //================================================================
   void CacheEmojis()
   {
      //--- Supplementary Plane (U+1Fxxx) — surrogat pair
      m_rocket       = Emoji(0xD83D, 0xDE80);   // U+1F680
      m_chart        = Emoji(0xD83D, 0xDCCA);   // U+1F4CA
      m_money        = Emoji(0xD83D, 0xDCB1);   // U+1F4B1
      m_dollar       = Emoji(0xD83D, 0xDCB5);   // U+1F4B5
      m_target       = Emoji(0xD83C, 0xDFAF);   // U+1F3AF
      m_shield       = Emoji(0xD83D, 0xDEE1);   // U+1F6E1
      m_fire         = Emoji(0xD83D, 0xDD25);   // U+1F525
      m_muscle       = Emoji(0xD83D, 0xDCAA);   // U+1F4AA
      m_gem          = Emoji(0xD83D, 0xDC8E);   // U+1F48E
      m_bank         = Emoji(0xD83C, 0xDFE6);   // U+1F3E6
      m_pc           = Emoji(0xD83D, 0xDCBB);   // U+1F4BB
      m_moneybag     = Emoji(0xD83D, 0xDCB0);   // U+1F4B0
      m_greenCircle  = Emoji(0xD83D, 0xDFE2);   // U+1F7E2
      m_redCircle    = Emoji(0xD83D, 0xDD34);   // U+1F534
      m_upArrow      = Emoji(0xD83D, 0xDCC8);   // U+1F4C8
      m_downArrow    = Emoji(0xD83D, 0xDCC9);   // U+1F4C9
      m_sparkle      = Emoji(0xD83D, 0xDCAB);   // U+1F4AB
      m_office       = Emoji(0xD83C, 0xDFE2);   // U+1F3E2
      m_cycle        = Emoji(0xD83D, 0xDD04);   // U+1F504
      m_blueCircle   = Emoji(0xD83D, 0xDD35);   // U+1F535
      m_yellowCircle = Emoji(0xD83D, 0xDFE1);   // U+1F7E1
      m_wave         = Emoji(0xD83C, 0xDF0A);   // U+1F30A
      m_clipboard    = Emoji(0xD83D, 0xDCCB);   // U+1F4CB
      m_medal1       = Emoji(0xD83E, 0xDD47);   // U+1F947
      m_medal2       = Emoji(0xD83E, 0xDD48);   // U+1F948
      m_medal3       = Emoji(0xD83E, 0xDD49);   // U+1F949

      //--- BMP (tek karakter)
      m_star      = ShortToString(0x2B50);   // U+2B50  ⭐
      m_warning   = ShortToString(0x26A0);   // U+26A0  ⚠
      m_bolt      = ShortToString(0x26A1);   // U+26A1  ⚡
      m_line      = ShortToString(0x2501);   // U+2501  ━
      m_check     = ShortToString(0x2705);   // U+2705  ✅
      m_cross     = ShortToString(0x274C);   // U+274C  ❌
      m_clock     = ShortToString(0x23F0);   // U+23F0  ⏰
      m_stopwatch = ShortToString(0x23F1);   // U+23F1  ⏱
      m_gear      = ShortToString(0x2699);   // U+2699  ⚙
      m_barFull   = ShortToString(0x2593);   // U+2593  ▓
      m_barEmpty  = ShortToString(0x2591);   // U+2591  ░
   }

   string Emoji(ushort high, ushort low)
   {
      return ShortToString(high) + ShortToString(low);
   }

   //================================================================
   // FORMAT HELPER'LAR
   //================================================================

   //--- Baslik cercevesi
   string FmtHeader(string emoji, string title)
   {
      string h = "";
      h += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      h += "  " + emoji + " <b>BytamerFX v" + EA_VERSION + "</b> " + emoji + "\n";
      h += "  " + title + "\n";
      h += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n\n";
      return h;
   }

   //--- Bolum basligi
   string FmtSection(string emoji, string title)
   {
      return m_line + m_line + " " + emoji + " <b>" + title + "</b> " + m_line + m_line + "\n";
   }

   //--- Alt bilgi (tam)
   string FmtFooter()
   {
      string f = "";
      f += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      f += m_clock + " " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + "\n";
      f += m_warning + " <i>Yatirim Tavsiyesi Degildir</i>\n";
      f += "          " + m_gem + " <i>@ByT@MER</i> " + m_gem;
      return f;
   }

   //--- Alt bilgi (kisa)
   string FmtFooterShort()
   {
      string f = "";
      f += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      f += m_gem + " <i>@ByT@MER</i> " + m_gem;
      return f;
   }

   //--- Para formati: $1,234.56
   string FmtMoney(double val)
   {
      string s = "$" + DoubleToString(MathAbs(val), 2);
      if(val < 0) s = "-" + s;
      return s;
   }

   //--- Para P/L formati: +$12.34 veya -$5.67
   string FmtMoneyPL(double val)
   {
      if(val >= 0)
         return "+$" + DoubleToString(val, 2);
      else
         return "-$" + DoubleToString(MathAbs(val), 2);
   }

   //--- Yuzde P/L formati: +6.3% veya -2.1%
   string FmtPercentPL(double val)
   {
      if(val >= 0)
         return "+" + DoubleToString(val, 2) + "%";
      else
         return DoubleToString(val, 2) + "%";
   }

   //--- Fiyat formati (sembol digits'e gore)
   string FmtPrice(double price, string symbol)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits <= 0) digits = 5;
      return DoubleToString(price, digits);
   }

   //--- Progress bar: ▓▓▓▓░░░░ (8 karakter)
   string FmtProgressBar(double pct)
   {
      int total = 8;
      int filled = (int)MathRound((pct / 100.0) * total);
      if(filled < 0) filled = 0;
      if(filled > total) filled = total;

      string bar = "";
      for(int i = 0; i < filled; i++)
         bar += m_barFull;
      for(int i = filled; i < total; i++)
         bar += m_barEmpty;
      return bar;
   }

   //================================================================
   // MESAJ GONDER (internal) — v3.5.3: Rate limit + Duplicate suppress
   // v4.3: Detayli hata loglama + response body
   //================================================================
   void SendMsg(string text)
   {
      if(!m_enabled || StringLen(m_token) < 10) return;

      datetime now = TimeCurrent();

      //--- Telegram 429 retry_after bekleme
      if(m_retryUntil > 0 && now < m_retryUntil)
      {
         PrintFormat("Telegram: 429 bekleme aktif, %d sn kaldi", (int)(m_retryUntil - now));
         return;
      }
      m_retryUntil = 0;

      //--- Duplicate mesaj onleme (3 saniye icinde ayni mesaj)
      string msgHash = StringSubstr(text, 0, 100);
      if(msgHash == m_lastMsgHash && (now - m_lastMsgTime) < 3)
         return;

      //--- Rate limiting (15 mesaj/dakika)
      int validCount = 0;
      for(int i = 0; i < ArraySize(m_msgTimestamps); i++)
      {
         if(now - m_msgTimestamps[i] < 60)
         {
            if(i != validCount)
               m_msgTimestamps[validCount] = m_msgTimestamps[i];
            validCount++;
         }
      }
      ArrayResize(m_msgTimestamps, validCount);

      if(validCount >= 15)
      {
         PrintFormat("Telegram: Rate limit (15/dk) asildi, mesaj atlandi");
         return;
      }

      //--- Timestamp kaydet
      ArrayResize(m_msgTimestamps, validCount + 1);
      m_msgTimestamps[validCount] = now;
      m_lastMsgHash = msgHash;
      m_lastMsgTime = now;

      //--- HTTP istegi
      string url = "https://api.telegram.org/bot" + m_token + "/sendMessage";

      string json = "{";
      json += "\"chat_id\":\"" + m_chatId + "\",";
      json += "\"text\":\"" + EscapeJSON(text) + "\",";
      json += "\"parse_mode\":\"HTML\",";
      json += "\"disable_web_page_preview\":true";
      json += "}";

      char   data[];
      char   result[];
      string headers    = "Content-Type: application/json\r\n";
      string resHeaders;

      StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);

      int dataLen = ArraySize(data);
      if(dataLen > 0 && data[dataLen - 1] == 0) dataLen--;

      int res = WebRequest("POST", url, headers, 5000, data, result, resHeaders);

      if(res == 200)
      {
         // Basarili — sessiz
      }
      else if(res == 429)
      {
         //--- Telegram rate limit
         string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
         int retryPos = StringFind(body, "retry_after");
         if(retryPos >= 0)
         {
            string retryPart = StringSubstr(body, retryPos + 13, 5);
            string numStr = "";
            for(int c = 0; c < StringLen(retryPart); c++)
            {
               ushort ch = StringGetCharacter(retryPart, c);
               if(ch >= '0' && ch <= '9') numStr += ShortToString(ch);
               else break;
            }
            m_retryAfter = (int)StringToInteger(numStr);
            if(m_retryAfter <= 0) m_retryAfter = 30;
         }
         else
            m_retryAfter = 30;

         m_retryUntil = now + m_retryAfter;
         PrintFormat("Telegram 429: %d sn bekleme", m_retryAfter);
      }
      else
      {
         //--- v4.3: Detayli hata — response body dahil
         string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
         PrintFormat("Telegram HATA: HTTP %d | %s", res, body);

         if(res == 401)
            Print("!!! TOKEN GECERSIZ — BotFather'dan yeni token alin !!!");
         else if(res == 400)
            Print("!!! ISTEK HATALI — Chat ID veya mesaj formati kontrol edin !!!");
         else if(res == -1)
         {
            int err = GetLastError();
            PrintFormat("WebRequest hatasi: %d | URL listesine https://api.telegram.org ekleyin", err);
         }
      }
   }

   string EscapeJSON(string text)
   {
      string out = text;
      StringReplace(out, "\\", "\\\\");
      StringReplace(out, "\"", "\\\"");
      StringReplace(out, "\n", "\\n");
      StringReplace(out, "\r", "");
      StringReplace(out, "\t", "\\t");
      return out;
   }
};

#endif
