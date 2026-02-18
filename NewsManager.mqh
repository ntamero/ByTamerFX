//+------------------------------------------------------------------+
//|                                              NewsManager.mqh     |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| UNIVERSAL NEWS INTELLIGENCE SYSTEM v2.2                          |
//| Multi-Category, Multi-Tier Haber Yonetim Sistemi                 |
//| Kategori bazli haber filtreleme + islem kontrolu                 |
//| Telegram/Discord entegre bildirim sistemi                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef NEWS_MANAGER_MQH
#define NEWS_MANAGER_MQH

#include "Config.mqh"

//=================================================================
// HABER ONEM SEVIYELERI
//=================================================================
enum ENUM_NEWS_IMPACT
{
   NEWS_CRITICAL = 3,    // Kirmizi - Kritik (NFP, FOMC, ECB vb.)
   NEWS_HIGH     = 2,    // Turuncu - Yuksek (CPI, GDP, Employment)
   NEWS_MEDIUM   = 1,    // Sari   - Orta (PMI, Retail Sales)
   NEWS_LOW      = 0     // Gri    - Dusuk (minor haberleri)
};

//=================================================================
// HABER VERI YAPISI
//=================================================================
struct NewsEvent
{
   datetime          eventTime;        // Haber zamani (GMT)
   string            title;            // Haber basligi
   string            currency;         // Etkilenen para birimi (USD, EUR, GBP...)
   ENUM_NEWS_IMPACT  impact;           // Onem seviyesi
   bool              isActive;         // Su anda aktif mi?
   datetime          blockStartTime;   // Islem blok baslangici (haber-20dk)
   datetime          blockEndTime;     // Islem blok bitisi (haber+5dk)
};

//=================================================================
// SABITLER
//=================================================================
#define MAX_NEWS_EVENTS    50
#define NEWS_BLOCK_BEFORE  1200    // 20 dakika once (saniye)
#define NEWS_BLOCK_AFTER   300     // 5 dakika sonra (saniye)
#define NEWS_ALERT_BEFORE  1800    // 30 dakika once bildirim (saniye)

//=================================================================
// KRITIK HABER ANAHTAR KELIMELERI (Multi-Tier)
//=================================================================
class CNewsManager
{
private:
   //--- Haber deposu
   NewsEvent         m_events[];
   int               m_eventCount;

   //--- Durum
   string            m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   string            m_baseCurrency;     // Sembolun baz para birimi
   string            m_quoteCurrency;    // Sembolun karsi para birimi
   bool              m_tradingBlocked;   // Haber nedeniyle islem bloke mu?
   datetime          m_blockUntil;       // Blok bitis zamani
   datetime          m_lastCheck;        // Son kontrol zamani
   datetime          m_lastAlertTime;    // Son bildirim zamani
   NewsEvent         m_activeNews;       // Su an aktif haber

   //--- Keyword arrays (static)
   string            m_criticalKeys[];   // NFP, FOMC, ECB...
   string            m_highKeys[];       // CPI, GDP, Employment...
   string            m_mediumKeys[];     // PMI, Retail, Trade Balance...
   string            m_lowKeys[];        // Minor indicators...

   //--- Kategori bazli para birimi eslestirme
   string            m_affectedCurrencies[];  // Bu sembolü etkileyen para birimleri

