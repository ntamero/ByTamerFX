//+------------------------------------------------------------------+
//|                                              TelegramMsg.mqh     |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| Telegram Mesaj Sistemi - Emoji + Cerceve + HTML Format           |
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

   //--- Emoji cache
   string m_rocket, m_chart, m_money, m_dollar, m_target;
   string m_shield, m_fire, m_muscle, m_star, m_warning;
   string m_gem, m_bolt, m_bank, m_pc, m_check, m_cross;
   string m_greenCircle, m_redCircle, m_upArrow, m_downArrow;
   string m_line, m_moneybag, m_sparkle;

public:
   CTelegramMsg() : m_enabled(false) {}

   void Initialize(string token, string chatId, bool enabled)
   {
      m_token   = token;
      m_chatId  = chatId;
      m_enabled = enabled;
      CacheEmojis();
      if(m_enabled)
         Print("Telegram Mesaj: AKTIF");
   }

   //========================================
   // ISLEM ACILDI MESAJI
   //========================================
   void SendTradeOpen(string symbol, string category, ENUM_SIGNAL_DIR dir,
                      double lot, double price, double tp, double sl,
                      double atr, double rsi, double adx, int score,
                      long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      bool isBuy = (dir == SIGNAL_BUY);
      string dirEmoji = isBuy ? m_greenCircle : m_redCircle;
      string dirText  = isBuy ? "AL (BUY)" : "SAT (SELL)";
      string arrow    = isBuy ? m_upArrow : m_downArrow;

      string msg = "";
      // Baslik
      msg += dirEmoji + " <b>" + EA_VERSION_FULL + "</b> " + dirEmoji + "\n";
      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n\n";

      // Islem bilgisi
      msg += arrow + " <b>ISLEM: " + dirText + "</b> " + arrow + "\n\n";

      // Sembol detaylari
      msg += m_money + " <b>Sembol:</b> <code>" + symbol + "</code> (" + category + ")\n";
      msg += m_chart + " <b>Lot:</b> <code>" + DoubleToString(lot, 2) + "</code>\n";
      msg += m_dollar + " <b>Fiyat:</b> <code>" + DoubleToString(price, 5) + "</code>\n\n";

      // TP / SL
      msg += m_target + " <b>TP:</b> <code>" + DoubleToString(tp, 5) + "</code>\n";
      msg += m_shield + " <b>SL:</b> <code>YOK</code>\n\n";

      // Indikatorler
      msg += m_line + m_line + " " + m_chart + " <b>Indikatorler</b> " + m_line + m_line + "\n";
      msg += m_fire + " <b>ATR:</b> <code>" + DoubleToString(atr, 5) + "</code>\n";
      msg += m_chart + " <b>RSI:</b> <code>" + DoubleToString(rsi, 1) + "</code>\n";
      msg += m_muscle + " <b>ADX:</b> <code>" + DoubleToString(adx, 1) + "</code>\n";
      msg += m_star + " <b>Skor:</b> <code>" + IntegerToString(score) + "/100</code>\n\n";

      // Hesap bilgisi
      msg += m_line + m_line + " " + m_bank + " <b>Hesap</b> " + m_line + m_line + "\n";
      msg += m_pc + " <b>Hesap:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_bank + " <b>Broker:</b> <code>" + broker + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>$" + DoubleToString(balance, 2) + "</code>\n\n";

      // Uyari + imza
      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      msg += m_warning + " <b><i>Yatirim Tavsiyesi Degildir</i></b> " + m_warning + "\n";
      msg += "          " + m_gem + " <i>@ByT@MER</i> " + m_gem;

      SendMsg(msg);
   }

   //========================================
   // ISLEM KAPANDI MESAJI
   //========================================
   void SendTradeClose(string symbol, string category, ENUM_SIGNAL_DIR dir,
                       double lot, double openPrice, double closePrice,
                       double netProfit, double pctProfit,
                       long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      bool isProfit = (netProfit >= 0);
      string resultEmoji = isProfit ? m_greenCircle : m_redCircle;
      string resultText  = isProfit ? "KAR" : "ZARAR";
      string dirText = (dir == SIGNAL_BUY) ? "BUY" : "SELL";

      string msg = "";
      msg += resultEmoji + " <b>" + EA_VERSION_FULL + "</b> " + resultEmoji + "\n";
      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n\n";

      msg += m_check + " <b>ISLEM KAPANDI: " + resultText + "</b>\n\n";

      msg += m_money + " <b>Sembol:</b> <code>" + symbol + "</code> (" + category + ")\n";
      msg += m_chart + " <b>Yon:</b> <code>" + dirText + "</code> | Lot: <code>" + DoubleToString(lot, 2) + "</code>\n";
      msg += m_upArrow + " <b>Alis:</b> <code>" + DoubleToString(openPrice, 5) + "</code>\n";
      msg += m_downArrow + " <b>Kapanis:</b> <code>" + DoubleToString(closePrice, 5) + "</code>\n\n";

      // Kar/Zarar
      string profitColor = isProfit ? "" : "";
      msg += m_dollar + " <b>Net P/L:</b> <code>" + (isProfit ? "+" : "") + DoubleToString(netProfit, 2) + " USD</code>\n";
      msg += m_chart + " <b>Oran:</b> <code>" + (isProfit ? "+" : "") + DoubleToString(pctProfit, 2) + "%</code>\n\n";

      // Hesap
      msg += m_line + m_line + " " + m_bank + " <b>Hesap</b> " + m_line + m_line + "\n";
      msg += m_pc + " <b>Hesap:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_bank + " <b>Broker:</b> <code>" + broker + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>$" + DoubleToString(balance, 2) + "</code>\n\n";

      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      msg += m_warning + " <b><i>Yatirim Tavsiyesi Degildir</i></b> " + m_warning + "\n";
      msg += "          " + m_gem + " <i>@ByT@MER</i> " + m_gem;

      SendMsg(msg);
   }

   //========================================
   // BASLANGIC MESAJI
   //========================================
   void SendStartup(string symbol, string category, long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      string msg = "";
      msg += m_rocket + " <b>" + EA_VERSION_FULL + "</b> " + m_rocket + "\n";
      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n\n";

      msg += m_sparkle + " <b>EA BASLATILDI</b> " + m_sparkle + "\n\n";

      msg += m_money + " <b>Sembol:</b> <code>" + symbol + "</code> (" + category + ")\n";
      msg += m_pc + " <b>Hesap:</b> <code>" + IntegerToString(accNo) + "</code>\n";
      msg += m_bank + " <b>Broker:</b> <code>" + broker + "</code>\n";
      msg += m_moneybag + " <b>Bakiye:</b> <code>$" + DoubleToString(balance, 2) + "</code>\n\n";

      msg += m_shield + " <b>Strateji:</b> SPM+FIFO | SL=YOK\n";
      msg += m_target + " <b>Net Hedef:</b> $" + DoubleToString(SPM_NetTargetUSD, 2) + "\n";
      msg += m_bolt + " <b>Koruma:</b> DD=" + DoubleToString(MaxDrawdownPercent, 0) + "%\n\n";

      msg += m_line + m_line + m_line + m_line + m_line + m_line + m_line + m_line + "\n";
      msg += m_warning + " <b><i>Yatirim Tavsiyesi Degildir</i></b> " + m_warning + "\n";
      msg += "          " + m_gem + " <i>@ByT@MER</i> " + m_gem;

      SendMsg(msg);
   }

   //========================================
   // GENEL MESAJ (public - PositionManager icin)
   //========================================
   void SendMessage(string text)
   {
      SendMsg(text);
   }

