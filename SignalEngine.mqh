//+------------------------------------------------------------------+
//|                                             SignalEngine.mqh     |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| ByTamer Hybrid Signal System (BHSS)                              |
//| Advanced 7-Layer Scoring Engine with:                            |
//|   - Multi-Timeframe Confirmation (M15 + H1 + H4)                |
//|   - Divergence Detection (Regular + Hidden)                      |
//|   - Market Structure Analysis (HH/HL/LH/LL)                     |
//|   - Candle Pattern Recognition                                   |
//|   - Bollinger Squeeze Detection                                  |
//|   - Momentum Shift Detection                                     |
//|   - ATR Percentile Volatility Regime                             |
//|   - EMA Ribbon Expansion/Contraction                             |
//| Entry: M15 | Trend Filter: H1 + H4                              |
//| Score Range: 0-100 (7 weighted layers)                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef SIGNAL_ENGINE_MQH
#define SIGNAL_ENGINE_MQH

#include "Config.mqh"

//+------------------------------------------------------------------+
//| CSignalEngine - ByTamer Hybrid Signal System                     |
//+------------------------------------------------------------------+
class CSignalEngine
{
private:
   //--- Symbol & category
   string               m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   ENUM_TIMEFRAMES      m_tfEntry;     // M15 - primary entry
   ENUM_TIMEFRAMES      m_tfTrend;     // H1  - trend filter
   ENUM_TIMEFRAMES      m_tfHigher;    // H4  - higher TF filter

   //=== INDICATOR HANDLES ===

   //--- M15 handles (9 handles)
   int m_hEmaFast;       // EMA(8)  on M15
   int m_hEmaMid;        // EMA(21) on M15
   int m_hEmaSlow;       // EMA(50) on M15
   int m_hMacd;          // MACD(12,26,9) on M15
   int m_hAdx;           // ADX(14) on M15
   int m_hRsi;           // RSI(14) on M15
   int m_hBB;            // BB(20,2) on M15
   int m_hStoch;         // Stoch(14,3,3) on M15
   int m_hAtr;           // ATR(14) on M15

   //--- H1 handles (2 handles)
   int m_hEmaH1;         // EMA(50) on H1
   int m_hRsiH1;         // RSI(14) on H1

   //--- H4 handle (1 handle)
   int m_hEmaH4;         // EMA(50) on H4

   //=== SINGLE-BAR DATA CACHE ===
   double m_emaFast, m_emaMid, m_emaSlow;
   double m_macdMain, m_macdSignal, m_macdHist;
   double m_adx, m_plusDI, m_minusDI;
   double m_rsi;
   double m_bbUpper, m_bbLower, m_bbMiddle;
   double m_stochK, m_stochD;
   double m_atr;
   double m_emaH1;
   double m_rsiH1;
   double m_emaH4;

   //=== MULTI-BAR BUFFERS (for divergence, structure, history) ===
   double m_emaFastBuf[10];
   double m_emaMidBuf[10];
   double m_emaSlowBuf[10];
   double m_macdMainBuf[10];
   double m_macdSignalBuf[10];
   double m_rsiBuf[10];
   double m_rsiH1Buf[5];
   double m_stochKBuf[5];
   double m_stochDBuf[5];
   double m_adxBuf[5];
   double m_plusDIBuf[5];
   double m_minusDIBuf[5];
   double m_atrBuf[50];
   double m_bbUpperBuf[10];
   double m_bbLowerBuf[10];
   double m_bbMiddleBuf[10];

   //--- Price history for divergence & structure
   double m_highBuf[10];
   double m_lowBuf[10];
   double m_closeBuf[10];
   double m_openBuf[10];

   //=== SCORE BREAKDOWNS ===
   ScoreBreakdown m_buyBreakdown;
   ScoreBreakdown m_sellBreakdown;
   ScoreBreakdown m_lastBreakdown;

   //=== TIMING ===
   datetime m_lastSignalTime;
   int      m_cooldownSec;

   //=== DATA VALIDITY FLAGS ===
   bool m_dataReady;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSignalEngine() :
      m_lastSignalTime(0),
      m_cooldownSec(120),
      m_dataReady(false),
      m_hEmaFast(INVALID_HANDLE),
      m_hEmaMid(INVALID_HANDLE),
      m_hEmaSlow(INVALID_HANDLE),
      m_hMacd(INVALID_HANDLE),
      m_hAdx(INVALID_HANDLE),
      m_hRsi(INVALID_HANDLE),
      m_hBB(INVALID_HANDLE),
      m_hStoch(INVALID_HANDLE),
      m_hAtr(INVALID_HANDLE),
      m_hEmaH1(INVALID_HANDLE),
      m_hRsiH1(INVALID_HANDLE),
      m_hEmaH4(INVALID_HANDLE)
   {
      ArrayInitialize(m_emaFastBuf, 0);
      ArrayInitialize(m_emaMidBuf, 0);
      ArrayInitialize(m_emaSlowBuf, 0);
      ArrayInitialize(m_macdMainBuf, 0);
      ArrayInitialize(m_macdSignalBuf, 0);
      ArrayInitialize(m_rsiBuf, 0);
      ArrayInitialize(m_rsiH1Buf, 0);
      ArrayInitialize(m_stochKBuf, 0);
      ArrayInitialize(m_stochDBuf, 0);
      ArrayInitialize(m_adxBuf, 0);
      ArrayInitialize(m_plusDIBuf, 0);
      ArrayInitialize(m_minusDIBuf, 0);
      ArrayInitialize(m_atrBuf, 0);
      ArrayInitialize(m_bbUpperBuf, 0);
      ArrayInitialize(m_bbLowerBuf, 0);
      ArrayInitialize(m_bbMiddleBuf, 0);
      ArrayInitialize(m_highBuf, 0);
      ArrayInitialize(m_lowBuf, 0);
      ArrayInitialize(m_closeBuf, 0);
      ArrayInitialize(m_openBuf, 0);
   }