   //=================================================================
   // KEYWORD LISTELERINI DOLDUR
   //=================================================================
   void InitKeywords()
   {
      //--- CRITICAL (Piyasayi sidddetli etkiler)
      int cs = 20;
      ArrayResize(m_criticalKeys, cs);
      m_criticalKeys[0]  = "NFP";
      m_criticalKeys[1]  = "Non-Farm";
      m_criticalKeys[2]  = "FOMC";
      m_criticalKeys[3]  = "Fed Rate";
      m_criticalKeys[4]  = "Interest Rate Decision";
      m_criticalKeys[5]  = "ECB Rate";
      m_criticalKeys[6]  = "BOE Rate";
      m_criticalKeys[7]  = "BOJ Rate";
      m_criticalKeys[8]  = "RBA Rate";
      m_criticalKeys[9]  = "SNB Rate";
      m_criticalKeys[10] = "RBNZ Rate";
      m_criticalKeys[11] = "BOC Rate";
      m_criticalKeys[12] = "Central Bank";
      m_criticalKeys[13] = "Monetary Policy";
      m_criticalKeys[14] = "Jackson Hole";
      m_criticalKeys[15] = "Fed Chair";
      m_criticalKeys[16] = "ECB President";
      m_criticalKeys[17] = "Emergency Meeting";
      m_criticalKeys[18] = "Quantitative";
      m_criticalKeys[19] = "Taper";

      //--- HIGH (Piyasayi guclu etkiler)
      int hs = 20;
      ArrayResize(m_highKeys, hs);
      m_highKeys[0]  = "CPI";
      m_highKeys[1]  = "Consumer Price";
      m_highKeys[2]  = "Inflation";
      m_highKeys[3]  = "GDP";
      m_highKeys[4]  = "Gross Domestic";
      m_highKeys[5]  = "Employment";
      m_highKeys[6]  = "Unemployment";
      m_highKeys[7]  = "Jobless Claims";
      m_highKeys[8]  = "Retail Sales";
      m_highKeys[9]  = "ISM Manufacturing";
      m_highKeys[10] = "ISM Services";
      m_highKeys[11] = "Core PCE";
      m_highKeys[12] = "PPI";
      m_highKeys[13] = "Producer Price";
      m_highKeys[14] = "Trade Balance";
      m_highKeys[15] = "Current Account";
      m_highKeys[16] = "Housing Starts";
      m_highKeys[17] = "Durable Goods";
      m_highKeys[18] = "ADP Employment";
      m_highKeys[19] = "Average Earnings";

      //--- MEDIUM (Orta etki)
      int ms = 15;
      ArrayResize(m_mediumKeys, ms);
      m_mediumKeys[0]  = "PMI";
      m_mediumKeys[1]  = "Manufacturing PMI";
      m_mediumKeys[2]  = "Services PMI";
      m_mediumKeys[3]  = "Industrial Production";
      m_mediumKeys[4]  = "Consumer Confidence";
      m_mediumKeys[5]  = "Business Confidence";
      m_mediumKeys[6]  = "ZEW";
      m_mediumKeys[7]  = "IFO";
      m_mediumKeys[8]  = "Building Permits";
      m_mediumKeys[9]  = "Existing Home";
      m_mediumKeys[10] = "New Home";
      m_mediumKeys[11] = "Factory Orders";
      m_mediumKeys[12] = "Capacity Utilization";
      m_mediumKeys[13] = "Pending Home";
      m_mediumKeys[14] = "Philly Fed";

      //--- LOW (Dusuk etki)
      int ls = 10;
      ArrayResize(m_lowKeys, ls);
      m_lowKeys[0]  = "Redbook";
      m_lowKeys[1]  = "Richmond Fed";
      m_lowKeys[2]  = "Chicago Fed";
      m_lowKeys[3]  = "Kansas Fed";
      m_lowKeys[4]  = "Dallas Fed";
      m_lowKeys[5]  = "Leading Index";
      m_lowKeys[6]  = "Wholesale";
      m_lowKeys[7]  = "Import Price";
      m_lowKeys[8]  = "Export Price";
      m_lowKeys[9]  = "Beige Book";
   }

