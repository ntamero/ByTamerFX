//+------------------------------------------------------------------+
//|                                              SpreadFilter.mqh    |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef SPREAD_FILTER_MQH
#define SPREAD_FILTER_MQH

#include "Config.mqh"

class CSpreadFilter
{
private:
   string   m_symbol;
   double   m_defaultSpread;    // Puan cinsinden
   double   m_maxSpreadPct;     // Yuzde tolerans
   double   m_maxAllowed;       // Hesaplanan max spread (puan)
   datetime m_lastLogTime;

public:
   CSpreadFilter() : m_defaultSpread(0), m_maxSpreadPct(15.0), m_lastLogTime(0) {}

   void Initialize(string symbol, double defaultSpreadPoints, double maxSpreadPct)
   {
      m_symbol        = symbol;
      m_defaultSpread = defaultSpreadPoints;
      m_maxSpreadPct  = maxSpreadPct;
      m_maxAllowed    = m_defaultSpread * (1.0 + m_maxSpreadPct / 100.0);

      Print(StringFormat("Spread Filtresi: %s | Default=%.1f | Max=%.1f (+%%%.0f) | MUTLAK KURAL",
            symbol, m_defaultSpread, m_maxAllowed, m_maxSpreadPct));
   }

   bool IsSpreadOK()
   {
      double currentSpread = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);

      if(currentSpread > m_maxAllowed)
      {
         // 60 saniyede bir logla (spam onle)
         if(TimeCurrent() - m_lastLogTime >= 60)
         {
            Print(StringFormat("SPREAD ENGEL: %s | Mevcut=%.1f > Max=%.1f (Default=%.1f +%%%.0f) | ISLEM YAPILMAYACAK",
                  m_symbol, currentSpread, m_maxAllowed, m_defaultSpread, m_maxSpreadPct));
            m_lastLogTime = TimeCurrent();
         }
         return false;
      }
      return true;
   }

   double GetCurrentSpread() const { return (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD); }
   double GetMaxAllowed()    const { return m_maxAllowed; }
   double GetDefaultSpread() const { return m_defaultSpread; }
};

#endif
