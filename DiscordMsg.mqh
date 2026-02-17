//+------------------------------------------------------------------+
//|                                              DiscordMsg.mqh      |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| Discord Mesaj Sistemi - Embed Format + Emoji                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef DISCORD_MSG_MQH
#define DISCORD_MSG_MQH

#include "Config.mqh"

class CDiscordMsg
{
private:
   string   m_webhookUrl;
   bool     m_enabled;
   datetime m_lastSendTime;

public:
   CDiscordMsg() : m_enabled(false), m_lastSendTime(0) {}

   void Initialize(string webhookUrl, bool enabled)
   {
      m_webhookUrl = webhookUrl;
      m_enabled    = enabled;
      if(m_enabled)
         Print("Discord Mesaj: AKTIF");
   }

   //========================================
   // ISLEM ACILDI
   //========================================
   void SendTradeOpen(string symbol, string category, ENUM_SIGNAL_DIR dir,
                      double lot, double price, double tp, double sl,
                      double atr, double rsi, double adx, int score,
                      long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      bool isBuy = (dir == SIGNAL_BUY);
      int clr = isBuy ? 3066993 : 15158332;  // yesil / kirmizi
      string dirText = isBuy ? "AL (BUY)" : "SAT (SELL)";
      string dirEmoji = isBuy ? ":green_circle:" : ":red_circle:";

      string desc = "";
      desc += dirEmoji + " **ISLEM: " + dirText + "** " + dirEmoji + "\\n\\n";
      desc += ":moneybag: **Sembol:** `" + symbol + "` (" + category + ")\\n";
      desc += ":chart_with_upwards_trend: **Lot:** `" + DoubleToString(lot, 2) + "`\\n";
      desc += ":dollar: **Fiyat:** `" + DoubleToString(price, 5) + "`\\n\\n";
      desc += ":dart: **TP:** `" + DoubleToString(tp, 5) + "`\\n";
      desc += ":shield: **SL:** `YOK`\\n\\n";
      desc += ":fire: **ATR:** `" + DoubleToString(atr, 5) + "` | ";
      desc += "**RSI:** `" + DoubleToString(rsi, 1) + "` | ";
      desc += "**ADX:** `" + DoubleToString(adx, 1) + "`\\n";
      desc += ":star: **Skor:** `" + IntegerToString(score) + "/100`\\n\\n";
      desc += ":office: **Hesap:** `" + IntegerToString(accNo) + "` | **Broker:** `" + broker + "`\\n";
      desc += ":money_with_wings: **Bakiye:** `$" + DoubleToString(balance, 2) + "`";

      string footer = ":warning: Yatirim Tavsiyesi Degildir | @ByT@MER";

      SendEmbed(EA_VERSION_FULL, desc, clr, footer);
   }

   //========================================
   // ISLEM KAPANDI
   //========================================
   void SendTradeClose(string symbol, string category, ENUM_SIGNAL_DIR dir,
                       double lot, double openPrice, double closePrice,
                       double netProfit, double pctProfit,
                       long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      bool isProfit = (netProfit >= 0);
      int clr = isProfit ? 3066993 : 15158332;
      string resultText = isProfit ? "KAR" : "ZARAR";
      string resultEmoji = isProfit ? ":green_circle:" : ":red_circle:";
      string dirText = (dir == SIGNAL_BUY) ? "BUY" : "SELL";

      string desc = "";
      desc += resultEmoji + " **ISLEM KAPANDI: " + resultText + "** " + resultEmoji + "\\n\\n";
      desc += ":moneybag: **Sembol:** `" + symbol + "` (" + category + ")\\n";
      desc += ":chart_with_upwards_trend: **Yon:** `" + dirText + "` | **Lot:** `" + DoubleToString(lot, 2) + "`\\n";
      desc += ":arrow_up: **Alis:** `" + DoubleToString(openPrice, 5) + "`\\n";
      desc += ":arrow_down: **Kapanis:** `" + DoubleToString(closePrice, 5) + "`\\n\\n";
      desc += ":dollar: **Net P/L:** `" + (isProfit ? "+" : "") + DoubleToString(netProfit, 2) + " USD`\\n";
      desc += ":chart_with_upwards_trend: **Oran:** `" + (isProfit ? "+" : "") + DoubleToString(pctProfit, 2) + "%`\\n\\n";
      desc += ":office: **Hesap:** `" + IntegerToString(accNo) + "` | **Broker:** `" + broker + "`\\n";
      desc += ":money_with_wings: **Bakiye:** `$" + DoubleToString(balance, 2) + "`";

      string footer = ":warning: Yatirim Tavsiyesi Degildir | @ByT@MER";

      SendEmbed(EA_VERSION_FULL + " - " + resultText, desc, clr, footer);
   }