   //+------------------------------------------------------------------+
   //| Initialize - create all indicator handles                         |
   //+------------------------------------------------------------------+
   bool Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat)
   {
      m_symbol    = symbol;
      m_category  = cat;
      m_tfEntry   = PERIOD_M15;
      m_tfTrend   = PERIOD_H1;
      m_tfHigher  = PERIOD_H4;
      m_cooldownSec = SignalCooldownSec;

      //--- M15 indicators (9 handles)
      m_hEmaFast = iMA(symbol, m_tfEntry, 8, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaMid  = iMA(symbol, m_tfEntry, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(symbol, m_tfEntry, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_hMacd    = iMACD(symbol, m_tfEntry, 12, 26, 9, PRICE_CLOSE);
      m_hAdx     = iADX(symbol, m_tfEntry, 14);
      m_hRsi     = iRSI(symbol, m_tfEntry, 14, PRICE_CLOSE);
      m_hBB      = iBands(symbol, m_tfEntry, 20, 0, 2.0, PRICE_CLOSE);
      m_hStoch   = iStochastic(symbol, m_tfEntry, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
      m_hAtr     = iATR(symbol, m_tfEntry, 14);

      //--- H1 indicators (2 handles)
      m_hEmaH1   = iMA(symbol, m_tfTrend, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_hRsiH1   = iRSI(symbol, m_tfTrend, 14, PRICE_CLOSE);

      //--- H4 indicator (1 handle)
      m_hEmaH4   = iMA(symbol, m_tfHigher, 50, 0, MODE_EMA, PRICE_CLOSE);

      //--- Validate all 12 handles
      if(m_hEmaFast == INVALID_HANDLE || m_hEmaMid == INVALID_HANDLE ||
         m_hEmaSlow == INVALID_HANDLE || m_hMacd == INVALID_HANDLE   ||
         m_hAdx == INVALID_HANDLE     || m_hRsi == INVALID_HANDLE    ||
         m_hBB == INVALID_HANDLE      || m_hStoch == INVALID_HANDLE  ||
         m_hAtr == INVALID_HANDLE     || m_hEmaH1 == INVALID_HANDLE  ||
         m_hRsiH1 == INVALID_HANDLE   || m_hEmaH4 == INVALID_HANDLE)
      {
         Print("!!! BHSS ERROR: Failed to create indicator handles for ", symbol);
         return false;
      }

      Print(StringFormat("BHSS Initialized: %s | Cat=%s | Entry=%s | Trend=%s | Higher=%s | MinScore=%d | Cooldown=%ds",
            symbol, EnumToString(cat),
            EnumToString(m_tfEntry), EnumToString(m_tfTrend), EnumToString(m_tfHigher),
            SignalMinScore, m_cooldownSec));
      return true;
   }

   //+------------------------------------------------------------------+
   //| Evaluate - main signal generation with full hybrid analysis       |
   //+------------------------------------------------------------------+
   SignalData Evaluate()
   {
      SignalData sig;
      sig.Clear();

      //--- Update all breakdowns
      UpdateBreakdown();

      //--- Populate indicator data into signal
      sig.atr         = m_atr;
      sig.rsi         = m_rsi;
      sig.adx         = m_adx;
      sig.plusDI       = m_plusDI;
      sig.minusDI     = m_minusDI;
      sig.macd_main   = m_macdMain;
      sig.macd_signal = m_macdSignal;
      sig.macd_hist   = m_macdHist;
      sig.bb_upper    = m_bbUpper;
      sig.bb_lower    = m_bbLower;
      sig.bb_middle   = m_bbMiddle;
      sig.ema_fast    = m_emaFast;
      sig.ema_mid     = m_emaMid;
      sig.ema_slow    = m_emaSlow;
      sig.stoch_k     = m_stochK;
      sig.stoch_d     = m_stochD;
      sig.time        = TimeCurrent();

      if(!m_dataReady)
         return sig;

      //--- Cooldown enforcement
      if(TimeCurrent() - m_lastSignalTime < m_cooldownSec)
         return sig;

      //--- Count active layers for each direction
      int buyLayers  = CountActiveLayers(m_buyBreakdown);
      int sellLayers = CountActiveLayers(m_sellBreakdown);

      int totalBuy  = m_buyBreakdown.totalScore;
      int totalSell = m_sellBreakdown.totalScore;

      //--- Bollinger squeeze check: if squeezing, require breakout confirmation
      bool squeezing = IsSqueezing();

      //--- Signal decision: BUY
      if(totalBuy >= SignalMinScore && buyLayers >= 4 && totalBuy > totalSell + 10)
      {
         //--- Squeeze filter: in squeeze, need strong momentum confirmation
         if(squeezing && m_buyBreakdown.macdMomentum < 10)
         {
            // Squeeze without breakout confirmation - skip
         }
         else
         {
            sig.direction = SIGNAL_BUY;
            sig.score = totalBuy;
            sig.reason = StringFormat("BUY[%d] L=%d EMA=%d MACD=%d ADX=%d RSI=%d BB=%d ST=%d ATR=%d",
                  totalBuy, buyLayers,
                  m_buyBreakdown.emaTrend, m_buyBreakdown.macdMomentum,
                  m_buyBreakdown.adxStrength, m_buyBreakdown.rsiLevel,
                  m_buyBreakdown.bbPosition, m_buyBreakdown.stochSignal,
                  m_buyBreakdown.atrVolatility);
         }
      }
      //--- Signal decision: SELL
      else if(totalSell >= SignalMinScore && sellLayers >= 4 && totalSell > totalBuy + 10)
      {
         if(squeezing && m_sellBreakdown.macdMomentum < 10)
         {
            // Squeeze without breakout confirmation - skip
         }
         else
         {
            sig.direction = SIGNAL_SELL;
            sig.score = totalSell;
            sig.reason = StringFormat("SELL[%d] L=%d EMA=%d MACD=%d ADX=%d RSI=%d BB=%d ST=%d ATR=%d",
                  totalSell, sellLayers,
                  m_sellBreakdown.emaTrend, m_sellBreakdown.macdMomentum,
                  m_sellBreakdown.adxStrength, m_sellBreakdown.rsiLevel,
                  m_sellBreakdown.bbPosition, m_sellBreakdown.stochSignal,
                  m_sellBreakdown.atrVolatility);
         }
      }

      //--- If signal found, calculate TPs and stamp
      if(sig.direction != SIGNAL_NONE)
      {
         m_lastSignalTime = TimeCurrent();
         CalculateTPLevels(sig);

         Print(StringFormat("BHSS SIGNAL: %s | Score: %d/100 | Layers: %d | %s",
               (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL",
               sig.score,
               (sig.direction == SIGNAL_BUY) ? buyLayers : sellLayers,
               sig.reason));
      }

      return sig;
   }

   //+------------------------------------------------------------------+
   //| UpdateBreakdown - recalculate all 7 layers for dashboard          |
   //+------------------------------------------------------------------+
   void UpdateBreakdown()
   {
      RefreshData();

      if(!m_dataReady)
         return;

      m_buyBreakdown.Clear();
      m_sellBreakdown.Clear();

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(price <= 0) return;

      //--- LAYER 1: EMA Trend (0-20)
      CalcEMATrend(price);

      //--- LAYER 2: MACD Momentum (0-20)
      CalcMACDMomentum();

      //--- LAYER 3: ADX Strength (0-15)
      CalcADXStrength();

      //--- LAYER 4: RSI Level (0-15)
      CalcRSILevel();

      //--- LAYER 5: Bollinger Bands (0-15)
      CalcBBPosition(price);

      //--- LAYER 6: Stochastic (0-10)
      CalcStochSignal();

      //--- LAYER 7: ATR Volatility (0-5)
      CalcATRVolatility();

      //--- Market structure bonus/penalty (modifies EMA layer)
      int structure = DetectMarketStructure();
      if(structure > 0)
      {
         m_buyBreakdown.emaTrend = MathMin(20, m_buyBreakdown.emaTrend + 2);
      }
      else if(structure < 0)
      {
         m_sellBreakdown.emaTrend = MathMin(20, m_sellBreakdown.emaTrend + 2);
      }

      //--- Candle pattern bonus/penalty
      int candleScore = DetectCandlePattern();
      ApplyCandleBonus(candleScore);

      //--- Momentum shift bonus (feeds into MACD layer)
      DetectMomentumShift(price);

      //--- Multi-TF filter (H1/H4 bonuses/penalties applied last)
      ApplyMultiTFFilter();

      //--- Clamp all fields to their maximums
      ClampBreakdown(m_buyBreakdown);
      ClampBreakdown(m_sellBreakdown);

      //--- Calculate totals
      m_buyBreakdown.totalScore = m_buyBreakdown.emaTrend + m_buyBreakdown.macdMomentum +
            m_buyBreakdown.adxStrength + m_buyBreakdown.rsiLevel + m_buyBreakdown.bbPosition +
            m_buyBreakdown.stochSignal + m_buyBreakdown.atrVolatility;

      m_sellBreakdown.totalScore = m_sellBreakdown.emaTrend + m_sellBreakdown.macdMomentum +
            m_sellBreakdown.adxStrength + m_sellBreakdown.rsiLevel + m_sellBreakdown.bbPosition +
            m_sellBreakdown.stochSignal + m_sellBreakdown.atrVolatility;

      //--- Store dominant breakdown
      if(m_buyBreakdown.totalScore >= m_sellBreakdown.totalScore)
         m_lastBreakdown = m_buyBreakdown;
      else
         m_lastBreakdown = m_sellBreakdown;
   }

   //+------------------------------------------------------------------+
   //| GetCurrentTrend - H1 trend direction                              |
   //+------------------------------------------------------------------+
   ENUM_SIGNAL_DIR GetCurrentTrend()
   {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(price > m_emaH1 && m_emaFast > m_emaSlow)
         return SIGNAL_BUY;
      if(price < m_emaH1 && m_emaFast < m_emaSlow)
         return SIGNAL_SELL;
      return SIGNAL_NONE;
   }

   //+------------------------------------------------------------------+
   //| GetTrendStrength - ADX-based strength classification              |
   //+------------------------------------------------------------------+
   ENUM_TREND_STRENGTH GetTrendStrength()
   {
      if(m_adx >= 35) return TREND_STRONG;
      if(m_adx >= 25) return TREND_MODERATE;
      return TREND_WEAK;
   }

   //--- Public getters
   double         GetATR()             const { return m_atr; }
   double         GetRSI()             const { return m_rsi; }
   double         GetADX()             const { return m_adx; }
   double         GetPlusDI()          const { return m_plusDI; }
   double         GetMinusDI()         const { return m_minusDI; }
   double         GetMACDHist()        const { return m_macdHist; }
   ScoreBreakdown GetBreakdown()       const { return m_lastBreakdown; }
   ScoreBreakdown GetBuyBreakdown()    const { return m_buyBreakdown; }
   ScoreBreakdown GetSellBreakdown()   const { return m_sellBreakdown; }

private:
   //+------------------------------------------------------------------+
   //| RefreshData - copy all indicator buffers from handles             |
   //+------------------------------------------------------------------+
   void RefreshData()
   {
      m_dataReady = true;

      //--- M15 EMA buffers (10 bars for ribbon analysis)
      if(CopyBuffer(m_hEmaFast, 0, 0, 10, m_emaFastBuf) < 10) m_dataReady = false;
      if(CopyBuffer(m_hEmaMid,  0, 0, 10, m_emaMidBuf)  < 10) m_dataReady = false;
      if(CopyBuffer(m_hEmaSlow, 0, 0, 10, m_emaSlowBuf) < 10) m_dataReady = false;

      //--- M15 MACD (10 bars for divergence)
      if(CopyBuffer(m_hMacd, 0, 0, 10, m_macdMainBuf)   < 10) m_dataReady = false;
      if(CopyBuffer(m_hMacd, 1, 0, 10, m_macdSignalBuf) < 10) m_dataReady = false;

      //--- M15 ADX (5 bars for slope)
      if(CopyBuffer(m_hAdx, 0, 0, 5, m_adxBuf)    < 5) m_dataReady = false;
      if(CopyBuffer(m_hAdx, 1, 0, 5, m_plusDIBuf)  < 5) m_dataReady = false;
      if(CopyBuffer(m_hAdx, 2, 0, 5, m_minusDIBuf) < 5) m_dataReady = false;

      //--- M15 RSI (10 bars for divergence)
      if(CopyBuffer(m_hRsi, 0, 0, 10, m_rsiBuf) < 10) m_dataReady = false;

      //--- M15 Bollinger (10 bars for squeeze)
      if(CopyBuffer(m_hBB, 0, 0, 10, m_bbMiddleBuf) < 10) m_dataReady = false;
      if(CopyBuffer(m_hBB, 1, 0, 10, m_bbUpperBuf)  < 10) m_dataReady = false;
      if(CopyBuffer(m_hBB, 2, 0, 10, m_bbLowerBuf)  < 10) m_dataReady = false;

      //--- M15 Stochastic (5 bars)
      if(CopyBuffer(m_hStoch, 0, 0, 5, m_stochKBuf) < 5) m_dataReady = false;
      if(CopyBuffer(m_hStoch, 1, 0, 5, m_stochDBuf) < 5) m_dataReady = false;

      //--- M15 ATR (50 bars for percentile)
      if(CopyBuffer(m_hAtr, 0, 0, 50, m_atrBuf) < 50) m_dataReady = false;

      //--- H1 EMA
      double tmpBuf[1];
      if(CopyBuffer(m_hEmaH1, 0, 0, 1, tmpBuf) > 0)
         m_emaH1 = tmpBuf[0];
      else
         m_dataReady = false;

      //--- H1 RSI (5 bars for MTF)
      if(CopyBuffer(m_hRsiH1, 0, 0, 5, m_rsiH1Buf) < 5) m_dataReady = false;

      //--- H4 EMA
      if(CopyBuffer(m_hEmaH4, 0, 0, 1, tmpBuf) > 0)
         m_emaH4 = tmpBuf[0];
      else
         m_dataReady = false;

      //--- M15 price bars (10 bars for structure & candle analysis)
      MqlRates rates[];
      ArraySetAsSeries(rates, false);
      if(CopyRates(m_symbol, m_tfEntry, 0, 10, rates) >= 10)
      {
         for(int i = 0; i < 10; i++)
         {
            m_highBuf[i]  = rates[i].high;
            m_lowBuf[i]   = rates[i].low;
            m_closeBuf[i] = rates[i].close;
            m_openBuf[i]  = rates[i].open;
         }
      }
      else
      {
         m_dataReady = false;
      }

      if(!m_dataReady)
         return;

      //--- Set single-bar cache from latest values (index 9 = most recent for non-series)
      m_emaFast    = m_emaFastBuf[9];
      m_emaMid     = m_emaMidBuf[9];
      m_emaSlow    = m_emaSlowBuf[9];
      m_macdMain   = m_macdMainBuf[9];
      m_macdSignal = m_macdSignalBuf[9];
      m_macdHist   = m_macdMain - m_macdSignal;
      m_adx        = m_adxBuf[4];
      m_plusDI      = m_plusDIBuf[4];
      m_minusDI     = m_minusDIBuf[4];
      m_rsi        = m_rsiBuf[9];
      m_bbMiddle   = m_bbMiddleBuf[9];
      m_bbUpper    = m_bbUpperBuf[9];
      m_bbLower    = m_bbLowerBuf[9];
      m_stochK     = m_stochKBuf[4];
      m_stochD     = m_stochDBuf[4];
      m_atr        = m_atrBuf[49];
      m_rsiH1      = m_rsiH1Buf[4];
   }

   //+------------------------------------------------------------------+
   //| LAYER 1: EMA TREND (0-20 points)                                 |
   //| Enhanced with ribbon expansion, crossover freshness, H1 filter    |
   //+------------------------------------------------------------------+
   void CalcEMATrend(double price)
   {
      //--- Full alignment: fast > mid > slow (BUY) or fast < mid < slow (SELL)
      bool bullAlign = (m_emaFast > m_emaMid && m_emaMid > m_emaSlow);
      bool bearAlign = (m_emaFast < m_emaMid && m_emaMid < m_emaSlow);

      //--- Ribbon spacing quality: distance between fast and slow
      double ribbonWidth = MathAbs(m_emaFast - m_emaSlow);
      double prevRibbonWidth = MathAbs(m_emaFastBuf[7] - m_emaSlowBuf[7]);
      bool expanding  = (ribbonWidth > prevRibbonWidth * 1.05);

      //--- Crossover freshness: check if EMA(8) crossed EMA(21) in last 3 bars
      bool freshBullCross = false;
      bool freshBearCross = false;
      for(int i = 7; i < 9; i++)
      {
         if(m_emaFastBuf[i] > m_emaMidBuf[i] && m_emaFastBuf[i - 1] <= m_emaMidBuf[i - 1])
            freshBullCross = true;
         if(m_emaFastBuf[i] < m_emaMidBuf[i] && m_emaFastBuf[i - 1] >= m_emaMidBuf[i - 1])
            freshBearCross = true;
      }

      //--- BUY scoring
      if(bullAlign)
      {
         m_buyBreakdown.emaTrend += 8;
         if(price > m_emaFast) m_buyBreakdown.emaTrend += 3;
         if(price > m_emaH1)  m_buyBreakdown.emaTrend += 4;
         if(expanding)        m_buyBreakdown.emaTrend += 3;
         if(freshBullCross)   m_buyBreakdown.emaTrend += 2;
      }
      else if(m_emaFast > m_emaMid)
      {
         m_buyBreakdown.emaTrend += 4;
         if(price > m_emaH1) m_buyBreakdown.emaTrend += 2;
         if(freshBullCross)  m_buyBreakdown.emaTrend += 2;
      }

      //--- SELL scoring
      if(bearAlign)
      {
         m_sellBreakdown.emaTrend += 8;
         if(price < m_emaFast) m_sellBreakdown.emaTrend += 3;
         if(price < m_emaH1)  m_sellBreakdown.emaTrend += 4;
         if(expanding)        m_sellBreakdown.emaTrend += 3;
         if(freshBearCross)   m_sellBreakdown.emaTrend += 2;
      }
      else if(m_emaFast < m_emaMid)
      {
         m_sellBreakdown.emaTrend += 4;
         if(price < m_emaH1) m_sellBreakdown.emaTrend += 2;
         if(freshBearCross)  m_sellBreakdown.emaTrend += 2;
      }
   }

   //+------------------------------------------------------------------+
   //| LAYER 2: MACD MOMENTUM (0-20 points)                             |
   //| Enhanced with histogram momentum, divergence, zero-line prox      |
   //+------------------------------------------------------------------+
   void CalcMACDMomentum()
   {
      double hist     = m_macdMain - m_macdSignal;
      double prevHist = m_macdMainBuf[8] - m_macdSignalBuf[8];

      bool histGrowing   = (MathAbs(hist) > MathAbs(prevHist));
      bool nearZeroLine  = (MathAbs(m_macdMain) < m_atr * 0.3);

      //--- Divergence detection on MACD
      int bullDivMACD = CheckDivergence(m_lowBuf, m_macdMainBuf, true);
      int bearDivMACD = CheckDivergence(m_highBuf, m_macdMainBuf, false);

      //--- BUY: MACD > Signal
      if(m_macdMain > m_macdSignal)
      {
         m_buyBreakdown.macdMomentum += 6;
         if(hist > 0 && histGrowing)   m_buyBreakdown.macdMomentum += 5;
         else if(hist > 0)             m_buyBreakdown.macdMomentum += 3;
         if(m_macdMain > 0)            m_buyBreakdown.macdMomentum += 3;
         if(nearZeroLine && hist > 0)  m_buyBreakdown.macdMomentum += 2;
      }
      //--- Regular bullish divergence: price lower low, MACD higher low
      if(bullDivMACD > 0)
         m_buyBreakdown.macdMomentum += MathMin(4, bullDivMACD * 2);

      //--- SELL: MACD < Signal
      if(m_macdMain < m_macdSignal)
      {
         m_sellBreakdown.macdMomentum += 6;
         if(hist < 0 && histGrowing)   m_sellBreakdown.macdMomentum += 5;
         else if(hist < 0)             m_sellBreakdown.macdMomentum += 3;
         if(m_macdMain < 0)            m_sellBreakdown.macdMomentum += 3;
         if(nearZeroLine && hist < 0)  m_sellBreakdown.macdMomentum += 2;
      }
      //--- Regular bearish divergence: price higher high, MACD lower high
      if(bearDivMACD > 0)
         m_sellBreakdown.macdMomentum += MathMin(4, bearDivMACD * 2);
   }

   //+------------------------------------------------------------------+
   //| LAYER 3: ADX STRENGTH (0-15 points)                              |
   //| Enhanced with slope detection and DI gap quality                  |
   //+------------------------------------------------------------------+
   void CalcADXStrength()
   {
      //--- ADX threshold zones
      if(m_adx < 20) return;  // No trend, no score

      //--- ADX slope: rising = strengthening trend
      bool adxRising = (m_adxBuf[4] > m_adxBuf[2]);

      //--- DI gap quality
      double diGap = 0;

      //--- BUY: +DI > -DI
      if(m_plusDI > m_minusDI)
      {
         diGap = m_plusDI - m_minusDI;

         // ADX zone scoring
         if(m_adx >= 35)      m_buyBreakdown.adxStrength += 6;
         else if(m_adx >= 25) m_buyBreakdown.adxStrength += 4;
         else                 m_buyBreakdown.adxStrength += 2; // 20-25 caution zone

         // DI gap quality
         if(diGap > 15)      m_buyBreakdown.adxStrength += 4;
         else if(diGap > 8)  m_buyBreakdown.adxStrength += 3;
         else if(diGap > 3)  m_buyBreakdown.adxStrength += 1;

         // ADX slope bonus
         if(adxRising)        m_buyBreakdown.adxStrength += 3;

         // Fresh DI crossover bonus
         if(m_plusDIBuf[2] <= m_minusDIBuf[2] && m_plusDI > m_minusDI)
            m_buyBreakdown.adxStrength += 2;
      }

      //--- SELL: -DI > +DI
      if(m_minusDI > m_plusDI)
      {
         diGap = m_minusDI - m_plusDI;

         if(m_adx >= 35)      m_sellBreakdown.adxStrength += 6;
         else if(m_adx >= 25) m_sellBreakdown.adxStrength += 4;
         else                 m_sellBreakdown.adxStrength += 2;

         if(diGap > 15)      m_sellBreakdown.adxStrength += 4;
         else if(diGap > 8)  m_sellBreakdown.adxStrength += 3;
         else if(diGap > 3)  m_sellBreakdown.adxStrength += 1;

         if(adxRising)        m_sellBreakdown.adxStrength += 3;

         if(m_minusDIBuf[2] <= m_plusDIBuf[2] && m_minusDI > m_plusDI)
            m_sellBreakdown.adxStrength += 2;
      }
   }

   //+------------------------------------------------------------------+
   //| LAYER 4: RSI LEVEL (0-15 points)                                 |
   //| Enhanced with divergence, momentum, MTF RSI                       |
   //+------------------------------------------------------------------+
   void CalcRSILevel()
   {
      double rsiPrev = m_rsiBuf[8];
      bool rsiRising  = (m_rsi > rsiPrev);
      bool rsiFalling = (m_rsi < rsiPrev);

      //--- RSI divergence
      int bullDivRSI = CheckDivergence(m_lowBuf, m_rsiBuf, true);
      int bearDivRSI = CheckDivergence(m_highBuf, m_rsiBuf, false);

      //--- MTF agreement: M15 RSI vs H1 RSI
      bool h1RsiBullish = (m_rsiH1 > 45 && m_rsiH1 < 70);
      bool h1RsiBearish = (m_rsiH1 < 55 && m_rsiH1 > 30);

      //--- BUY scoring
      if(m_rsi >= 30 && m_rsi <= 50)
      {
         m_buyBreakdown.rsiLevel += 5;
         if(rsiRising)    m_buyBreakdown.rsiLevel += 3;
         if(m_rsi < 35)   m_buyBreakdown.rsiLevel += 2;  // Near oversold
      }
      else if(m_rsi > 50 && m_rsi <= 65)
      {
         m_buyBreakdown.rsiLevel += 3;
         if(rsiRising)    m_buyBreakdown.rsiLevel += 2;
      }
      // Bullish divergence: strong reversal signal
      if(bullDivRSI > 0 && m_rsi < 45)
         m_buyBreakdown.rsiLevel += 3;
      // MTF agreement bonus
      if(h1RsiBullish && m_buyBreakdown.rsiLevel > 0)
         m_buyBreakdown.rsiLevel += 2;
      // Overbought penalty
      if(m_rsi > 75) m_buyBreakdown.rsiLevel = 0;

      //--- SELL scoring
      if(m_rsi >= 50 && m_rsi <= 70)
      {
         m_sellBreakdown.rsiLevel += 5;
         if(rsiFalling)   m_sellBreakdown.rsiLevel += 3;
         if(m_rsi > 65)   m_sellBreakdown.rsiLevel += 2;
      }
      else if(m_rsi >= 35 && m_rsi < 50)
      {
         m_sellBreakdown.rsiLevel += 3;
         if(rsiFalling)   m_sellBreakdown.rsiLevel += 2;
      }
      // Bearish divergence
      if(bearDivRSI > 0 && m_rsi > 55)
         m_sellBreakdown.rsiLevel += 3;
      // MTF agreement bonus
      if(h1RsiBearish && m_sellBreakdown.rsiLevel > 0)
         m_sellBreakdown.rsiLevel += 2;
      // Oversold penalty
      if(m_rsi < 25) m_sellBreakdown.rsiLevel = 0;
   }

   //+------------------------------------------------------------------+
   //| LAYER 5: BOLLINGER BANDS (0-15 points)                           |
   //| Enhanced with squeeze, band walk, %B indicator                    |
   //+------------------------------------------------------------------+
   void CalcBBPosition(double price)
   {
      if(m_bbUpper <= m_bbLower) return;

      double percentB = CalcBBPercentB(price);
      bool squeezing  = IsSqueezing();

      //--- Band walk detection (price consistently near band edge)
      bool walkingUpper = true;
      bool walkingLower = true;
      for(int i = 7; i < 10; i++)
      {
         double bw = m_bbUpperBuf[i] - m_bbLowerBuf[i];
         if(bw <= 0) { walkingUpper = false; walkingLower = false; break; }
         double pB = (m_closeBuf[i] - m_bbLowerBuf[i]) / bw;
         if(pB < 0.75) walkingUpper = false;
         if(pB > 0.25) walkingLower = false;
      }

      //--- BUY scoring based on %B
      if(percentB <= 0.10)
      {
         m_buyBreakdown.bbPosition += 10;  // Touching/below lower band
      }
      else if(percentB <= 0.25)
      {
         m_buyBreakdown.bbPosition += 7;
      }
      else if(percentB <= 0.40)
      {
         m_buyBreakdown.bbPosition += 4;
      }

      // Squeeze with bullish setup: breakout potential
      if(squeezing && m_emaFast > m_emaMid)
         m_buyBreakdown.bbPosition += 3;

      // Band walk penalty for BUY (price walking lower = continuation down, bad for buy)
      if(walkingLower && m_buyBreakdown.bbPosition > 0)
         m_buyBreakdown.bbPosition = (int)(m_buyBreakdown.bbPosition * 0.5);

      //--- SELL scoring based on %B
      if(percentB >= 0.90)
      {
         m_sellBreakdown.bbPosition += 10;
      }
      else if(percentB >= 0.75)
      {
         m_sellBreakdown.bbPosition += 7;
      }
      else if(percentB >= 0.60)
      {
         m_sellBreakdown.bbPosition += 4;
      }

      if(squeezing && m_emaFast < m_emaMid)
         m_sellBreakdown.bbPosition += 3;

      // Band walk upper = continuation up, bad for sell
      if(walkingUpper && m_sellBreakdown.bbPosition > 0)
         m_sellBreakdown.bbPosition = (int)(m_sellBreakdown.bbPosition * 0.5);
   }

   //+------------------------------------------------------------------+
   //| LAYER 6: STOCHASTIC (0-10 points)                                |
   //| Enhanced with multi-zone scoring and divergence                   |
   //+------------------------------------------------------------------+
   void CalcStochSignal()
   {
      //--- Previous values for crossover detection
      double prevK = m_stochKBuf[3];
      double prevD = m_stochDBuf[3];
      bool kCrossedAboveD = (prevK <= prevD && m_stochK > m_stochD);
      bool kCrossedBelowD = (prevK >= prevD && m_stochK < m_stochD);

      //--- BUY: oversold zone with bullish crossover
      if(m_stochK < 20 && kCrossedAboveD)
      {
         m_buyBreakdown.stochSignal += 10;  // Full points: deep oversold + cross
      }
      else if(m_stochK < 30 && kCrossedAboveD)
      {
         m_buyBreakdown.stochSignal += 7;
      }
      else if(m_stochK < 40 && m_stochK > m_stochD)
      {
         m_buyBreakdown.stochSignal += 4;
      }
      else if(m_stochK < 50 && m_stochK > m_stochD)
      {
         m_buyBreakdown.stochSignal += 2;
      }

      //--- SELL: overbought zone with bearish crossover
      if(m_stochK > 80 && kCrossedBelowD)
      {
         m_sellBreakdown.stochSignal += 10;
      }
      else if(m_stochK > 70 && kCrossedBelowD)
      {
         m_sellBreakdown.stochSignal += 7;
      }
      else if(m_stochK > 60 && m_stochK < m_stochD)
      {
         m_sellBreakdown.stochSignal += 4;
      }
      else if(m_stochK > 50 && m_stochK < m_stochD)
      {
         m_sellBreakdown.stochSignal += 2;
      }
   }

   //+------------------------------------------------------------------+
   //| LAYER 7: ATR VOLATILITY (0-5 points)                             |
   //| Enhanced with percentile ranking and regime detection             |
   //+------------------------------------------------------------------+
   void CalcATRVolatility()
   {
      if(m_atr <= 0) return;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(bid <= 0) return;

      //--- ATR percentile: compare current ATR to average of last 50 bars
      double atrSum = 0;
      for(int i = 0; i < 50; i++)
         atrSum += m_atrBuf[i];
      double atrAvg = atrSum / 50.0;

      if(atrAvg <= 0) return;

      double atrRatio = m_atr / atrAvg;

      //--- Ideal volatility: current ATR between 0.8x and 2.0x of average
      if(atrRatio >= 0.8 && atrRatio <= 2.0)
      {
         m_buyBreakdown.atrVolatility  += 3;
         m_sellBreakdown.atrVolatility += 3;

         //--- Sweet spot bonus: 1.0x to 1.5x (active but not extreme)
         if(atrRatio >= 1.0 && atrRatio <= 1.5)
         {
            m_buyBreakdown.atrVolatility  += 2;
            m_sellBreakdown.atrVolatility += 2;
         }
      }
      //--- Marginal volatility: 0.5x to 0.8x - low but tradeable
      else if(atrRatio >= 0.5 && atrRatio < 0.8)
      {
         m_buyBreakdown.atrVolatility  += 1;
         m_sellBreakdown.atrVolatility += 1;
      }
      //--- Too extreme (>2.0x) or too dead (<0.5x): no points
   }

   //+------------------------------------------------------------------+
   //| DetectMarketStructure - HH/HL/LH/LL analysis                     |
   //| Returns: +1 uptrend, -1 downtrend, 0 range                       |
   //+------------------------------------------------------------------+
   int DetectMarketStructure()
   {
      //--- Need at least 6 bars: use bars [2]-[8] to find swing points
      //--- Fractal-like: bar[i] high > bar[i-1] and bar[i+1] = swing high
      double swingHighs[3];
      double swingLows[3];
      int shCount = 0, slCount = 0;

      for(int i = 2; i < 8 && (shCount < 3 || slCount < 3); i++)
      {
         // Swing high: bar higher than neighbors
         if(shCount < 3 && i > 0 && i < 9)
         {
            if(m_highBuf[i] > m_highBuf[i - 1] && m_highBuf[i] > m_highBuf[i + 1])
            {
               swingHighs[shCount] = m_highBuf[i];
               shCount++;
            }
         }
         // Swing low: bar lower than neighbors
         if(slCount < 3 && i > 0 && i < 9)
         {
            if(m_lowBuf[i] < m_lowBuf[i - 1] && m_lowBuf[i] < m_lowBuf[i + 1])
            {
               swingLows[slCount] = m_lowBuf[i];
               slCount++;
            }
         }
      }

      //--- Need at least 2 swing points to determine structure
      bool higherHighs = false;
      bool higherLows  = false;
      bool lowerHighs  = false;
      bool lowerLows   = false;

      if(shCount >= 2)
      {
         // Most recent swing high vs previous (index 0 = most recent due to buffer order)
         higherHighs = (swingHighs[0] > swingHighs[1]);
         lowerHighs  = (swingHighs[0] < swingHighs[1]);
      }
      if(slCount >= 2)
      {
         higherLows = (swingLows[0] > swingLows[1]);
         lowerLows  = (swingLows[0] < swingLows[1]);
      }

      //--- Uptrend: HH + HL
      if(higherHighs && higherLows) return 1;
      //--- Downtrend: LH + LL
      if(lowerHighs && lowerLows) return -1;

      return 0;
   }

   //+------------------------------------------------------------------+
   //| DetectCandlePattern - pattern recognition on last candle          |
   //| Returns: +score for bullish, -score for bearish, 0 for none      |
   //| Magnitude: 1=weak, 2=moderate, 3=strong, -99=doji penalty        |
   //+------------------------------------------------------------------+
   int DetectCandlePattern()
   {
      //--- Use bar[1] as the completed candle (bar[0] is forming)
      //--- In our non-series buffer: index 8 is bar[1], index 9 is bar[0]
      int idx  = 8;  // Last completed bar
      int idx2 = 7;  // Bar before that

      double bodySize  = MathAbs(m_closeBuf[idx] - m_openBuf[idx]);
      double totalSize = m_highBuf[idx] - m_lowBuf[idx];

      if(totalSize <= 0) return 0;

      double bodyRatio = bodySize / totalSize;
      bool isBullCandle = (m_closeBuf[idx] > m_openBuf[idx]);
      bool isBearCandle = (m_closeBuf[idx] < m_openBuf[idx]);

      //--- DOJI detection: very small body at extreme positions
      if(bodyRatio < 0.1)
      {
         // Doji at upper BB = indecision at top
         double percentB = 0;
         double bw = m_bbUpperBuf[idx] - m_bbLowerBuf[idx];
         if(bw > 0)
            percentB = (m_closeBuf[idx] - m_bbLowerBuf[idx]) / bw;

         if(percentB > 0.85 || percentB < 0.15)
            return -99;  // Doji at extremes = penalty signal
         return 0;
      }

      //--- PIN BAR detection: long wick rejection
      double upperWick = m_highBuf[idx] - MathMax(m_openBuf[idx], m_closeBuf[idx]);
      double lowerWick = MathMin(m_openBuf[idx], m_closeBuf[idx]) - m_lowBuf[idx];

      // Bullish pin bar: long lower wick, small upper wick
      if(lowerWick > bodySize * 2.0 && upperWick < bodySize * 0.5)
         return 2;  // Bullish reversal

      // Bearish pin bar: long upper wick, small lower wick
      if(upperWick > bodySize * 2.0 && lowerWick < bodySize * 0.5)
         return -2;  // Bearish reversal

      //--- ENGULFING detection
      double prevBody = MathAbs(m_closeBuf[idx2] - m_openBuf[idx2]);
      bool prevBull   = (m_closeBuf[idx2] > m_openBuf[idx2]);
      bool prevBear   = (m_closeBuf[idx2] < m_openBuf[idx2]);

      // Bullish engulfing: previous bear, current bull engulfs
      if(prevBear && isBullCandle && bodySize > prevBody * 1.3 &&
         m_closeBuf[idx] > m_openBuf[idx2] && m_openBuf[idx] < m_closeBuf[idx2])
         return 3;

      // Bearish engulfing: previous bull, current bear engulfs
      if(prevBull && isBearCandle && bodySize > prevBody * 1.3 &&
         m_closeBuf[idx] < m_openBuf[idx2] && m_openBuf[idx] > m_closeBuf[idx2])
         return -3;

      //--- THREE SOLDIERS / THREE CROWS (check bars idx-2, idx-1, idx)
      if(idx >= 2)
      {
         int idx3 = idx - 2;
         bool sol1 = (m_closeBuf[idx3]     > m_openBuf[idx3]);
         bool sol2 = (m_closeBuf[idx3 + 1] > m_openBuf[idx3 + 1]);
         bool sol3 = (m_closeBuf[idx]       > m_openBuf[idx]);

         if(sol1 && sol2 && sol3 &&
            m_closeBuf[idx3 + 1] > m_closeBuf[idx3] &&
            m_closeBuf[idx] > m_closeBuf[idx3 + 1])
            return 2;  // Three white soldiers

         bool cr1 = (m_closeBuf[idx3]     < m_openBuf[idx3]);
         bool cr2 = (m_closeBuf[idx3 + 1] < m_openBuf[idx3 + 1]);
         bool cr3 = (m_closeBuf[idx]       < m_openBuf[idx]);

         if(cr1 && cr2 && cr3 &&
            m_closeBuf[idx3 + 1] < m_closeBuf[idx3] &&
            m_closeBuf[idx] < m_closeBuf[idx3 + 1])
            return -2;  // Three black crows
      }

      return 0;
   }

   //+------------------------------------------------------------------+
   //| ApplyCandleBonus - distribute candle pattern into layers          |
   //+------------------------------------------------------------------+
   void ApplyCandleBonus(int candleScore)
   {
      if(candleScore == 0) return;

      //--- Doji at extremes: reduce ALL scores by 20%
      if(candleScore == -99)
      {
         m_buyBreakdown.emaTrend      = (int)(m_buyBreakdown.emaTrend * 0.8);
         m_buyBreakdown.macdMomentum  = (int)(m_buyBreakdown.macdMomentum * 0.8);
         m_buyBreakdown.adxStrength   = (int)(m_buyBreakdown.adxStrength * 0.8);
         m_buyBreakdown.rsiLevel      = (int)(m_buyBreakdown.rsiLevel * 0.8);
         m_buyBreakdown.bbPosition    = (int)(m_buyBreakdown.bbPosition * 0.8);
         m_buyBreakdown.stochSignal   = (int)(m_buyBreakdown.stochSignal * 0.8);
         m_buyBreakdown.atrVolatility = (int)(m_buyBreakdown.atrVolatility * 0.8);

         m_sellBreakdown.emaTrend      = (int)(m_sellBreakdown.emaTrend * 0.8);
         m_sellBreakdown.macdMomentum  = (int)(m_sellBreakdown.macdMomentum * 0.8);
         m_sellBreakdown.adxStrength   = (int)(m_sellBreakdown.adxStrength * 0.8);
         m_sellBreakdown.rsiLevel      = (int)(m_sellBreakdown.rsiLevel * 0.8);
         m_sellBreakdown.bbPosition    = (int)(m_sellBreakdown.bbPosition * 0.8);
         m_sellBreakdown.stochSignal   = (int)(m_sellBreakdown.stochSignal * 0.8);
         m_sellBreakdown.atrVolatility = (int)(m_sellBreakdown.atrVolatility * 0.8);
         return;
      }

      //--- Positive = bullish pattern
      if(candleScore > 0)
      {
         int bonus = MathMin(candleScore, 3);
         // Pin bar feeds RSI layer, engulfing feeds MACD, soldiers feed ADX
         if(candleScore == 2)       // Pin bar or soldiers
            m_buyBreakdown.rsiLevel = MathMin(15, m_buyBreakdown.rsiLevel + bonus);
         else if(candleScore == 3)  // Engulfing
            m_buyBreakdown.macdMomentum = MathMin(20, m_buyBreakdown.macdMomentum + bonus);
      }
      //--- Negative = bearish pattern
      else if(candleScore < 0)
      {
         int bonus = (int)MathMin(MathAbs(candleScore), 3);
         if(candleScore == -2)
            m_sellBreakdown.rsiLevel = MathMin(15, m_sellBreakdown.rsiLevel + bonus);
         else if(candleScore == -3)
            m_sellBreakdown.macdMomentum = MathMin(20, m_sellBreakdown.macdMomentum + bonus);
      }
   }

   //+------------------------------------------------------------------+
   //| DetectMomentumShift - large candle body vs ATR                    |
   //| Feeds bonus into MACD layer if aligned                           |
   //+------------------------------------------------------------------+
   void DetectMomentumShift(double price)
   {
      if(m_atr <= 0) return;

      //--- Check last completed candle (index 8 in non-series)
      double bodySize = MathAbs(m_closeBuf[8] - m_openBuf[8]);
      bool isBullish  = (m_closeBuf[8] > m_openBuf[8]);

      //--- Momentum shift: body > 1.5x ATR
      if(bodySize > m_atr * 1.5)
      {
         if(isBullish)
            m_buyBreakdown.macdMomentum = MathMin(20, m_buyBreakdown.macdMomentum + 3);
         else
            m_sellBreakdown.macdMomentum = MathMin(20, m_sellBreakdown.macdMomentum + 3);
      }
   }

   //+------------------------------------------------------------------+
   //| CheckDivergence - generic divergence detector                     |
   //| prices[]: high or low buffer; indicator[]: MACD or RSI buffer     |
   //| isBull: true = check for bullish div (lower lows in price)        |
   //| Returns: 0 = none, 1 = regular div, 2 = hidden div               |
   //+------------------------------------------------------------------+
   int CheckDivergence(double &prices[], double &indicator[], bool isBull)
   {
      //--- Find two recent swing points in 10-bar lookback
      //--- Compare price swing with indicator swing
      //--- Bars: indices 2-8 in non-series arrays (skip forming bar)

      double swingPrice1 = 0, swingPrice2 = 0;
      double swingInd1 = 0, swingInd2 = 0;
      int found = 0;

      if(isBull)
      {
         //--- Looking for swing lows in price
         for(int i = 3; i < 8 && found < 2; i++)
         {
            if(prices[i] < prices[i - 1] && prices[i] < prices[i + 1])
            {
               if(found == 0) { swingPrice1 = prices[i]; swingInd1 = indicator[i]; }
               else           { swingPrice2 = prices[i]; swingInd2 = indicator[i]; }
               found++;
            }
         }

         if(found >= 2)
         {
            //--- Regular bullish divergence: price lower low, indicator higher low
            if(swingPrice1 < swingPrice2 && swingInd1 > swingInd2)
               return 1;
            //--- Hidden bullish divergence: price higher low, indicator lower low
            if(swingPrice1 > swingPrice2 && swingInd1 < swingInd2)
               return 2;
         }
      }
      else
      {
         //--- Looking for swing highs in price
         for(int i = 3; i < 8 && found < 2; i++)
         {
            if(prices[i] > prices[i - 1] && prices[i] > prices[i + 1])
            {
               if(found == 0) { swingPrice1 = prices[i]; swingInd1 = indicator[i]; }
               else           { swingPrice2 = prices[i]; swingInd2 = indicator[i]; }
               found++;
            }
         }

         if(found >= 2)
         {
            //--- Regular bearish divergence: price higher high, indicator lower high
            if(swingPrice1 > swingPrice2 && swingInd1 < swingInd2)
               return 1;
            //--- Hidden bearish divergence: price lower high, indicator higher high
            if(swingPrice1 < swingPrice2 && swingInd1 > swingInd2)
               return 2;
         }
      }

      return 0;
   }

   //+------------------------------------------------------------------+
   //| CalcBBPercentB - Bollinger %B = (Price - Lower) / (Upper - Lower)|
   //+------------------------------------------------------------------+
   double CalcBBPercentB(double price)
   {
      double bandwidth = m_bbUpper - m_bbLower;
      if(bandwidth <= 0) return 0.5;
      return (price - m_bbLower) / bandwidth;
   }

   //+------------------------------------------------------------------+
   //| IsSqueezing - Bollinger squeeze: bands narrowing significantly    |
   //| Compares current bandwidth to average of last 10 bars             |
   //+------------------------------------------------------------------+
   bool IsSqueezing()
   {
      double currentBW = m_bbUpper - m_bbLower;
      if(currentBW <= 0) return false;

      //--- Average bandwidth over last 10 bars
      double bwSum = 0;
      for(int i = 0; i < 10; i++)
      {
         double bw = m_bbUpperBuf[i] - m_bbLowerBuf[i];
         if(bw > 0) bwSum += bw;
      }
      double bwAvg = bwSum / 10.0;

      if(bwAvg <= 0) return false;

      //--- Squeeze: current bandwidth < 70% of average
      return (currentBW < bwAvg * 0.70);
   }

   //+------------------------------------------------------------------+
   //| SumBreakdownRaw - sum all layer fields (before totalScore set)   |
   //+------------------------------------------------------------------+
   int SumBreakdownRaw(const ScoreBreakdown &bd)
   {
      return bd.emaTrend + bd.macdMomentum + bd.adxStrength +
             bd.rsiLevel + bd.bbPosition + bd.stochSignal + bd.atrVolatility;
   }

   //+------------------------------------------------------------------+
   //| ApplyMultiTFFilter - H1 and H4 trend confirmation                |
   //| H1+H4 agree: +15% bonus to total | H1 disagrees: -30%           |
   //| H4 disagrees: -15%                                               |
   //+------------------------------------------------------------------+
   void ApplyMultiTFFilter()
   {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(price <= 0) return;

      //--- Determine H1 trend direction
      ENUM_SIGNAL_DIR h1Dir = SIGNAL_NONE;
      if(price > m_emaH1) h1Dir = SIGNAL_BUY;
      else if(price < m_emaH1) h1Dir = SIGNAL_SELL;

      //--- Determine H4 trend direction
      ENUM_SIGNAL_DIR h4Dir = SIGNAL_NONE;
      if(price > m_emaH4) h4Dir = SIGNAL_BUY;
      else if(price < m_emaH4) h4Dir = SIGNAL_SELL;

      //--- Apply to BUY breakdown
      if(SumBreakdownRaw(m_buyBreakdown) > 0)
      {
         bool h1Agrees = (h1Dir == SIGNAL_BUY);
         bool h4Agrees = (h4Dir == SIGNAL_BUY);

         if(h1Agrees && h4Agrees)
         {
            //--- Full MTF agreement: +15% bonus
            ApplyPercentBonus(m_buyBreakdown, 0.15);
         }
         else if(!h1Agrees && h1Dir != SIGNAL_NONE)
         {
            //--- H1 opposes: -30% penalty
            ApplyPercentPenalty(m_buyBreakdown, 0.30);
         }
         else if(!h4Agrees && h4Dir != SIGNAL_NONE)
         {
            //--- H4 opposes (H1 neutral or agrees): -15% penalty
            ApplyPercentPenalty(m_buyBreakdown, 0.15);
         }
      }

      //--- Apply to SELL breakdown
      if(SumBreakdownRaw(m_sellBreakdown) > 0)
      {
         bool h1Agrees = (h1Dir == SIGNAL_SELL);
         bool h4Agrees = (h4Dir == SIGNAL_SELL);

         if(h1Agrees && h4Agrees)
         {
            ApplyPercentBonus(m_sellBreakdown, 0.15);
         }
         else if(!h1Agrees && h1Dir != SIGNAL_NONE)
         {
            ApplyPercentPenalty(m_sellBreakdown, 0.30);
         }
         else if(!h4Agrees && h4Dir != SIGNAL_NONE)
         {
            ApplyPercentPenalty(m_sellBreakdown, 0.15);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| ApplyPercentBonus - add percentage bonus to all layer scores      |
   //+------------------------------------------------------------------+
   void ApplyPercentBonus(ScoreBreakdown &bd, double pct)
   {
      bd.emaTrend      = (int)MathRound(bd.emaTrend * (1.0 + pct));
      bd.macdMomentum  = (int)MathRound(bd.macdMomentum * (1.0 + pct));
      bd.adxStrength   = (int)MathRound(bd.adxStrength * (1.0 + pct));
      bd.rsiLevel      = (int)MathRound(bd.rsiLevel * (1.0 + pct));
      bd.bbPosition    = (int)MathRound(bd.bbPosition * (1.0 + pct));
      bd.stochSignal   = (int)MathRound(bd.stochSignal * (1.0 + pct));
      bd.atrVolatility = (int)MathRound(bd.atrVolatility * (1.0 + pct));
   }

   //+------------------------------------------------------------------+
   //| ApplyPercentPenalty - reduce all layer scores by percentage       |
   //+------------------------------------------------------------------+
   void ApplyPercentPenalty(ScoreBreakdown &bd, double pct)
   {
      bd.emaTrend      = (int)MathRound(bd.emaTrend * (1.0 - pct));
      bd.macdMomentum  = (int)MathRound(bd.macdMomentum * (1.0 - pct));
      bd.adxStrength   = (int)MathRound(bd.adxStrength * (1.0 - pct));
      bd.rsiLevel      = (int)MathRound(bd.rsiLevel * (1.0 - pct));
      bd.bbPosition    = (int)MathRound(bd.bbPosition * (1.0 - pct));
      bd.stochSignal   = (int)MathRound(bd.stochSignal * (1.0 - pct));
      bd.atrVolatility = (int)MathRound(bd.atrVolatility * (1.0 - pct));
   }

   //+------------------------------------------------------------------+
   //| ClampBreakdown - enforce maximum per-layer limits                 |
   //+------------------------------------------------------------------+
   void ClampBreakdown(ScoreBreakdown &bd)
   {
      if(bd.emaTrend < 0)      bd.emaTrend = 0;
      if(bd.emaTrend > 20)     bd.emaTrend = 20;
      if(bd.macdMomentum < 0)  bd.macdMomentum = 0;
      if(bd.macdMomentum > 20) bd.macdMomentum = 20;
      if(bd.adxStrength < 0)   bd.adxStrength = 0;
      if(bd.adxStrength > 15)  bd.adxStrength = 15;
      if(bd.rsiLevel < 0)      bd.rsiLevel = 0;
      if(bd.rsiLevel > 15)     bd.rsiLevel = 15;
      if(bd.bbPosition < 0)    bd.bbPosition = 0;
      if(bd.bbPosition > 15)   bd.bbPosition = 15;
      if(bd.stochSignal < 0)   bd.stochSignal = 0;
      if(bd.stochSignal > 10)  bd.stochSignal = 10;
      if(bd.atrVolatility < 0) bd.atrVolatility = 0;
      if(bd.atrVolatility > 5) bd.atrVolatility = 5;
   }

   //+------------------------------------------------------------------+
   //| CountActiveLayers - count layers with score > 0                   |
   //+------------------------------------------------------------------+
   int CountActiveLayers(const ScoreBreakdown &bd)
   {
      int count = 0;
      if(bd.emaTrend > 0)      count++;
      if(bd.macdMomentum > 0)  count++;
      if(bd.adxStrength > 0)   count++;
      if(bd.rsiLevel > 0)      count++;
      if(bd.bbPosition > 0)    count++;
      if(bd.stochSignal > 0)   count++;
      if(bd.atrVolatility > 0) count++;
      return count;
   }

   //+------------------------------------------------------------------+
   //| CalculateTPLevels - ATR-based TP with trend strength adaptation   |
   //| SL is always 0 (ABSOLUTE RULE)                                   |
   //+------------------------------------------------------------------+
   void CalculateTPLevels(SignalData &sig)
   {
      if(m_atr <= 0) return;

      //--- Category multiplier
      double catMult = 1.0;
      switch(m_category)
      {
         case CAT_FOREX:   catMult = 1.0;  break;
         case CAT_METAL:   catMult = 0.9;  break;
         case CAT_CRYPTO:  catMult = 1.25; break;
         case CAT_INDICES: catMult = 1.0;  break;
         case CAT_ENERGY:  catMult = 0.85; break;
         case CAT_STOCKS:  catMult = 1.0;  break;
         default:          catMult = 1.0;  break;
      }

      //--- Trend strength adaptation
      ENUM_TREND_STRENGTH strength = GetTrendStrength();
      double tp1Mult = 1.5, tp2Mult = 2.5, tp3Mult = 4.0;  // Default: MODERATE

      switch(strength)
      {
         case TREND_WEAK:
            tp1Mult = 1.0;  tp2Mult = 1.5;  tp3Mult = 2.5;  // Conservative
            break;
         case TREND_MODERATE:
            tp1Mult = 1.5;  tp2Mult = 2.5;  tp3Mult = 4.0;  // Standard
            break;
         case TREND_STRONG:
            tp1Mult = 2.0;  tp2Mult = 3.5;  tp3Mult = 5.5;  // Aggressive
            break;
      }

      double tp1Distance = m_atr * tp1Mult * catMult;
      double tp2Distance = m_atr * tp2Mult * catMult;
      double tp3Distance = m_atr * tp3Mult * catMult;

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(sig.direction == SIGNAL_BUY)
      {
         sig.tp1 = ask + tp1Distance;
         sig.tp2 = ask + tp2Distance;
         sig.tp3 = ask + tp3Distance;
         sig.tp  = sig.tp1;
      }
      else
      {
         sig.tp1 = bid - tp1Distance;
         sig.tp2 = bid - tp2Distance;
         sig.tp3 = bid - tp3Distance;
         sig.tp  = sig.tp1;
      }

      sig.sl = 0;  // SL = NONE (ABSOLUTE RULE)
      sig.trendStrength = strength;
   }
};

#endif
