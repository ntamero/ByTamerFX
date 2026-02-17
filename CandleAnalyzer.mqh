//+------------------------------------------------------------------+
//|                                            CandleAnalyzer.mqh    |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef CANDLE_ANALYZER_MQH
#define CANDLE_ANALYZER_MQH

#include "Config.mqh"

class CCandleAnalyzer
{
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf;
   datetime         m_lastBarTime;

public:
   CCandleAnalyzer() : m_lastBarTime(0) {}

   void Initialize(string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol     = symbol;
      m_tf         = tf;
      m_lastBarTime = iTime(m_symbol, m_tf, 0);
   }

   //--- Yeni bar kontrolu
   bool CheckNewBar()
   {
      datetime currentBar = iTime(m_symbol, m_tf, 0);
      if(currentBar != m_lastBarTime)
      {
         m_lastBarTime = currentBar;
         return true;
      }
      return false;
   }

   //--- Son kapanan mumun yonu: +1=yukari, -1=asagi, 0=doji
   int GetLastCandleDirection()
   {
      double open  = iOpen(m_symbol, m_tf, 1);
      double close = iClose(m_symbol, m_tf, 1);
      double body  = MathAbs(close - open);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      // Doji: govde cok kucuk
      if(body < point * 3) return 0;

      if(close > open) return +1;
      if(close < open) return -1;
      return 0;
   }

   //--- Canli mumun yonu
   int GetCurrentCandleDirection()
   {
      double open  = iOpen(m_symbol, m_tf, 0);
      double close = iClose(m_symbol, m_tf, 0);

      if(close > open) return +1;
      if(close < open) return -1;
      return 0;
   }

   //--- Donus formasyonu (Hammer, Shooting Star, Pin Bar)
   // +1 = yukari donus, -1 = asagi donus, 0 = yok
   int DetectReversal()
   {
      double open1  = iOpen(m_symbol, m_tf, 1);
      double close1 = iClose(m_symbol, m_tf, 1);
      double high1  = iHigh(m_symbol, m_tf, 1);
      double low1   = iLow(m_symbol, m_tf, 1);

      double body    = MathAbs(close1 - open1);
      double range   = high1 - low1;
      if(range <= 0) return 0;

      double upperWick = high1 - MathMax(open1, close1);
      double lowerWick = MathMin(open1, close1) - low1;

      // Hammer: kucuk govde, uzun alt fitil → yukari donus
      if(lowerWick > body * 2.0 && upperWick < body * 0.5 && body > 0)
         return +1;

      // Shooting Star: kucuk govde, uzun ust fitil → asagi donus
      if(upperWick > body * 2.0 && lowerWick < body * 0.5 && body > 0)
         return -1;

      return 0;
   }

   //--- Engulfing formasyonu
   // +1 = bullish engulfing, -1 = bearish engulfing, 0 = yok
   int DetectEngulfing()
   {
      double open1  = iOpen(m_symbol, m_tf, 1);
      double close1 = iClose(m_symbol, m_tf, 1);
      double open2  = iOpen(m_symbol, m_tf, 2);
      double close2 = iClose(m_symbol, m_tf, 2);

      double body1  = MathAbs(close1 - open1);
      double body2  = MathAbs(close2 - open2);

      if(body1 <= 0 || body2 <= 0) return 0;

      // Bullish Engulfing: onceki bearish, sonraki bullish ve tamamen kapliyor
      if(close2 < open2 && close1 > open1)
      {
         if(close1 > open2 && open1 < close2)
            return +1;
      }

      // Bearish Engulfing: onceki bullish, sonraki bearish ve tamamen kapliyor
      if(close2 > open2 && close1 < open1)
      {
         if(close1 < open2 && open1 > close2)
            return -1;
      }

      return 0;
   }
};

#endif