   //=================================================================
   // SEMBOL ICIN ETKILENEN PARA BIRIMLERINI BELIRLE
   //=================================================================
   void DetectAffectedCurrencies()
   {
      string symUpper = m_symbol;
      StringToUpper(symUpper);

      ArrayResize(m_affectedCurrencies, 0);

      //--- Forex pariteler: her iki para birimi
      if(m_category == CAT_FOREX)
      {
         // Genellikle 6-7 karakter: EURUSD, EURUSDm, USDJPY vb.
         string cleanSym = symUpper;
         // "m" suffix'ini temizle (Exness vb.)
         if(StringLen(cleanSym) >= 7 && StringSubstr(cleanSym, 6, 1) == "M")
            cleanSym = StringSubstr(cleanSym, 0, 6);

         if(StringLen(cleanSym) >= 6)
         {
            string base  = StringSubstr(cleanSym, 0, 3);
            string quote = StringSubstr(cleanSym, 3, 3);
            AddCurrency(base);
            AddCurrency(quote);
            m_baseCurrency  = base;
            m_quoteCurrency = quote;
         }
      }
      //--- Metal: USD herzaman + metal para birimi
      else if(m_category == CAT_METAL)
      {
         AddCurrency("USD");
         if(StringFind(symUpper, "XAU") >= 0 || StringFind(symUpper, "GOLD") >= 0)
         {
            AddCurrency("XAU");
            m_baseCurrency = "XAU";
         }
         else if(StringFind(symUpper, "XAG") >= 0 || StringFind(symUpper, "SILVER") >= 0)
         {
            AddCurrency("XAG");
            m_baseCurrency = "XAG";
         }
         else
         {
            m_baseCurrency = "METAL";
         }
         m_quoteCurrency = "USD";
      }
      //--- Crypto: USD herzaman
      else if(m_category == CAT_CRYPTO)
      {
         AddCurrency("USD");
         if(StringFind(symUpper, "BTC") >= 0)
         {
            AddCurrency("BTC");
            m_baseCurrency = "BTC";
         }
         else if(StringFind(symUpper, "ETH") >= 0)
         {
            AddCurrency("ETH");
            m_baseCurrency = "ETH";
         }
         else
         {
            m_baseCurrency = "CRYPTO";
         }
         m_quoteCurrency = "USD";
      }
      //--- Endeksler: ulke para birimi
      else if(m_category == CAT_INDICES)
      {
         if(StringFind(symUpper, "US30") >= 0 || StringFind(symUpper, "NAS") >= 0 ||
            StringFind(symUpper, "SPX") >= 0)
            AddCurrency("USD");
         else if(StringFind(symUpper, "UK100") >= 0)
            AddCurrency("GBP");
         else if(StringFind(symUpper, "DE40") >= 0 || StringFind(symUpper, "DAX") >= 0)
            AddCurrency("EUR");
         else if(StringFind(symUpper, "JP225") >= 0)
            AddCurrency("JPY");
         else
            AddCurrency("USD");

         m_baseCurrency  = "INDEX";
         m_quoteCurrency = "";
      }
      //--- Enerji: USD
      else if(m_category == CAT_ENERGY)
      {
         AddCurrency("USD");
         m_baseCurrency  = "OIL";
         m_quoteCurrency = "USD";
      }
      //--- Default: USD
      else
      {
         AddCurrency("USD");
         m_baseCurrency  = "UNKNOWN";
         m_quoteCurrency = "USD";
      }

      string currencies = "";
      for(int i = 0; i < ArraySize(m_affectedCurrencies); i++)
      {
         if(i > 0) currencies += ",";
         currencies += m_affectedCurrencies[i];
      }
      PrintFormat("[NEWS-%s] Etkilenen para birimleri: %s", m_symbol, currencies);
   }

   void AddCurrency(string curr)
   {
      int size = ArraySize(m_affectedCurrencies);
      // Duplikat kontrol
      for(int i = 0; i < size; i++)
         if(m_affectedCurrencies[i] == curr) return;
      ArrayResize(m_affectedCurrencies, size + 1);
      m_affectedCurrencies[size] = curr;
   }

