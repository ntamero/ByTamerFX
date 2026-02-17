//+------------------------------------------------------------------+
//|                                             SymbolManager.mqh    |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef SYMBOL_MANAGER_MQH
#define SYMBOL_MANAGER_MQH

#include "Config.mqh"

class CSymbolManager
{
private:
   string               m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   double               m_point;
   int                  m_digits;
   double               m_lotMin;
   double               m_lotMax;
   double               m_lotStep;
   double               m_tickValue;
   double               m_contractSize;
   double               m_defaultSpread;
   string               m_path;
   string               m_description;

public:
   CSymbolManager() : m_category(CAT_UNKNOWN), m_point(0), m_digits(0) {}

   bool Initialize(string symbol)
   {
      m_symbol       = symbol;
      m_point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
      m_digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_lotMin       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_lotMax       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_lotStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      m_tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_path         = SymbolInfoString(symbol, SYMBOL_PATH);
      m_description  = SymbolInfoString(symbol, SYMBOL_DESCRIPTION);

      if(m_lotStep <= 0) m_lotStep = 0.01;

      // Varsayilan spread hesapla (son 100 tick ortalamasi yerine anlik)
      int spreadPts = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      m_defaultSpread = spreadPts * m_point;

      DetectCategory();

      Print(StringFormat("Sembol: %s | Kategori: %s | Digits: %d | Spread: %.1f puan",
            m_symbol, GetCategoryName(), m_digits, (double)spreadPts));
      Print(StringFormat("  Path: %s | Lot: %.2f-%.2f step=%.2f",
            m_path, m_lotMin, m_lotMax, m_lotStep));

      return true;
   }

   //--- Kategori tespiti (broker path + isim analizi)
   void DetectCategory()
   {
      string pathLower = m_path;
      string symLower  = m_symbol;
      string descLower = m_description;
      StringToLower(pathLower);
      StringToLower(symLower);
      StringToLower(descLower);

      // CRYPTO: BTC, ETH, LTC, XRP, DOGE, SOL, ADA, DOT, BNB...
      if(StringFind(pathLower, "crypto") >= 0 || StringFind(pathLower, "coin") >= 0)
      { m_category = CAT_CRYPTO; return; }
      if(StringFind(symLower, "btc") >= 0 || StringFind(symLower, "eth") >= 0 ||
         StringFind(symLower, "ltc") >= 0 || StringFind(symLower, "xrp") >= 0 ||
         StringFind(symLower, "doge") >= 0 || StringFind(symLower, "sol") >= 0 ||
         StringFind(symLower, "ada") >= 0 || StringFind(symLower, "bnb") >= 0 ||
         StringFind(symLower, "dot") >= 0)
      { m_category = CAT_CRYPTO; return; }

      // METAL: XAU, XAG, XPT, XPD, Gold, Silver
      if(StringFind(pathLower, "metal") >= 0 || StringFind(pathLower, "precious") >= 0)
      { m_category = CAT_METAL; return; }
      if(StringFind(symLower, "xau") >= 0 || StringFind(symLower, "xag") >= 0 ||
         StringFind(symLower, "xpt") >= 0 || StringFind(symLower, "xpd") >= 0 ||
         StringFind(symLower, "gold") >= 0 || StringFind(symLower, "silver") >= 0)
      { m_category = CAT_METAL; return; }

      // INDICES: US30, NAS100, SPX500, UK100, DE40, JP225...
      if(StringFind(pathLower, "indic") >= 0 || StringFind(pathLower, "index") >= 0)
      { m_category = CAT_INDICES; return; }
      if(StringFind(symLower, "us30") >= 0 || StringFind(symLower, "nas") >= 0 ||
         StringFind(symLower, "spx") >= 0 || StringFind(symLower, "uk100") >= 0 ||
         StringFind(symLower, "de40") >= 0 || StringFind(symLower, "jp225") >= 0 ||
         StringFind(symLower, "dax") >= 0 || StringFind(symLower, "dow") >= 0)
      { m_category = CAT_INDICES; return; }

      // ENERGY: USOIL, UKOIL, NGAS, WTI, Brent
      if(StringFind(pathLower, "energy") >= 0 || StringFind(pathLower, "oil") >= 0)
      { m_category = CAT_ENERGY; return; }
      if(StringFind(symLower, "oil") >= 0 || StringFind(symLower, "ngas") >= 0 ||
         StringFind(symLower, "wti") >= 0 || StringFind(symLower, "brent") >= 0)
      { m_category = CAT_ENERGY; return; }

      // STOCKS: genellikle description'da "share" veya "stock"
      if(StringFind(pathLower, "stock") >= 0 || StringFind(pathLower, "share") >= 0 ||
         StringFind(descLower, "stock") >= 0 || StringFind(descLower, "share") >= 0)
      { m_category = CAT_STOCKS; return; }

      // FOREX: kalan her sey (6 harf ciftler genellikle)
      if(StringLen(m_symbol) == 6 || StringLen(m_symbol) == 7)
      {
         string base = StringSubstr(symLower, 0, 3);
         if(base == "eur" || base == "usd" || base == "gbp" ||
            base == "jpy" || base == "aud" || base == "nzd" ||
            base == "cad" || base == "chf")
         { m_category = CAT_FOREX; return; }
      }

      m_category = CAT_UNKNOWN;
   }

   string GetCategoryName() const
   {
      switch(m_category)
      {
         case CAT_FOREX:   return "Forex";
         case CAT_METAL:   return "Metal";
         case CAT_CRYPTO:  return "Crypto";
         case CAT_INDICES: return "Indices";
         case CAT_STOCKS:  return "Stocks";
         case CAT_ENERGY:  return "Energy";
         default:          return "Unknown";
      }
   }

   // Getters
   ENUM_SYMBOL_CATEGORY GetCategory()      const { return m_category; }
   double               GetPoint()         const { return m_point; }
   int                  GetDigits()        const { return m_digits; }
   double               GetLotMin()        const { return m_lotMin; }
   double               GetLotMax()        const { return m_lotMax; }
   double               GetLotStep()       const { return m_lotStep; }
   double               GetTickValue()     const { return m_tickValue; }
   double               GetContractSize()  const { return m_contractSize; }
   double               GetDefaultSpread() const { return m_defaultSpread; }
   string               GetPath()          const { return m_path; }
};

#endif
