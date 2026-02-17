//+------------------------------------------------------------------+
//|                                             LotCalculator.mqh    |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef LOT_CALCULATOR_MQH
#define LOT_CALCULATOR_MQH

#include "Config.mqh"

class CLotCalculator
{
private:
   string               m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   double               m_minLot;
   double               m_maxLot;
   double               m_lotStep;

public:
   CLotCalculator() : m_minLot(0.01), m_maxLot(0.5), m_lotStep(0.01) {}

   void Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat)
   {
      m_symbol   = symbol;
      m_category = cat;
      m_minLot   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_maxLot   = InputMaxLot;
      m_lotStep  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(m_lotStep <= 0) m_lotStep = 0.01;
      if(m_minLot <= 0)  m_minLot = 0.01;
   }

   double Calculate(double balance, double atr, int score)
   {
      //--- 1. Bakiye bazli temel lot
      double baseLot = (balance / 1000.0) * BaseLotPer1000;

      //--- 2. Sinyal gucu carpani
      double signalMult = 1.0;
      if(score >= 80)      signalMult = 1.3;
      else if(score >= 65) signalMult = 1.0;
      else if(score >= 50) signalMult = 0.8;
      else                 signalMult = 0.6;

      //--- 3. Kategori risk carpani
      double catMult = 1.0;
      switch(m_category)
      {
         case CAT_CRYPTO:  catMult = 0.5; break;   // Crypto cok volatil
         case CAT_METAL:   catMult = 0.7; break;    // Metal orta-yuksek
         case CAT_INDICES: catMult = 0.8; break;    // Indeks orta
         case CAT_ENERGY:  catMult = 0.6; break;    // Enerji yuksek volatilite
         case CAT_STOCKS:  catMult = 0.9; break;    // Hisse orta-dusuk
         case CAT_FOREX:   catMult = 1.0; break;    // Forex standart
         default:          catMult = 0.7; break;
      }

      //--- 4. Volatilite duzeltmesi (ATR bazli)
      double volMult = 1.0;
      if(atr > 0)
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         if(bid > 0)
         {
            double atrPct = (atr / bid) * 100.0;
            if(atrPct > 2.0)      volMult = 0.5;   // Cok volatil
            else if(atrPct > 1.0) volMult = 0.7;
            else if(atrPct > 0.5) volMult = 0.85;
            else                  volMult = 1.0;
         }
      }

      //--- Final lot hesaplama
      double lot = baseLot * signalMult * catMult * volMult;

      //--- Normalize et
      lot = MathFloor(lot / m_lotStep) * m_lotStep;
      if(lot < m_minLot) lot = m_minLot;
      if(lot > m_maxLot) lot = m_maxLot;

      return NormalizeDouble(lot, 2);
   }
};

#endif
