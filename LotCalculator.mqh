//+------------------------------------------------------------------+
//|                                             LotCalculator.mqh    |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX v2.2 - Dinamik Lot Hesaplayici                         |
//| 8 Faktor: Balance + Score + Trend + Category + ATR + Margin      |
//|           + Toplam Acik Lot Dengeleme + Broker Bilgi              |
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
   double               m_contractSize;   // v2.2: Broker'dan alinan kontrat buyuklugu
   double               m_tickValue;      // v2.2: Broker'dan alinan tick degeri

   //--- Sinyal skoru carpani (daha granular)
   double GetScoreMultiplier(int score) const
   {
      if(score >= 85) return 1.5;    // Cok guclu sinyal
      if(score >= 70) return 1.3;
      if(score >= 55) return 1.1;
      if(score >= 45) return 1.0;    // Standart
      if(score >= 38) return 0.8;    // Minimum esik, dikkatli
      return 0.5;                     // Cok zayif, minimum lot
   }

   //--- Trend gucu carpani
   double GetTrendMultiplier(ENUM_TREND_STRENGTH trendStr) const
   {
      switch(trendStr)
      {
         case TREND_STRONG:   return 1.3;
         case TREND_MODERATE: return 1.0;
         case TREND_WEAK:     return 0.7;
      }
      return 1.0;
   }

   //--- Kategori risk carpani (broker bilgisinden dogrulanir)
   double GetCategoryMultiplier() const
   {
      switch(m_category)
      {
         case CAT_FOREX:   return 1.0;
         case CAT_STOCKS:  return 0.9;
         case CAT_INDICES: return 0.8;
         case CAT_METAL:   return 0.7;
         case CAT_ENERGY:  return 0.6;
         case CAT_CRYPTO:  return 0.5;
         default:          return 0.7;
      }
   }

   //--- ATR volatilite carpani (broker tick value ile dogrulanir)
   double GetVolatilityMultiplier(double atr) const
   {
      if(atr <= 0) return 1.0;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(bid <= 0) return 1.0;

      double atrPct = (atr / bid) * 100.0;

      //--- v2.2: Tick value bazli ek kontrol
      //--- 1 pip hareket kac $ etkiliyor?
      if(m_tickValue > 0 && m_minLot > 0)
      {
         double dollarPerPip = m_tickValue * m_minLot;
         double atrPips = atr / SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         double potentialLoss = dollarPerPip * atrPips;

         // ATR hareketi $50'den fazla kayba sebep oluyorsa ekstra temkinli
         if(potentialLoss > 50.0) return 0.3;
         if(potentialLoss > 30.0) return 0.4;
         if(potentialLoss > 15.0) return 0.5;
      }

      if(atrPct > 3.0) return 0.4;   // Extreme volatilite
      if(atrPct > 2.0) return 0.5;
      if(atrPct > 1.5) return 0.6;
      if(atrPct > 1.0) return 0.7;
      if(atrPct > 0.5) return 0.85;
      return 1.0;                      // Normal
   }

   //--- Margin seviye guvenlik carpani
   double GetMarginMultiplier(double marginLevel) const
   {
      if(marginLevel <= 0) return 1.0;  // Margin bilgisi yok veya pozisyon yok

      if(marginLevel < 300)  return 0.5;
      if(marginLevel < 500)  return 0.7;
      if(marginLevel < 1000) return 0.85;
      return 1.0;
   }

   //--- v2.2: Toplam acik lot dengeleme carpani
   //--- Fazla lot aciksa yeni lot azaltilir (riskin yigilmasini onler)
   double GetOpenLotBalancer(double totalOpenLots) const
   {
      if(totalOpenLots <= 0.0) return 1.0;   // Pozisyon yok, serbest

      double maxVol = MaxTotalVolume;
      if(maxVol <= 0) maxVol = 2.0;

      double usageRatio = totalOpenLots / maxVol;

      if(usageRatio >= 0.90) return 0.3;   // %90+ kullanildi, minimal yeni lot
      if(usageRatio >= 0.70) return 0.5;
      if(usageRatio >= 0.50) return 0.7;
      if(usageRatio >= 0.30) return 0.85;
      return 1.0;
   }

   //--- Lot normalize ve clamp
   double NormalizeLot(double lot) const
   {
      lot = MathFloor(lot / m_lotStep) * m_lotStep;
      if(lot < m_minLot) lot = m_minLot;
      if(lot > m_maxLot) lot = m_maxLot;
      return NormalizeDouble(lot, 2);
   }

public:
   CLotCalculator() : m_minLot(0.01), m_maxLot(0.5), m_lotStep(0.01),
                      m_contractSize(0), m_tickValue(0) {}

   void Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat, double profileMinLot = 0.0)
   {
      m_symbol       = symbol;
      m_category     = cat;
      m_minLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_maxLot       = InputMaxLot;
      m_lotStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      m_contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

      if(m_lotStep <= 0) m_lotStep = 0.01;
      if(m_minLot  <= 0) m_minLot  = 0.01;

      //--- v2.2.1: Profil bazli min lot override
      double brokerMin = m_minLot;
      if(profileMinLot > 0.0 && profileMinLot >= brokerMin)
      {
         m_minLot = profileMinLot;
         PrintFormat("[LOT-%s] MinLot profil override: %.2f (broker min: %.2f)",
                     symbol, m_minLot, brokerMin);
      }

      PrintFormat("[LOT-%s] Broker: MinLot=%.2f MaxLot=%.2f Step=%.2f Contract=%.0f TickVal=%.4f",
                  symbol, m_minLot, m_maxLot, m_lotStep, m_contractSize, m_tickValue);
   }

   //--- v2.2: Tam dinamik lot hesaplama (8 faktor)
   double CalculateDynamic(double balance, double atr, int score,
                           ENUM_TREND_STRENGTH trendStr, double marginLevel,
                           double totalOpenLots = 0.0)
   {
      //--- 1. Bakiye bazli temel lot
      double baseLot = (balance / 1000.0) * BaseLotPer1000;

      //--- 2-8. Tum carpanlari uygula
      double scoreMult  = GetScoreMultiplier(score);
      double trendMult  = GetTrendMultiplier(trendStr);
      double catMult    = GetCategoryMultiplier();
      double volMult    = GetVolatilityMultiplier(atr);
      double marginMult = GetMarginMultiplier(marginLevel);
      double lotBalMult = GetOpenLotBalancer(totalOpenLots);

      double lot = baseLot * scoreMult * trendMult * catMult * volMult * marginMult * lotBalMult;

      return NormalizeLot(lot);
   }

   //--- Geriye uyumlu (eski cagrilar icin)
   double CalculateDynamic(double balance, double atr, int score,
                           ENUM_TREND_STRENGTH trendStr, double marginLevel)
   {
      return CalculateDynamic(balance, atr, score, trendStr, marginLevel, 0.0);
   }

   //--- Geriye uyumlu basit hesaplama (trend=MODERATE, margin=0)
   double Calculate(double balance, double atr, int score)
   {
      return CalculateDynamic(balance, atr, score, TREND_MODERATE, 0, 0.0);
   }

   //--- Getter'lar
   double GetMinLot()       const { return m_minLot;       }
   double GetMaxLot()       const { return m_maxLot;       }
   double GetContractSize() const { return m_contractSize; }
   double GetTickValue()    const { return m_tickValue;    }
};

#endif