   //=================================================================
   // HABER ONEM SEVIYESINI BELIRLE (keyword bazli)
   //=================================================================
   ENUM_NEWS_IMPACT ClassifyNewsImpact(string title)
   {
      string titleUpper = title;
      StringToUpper(titleUpper);

      // Oncelik: CRITICAL > HIGH > MEDIUM > LOW
      for(int i = 0; i < ArraySize(m_criticalKeys); i++)
      {
         string keyUpper = m_criticalKeys[i];
         StringToUpper(keyUpper);
         if(StringFind(titleUpper, keyUpper) >= 0) return NEWS_CRITICAL;
      }
      for(int i = 0; i < ArraySize(m_highKeys); i++)
      {
         string keyUpper = m_highKeys[i];
         StringToUpper(keyUpper);
         if(StringFind(titleUpper, keyUpper) >= 0) return NEWS_HIGH;
      }
      for(int i = 0; i < ArraySize(m_mediumKeys); i++)
      {
         string keyUpper = m_mediumKeys[i];
         StringToUpper(keyUpper);
         if(StringFind(titleUpper, keyUpper) >= 0) return NEWS_MEDIUM;
      }
      for(int i = 0; i < ArraySize(m_lowKeys); i++)
      {
         string keyUpper = m_lowKeys[i];
         StringToUpper(keyUpper);
         if(StringFind(titleUpper, keyUpper) >= 0) return NEWS_LOW;
      }

      return NEWS_LOW;  // Tanimlanmamis = LOW
   }

   //=================================================================
   // HABER BU SEMBOLU ETKILIYOR MU?
   //=================================================================
   bool DoesNewsAffectSymbol(string newsCurrency)
   {
      string newsUpper = newsCurrency;
      StringToUpper(newsUpper);

      for(int i = 0; i < ArraySize(m_affectedCurrencies); i++)
      {
         if(m_affectedCurrencies[i] == newsUpper) return true;
      }

      // USD haberleri XAU, XAG, BTC ve tum USD paritelerini etkiler
      if(newsUpper == "USD") return true;

      return false;
   }

   //=================================================================
   // ONEM SEVIYESINE GORE ISLEM ENGELLENMELI MI?
   //=================================================================
   bool ShouldBlockTrading(ENUM_NEWS_IMPACT impact)
   {
      // CRITICAL ve HIGH haberlerde islem engelle
      // MEDIUM: sadece uyari gonder, engelleme
      // LOW: sadece log
      return (impact >= NEWS_HIGH);
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CNewsManager()
   {
      m_eventCount    = 0;
      m_tradingBlocked = false;
      m_blockUntil    = 0;
      m_lastCheck     = 0;
      m_lastAlertTime = 0;
      m_baseCurrency  = "";
      m_quoteCurrency = "";
      ArrayResize(m_events, 0);
   }

   //+------------------------------------------------------------------+
   //| Initialize                                                        |
   //+------------------------------------------------------------------+
   void Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat)
   {
      m_symbol   = symbol;
      m_category = cat;

      InitKeywords();
      DetectAffectedCurrencies();

      //--- MQL5 Ekonomik Takvim'den haberleri yukle
      LoadUpcomingNews();

      PrintFormat("[NEWS-%s] Universal News Intelligence aktif | %d haber yuklendi",
                  m_symbol, m_eventCount);
   }

   //+------------------------------------------------------------------+
   //| LoadUpcomingNews - MQL5 CalendarValueHistory API ile haber yukle  |
   //+------------------------------------------------------------------+
   void LoadUpcomingNews()
   {
      ArrayResize(m_events, 0);
      m_eventCount = 0;

      //--- Simdi + 24 saat ilerisi
      datetime fromTime = TimeGMT();
      datetime toTime   = fromTime + 86400;  // +24 saat

      MqlCalendarValue values[];
      int total = CalendarValueHistory(values, fromTime, toTime);

      if(total <= 0)
      {
         PrintFormat("[NEWS-%s] Yaklasan haber bulunamadi (24 saat icinde)", m_symbol);
         return;
      }

      for(int i = 0; i < total && m_eventCount < MAX_NEWS_EVENTS; i++)
      {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event))
            continue;

         MqlCalendarCountry country;
         if(!CalendarCountryById(event.country_id, country))
            continue;

         string currency = country.currency;

         //--- Bu sembolü etkiliyor mu?
         if(!DoesNewsAffectSymbol(currency))
            continue;