   //========================================
   // BASLANGIC
   //========================================
   void SendStartup(string symbol, string category, long accNo, string broker, double balance)
   {
      if(!m_enabled) return;

      string desc = "";
      desc += ":rocket: **EA BASLATILDI** :rocket:\\n\\n";
      desc += ":moneybag: **Sembol:** `" + symbol + "` (" + category + ")\\n";
      desc += ":office: **Hesap:** `" + IntegerToString(accNo) + "`\\n";
      desc += ":bank: **Broker:** `" + broker + "`\\n";
      desc += ":money_with_wings: **Bakiye:** `$" + DoubleToString(balance, 2) + "`\\n\\n";
      desc += ":shield: **Strateji:** SPM+FIFO | SL=YOK\\n";
      desc += ":dart: **Net Hedef:** $" + DoubleToString(SPM_NetTargetUSD, 2) + "\\n";
      desc += ":zap: **Koruma:** DD=" + DoubleToString(MaxDrawdownPercent, 0) + "%";

      string footer = ":warning: Yatirim Tavsiyesi Degildir | @ByT@MER";

      SendEmbed(EA_VERSION_FULL, desc, 3447003, footer);
   }

   //========================================
   // GENEL MESAJ (basit embed)
   //========================================
   void SendMessage(string text)
   {
      if(!m_enabled) return;
      SendEmbed(EA_VERSION_FULL, text, 3447003, ":warning: BytamerFX | @ByT@MER");
   }

private:
   //========================================
   // DISCORD EMBED GONDER
   //========================================
   void SendEmbed(string title, string description, int clr, string footer)
   {
      // Rate limiting: min 3sn arasinda
      if(TimeCurrent() - m_lastSendTime < 3)
         Sleep(3000);

      string json = "{\"embeds\":[{";
      json += "\"title\":\"" + EscapeJSON(title) + "\",";
      json += "\"description\":\"" + EscapeJSON(description) + "\",";
      json += "\"color\":" + IntegerToString(clr) + ",";
      json += "\"footer\":{\"text\":\"" + EscapeJSON(footer) + "\"},";

      // Timestamp
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      json += "\"timestamp\":\"" + StringFormat("%04d-%02d-%02dT%02d:%02d:%02d.000Z",
            dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec) + "\"";

      json += "}]}";

      char data[];
      char result[];
      string headers = "Content-Type: application/json\r\n";
      string resultHeaders;

      StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
      int dataLen = ArraySize(data);
      if(dataLen > 0 && data[dataLen - 1] == 0) dataLen--;

      int res = WebRequest("POST", m_webhookUrl, headers, 5000, data, result, resultHeaders);

      m_lastSendTime = TimeCurrent();

      if(res == 204 || res == 200)
         Print("Discord mesaj gonderildi!");
      else
         Print(StringFormat("Discord HATA: HTTP %d", res));
   }

   string EscapeJSON(string text)
   {
      string out = text;
      StringReplace(out, "\\", "\\\\");
      StringReplace(out, "\"", "\\\"");
      StringReplace(out, "\n", "\\n");
      StringReplace(out, "\r", "");
      return out;
   }
};

#endif
