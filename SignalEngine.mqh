//+------------------------------------------------------------------+
//|                                             SignalEngine.mqh     |
//|                              Copyright 2026, By T@MER            |
//|                              https://www.bytamer.com             |
//+------------------------------------------------------------------+
//| BytamerFX Hibrit Sinyal Motoru                                   |
//| 7 Katmanli Skor Sistemi (0-100)                                  |
//| Entry: M15 | Trend Filtre: H1                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, By T@MER"
#property link      "https://www.bytamer.com"
#property strict

#ifndef SIGNAL_ENGINE_MQH
#define SIGNAL_ENGINE_MQH

#include "Config.mqh"

class CSignalEngine
{
private:
   string               m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   ENUM_TIMEFRAMES      m_tfEntry;     // M15
   ENUM_TIMEFRAMES      m_tfTrend;     // H1

   //--- Indikator handle'lari (M15)
   int m_hEmaFast;       // EMA(8)
   int m_hEmaMid;        // EMA(21)
   int m_hEmaSlow;       // EMA(50)
   int m_hMacd;          // MACD(12,26,9)
   int m_hAdx;           // ADX(14)
   int m_hRsi;           // RSI(14)
   int m_hBB;            // Bollinger(20,2)
   int m_hStoch;         // Stochastic(14,3,3)
   int m_hAtr;           // ATR(14)

   //--- H1 Trend filtresi
   int m_hEmaH1;         // EMA(50) on H1

   //--- Veri cache
   double m_emaFast, m_emaMid, m_emaSlow;
   double m_macdMain, m_macdSignal, m_macdHist;
   double m_macdHistPrev;
   double m_adx, m_plusDI, m_minusDI;
   double m_rsi, m_rsiPrev;
   double m_bbUpper, m_bbLower, m_bbMiddle;
   double m_stochK, m_stochD;
   double m_atr;
   double m_emaH1;

   //--- Skor
   ScoreBreakdown m_buyBreakdown;
   ScoreBreakdown m_sellBreakdown;
   ScoreBreakdown m_lastBreakdown;

   //--- Cooldown
   datetime m_lastSignalTime;
   int      m_cooldownSec;

public:
   CSignalEngine() : m_lastSignalTime(0), m_cooldownSec(120) {}