private:
   //========================================
   // EMOJI CACHE (surrogat pair + BMP)
   //========================================
   void CacheEmojis()
   {
      // Supplementary Plane (U+1Fxxx) - surrogat pair gerekir
      m_rocket      = Emoji(0xD83D, 0xDE80);  // U+1F680
      m_chart       = Emoji(0xD83D, 0xDCCA);  // U+1F4CA
      m_money       = Emoji(0xD83D, 0xDCB1);  // U+1F4B1
      m_dollar      = Emoji(0xD83D, 0xDCB5);  // U+1F4B5
      m_target      = Emoji(0xD83C, 0xDFAF);  // U+1F3AF
      m_shield      = Emoji(0xD83D, 0xDEE1);  // U+1F6E1
      m_fire        = Emoji(0xD83D, 0xDD25);  // U+1F525
      m_muscle      = Emoji(0xD83D, 0xDCAA);  // U+1F4AA
      m_gem         = Emoji(0xD83D, 0xDC8E);  // U+1F48E
      m_bank        = Emoji(0xD83C, 0xDFE6);  // U+1F3E6
      m_pc          = Emoji(0xD83D, 0xDCBB);  // U+1F4BB
      m_moneybag    = Emoji(0xD83D, 0xDCB0);  // U+1F4B0
      m_greenCircle = Emoji(0xD83D, 0xDFE2);  // U+1F7E2
      m_redCircle   = Emoji(0xD83D, 0xDD34);  // U+1F534
      m_upArrow     = Emoji(0xD83D, 0xDCC8);  // U+1F4C8
      m_downArrow   = Emoji(0xD83D, 0xDCC9);  // U+1F4C9
      m_sparkle     = Emoji(0xD83D, 0xDCAB);  // U+1F4AB

      // BMP (tek karakter)
      m_star    = ShortToString(0x2B50);    // U+2B50
      m_warning = ShortToString(0x26A0);    // U+26A0
      m_bolt    = ShortToString(0x26A1);    // U+26A1
      m_line    = ShortToString(0x2501);    // U+2501 (kalin yatay cizgi)
      m_check   = ShortToString(0x2705);    // U+2705
      m_cross   = ShortToString(0x274C);    // U+274C
   }

   string Emoji(ushort high, ushort low)
   {
      return ShortToString(high) + ShortToString(low);
   }

   //========================================
   // MESAJ GONDER (internal)
   //========================================
   void SendMsg(string text)
   {
      if(!m_enabled || StringLen(m_token) < 10) return;

      string url = "https://api.telegram.org/bot" + m_token + "/sendMessage";

      // JSON body
      string json = "{";
      json += "\"chat_id\":\"" + m_chatId + "\",";
      json += "\"text\":\"" + EscapeJSON(text) + "\",";
      json += "\"parse_mode\":\"HTML\",";
      json += "\"disable_web_page_preview\":true";
      json += "}";

      char data[];
      char result[];
      string headers = "Content-Type: application/json\r\n";
      string resultHeaders;

      StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);

      // Son byte null ise cikar
      int dataLen = ArraySize(data);
      if(dataLen > 0 && data[dataLen - 1] == 0) dataLen--;

      Print(StringFormat("Telegram mesaj uzunlugu: %d | JSON: %d", StringLen(text), dataLen));

      int res = WebRequest("POST", url, headers, 5000, data, result, resultHeaders);

      if(res == 200)
         Print("Telegram mesaj gonderildi!");
      else
         Print(StringFormat("Telegram HATA: HTTP %d | %s", res, CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8)));
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