         //--- Haber bilgisi olustur
         NewsEvent ne;
         ne.eventTime      = values[i].time;
         ne.title          = event.name;
         ne.currency       = currency;
         ne.impact         = ClassifyNewsImpact(event.name);
         ne.isActive       = false;
         ne.blockStartTime = ne.eventTime - NEWS_BLOCK_BEFORE;
         ne.blockEndTime   = ne.eventTime + NEWS_BLOCK_AFTER;

         //--- MQL5 Calendar severity'yi de dikkate al
         if(event.importance == CALENDAR_IMPORTANCE_HIGH && ne.impact < NEWS_HIGH)
            ne.impact = NEWS_HIGH;
         if(event.importance == CALENDAR_IMPORTANCE_MODERATE && ne.impact < NEWS_MEDIUM)
            ne.impact = NEWS_MEDIUM;

         //--- Listeye ekle
         int idx = m_eventCount;
         ArrayResize(m_events, idx + 1);
         m_events[idx] = ne;
         m_eventCount++;

         string impactStr = GetImpactStr(ne.impact);
         PrintFormat("[NEWS-%s] %s | %s | %s | %s",
                     m_symbol, TimeToString(ne.eventTime, TIME_DATE|TIME_MINUTES),
                     ne.currency, impactStr, ne.title);
      }
   }

   //+------------------------------------------------------------------+
   //| OnTick - Her tickte cagirilir, haber durumunu kontrol eder       |
   //+------------------------------------------------------------------+
   void OnTick()
   {
      datetime now = TimeGMT();

      //--- Her 60 saniyede bir kontrol
      if(now - m_lastCheck < 60) return;
      m_lastCheck = now;

      //--- Her 6 saatte haberleri yeniden yukle
      static datetime lastReload = 0;
      if(now - lastReload > 21600)  // 6 saat
      {
         LoadUpcomingNews();
         lastReload = now;
      }

      //--- Aktif haber kontrolu
      m_tradingBlocked = false;
      bool foundActiveNews = false;

      for(int i = 0; i < m_eventCount; i++)
      {
         //--- Haber blok zamaninda miyiz?
         if(now >= m_events[i].blockStartTime && now <= m_events[i].blockEndTime)
         {
            if(ShouldBlockTrading(m_events[i].impact))
            {
               m_tradingBlocked = true;
               m_blockUntil     = m_events[i].blockEndTime;
               m_activeNews     = m_events[i];
               m_events[i].isActive = true;
               foundActiveNews = true;
            }
         }
         else
         {
            m_events[i].isActive = false;
         }
      }

      if(!foundActiveNews && m_blockUntil > 0 && now > m_blockUntil)
      {
         m_blockUntil = 0;
         PrintFormat("[NEWS-%s] Haber blok suresi bitti. Islemler serbest.", m_symbol);
      }
   }

   //+------------------------------------------------------------------+
   //| CheckNewsAlert - 30 dakika oncesinden bildirim kontrolu          |
   //| Donduruyor: bildirilecek haber var mi, mesaj string'i            |
   //+------------------------------------------------------------------+
   bool CheckNewsAlert(string &alertMsg)
   {
      datetime now = TimeGMT();
      alertMsg = "";

      for(int i = 0; i < m_eventCount; i++)
      {
         datetime alertTime = m_events[i].eventTime - NEWS_ALERT_BEFORE;

         //--- 30 dakika kala bildirim (sadece HIGH ve CRITICAL icin)
         if(m_events[i].impact >= NEWS_HIGH &&
            now >= alertTime && now < alertTime + 120)  // 2 dakikalik pencere
         {
            if(now - m_lastAlertTime < 300) return false;  // 5dk rate limit

            int minutesLeft = (int)((m_events[i].eventTime - now) / 60);
            string impactStr = GetImpactStr(m_events[i].impact);
            string impactIcon = GetImpactIcon(m_events[i].impact);

            alertMsg = StringFormat(
               "%s HABER UYARISI %s\n"
               "Sembol: %s\n"
               "Haber: %s\n"
               "Para: %s | Onem: %s\n"
               "Saat: %s\n"
               "Kalan: %d dakika\n"
               "Durum: %s\n"
               "Islem: %s",
               impactIcon, impactIcon,
               m_symbol,
               m_events[i].title,
               m_events[i].currency, impactStr,
               TimeToString(m_events[i].eventTime, TIME_MINUTES),
               minutesLeft,
               impactStr,
               (m_events[i].impact >= NEWS_HIGH) ?
                  "20dk once BLOK / 5dk sonra SERBEST" : "Sadece uyari"
            );

            m_lastAlertTime = now;
            return true;
         }
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| GETTERS                                                           |
   //+------------------------------------------------------------------+
   bool IsTradingBlocked() const { return m_tradingBlocked; }
   datetime GetBlockUntil() const { return m_blockUntil; }
   int GetNewsCount() const { return m_eventCount; }

   bool HasActiveNews() const
   {
      for(int i = 0; i < m_eventCount; i++)
         if(m_events[i].isActive) return true;
      return false;
   }

   //--- Aktif haber bilgisi (Dashboard icin)
   bool GetActiveNewsInfo(string &title, string &currency, ENUM_NEWS_IMPACT &impact,
                          datetime &eventTime, int &minutesLeft)
   {
      datetime now = TimeGMT();

      for(int i = 0; i < m_eventCount; i++)
      {
         if(now >= m_events[i].blockStartTime && now <= m_events[i].blockEndTime)
         {
            title       = m_events[i].title;
            currency    = m_events[i].currency;
            impact      = m_events[i].impact;
            eventTime   = m_events[i].eventTime;
            minutesLeft = (int)((m_events[i].eventTime - now) / 60);
            return true;
         }
      }
      return false;
   }

   //--- Sonraki haber bilgisi (Dashboard icin)
   bool GetNextNewsInfo(string &title, string &currency, ENUM_NEWS_IMPACT &impact,
                        datetime &eventTime, int &minutesLeft)
   {
      datetime now = TimeGMT();
      datetime nearest = D'2099.01.01';
      int nearestIdx = -1;

      for(int i = 0; i < m_eventCount; i++)
      {
         if(m_events[i].eventTime > now && m_events[i].eventTime < nearest)
         {
            nearest = m_events[i].eventTime;
            nearestIdx = i;
         }
      }

      if(nearestIdx >= 0)
      {
         title       = m_events[nearestIdx].title;
         currency    = m_events[nearestIdx].currency;
         impact      = m_events[nearestIdx].impact;
         eventTime   = m_events[nearestIdx].eventTime;
         minutesLeft = (int)((eventTime - now) / 60);
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| YARDIMCI FONKSIYONLAR                                             |
   //+------------------------------------------------------------------+
   static string GetImpactStr(ENUM_NEWS_IMPACT impact)
   {
      switch(impact)
      {
         case NEWS_CRITICAL: return "KRITIK";
         case NEWS_HIGH:     return "YUKSEK";
         case NEWS_MEDIUM:   return "ORTA";
         case NEWS_LOW:      return "DUSUK";
      }
      return "BILINMEYEN";
   }

   static string GetImpactIcon(ENUM_NEWS_IMPACT impact)
   {
      switch(impact)
      {
         case NEWS_CRITICAL: return ShortToString(0xD83D) + ShortToString(0xDED1);   // U+1F6D1 stop sign
         case NEWS_HIGH:     return ShortToString(0xD83D) + ShortToString(0xDD34);   // U+1F534 red circle
         case NEWS_MEDIUM:   return ShortToString(0xD83D) + ShortToString(0xDFE0);   // U+1F7E0 orange circle
         case NEWS_LOW:      return ShortToString(0xD83D) + ShortToString(0xDFE2);   // U+1F7E2 green circle
      }
      return ShortToString(0x2753);  // question mark
   }

   //--- Telegram formatli haber bildirimi
   static string FormatTelegramNewsAlert(string symbol, const NewsEvent &ne, double balance, double equity)
   {
      string impactIcon = GetImpactIcon(ne.impact);
      string impactStr  = GetImpactStr(ne.impact);
      int minutesLeft   = (int)((ne.eventTime - TimeGMT()) / 60);

      string bell = ShortToString(0xD83D) + ShortToString(0xDD14);    // U+1F514 bell
      string news = ShortToString(0xD83D) + ShortToString(0xDCF0);    // U+1F4F0 newspaper
      string clock = ShortToString(0xD83D) + ShortToString(0xDD50);   // U+1F550 clock
      string chart = ShortToString(0xD83D) + ShortToString(0xDCCA);   // U+1F4CA chart
      string bag   = ShortToString(0xD83D) + ShortToString(0xDCB0);   // U+1F4B0 moneybag
      string line  = ShortToString(0x2501);
      string warn  = ShortToString(0x26A0);

      string msg = "";
      msg += bell + " <b>HABER UYARISI</b> " + bell + "\n";
      msg += line + line + line + line + line + line + line + line + "\n\n";

      msg += impactIcon + " <b>Onem: " + impactStr + "</b>\n\n";

      msg += news + " <b>Haber:</b> <code>" + ne.title + "</code>\n";
      msg += chart + " <b>Sembol:</b> <code>" + symbol + "</code>\n";
      msg += " <b>Para:</b> <code>" + ne.currency + "</code>\n";
      msg += clock + " <b>Saat:</b> <code>" + TimeToString(ne.eventTime, TIME_MINUTES) + "</code>\n";
      msg += " <b>Kalan:</b> <code>" + IntegerToString(minutesLeft) + " dk</code>\n\n";

      if(ne.impact >= NEWS_HIGH)
      {
         msg += warn + " <b>Islem 20dk once DURDURULACAK</b>\n";
         msg += warn + " <b>5dk sonra SERBEST</b>\n\n";
      }

      msg += bag + " <b>Bakiye:</b> <code>$" + DoubleToString(balance, 2) + "</code>\n";
      msg += bag + " <b>Varlik:</b> <code>$" + DoubleToString(equity, 2) + "</code>\n\n";

      msg += line + line + line + line + line + line + line + line + "\n";
      msg += ShortToString(0xD83D) + ShortToString(0xDC8E) + " <i>@ByT@MER</i> " +
             ShortToString(0xD83D) + ShortToString(0xDC8E);

      return msg;
   }

   //--- Discord formatli haber bildirimi
   static string FormatDiscordNewsAlert(string symbol, const NewsEvent &ne, double balance, double equity)
   {
      string impactStr = GetImpactStr(ne.impact);
      int minutesLeft  = (int)((ne.eventTime - TimeGMT()) / 60);

      string desc = "";
      desc += ":bell: **HABER UYARISI** :bell:\\n\\n";
      desc += ":newspaper: **Haber:** `" + ne.title + "`\\n";
      desc += ":chart_with_upwards_trend: **Sembol:** `" + symbol + "`\\n";
      desc += ":money_with_wings: **Para:** `" + ne.currency + "`\\n";
      desc += ":clock1: **Saat:** `" + TimeToString(ne.eventTime, TIME_MINUTES) + "`\\n";
      desc += ":hourglass: **Kalan:** `" + IntegerToString(minutesLeft) + " dk`\\n\\n";

      if(ne.impact >= NEWS_HIGH)
      {
         desc += ":warning: **Islem 20dk once DURDURULACAK**\\n";
         desc += ":warning: **5dk sonra SERBEST**\\n\\n";
      }

      desc += ":moneybag: **Bakiye:** `$" + DoubleToString(balance, 2) + "`\\n";
      desc += ":moneybag: **Varlik:** `$" + DoubleToString(equity, 2) + "`";

      return desc;
   }

   //--- Discord embed rengi (impact'e gore)
   static int GetDiscordColor(ENUM_NEWS_IMPACT impact)
   {
      switch(impact)
      {
         case NEWS_CRITICAL: return 15158332;  // Kirmizi
         case NEWS_HIGH:     return 15105570;  // Turuncu
         case NEWS_MEDIUM:   return 16776960;  // Sari
         case NEWS_LOW:      return 3066993;   // Yesil
      }
      return 3447003;  // Mavi
   }
};

#endif