   bool Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat)
   {
      m_symbol   = symbol;
      m_category = cat;
      m_tfEntry  = PERIOD_M15;
      m_tfTrend  = PERIOD_H1;
      m_cooldownSec = SignalCooldownSec;

      //--- M15 indikatorleri
      m_hEmaFast = iMA(symbol, m_tfEntry, 8, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaMid  = iMA(symbol, m_tfEntry, 21, 0, MODE_EMA, PRICE_CLOSE);
      m_hEmaSlow = iMA(symbol, m_tfEntry, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_hMacd    = iMACD(symbol, m_tfEntry, 12, 26, 9, PRICE_CLOSE);
      m_hAdx     = iADX(symbol, m_tfEntry, 14);
      m_hRsi     = iRSI(symbol, m_tfEntry, 14, PRICE_CLOSE);
      m_hBB      = iBands(symbol, m_tfEntry, 20, 0, 2.0, PRICE_CLOSE);
      m_hStoch   = iStochastic(symbol, m_tfEntry, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
      m_hAtr     = iATR(symbol, m_tfEntry, 14);

      //--- H1 trend filtresi
      m_hEmaH1   = iMA(symbol, m_tfTrend, 50, 0, MODE_EMA, PRICE_CLOSE);

      //--- Handle dogrulama
      if(m_hEmaFast == INVALID_HANDLE || m_hEmaMid == INVALID_HANDLE ||
         m_hEmaSlow == INVALID_HANDLE || m_hMacd == INVALID_HANDLE ||
         m_hAdx == INVALID_HANDLE     || m_hRsi == INVALID_HANDLE ||
         m_hBB == INVALID_HANDLE      || m_hStoch == INVALID_HANDLE ||
         m_hAtr == INVALID_HANDLE     || m_hEmaH1 == INVALID_HANDLE)
      {
         Print("!!! SINYAL MOTORU HATA: Indikator handle olusturulamadi!");
         return false;
      }

      Print(StringFormat("Sinyal Motoru: %s | Entry=%s | Trend=%s | MinSkor=%d | Cooldown=%dsn",
            symbol, EnumToString(m_tfEntry), EnumToString(m_tfTrend),
            SignalMinScore, m_cooldownSec));
      return true;
   }

   //========================================
   // VERI GUNCELLEME (her tick)
   //========================================
   void RefreshData()
   {
      double buf[2];

      // EMA
      if(CopyBuffer(m_hEmaFast, 0, 0, 1, buf) > 0) m_emaFast = buf[0];
      if(CopyBuffer(m_hEmaMid,  0, 0, 1, buf) > 0) m_emaMid  = buf[0];
      if(CopyBuffer(m_hEmaSlow, 0, 0, 1, buf) > 0) m_emaSlow = buf[0];

      // MACD
      if(CopyBuffer(m_hMacd, 0, 0, 1, buf) > 0) m_macdMain   = buf[0];
      if(CopyBuffer(m_hMacd, 1, 0, 1, buf) > 0) m_macdSignal = buf[0];
      double histBuf[2];
      if(CopyBuffer(m_hMacd, 0, 0, 2, histBuf) > 0)
      {
         m_macdHist     = histBuf[1] - m_macdSignal; // MACD - Signal
         m_macdHistPrev = histBuf[0];
      }
      // Duzelt: MQL5 MACD buffer0=main, buffer1=signal
      // Histogram = main - signal
      m_macdHist = m_macdMain - m_macdSignal;

      // ADX
      if(CopyBuffer(m_hAdx, 0, 0, 1, buf) > 0) m_adx     = buf[0];
      if(CopyBuffer(m_hAdx, 1, 0, 1, buf) > 0) m_plusDI   = buf[0];
      if(CopyBuffer(m_hAdx, 2, 0, 1, buf) > 0) m_minusDI  = buf[0];

      // RSI
      double rsiBuf[2];
      if(CopyBuffer(m_hRsi, 0, 0, 2, rsiBuf) > 0)
      {
         m_rsi     = rsiBuf[1];
         m_rsiPrev = rsiBuf[0];
      }

      // Bollinger
      if(CopyBuffer(m_hBB, 0, 0, 1, buf) > 0) m_bbMiddle = buf[0];
      if(CopyBuffer(m_hBB, 1, 0, 1, buf) > 0) m_bbUpper  = buf[0];
      if(CopyBuffer(m_hBB, 2, 0, 1, buf) > 0) m_bbLower  = buf[0];

      // Stochastic
      if(CopyBuffer(m_hStoch, 0, 0, 1, buf) > 0) m_stochK = buf[0];
      if(CopyBuffer(m_hStoch, 1, 0, 1, buf) > 0) m_stochD = buf[0];

      // ATR
      if(CopyBuffer(m_hAtr, 0, 0, 1, buf) > 0) m_atr = buf[0];

      // H1 EMA
      if(CopyBuffer(m_hEmaH1, 0, 0, 1, buf) > 0) m_emaH1 = buf[0];
   }

   //========================================
   // SKOR HESAPLAMA (dashboard icin her tick)
   //========================================
   void UpdateBreakdown()
   {
      RefreshData();

      m_buyBreakdown.Clear();
      m_sellBreakdown.Clear();

      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      //--- KATMAN 1: EMA TREND (0-20 puan)
      CalcEMATrend(price);

      //--- KATMAN 2: MACD MOMENTUM (0-20 puan)
      CalcMACDMomentum();

      //--- KATMAN 3: ADX GUCLU TREND (0-15 puan)
      CalcADXStrength();

      //--- KATMAN 4: RSI SEVIYESI (0-15 puan)
      CalcRSILevel();

      //--- KATMAN 5: BOLLINGER BANT (0-15 puan)
      CalcBBPosition(price);

      //--- KATMAN 6: STOCHASTIC (0-10 puan)
      CalcStochSignal();

      //--- KATMAN 7: ATR VOLATILITE (0-5 puan)
      CalcATRVolatility();

      // Toplam
      m_buyBreakdown.totalScore = m_buyBreakdown.emaTrend + m_buyBreakdown.macdMomentum +
            m_buyBreakdown.adxStrength + m_buyBreakdown.rsiLevel + m_buyBreakdown.bbPosition +
            m_buyBreakdown.stochSignal + m_buyBreakdown.atrVolatility;

      m_sellBreakdown.totalScore = m_sellBreakdown.emaTrend + m_sellBreakdown.macdMomentum +
            m_sellBreakdown.adxStrength + m_sellBreakdown.rsiLevel + m_sellBreakdown.bbPosition +
            m_sellBreakdown.stochSignal + m_sellBreakdown.atrVolatility;

      // Dominant yon icin breakdown kaydet
      if(m_buyBreakdown.totalScore >= m_sellBreakdown.totalScore)
         m_lastBreakdown = m_buyBreakdown;
      else
         m_lastBreakdown = m_sellBreakdown;
   }

   //========================================
   // SINYAL URETME (cooldown dahil)
   //========================================
   SignalData Evaluate()
   {
      SignalData sig;
      sig.Clear();

      // Breakdown'i guncelle
      UpdateBreakdown();

      // Veriyi doldur
      sig.atr = m_atr; sig.rsi = m_rsi; sig.adx = m_adx;
      sig.plusDI = m_plusDI; sig.minusDI = m_minusDI;
      sig.macd_main = m_macdMain; sig.macd_signal = m_macdSignal; sig.macd_hist = m_macdHist;
      sig.bb_upper = m_bbUpper; sig.bb_lower = m_bbLower; sig.bb_middle = m_bbMiddle;
      sig.ema_fast = m_emaFast; sig.ema_mid = m_emaMid; sig.ema_slow = m_emaSlow;
      sig.stoch_k = m_stochK; sig.stoch_d = m_stochD;
      sig.time = TimeCurrent();

      // Cooldown kontrolu
      if(TimeCurrent() - m_lastSignalTime < m_cooldownSec)
         return sig;

      // Kac katman uyumlu?
      int buyLayers = 0, sellLayers = 0;
      if(m_buyBreakdown.emaTrend > 0)      buyLayers++;
      if(m_buyBreakdown.macdMomentum > 0)  buyLayers++;
      if(m_buyBreakdown.adxStrength > 0)   buyLayers++;
      if(m_buyBreakdown.rsiLevel > 0)      buyLayers++;
      if(m_buyBreakdown.bbPosition > 0)    buyLayers++;
      if(m_buyBreakdown.stochSignal > 0)   buyLayers++;
      if(m_buyBreakdown.atrVolatility > 0) buyLayers++;

      if(m_sellBreakdown.emaTrend > 0)      sellLayers++;
      if(m_sellBreakdown.macdMomentum > 0)  sellLayers++;
      if(m_sellBreakdown.adxStrength > 0)   sellLayers++;
      if(m_sellBreakdown.rsiLevel > 0)      sellLayers++;
      if(m_sellBreakdown.bbPosition > 0)    sellLayers++;
      if(m_sellBreakdown.stochSignal > 0)   sellLayers++;
      if(m_sellBreakdown.atrVolatility > 0) sellLayers++;

      int totalBuy  = m_buyBreakdown.totalScore;
      int totalSell = m_sellBreakdown.totalScore;

      // BUY sinyal: skor >= min VE 4+ katman VE fark > 10
      if(totalBuy >= SignalMinScore && buyLayers >= 4 && totalBuy > totalSell + 10)
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
      // SELL sinyal
      else if(totalSell >= SignalMinScore && sellLayers >= 4 && totalSell > totalBuy + 10)
      {
         sig.direction = SIGNAL_SELL;
         sig.score = totalSell;
         sig.reason = StringFormat("SELL[%d] L=%d EMA=-%d MACD=-%d ADX=-%d RSI=-%d BB=-%d ST=-%d ATR=-%d",
               totalSell, sellLayers,
               m_sellBreakdown.emaTrend, m_sellBreakdown.macdMomentum,
               m_sellBreakdown.adxStrength, m_sellBreakdown.rsiLevel,
               m_sellBreakdown.bbPosition, m_sellBreakdown.stochSignal,
               m_sellBreakdown.atrVolatility);
      }

      // Sinyal varsa TP hesapla
      if(sig.direction != SIGNAL_NONE)
      {
         m_lastSignalTime = TimeCurrent();
         CalculateTPLevels(sig);

         Print(StringFormat("SINYAL: %s | Skor: %d/100 | Katman: %d | %s",
               (sig.direction == SIGNAL_BUY) ? "BUY" : "SELL",
               sig.score, (sig.direction == SIGNAL_BUY) ? buyLayers : sellLayers,
               sig.reason));
      }

      return sig;
   }

   //========================================
   // H1 TREND YONU
   //========================================
   ENUM_SIGNAL_DIR GetCurrentTrend()
   {
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(price > m_emaH1 && m_emaFast > m_emaSlow)
         return SIGNAL_BUY;
      if(price < m_emaH1 && m_emaFast < m_emaSlow)
         return SIGNAL_SELL;
      return SIGNAL_NONE;
   }

   //========================================
   // TREND GUCU
   //========================================
   ENUM_TREND_STRENGTH GetTrendStrength()
   {
      if(m_adx >= 35) return TREND_STRONG;
      if(m_adx >= 25) return TREND_MODERATE;
      return TREND_WEAK;
   }

   // Getters
   double GetATR()    const { return m_atr; }
   double GetRSI()    const { return m_rsi; }
   double GetADX()    const { return m_adx; }
   double GetPlusDI() const { return m_plusDI; }
   double GetMinusDI()const { return m_minusDI; }
   ScoreBreakdown GetBreakdown()     const { return m_lastBreakdown; }
   ScoreBreakdown GetBuyBreakdown()  const { return m_buyBreakdown; }
   ScoreBreakdown GetSellBreakdown() const { return m_sellBreakdown; }

private:
   //========================================
   // KATMAN 1: EMA TREND (0-20 puan)
   //========================================
   void CalcEMATrend(double price)
   {
      // BUY: fast>mid>slow dizilimi
      if(m_emaFast > m_emaMid && m_emaMid > m_emaSlow)
      {
         m_buyBreakdown.emaTrend += 10;
         if(price > m_emaFast) m_buyBreakdown.emaTrend += 5;
         if(price > m_emaH1)  m_buyBreakdown.emaTrend += 5;
      }
      // Partial: fast>mid ama slow uzerinde degil
      else if(m_emaFast > m_emaMid)
      {
         m_buyBreakdown.emaTrend += 5;
         if(price > m_emaH1) m_buyBreakdown.emaTrend += 3;
      }

      // SELL: fast<mid<slow dizilimi
      if(m_emaFast < m_emaMid && m_emaMid < m_emaSlow)
      {
         m_sellBreakdown.emaTrend += 10;
         if(price < m_emaFast) m_sellBreakdown.emaTrend += 5;
         if(price < m_emaH1)  m_sellBreakdown.emaTrend += 5;
      }
      else if(m_emaFast < m_emaMid)
      {
         m_sellBreakdown.emaTrend += 5;
         if(price < m_emaH1) m_sellBreakdown.emaTrend += 3;
      }
   }

   //========================================
   // KATMAN 2: MACD MOMENTUM (0-20 puan)
   //========================================
   void CalcMACDMomentum()
   {
      // BUY: MACD > Signal
      if(m_macdMain > m_macdSignal)
      {
         m_buyBreakdown.macdMomentum += 7;
         if(m_macdHist > 0) m_buyBreakdown.macdMomentum += 7;  // Histogram pozitif
         // Fresh crossover: MACD just crossed above signal
         if(m_macdMain > 0 && m_macdMain - m_macdSignal < m_atr * 0.5)
            m_buyBreakdown.macdMomentum += 6;
      }

      // SELL: MACD < Signal
      if(m_macdMain < m_macdSignal)
      {
         m_sellBreakdown.macdMomentum += 7;
         if(m_macdHist < 0) m_sellBreakdown.macdMomentum += 7;
         if(m_macdMain < 0 && m_macdSignal - m_macdMain < m_atr * 0.5)
            m_sellBreakdown.macdMomentum += 6;
      }
   }

   //========================================
   // KATMAN 3: ADX TREND GUCU (0-15 puan)
   //========================================
   void CalcADXStrength()
   {
      if(m_adx < 20) return;  // Trend yok, puan yok

      // BUY: +DI > -DI
      if(m_plusDI > m_minusDI)
      {
         m_buyBreakdown.adxStrength += 8;
         if(m_adx >= 30) m_buyBreakdown.adxStrength += 4;
         double diGap = m_plusDI - m_minusDI;
         if(diGap > 10) m_buyBreakdown.adxStrength += 3;
      }

      // SELL: -DI > +DI
      if(m_minusDI > m_plusDI)
      {
         m_sellBreakdown.adxStrength += 8;
         if(m_adx >= 30) m_sellBreakdown.adxStrength += 4;
         double diGap = m_minusDI - m_plusDI;
         if(diGap > 10) m_sellBreakdown.adxStrength += 3;
      }
   }

   //========================================
   // KATMAN 4: RSI SEVIYESI (0-15 puan)
   //========================================
   void CalcRSILevel()
   {
      // BUY: RSI 30-50 arasi (oversold'dan yukari)
      if(m_rsi >= 30 && m_rsi <= 50)
      {
         m_buyBreakdown.rsiLevel += 7;
         if(m_rsi > m_rsiPrev) m_buyBreakdown.rsiLevel += 4;  // Yukari gidiyor
         if(m_rsi < 35) m_buyBreakdown.rsiLevel += 4;          // Oversold yakin
      }
      else if(m_rsi > 50 && m_rsi <= 65)
      {
         m_buyBreakdown.rsiLevel += 4;
         if(m_rsi > m_rsiPrev) m_buyBreakdown.rsiLevel += 3;
      }
      // Overbought penalty
      if(m_rsi > 75) m_buyBreakdown.rsiLevel = 0;

      // SELL: RSI 50-70 arasi (overbought'tan asagi)
      if(m_rsi >= 50 && m_rsi <= 70)
      {
         m_sellBreakdown.rsiLevel += 7;
         if(m_rsi < m_rsiPrev) m_sellBreakdown.rsiLevel += 4;
         if(m_rsi > 65) m_sellBreakdown.rsiLevel += 4;
      }
      else if(m_rsi >= 35 && m_rsi < 50)
      {
         m_sellBreakdown.rsiLevel += 4;
         if(m_rsi < m_rsiPrev) m_sellBreakdown.rsiLevel += 3;
      }
      // Oversold penalty
      if(m_rsi < 25) m_sellBreakdown.rsiLevel = 0;
   }

   //========================================
   // KATMAN 5: BOLLINGER BANT (0-15 puan)
   //========================================
   void CalcBBPosition(double price)
   {
      if(m_bbUpper <= m_bbLower) return;

      double bbRange = m_bbUpper - m_bbLower;
      double position = (price - m_bbLower) / bbRange;  // 0.0=alt, 1.0=ust

      // BUY: fiyat alt banda yakin
      if(position <= 0.15)
      {
         m_buyBreakdown.bbPosition += 15;  // Alt banda dokundu
      }
      else if(position <= 0.30)
      {
         m_buyBreakdown.bbPosition += 10;
      }
      else if(position <= 0.45)
      {
         m_buyBreakdown.bbPosition += 5;
      }

      // SELL: fiyat ust banda yakin
      if(position >= 0.85)
      {
         m_sellBreakdown.bbPosition += 15;
      }
      else if(position >= 0.70)
      {
         m_sellBreakdown.bbPosition += 10;
      }
      else if(position >= 0.55)
      {
         m_sellBreakdown.bbPosition += 5;
      }
   }

   //========================================
   // KATMAN 6: STOCHASTIC (0-10 puan)
   //========================================
   void CalcStochSignal()
   {
      // BUY: K < 40 ve K > D (oversold zone, yukari kesisim)
      if(m_stochK < 40 && m_stochK > m_stochD)
      {
         m_buyBreakdown.stochSignal += 5;
         if(m_stochK < 25) m_buyBreakdown.stochSignal += 5;  // Deep oversold
      }
      else if(m_stochK < 50 && m_stochK > m_stochD)
      {
         m_buyBreakdown.stochSignal += 3;
      }

      // SELL: K > 60 ve K < D (overbought zone, asagi kesisim)
      if(m_stochK > 60 && m_stochK < m_stochD)
      {
         m_sellBreakdown.stochSignal += 5;
         if(m_stochK > 75) m_sellBreakdown.stochSignal += 5;
      }
      else if(m_stochK > 50 && m_stochK < m_stochD)
      {
         m_sellBreakdown.stochSignal += 3;
      }
   }

   //========================================
   // KATMAN 7: ATR VOLATILITE (0-5 puan)
   //========================================
   void CalcATRVolatility()
   {
      if(m_atr <= 0) return;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(bid <= 0) return;

      double atrPct = (m_atr / bid) * 100.0;

      // Yeterli volatilite varsa puan ver (her iki yon)
      if(atrPct >= 0.1 && atrPct <= 3.0)
      {
         m_buyBreakdown.atrVolatility  += 3;
         m_sellBreakdown.atrVolatility += 3;

         // Ideal aralik bonusu
         if(atrPct >= 0.3 && atrPct <= 1.5)
         {
            m_buyBreakdown.atrVolatility  += 2;
            m_sellBreakdown.atrVolatility += 2;
         }
      }
      // Cok dusuk veya cok yuksek volatilite = puan yok
   }

   //========================================
   // TP HESAPLAMA (ATR bazli, kategori ayarli)
   //========================================
   void CalculateTPLevels(SignalData &sig)
   {
      if(m_atr <= 0) return;

      // Kategori carpani
      double catMult = 1.0;
      switch(m_category)
      {
         case CAT_FOREX:   catMult = 1.0;  break;
         case CAT_METAL:   catMult = 0.9;  break;
         case CAT_CRYPTO:  catMult = 1.25; break;
         case CAT_INDICES: catMult = 1.0;  break;
         case CAT_ENERGY:  catMult = 0.85; break;
         default:          catMult = 1.0;  break;
      }

      double tp1Distance = m_atr * 1.5 * catMult;
      double tp2Distance = m_atr * 2.5 * catMult;
      double tp3Distance = m_atr * 4.0 * catMult;

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(sig.direction == SIGNAL_BUY)
      {
         sig.tp1 = ask + tp1Distance;
         sig.tp2 = ask + tp2Distance;
         sig.tp3 = ask + tp3Distance;
         sig.tp  = sig.tp1;  // Default TP = TP1
      }
      else
      {
         sig.tp1 = bid - tp1Distance;
         sig.tp2 = bid - tp2Distance;
         sig.tp3 = bid - tp3Distance;
         sig.tp  = sig.tp1;
      }

      sig.sl = 0;  // SL = YOK (MUTLAK KURAL)
      sig.trendStrength = GetTrendStrength();
   }
};

#endif
