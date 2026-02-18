#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH
//+------------------------------------------------------------------+
//|                                             PositionManager.mqh  |
//|                                    Copyright 2026, By T@MER      |
//|                                    https://www.bytamer.com        |
//|                                                                  |
//|              SPM + FIFO KAR ODAKLI SISTEM v1.3.0                 |
//|              SmartSPM: 5-Oy Yon + Guclu Hedge + Trend Bekle     |
//+------------------------------------------------------------------+
//|  KURALLAR:                                                       |
//|  1. SL YOK - ASLA                                                |
//|  2. ANA islem -3$ zarara gecti -> SPM1 ac                        |
//|     SPM1 yonu: Trend + Sinyal + Mum cogunlugu ile belirlenir    |
//|  3. SPM1 -3$ zarara gecti -> SPM2 ac (SPM1 tersine)             |
//|  4. SPM2 -3$ zarara gecti -> SPM3 ac (SPM2 tersine)             |
//|  5. SPM yon: 5-oy sistemi (Trend,Sinyal,Mum,MACD,DI)           |
//|     ASLA zarardaki ANA yonunde SPM acma (CheckSameDirectionBlock)|
//|  6. SPM +4$ karda -> KAPAT, FIFO'ya ekle                        |
//|  7. FIFO: spm_karlar_toplami - |ana_zarar| >= +5$ -> ANA kapat  |
//|  8. AMA: Trend ANA yonune donuyorsa -> BEKLE                    |
//|     Mum tersine dondu + ANA ekside -> KAPAT                     |
//|  9. ANA kapandiysa -> SPM1 yeni ANA olur                        |
//| 10. Lot carpanlari: 1.0x, 1.1x, 1.2x, 1.3x... (yukselen)      |
//| 11. Lot denge: Zarardaki lot > Kardaki lot OLMAMALI              |
//| 12. HER ZAMAN kar odakli: kucuk karlari topla, kasaya ekle      |
//+------------------------------------------------------------------+

#include "Config.mqh"
#include "TradeExecutor.mqh"
#include "SignalEngine.mqh"
#include "CandleAnalyzer.mqh"
#include "TelegramMsg.mqh"
#include "DiscordMsg.mqh"

//+------------------------------------------------------------------+
//| CPositionManager - Kar Odakli SPM + FIFO Engine                  |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   //--- Core references
   string               m_symbol;
   ENUM_SYMBOL_CATEGORY m_category;
   CTradeExecutor*      m_executor;
   CSignalEngine*       m_signalEngine;
   CTelegramMsg*        m_telegram;
   CDiscordMsg*         m_discord;

   //--- Position storage
   PositionInfo         m_positions[];
   int                  m_posCount;

   //--- SPM / FIFO tracking
   int                  m_spmLayerCount;
   double               m_spmClosedProfitTotal;
   int                  m_spmClosedCount;
   double               m_totalCashedProfit;     // Kasaya toplanan tum karlar

   //--- Candle analysis
   CCandleAnalyzer      m_candle;

   //--- Timing
   datetime             m_lastSPMTime;
   datetime             m_lastStatusLog;
   datetime             m_fifoWaitStart;          // FIFO hedef bekle baslangic

   //--- TP management
   bool                 m_tpExtended;
   int                  m_currentTPLevel;
   double               m_tp1Price, m_tp2Price, m_tp3Price;
   bool                 m_tp1Hit, m_tp2Hit;
   ENUM_TREND_STRENGTH  m_trendStrength;

   //--- Peak profit tracking
   double               m_peakProfit[];

   //--- SPM wait for ANA recovery
   datetime             m_spmWaitStart;
   bool                 m_spmWaitActive;

   //--- Main ticket
   bool                 m_adoptionDone;
   ulong                m_mainTicket;

   //--- Protection
   double               m_startBalance;
   double               m_dailyProfit;
   datetime             m_dailyResetTime;
   bool                 m_spmLimitLogged;
   datetime             m_protectionCooldownUntil;
   int                  m_protectionTriggerCount;
   bool                 m_tradingPaused;

   //=================================================================
   // PRIVATE METHODS
   //=================================================================

   //--- Position scanning
   void AdoptExistingPositions();
   void RefreshPositions();

   //--- Core SPM engine
   void ManageKarliPozisyonlar(bool newBar);
   void ManageSPMSystem();
   void ManageMainInLoss(int mainIdx, double mainProfit);
   void ManageActiveSPMs(int mainIdx);
   void CheckFIFOTarget();

   //--- Direction logic (5-oy sistemi)
   ENUM_SIGNAL_DIR DetermineSPMDirection(int parentLayer);
   ENUM_SIGNAL_DIR GetCandleDirection();
   bool CheckSameDirectionBlock(ENUM_SIGNAL_DIR proposedDir);
   bool ShouldWaitForANARecovery(int mainIdx);

   //--- Lot balance
   bool CheckLotBalance(ENUM_SIGNAL_DIR newDir, double newLot);
   double CalcSPMLot(double mainLot, int layer);

   //--- Trade execution
   void OpenNewMainTrade(ENUM_SIGNAL_DIR dirHint, string reason);
   void OpenSPM(ENUM_SIGNAL_DIR dir, double lot, int layer, ulong parentTicket);

   //--- Promotion
   void PromoteOldestSPMToMain(string reason);

   //--- TP management
   void ManageTPLevels();

   //--- Protection (sadece son care)
   bool CheckMarginEmergency();

   //--- Notification helpers
   void ClosePosWithNotification(int idx, string reason);
   void CloseMainWithFIFONotification(int mainIdx, double spmKar, double mainZarar, double net);

   //--- Helpers
   int    FindMainPosition();
   int    GetActiveSPMCount();
   int    GetHighestLayer();
   string GetCatName();
   void   ResetFIFO();
   void   CloseAllPositions(string reason);
   void   SetProtectionCooldown(string reason);
   void   PrintDetailedStatus();
   double GetTotalBuyLots();
   double GetTotalSellLots();

public:
                        CPositionManager();
                       ~CPositionManager() {}

   void                 Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat,
                                   CTradeExecutor &executor, CSignalEngine &engine,
                                   CTelegramMsg &telegram, CDiscordMsg &discord);
   void                 OnTick();

   bool                 HasPosition() const;
   bool                 IsTradingPaused() const;
   bool                 HasHedge() const;
   int                  GetSPMCount() const;
   CCandleAnalyzer*     GetCandleAnalyzer();
   FIFOSummary          GetFIFOSummary();
   TPLevelInfo          GetTPInfo() const;
   void                 SetTPTracking(double tp1, double tp2, double tp3, ENUM_TREND_STRENGTH strength);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CPositionManager::CPositionManager()
{
   m_symbol              = "";
   m_category            = CAT_FOREX;
   m_executor            = NULL;
   m_signalEngine        = NULL;
   m_telegram            = NULL;
   m_discord             = NULL;

   ArrayResize(m_positions, MAX_POSITIONS);
   m_posCount            = 0;

   m_spmLayerCount       = 0;
   m_spmClosedProfitTotal = 0.0;
   m_spmClosedCount      = 0;
   m_totalCashedProfit   = 0.0;

   m_lastSPMTime         = 0;
   m_lastStatusLog       = 0;
   m_fifoWaitStart       = 0;
   m_spmWaitStart        = 0;
   m_spmWaitActive       = false;

   m_tpExtended          = false;
   m_currentTPLevel      = 0;
   m_tp1Price            = 0.0;
   m_tp2Price            = 0.0;
   m_tp3Price            = 0.0;
   m_tp1Hit              = false;
   m_tp2Hit              = false;
   m_trendStrength       = TREND_WEAK;

   ArrayResize(m_peakProfit, MAX_POSITIONS);
   ArrayInitialize(m_peakProfit, 0.0);

   m_adoptionDone        = false;
   m_mainTicket          = 0;

   m_startBalance        = 0.0;
   m_dailyProfit         = 0.0;
   m_dailyResetTime      = 0;
   m_spmLimitLogged      = false;
   m_protectionCooldownUntil = 0;
   m_protectionTriggerCount  = 0;
   m_tradingPaused       = false;
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
void CPositionManager::Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat,
                                  CTradeExecutor &executor, CSignalEngine &engine,
                                  CTelegramMsg &telegram, CDiscordMsg &discord)
{
   m_symbol       = symbol;
   m_category     = cat;
   m_executor     = GetPointer(executor);
   m_signalEngine = GetPointer(engine);
   m_telegram     = GetPointer(telegram);
   m_discord      = GetPointer(discord);

   m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_dailyResetTime = iTime(m_symbol, PERIOD_D1, 0);

   m_candle.Initialize(m_symbol, PERIOD_M15);

   PrintFormat("[PM-%s] PositionManager v1.3.0 SmartSPM | Cat=%s | Balance=%.2f",
               m_symbol, GetCatName(), m_startBalance);
   PrintFormat("[PM-%s] SPM: Trigger=$%.1f | Close=$%.1f | Net=$%.1f | MaxLayers=%d",
               m_symbol, SPM_TriggerLossUSD, SPM_CloseProfitUSD, SPM_NetTargetUSD, SPM_MaxLayers);
   PrintFormat("[PM-%s] SPM Lot: Base=%.1f | Inc=%.2f | Cap=%.1f | Cooldown=%ds | Wait=%ds",
               m_symbol, SPM_LotBase, SPM_LotIncrement, SPM_LotCap, SPM_CooldownSec, SPM_WaitMaxSec);
   PrintFormat("[PM-%s] SmartSPM: 5-Oy Yon + SameDir Block + Trend Bekle + Guclu Hedge",
               m_symbol);

   AdoptExistingPositions();
}

//+------------------------------------------------------------------+
//| OnTick - Ana tick isleme dongusu                                  |
//+------------------------------------------------------------------+
void CPositionManager::OnTick()
{
   //--- 1. Pozisyon verilerini yenile
   RefreshPositions();

   //--- 2. Pozisyon yoksa
   if(m_posCount == 0)
   {
      if(m_spmClosedProfitTotal != 0.0 || m_spmClosedCount > 0)
      {
         PrintFormat("[PM-%s] Pozisyon yok, FIFO sifirlaniyor (Kar=%.2f, Sayi=%d)",
                     m_symbol, m_spmClosedProfitTotal, m_spmClosedCount);
         ResetFIFO();
      }
      if(m_tradingPaused && TimeCurrent() >= m_protectionCooldownUntil)
      {
         m_tradingPaused = false;
         PrintFormat("[PM-%s] Koruma suresi bitti. Islem devam.", m_symbol);
      }
      return;
   }

   //--- 3. Margin acil durum (SADECE SON CARE - %150 altinda)
   if(CheckMarginEmergency())
      return;

   //--- 4. Yeni bar kontrolu
   bool newBar = m_candle.CheckNewBar();

   //--- 5. KARLI POZISYONLARI YONET (kucuk karlari topla, kasaya ekle)
   ManageKarliPozisyonlar(newBar);

   //--- 6. SPM SISTEMI (hedge + ters islem)
   ManageSPMSystem();

   //--- 7. FIFO NET HEDEF kontrolu
   CheckFIFOTarget();

   //--- 8. TP seviyeleri yonet
   ManageTPLevels();

   //--- 9. Detayli log (30 saniyede bir)
   PrintDetailedStatus();
}

//+------------------------------------------------------------------+
//| HasPosition                                                       |
//+------------------------------------------------------------------+
bool CPositionManager::HasPosition() const
{
   return (m_posCount > 0);
}

//+------------------------------------------------------------------+
//| IsTradingPaused                                                   |
//+------------------------------------------------------------------+
bool CPositionManager::IsTradingPaused() const
{
   return (m_tradingPaused && TimeCurrent() < m_protectionCooldownUntil);
}

//+------------------------------------------------------------------+
//| HasHedge                                                          |
//+------------------------------------------------------------------+
bool CPositionManager::HasHedge() const
{
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM) return true;
   return false;
}

//+------------------------------------------------------------------+
//| GetSPMCount                                                       |
//+------------------------------------------------------------------+
int CPositionManager::GetSPMCount() const
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM) count++;
   return count;
}

//+------------------------------------------------------------------+
//| GetCandleAnalyzer                                                 |
//+------------------------------------------------------------------+
CCandleAnalyzer* CPositionManager::GetCandleAnalyzer()
{
   return GetPointer(m_candle);
}

//+------------------------------------------------------------------+
//| GetFIFOSummary                                                    |
//+------------------------------------------------------------------+
FIFOSummary CPositionManager::GetFIFOSummary()
{
   FIFOSummary summary;
   summary.closedProfitTotal = m_spmClosedProfitTotal;
   summary.closedCount       = m_spmClosedCount;
   summary.activeSPMCount    = GetActiveSPMCount();
   summary.spmLayerCount     = m_spmLayerCount;

   double openSPMProfit = 0.0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM)
         openSPMProfit += m_positions[i].profit;
   summary.openSPMProfit = openSPMProfit;

   int mainIdx = FindMainPosition();
   summary.mainLoss = (mainIdx >= 0) ? m_positions[mainIdx].profit : 0.0;

   summary.netResult = m_spmClosedProfitTotal + openSPMProfit;
   if(mainIdx >= 0 && m_positions[mainIdx].profit < 0.0)
      summary.netResult -= MathAbs(m_positions[mainIdx].profit);

   summary.targetUSD    = SPM_NetTargetUSD;
   summary.isProfitable = (summary.netResult >= SPM_NetTargetUSD);

   return summary;
}

//+------------------------------------------------------------------+
//| GetTPInfo                                                         |
//+------------------------------------------------------------------+
TPLevelInfo CPositionManager::GetTPInfo() const
{
   TPLevelInfo info;
   info.currentLevel  = m_currentTPLevel;
   info.tp1Price      = m_tp1Price;
   info.tp2Price      = m_tp2Price;
   info.tp3Price      = m_tp3Price;
   info.tp1Hit        = m_tp1Hit;
   info.tp2Hit        = m_tp2Hit;
   info.tpExtended    = m_tpExtended;
   info.trendStrength = m_trendStrength;
   return info;
}

//+------------------------------------------------------------------+
//| SetTPTracking                                                     |
//+------------------------------------------------------------------+
void CPositionManager::SetTPTracking(double tp1, double tp2, double tp3, ENUM_TREND_STRENGTH strength)
{
   m_tp1Price      = tp1;
   m_tp2Price      = tp2;
   m_tp3Price      = tp3;
   m_trendStrength = strength;
   m_currentTPLevel = 0;
   m_tp1Hit        = false;
   m_tp2Hit        = false;
   m_tpExtended    = false;
}

//+------------------------------------------------------------------+
//| AdoptExistingPositions                                            |
//+------------------------------------------------------------------+
void CPositionManager::AdoptExistingPositions()
{
   if(m_adoptionDone) return;
   m_adoptionDone = true;

   int totalAdopted = 0, spmAdopted = 0;
   ulong oldestNonSPM = 0;
   datetime oldestTime = D'2099.01.01';

   int totalPositions = PositionsTotal();
   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MAGIC) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      if(StringFind(comment, "BTFX_SPM_") >= 0)
         spmAdopted++;
      else if(openTime < oldestTime)
      {
         oldestTime = openTime;
         oldestNonSPM = ticket;
      }
      totalAdopted++;
   }

   if(oldestNonSPM > 0)
   {
      m_mainTicket = oldestNonSPM;
      PrintFormat("[PM-%s] ADOPT: Main=%d", m_symbol, (int)m_mainTicket);
   }
   else if(totalAdopted > 0)
   {
      // Tum pozisyonlar SPM - en eski ANA olsun
      datetime spmOldest = D'2099.01.01';
      ulong spmOldestTicket = 0;
      for(int i = 0; i < totalPositions; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != EA_MAGIC) continue;
         datetime t = (datetime)PositionGetInteger(POSITION_TIME);
         if(t < spmOldest) { spmOldest = t; spmOldestTicket = ticket; }
      }
      if(spmOldestTicket > 0)
         m_mainTicket = spmOldestTicket;
   }

   if(totalAdopted > 0)
   {
      m_spmLayerCount = spmAdopted;
      PrintFormat("[PM-%s] ADOPT: Total=%d SPM=%d Main=%d", m_symbol, totalAdopted, spmAdopted, (int)m_mainTicket);
   }
}

//+------------------------------------------------------------------+
//| RefreshPositions                                                  |
//+------------------------------------------------------------------+
void CPositionManager::RefreshPositions()
{
   m_posCount = 0;
   int totalPositions = PositionsTotal();

   // Gunluk sifirlama
   datetime today = iTime(m_symbol, PERIOD_D1, 0);
   if(today != m_dailyResetTime)
   {
      m_dailyResetTime = today;
      m_dailyProfit = 0.0;
      m_spmLimitLogged = false;
   }

   for(int i = 0; i < totalPositions && m_posCount < MAX_POSITIONS; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MAGIC) continue;

      int idx = m_posCount;
      m_positions[idx].ticket    = ticket;
      m_positions[idx].symbol    = m_symbol;
      m_positions[idx].type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      m_positions[idx].volume    = PositionGetDouble(POSITION_VOLUME);
      m_positions[idx].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      m_positions[idx].openTime  = (datetime)PositionGetInteger(POSITION_TIME);
      m_positions[idx].profit    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      m_positions[idx].comment   = PositionGetString(POSITION_COMMENT);
      m_positions[idx].sl        = 0;
      m_positions[idx].tp        = PositionGetDouble(POSITION_TP);

      string comment = m_positions[idx].comment;

      if(ticket == m_mainTicket)
      {
         m_positions[idx].role = ROLE_MAIN;
         m_positions[idx].spmLayer = 0;
      }
      else if(StringFind(comment, "BTFX_SPM_") >= 0)
      {
         m_positions[idx].role = ROLE_SPM;
         int spmPos = StringFind(comment, "BTFX_SPM_");
         if(spmPos >= 0)
         {
            string layerStr = StringSubstr(comment, spmPos + 9, 1);
            m_positions[idx].spmLayer = (int)StringToInteger(layerStr);
            if(m_positions[idx].spmLayer <= 0) m_positions[idx].spmLayer = 1;
         }
      }
      else if(m_mainTicket == 0 && m_posCount == 0)
      {
         m_positions[idx].role = ROLE_MAIN;
         m_positions[idx].spmLayer = 0;
         m_mainTicket = ticket;
      }
      else
      {
         m_positions[idx].role = ROLE_SPM;
         m_positions[idx].spmLayer = 1;
      }

      // Peak profit
      if(idx < ArraySize(m_peakProfit))
         if(m_positions[idx].profit > m_peakProfit[idx])
            m_peakProfit[idx] = m_positions[idx].profit;

      m_posCount++;
   }
}

//+------------------------------------------------------------------+
//| CheckMarginEmergency - SADECE SON CARE (%150 altinda)            |
//| SPM sistemi kendisi hedge yapar, bu sadece acil durum            |
//+------------------------------------------------------------------+
bool CPositionManager::CheckMarginEmergency()
{
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel == 0.0) return false;

   if(marginLevel < 150.0)
   {
      PrintFormat("[PM-%s] !!! MARGIN ACIL DURUM !!! Level=%.1f%% < 150%%", m_symbol, marginLevel);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("MARGIN ACIL %s: %.1f%% - TUM KAPATILDI", m_symbol, marginLevel));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("MARGIN ACIL %s: %.1f%% - TUM KAPATILDI", m_symbol, marginLevel));

      CloseAllPositions("MarginAcil_" + DoubleToString(marginLevel, 1) + "%");
      SetProtectionCooldown("MarginAcil");
      ResetFIFO();
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ManageKarliPozisyonlar - KAR ODAKLI: Kucuk karlari kasaya ekle  |
//| "irili ufakli toplayarak surekli cuzdana + olarak ekleyecek"    |
//+------------------------------------------------------------------+
void CPositionManager::ManageKarliPozisyonlar(bool newBar)
{
   for(int i = m_posCount - 1; i >= 0; i--)
   {
      double profit = m_positions[i].profit;
      if(profit <= 0.0) continue;

      ulong ticket = m_positions[i].ticket;
      ENUM_POS_ROLE role = m_positions[i].role;

      // Peak tracking
      if(i < ArraySize(m_peakProfit))
         if(profit > m_peakProfit[i])
            m_peakProfit[i] = profit;

      //=== KURAL 1: SPM +4$ karda -> HEMEN KAPAT ===
      if(role == ROLE_SPM && profit >= SPM_CloseProfitUSD)
      {
         PrintFormat("[PM-%s] SPM%d KAR: $%.2f >= $%.2f -> KAPAT + FIFO",
                     m_symbol, m_positions[i].spmLayer, profit, SPM_CloseProfitUSD);

         m_spmClosedProfitTotal += profit;
         m_spmClosedCount++;
         m_totalCashedProfit += profit;

         PrintFormat("[PM-%s] FIFO: +$%.2f -> Toplam=$%.2f (Sayi=%d) | Kasa=$%.2f",
                     m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount, m_totalCashedProfit);

         ClosePosWithNotification(i, StringFormat("SPM%d_Kar_%.2f", m_positions[i].spmLayer, profit));
         continue;
      }

      //=== KURAL 2: Trend ana tersinde, karda olan pozisyonlari karli kapat ===
      // "Trend ana tersinde ve karda olan pozisyonlari karli kapat"
      if(role == ROLE_SPM && profit >= 1.0)
      {
         // Trendin ANA yonune mi yoksa tersine mi gittigini kontrol et
         int mainIdx = FindMainPosition();
         if(mainIdx >= 0)
         {
            ENUM_SIGNAL_DIR trendDir = SIGNAL_NONE;
            if(m_signalEngine != NULL)
               trendDir = m_signalEngine.GetCurrentTrend();

            // Ana yonu belirle
            ENUM_SIGNAL_DIR mainDir = SIGNAL_NONE;
            if(m_positions[mainIdx].type == POSITION_TYPE_BUY) mainDir = SIGNAL_BUY;
            else mainDir = SIGNAL_SELL;

            // SPM yonu belirle
            ENUM_SIGNAL_DIR spmDir = SIGNAL_NONE;
            if(m_positions[i].type == POSITION_TYPE_BUY) spmDir = SIGNAL_BUY;
            else spmDir = SIGNAL_SELL;

            // Trend ANA yonune donuyorsa VE SPM ana tersinde ise
            // -> SPM karda, trend artik SPM aleyhine -> KAPAT
            if(trendDir == mainDir && spmDir != mainDir && profit >= 1.0)
            {
               PrintFormat("[PM-%s] TREND DONUS: Trend ANA yonune donuyor, SPM%d karda ($%.2f) -> KARLI KAPAT",
                           m_symbol, m_positions[i].spmLayer, profit);

               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
               m_totalCashedProfit += profit;

               ClosePosWithNotification(i, StringFormat("TrendDonus_SPM%d_Kar_%.2f",
                                        m_positions[i].spmLayer, profit));
               continue;
            }
         }
      }

      //=== KURAL 3: Mum terse dondu + pozisyon karda -> KARLI KAPAT ===
      if(newBar && profit >= 1.5)
      {
         ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
         bool candleAgainst = false;

         if(m_positions[i].type == POSITION_TYPE_BUY && candleDir == SIGNAL_SELL)
            candleAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && candleDir == SIGNAL_BUY)
            candleAgainst = true;

         if(candleAgainst)
         {
            PrintFormat("[PM-%s] MUM DONUS: %s #%d karda ($%.2f) + mum terse dondu -> KAPAT",
                        m_symbol, (role == ROLE_MAIN) ? "MAIN" : StringFormat("SPM%d", m_positions[i].spmLayer),
                        (int)ticket, profit);

            if(role == ROLE_SPM)
            {
               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
            }
            m_totalCashedProfit += profit;
            m_dailyProfit += profit;

            ClosePosWithNotification(i, "MumDonus_Kar_" + DoubleToString(profit, 2));

            if(role == ROLE_MAIN)
            {
               m_mainTicket = 0;
               PromoteOldestSPMToMain("MainKarliKapandi");
            }
            continue;
         }
      }

      //=== KURAL 4: Engulfing formasyonu ile karli kapat ===
      if(newBar && profit >= 0.80)
      {
         int engulfPattern = m_candle.DetectEngulfing();
         bool engulfAgainst = false;

         if(m_positions[i].type == POSITION_TYPE_BUY && engulfPattern == -1)
            engulfAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && engulfPattern == +1)
            engulfAgainst = true;

         if(engulfAgainst)
         {
            PrintFormat("[PM-%s] ENGULFING: #%d karda ($%.2f) + engulfing -> KAPAT",
                        m_symbol, (int)ticket, profit);

            if(role == ROLE_SPM)
            {
               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
            }
            m_totalCashedProfit += profit;

            ClosePosWithNotification(i, "Engulfing_Kar_" + DoubleToString(profit, 2));

            if(role == ROLE_MAIN)
            {
               m_mainTicket = 0;
               PromoteOldestSPMToMain("MainEngulfing");
            }
            continue;
         }
      }

      //=== KURAL 5: Peak drop %40 -> Karini koru ===
      double peakVal = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : profit;
      if(peakVal > 1.0 && profit > 0.0)
      {
         double dropPct = (peakVal - profit) / peakVal * 100.0;
         if(dropPct >= 40.0)
         {
            PrintFormat("[PM-%s] PEAK DROP: #%d Peak=$%.2f Now=$%.2f Drop=%.0f%% -> KAPAT",
                        m_symbol, (int)ticket, peakVal, profit, dropPct);

            if(role == ROLE_SPM)
            {
               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
            }
            m_totalCashedProfit += profit;

            ClosePosWithNotification(i, StringFormat("PeakDrop_%.0f%%", dropPct));

            if(role == ROLE_MAIN)
            {
               m_mainTicket = 0;
               PromoteOldestSPMToMain("MainPeakDrop");
            }
            continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ManageSPMSystem - SPM hedge motoru                                |
//+------------------------------------------------------------------+
void CPositionManager::ManageSPMSystem()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   double mainProfit = m_positions[mainIdx].profit;

   // Ana karda ise SPM gerek yok
   if(mainProfit >= 0.0) return;

   // Ana zararda - SPM sistemi devreye
   int activeSPMs = GetActiveSPMCount();

   if(activeSPMs == 0)
      ManageMainInLoss(mainIdx, mainProfit);
   else
      ManageActiveSPMs(mainIdx);
}

//+------------------------------------------------------------------+
//| ManageMainInLoss - Ana zararda, ilk SPM ac                       |
//+------------------------------------------------------------------+
void CPositionManager::ManageMainInLoss(int mainIdx, double mainProfit)
{
   if(GetActiveSPMCount() > 0) return;

   // -3$ tetik
   if(mainProfit > SPM_TriggerLossUSD) return;

   // Bakiye kontrolu
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + SPM_CooldownSeconds) return;

   // Paused
   if(IsTradingPaused()) return;

   // Margin kontrolu
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel) return;

   // Toplam hacim kontrolu
   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   //--- v1.3.0: ANA toparlanma bekleme kontrolu
   if(ShouldWaitForANARecovery(mainIdx))
   {
      PrintFormat("[PM-%s] SPM1 BEKLE: Trend ANA yonune donuyor, toparlanma bekleniyor.", m_symbol);
      return;
   }

   //--- SPM1 yonu: 5-OY gercek zamanli piyasa analizi
   ENUM_SIGNAL_DIR spmDir = DetermineSPMDirection(0);

   if(spmDir == SIGNAL_NONE)
   {
      // Fallback: ana tersine
      if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
         spmDir = SIGNAL_SELL;
      else
         spmDir = SIGNAL_BUY;
   }

   //--- v1.3.0: Ayni yon bloklama - ASLA zarardaki yonde ikiye katlama
   if(CheckSameDirectionBlock(spmDir))
   {
      PrintFormat("[PM-%s] SPM1 SAME-DIR BLOCK! Override: ANA tersine zorunlu.", m_symbol);
      if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
         spmDir = SIGNAL_SELL;
      else
         spmDir = SIGNAL_BUY;
   }

   // Lot hesapla (layer 1)
   double spmLot = CalcSPMLot(m_positions[mainIdx].volume, 1);

   // Lot denge kontrolu
   if(!CheckLotBalance(spmDir, spmLot))
   {
      PrintFormat("[PM-%s] SPM1 LOT DENGE: Tek tarafli risk! Engellendi.", m_symbol);
      return;
   }

   PrintFormat("[PM-%s] SPM1 TETIK: Ana zarar=$%.2f <= $%.2f -> %s lot=%.2f",
               m_symbol, mainProfit, SPM_TriggerLossUSD,
               (spmDir == SIGNAL_BUY) ? "BUY" : "SELL", spmLot);

   OpenSPM(spmDir, spmLot, 1, m_positions[mainIdx].ticket);
}

//+------------------------------------------------------------------+
//| ManageActiveSPMs - Mevcut SPM'leri yonet                         |
//+------------------------------------------------------------------+
void CPositionManager::ManageActiveSPMs(int mainIdx)
{
   int highestLayer = GetHighestLayer();

   for(int i = m_posCount - 1; i >= 0; i--)
   {
      if(m_positions[i].role != ROLE_SPM) continue;

      double spmProfit = m_positions[i].profit;
      int spmLayer = m_positions[i].spmLayer;

      //--- En ust katman SPM zararda -> yeni katman ac
      if(spmLayer == highestLayer && spmProfit <= SPM_TriggerLossUSD)
      {
         int nextLayer = highestLayer + 1;

         if(nextLayer > SPM_MaxLayers)
         {
            if(!m_spmLimitLogged)
            {
               PrintFormat("[PM-%s] SPM MaxLayers=%d ulasti.", m_symbol, SPM_MaxLayers);
               m_spmLimitLogged = true;
            }
            continue;
         }

         // Kontroller
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance < MinBalanceToTrade) continue;
         if(TimeCurrent() < m_lastSPMTime + SPM_CooldownSeconds) continue;
         if(IsTradingPaused()) continue;

         double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
         if(marginLevel > 0.0 && marginLevel < MinMarginLevel) continue;

         double totalVol = GetTotalBuyLots() + GetTotalSellLots();
         if(totalVol >= MaxTotalVolume) continue;

         //--- v1.3.0: ANA toparlanma bekleme kontrolu
         if(ShouldWaitForANARecovery(mainIdx))
         {
            PrintFormat("[PM-%s] SPM%d BEKLE: Trend ANA yonune donuyor.", m_symbol, nextLayer);
            continue;
         }

         //--- Yon: 5-OY gercek zamanli piyasa analizi (v1.3.0)
         ENUM_SIGNAL_DIR nextDir = DetermineSPMDirection(spmLayer);

         //--- v1.3.0: Ayni yon bloklama
         if(CheckSameDirectionBlock(nextDir))
         {
            PrintFormat("[PM-%s] SPM%d SAME-DIR BLOCK! Override: ANA tersine zorunlu.", m_symbol, nextLayer);
            if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
               nextDir = SIGNAL_SELL;
            else
               nextDir = SIGNAL_BUY;
         }

         // Lot
         double nextLot = CalcSPMLot(m_positions[mainIdx].volume, nextLayer);

         // Lot denge kontrolu
         if(!CheckLotBalance(nextDir, nextLot))
         {
            PrintFormat("[PM-%s] SPM%d LOT DENGE: Tek tarafli risk! Engellendi.", m_symbol, nextLayer);
            continue;
         }

         PrintFormat("[PM-%s] SPM%d TETIK: SPM%d zarar=$%.2f -> %s lot=%.2f",
                     m_symbol, nextLayer, spmLayer, spmProfit,
                     (nextDir == SIGNAL_BUY) ? "BUY" : "SELL", nextLot);

         OpenSPM(nextDir, nextLot, nextLayer, m_positions[i].ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| DetermineSPMDirection - 5-OY GERCEK ZAMANLI PIYASA ANALIZI      |
//| TUM katmanlar (SPM1-6) ayni 5-oy sistemi kullanir               |
//| Asla parent SPM'nin tersi degil, piyasanin GERCEK yonu          |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::DetermineSPMDirection(int parentLayer)
{
   int buyVotes = 0, sellVotes = 0;

   //--- OY 1: H1 Trend (EMA hizalamasi)
   ENUM_SIGNAL_DIR trendDir = SIGNAL_NONE;
   if(m_signalEngine != NULL)
   {
      trendDir = m_signalEngine.GetCurrentTrend();
      if(trendDir == SIGNAL_BUY) buyVotes++;
      else if(trendDir == SIGNAL_SELL) sellVotes++;
   }

   //--- OY 2: Sinyal Skoru (7-katman tam analiz)
   if(m_signalEngine != NULL)
   {
      SignalData sig = m_signalEngine.Evaluate();
      if(sig.direction == SIGNAL_BUY && sig.score >= 25) buyVotes++;
      else if(sig.direction == SIGNAL_SELL && sig.score >= 25) sellVotes++;
   }

   //--- OY 3: M15 Mum Yonu (son kapanan mum)
   ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
   if(candleDir == SIGNAL_BUY) buyVotes++;
   else if(candleDir == SIGNAL_SELL) sellVotes++;

   //--- OY 4: MACD Histogram Momentum
   if(m_signalEngine != NULL)
   {
      double macdHist = m_signalEngine.GetMACDHist();
      if(macdHist > 0) buyVotes++;
      else if(macdHist < 0) sellVotes++;
   }

   //--- OY 5: DI Crossover (+DI vs -DI)
   if(m_signalEngine != NULL)
   {
      double plusDI  = m_signalEngine.GetPlusDI();
      double minusDI = m_signalEngine.GetMinusDI();
      if(plusDI > minusDI) buyVotes++;
      else if(minusDI > plusDI) sellVotes++;
   }

   //--- Cogunluk karari
   PrintFormat("[PM-%s] 5-OY SPM%d: BUY=%d SELL=%d",
               m_symbol, parentLayer + 1, buyVotes, sellVotes);

   if(buyVotes > sellVotes) return SIGNAL_BUY;
   if(sellVotes > buyVotes) return SIGNAL_SELL;

   //--- Esitlik: H1 trend yonunu kullan
   if(trendDir != SIGNAL_NONE) return trendDir;

   //--- Hala belirsiz: ANA tersine (guvenli fallback)
   int mainIdx = FindMainPosition();
   if(mainIdx >= 0)
   {
      if(m_positions[mainIdx].type == POSITION_TYPE_BUY) return SIGNAL_SELL;
      else return SIGNAL_BUY;
   }

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| CheckSameDirectionBlock - MUTLAK GUVENLIK                        |
//| SPM yonu == ANA yonu VE ANA zararda → ENGELLE                   |
//| Asla zarardaki yonde ikiye katlanmaz                             |
//+------------------------------------------------------------------+
bool CPositionManager::CheckSameDirectionBlock(ENUM_SIGNAL_DIR proposedDir)
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return false;

   ENUM_SIGNAL_DIR mainDir = SIGNAL_NONE;
   if(m_positions[mainIdx].type == POSITION_TYPE_BUY) mainDir = SIGNAL_BUY;
   else mainDir = SIGNAL_SELL;

   if(proposedDir == mainDir && m_positions[mainIdx].profit < 0.0)
   {
      PrintFormat("[PM-%s] SAME-DIR BLOCK: SPM %s == ANA %s, ANA P/L=$%.2f < 0 -> ENGELLENDI",
                  m_symbol,
                  (proposedDir == SIGNAL_BUY) ? "BUY" : "SELL",
                  (mainDir == SIGNAL_BUY) ? "BUY" : "SELL",
                  m_positions[mainIdx].profit);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| ShouldWaitForANARecovery - Trend Bekleme Mekanizmasi             |
//| Trend+Mum+MACD ANA yonune donuyorsa → BEKLE (max SPM_WaitMaxSec)|
//| ANA kara gecebilir, gereksiz SPM acmayi onler                   |
//+------------------------------------------------------------------+
bool CPositionManager::ShouldWaitForANARecovery(int mainIdx)
{
   if(mainIdx < 0) return false;

   ENUM_SIGNAL_DIR mainDir = SIGNAL_NONE;
   if(m_positions[mainIdx].type == POSITION_TYPE_BUY) mainDir = SIGNAL_BUY;
   else mainDir = SIGNAL_SELL;

   //--- Trend kontrolu
   ENUM_SIGNAL_DIR tDir = SIGNAL_NONE;
   if(m_signalEngine != NULL)
      tDir = m_signalEngine.GetCurrentTrend();

   //--- Mum kontrolu
   ENUM_SIGNAL_DIR cDir = GetCandleDirection();

   //--- MACD momentum kontrolu
   bool macdAligned = false;
   if(m_signalEngine != NULL)
   {
      double macdHist = m_signalEngine.GetMACDHist();
      if(mainDir == SIGNAL_BUY && macdHist > 0) macdAligned = true;
      if(mainDir == SIGNAL_SELL && macdHist < 0) macdAligned = true;
   }

   //--- UC UCU ANA yonune donuyorsa → BEKLE
   if(tDir == mainDir && cDir == mainDir && macdAligned)
   {
      if(!m_spmWaitActive)
      {
         m_spmWaitStart = TimeCurrent();
         m_spmWaitActive = true;
         PrintFormat("[PM-%s] SPM BEKLE: Trend+Mum+MACD ANA yonune donuyor. MaxBekle=%dsn",
                     m_symbol, SPM_WaitMaxSeconds);
      }

      if(TimeCurrent() - m_spmWaitStart < SPM_WaitMaxSeconds)
         return true;

      PrintFormat("[PM-%s] SPM BEKLE SURESI DOLDU (%dsn). ANA hala zararda, SPM aciliyor.",
                  m_symbol, SPM_WaitMaxSeconds);
      m_spmWaitActive = false;
      return false;
   }

   //--- Hizalanma yok → bekleme yok, SPM hemen ac
   m_spmWaitActive = false;
   return false;
}

//+------------------------------------------------------------------+
//| CheckFIFOTarget - FIFO net hedef kontrolu                        |
//| spm_karlari - |ana_zarar| >= +5$ -> ANA kapat                   |
//| AMA: Trend ANA yonune donuyorsa BEKLE                           |
//+------------------------------------------------------------------+
void CPositionManager::CheckFIFOTarget()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   double mainProfit = m_positions[mainIdx].profit;
   if(mainProfit >= 0.0) return;

   double mainLoss = MathAbs(mainProfit);

   double openSPMNet = 0.0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM)
         openSPMNet += m_positions[i].profit;

   double net = m_spmClosedProfitTotal + openSPMNet - mainLoss;

   // Hedef ulasilmadi
   if(net < SPM_NetTargetUSD)
   {
      m_fifoWaitStart = 0;
      return;
   }

   //--- HEDEF ULASILDI! Ama trend kontrolu yap
   PrintFormat("[PM-%s] FIFO HEDEF: Net=$%.2f >= $%.2f", m_symbol, net, SPM_NetTargetUSD);

   //--- Trend ANA yonune donuyor mu?
   ENUM_SIGNAL_DIR mainDir = SIGNAL_NONE;
   if(m_positions[mainIdx].type == POSITION_TYPE_BUY) mainDir = SIGNAL_BUY;
   else mainDir = SIGNAL_SELL;

   ENUM_SIGNAL_DIR trendDir = SIGNAL_NONE;
   if(m_signalEngine != NULL)
      trendDir = m_signalEngine.GetCurrentTrend();

   ENUM_SIGNAL_DIR candleDir = GetCandleDirection();

   //--- Trend ANA yonune donuyorsa -> BEKLE (ana kara gecsin)
   if(trendDir == mainDir && candleDir == mainDir)
   {
      if(m_fifoWaitStart == 0)
      {
         m_fifoWaitStart = TimeCurrent();
         PrintFormat("[PM-%s] FIFO BEKLE: Trend+Mum ANA yonune donuyor, ANA kara gecebilir. MaxBekle=300sn",
                     m_symbol);
      }

      // Max 5 dakika bekle
      if(TimeCurrent() - m_fifoWaitStart < 300)
         return;

      PrintFormat("[PM-%s] FIFO BEKLE SURESI DOLDU (300sn). Kapatiliyor.", m_symbol);
   }

   //--- Mum terse dondu VEYA bekleme suresi doldu -> KAPAT
   PrintFormat("[PM-%s] +++ FIFO HEDEF ULASILDI +++ Net=$%.2f", m_symbol, net);
   PrintFormat("[PM-%s] FIFO: ClosedSPM=$%.2f + OpenSPM=$%.2f - MainLoss=$%.2f = $%.2f",
               m_symbol, m_spmClosedProfitTotal, openSPMNet, mainLoss, net);

   // Bildirim
   CloseMainWithFIFONotification(mainIdx, m_spmClosedProfitTotal + openSPMNet, mainProfit, net);

   // Tum pozisyonlari kapat
   CloseAllPositions("FIFO_Net=" + DoubleToString(net, 2));

   m_totalCashedProfit += net;
   m_dailyProfit += net;

   // FIFO sifirla
   ResetFIFO();
   m_fifoWaitStart = 0;

   // Yeni ANA icin sinyal ara
   ENUM_SIGNAL_DIR newDir = SIGNAL_NONE;
   if(m_signalEngine != NULL)
   {
      SignalData sig = m_signalEngine.Evaluate();
      newDir = sig.direction;
   }
   if(newDir == SIGNAL_NONE)
      newDir = GetCandleDirection();

   if(newDir != SIGNAL_NONE)
      OpenNewMainTrade(newDir, "FIFO_YeniDongu");
   else
      PrintFormat("[PM-%s] FIFO dongu tamamlandi, sinyal bekleniyor.", m_symbol);
}

//+------------------------------------------------------------------+
//| CheckLotBalance - Lot denge kontrolu                             |
//| "Zarardaki lot > Kardaki lot OLMAMALI"                           |
//| "Tek tarafli lot kalmasindan kacinmak gerekiyor"                |
//+------------------------------------------------------------------+
bool CPositionManager::CheckLotBalance(ENUM_SIGNAL_DIR newDir, double newLot)
{
   double totalBuy = GetTotalBuyLots();
   double totalSell = GetTotalSellLots();

   double proposedBuy = totalBuy;
   double proposedSell = totalSell;

   if(newDir == SIGNAL_BUY)
      proposedBuy += newLot;
   else if(newDir == SIGNAL_SELL)
      proposedSell += newLot;

   //--- v1.3.0: Tek tarafli birikim korumasi
   // Sadece bir tarafta pozisyon varsa, o tarafin max hacmi sinirla
   double oneSideMax = MaxTotalVolume * 0.6;  // Tek taraf max = toplam hacmin %60'i
   if(proposedSell <= 0.0 && proposedBuy > oneSideMax)
   {
      PrintFormat("[PM-%s] TEK TARAF KORUMA: Sadece BUY=%.2f > %.2f (MaxVol*0.6)",
                  m_symbol, proposedBuy, oneSideMax);
      return false;
   }
   if(proposedBuy <= 0.0 && proposedSell > oneSideMax)
   {
      PrintFormat("[PM-%s] TEK TARAF KORUMA: Sadece SELL=%.2f > %.2f (MaxVol*0.6)",
                  m_symbol, proposedSell, oneSideMax);
      return false;
   }

   // 2.5:1 oran limiti - iki tarafli risk onleme
   if(proposedBuy > 0 && proposedSell > 0)
   {
      double ratio = MathMax(proposedBuy, proposedSell) / MathMin(proposedBuy, proposedSell);
      if(ratio > 2.5)
      {
         PrintFormat("[PM-%s] LOT DENGE UYARI: BUY=%.2f SELL=%.2f Oran=%.1f > 2.5",
                     m_symbol, proposedBuy, proposedSell, ratio);
         return false;
      }
   }

   // Toplam hacim kontrolu
   if(proposedBuy + proposedSell > MaxTotalVolume)
   {
      PrintFormat("[PM-%s] MAX HACIM: %.2f + %.2f = %.2f > %.2f",
                  m_symbol, proposedBuy, proposedSell,
                  proposedBuy + proposedSell, MaxTotalVolume);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| CalcSPMLot - Guclu hedge carpanli lot hesaplama (v1.3.0)         |
//| Layer 1: mainLot * 1.5  (SPM_LotBase)                           |
//| Layer 2: mainLot * 1.8  (+SPM_LotIncrement)                     |
//| Layer 3: mainLot * 2.1  (max SPM_LotCap=2.2)                    |
//+------------------------------------------------------------------+
double CPositionManager::CalcSPMLot(double mainLot, int layer)
{
   double multiplier = SPM_LotMultiplier + (layer - 1) * SPM_LotIncrement;
   if(multiplier > SPM_LotCap) multiplier = SPM_LotCap;  // v1.3.0: Max carpan siniri
   double lot = mainLot * multiplier;

   // ADX bonusu: guclu trend -> biraz daha buyuk lot
   if(m_signalEngine != NULL)
   {
      double adxVal = m_signalEngine.GetADX();
      if(adxVal > 30.0)
      {
         double adxBonus = 1.0 + (adxVal - 30.0) / 150.0;
         adxBonus = MathMin(adxBonus, 1.15);
         lot *= adxBonus;
      }
   }

   // Normalize
   double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| OpenNewMainTrade                                                  |
//+------------------------------------------------------------------+
void CPositionManager::OpenNewMainTrade(ENUM_SIGNAL_DIR dirHint, string reason)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;

   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel) return;

   // Yon onceligi: 1.Sinyal 2.Trend 3.Mum 4.Hint
   ENUM_SIGNAL_DIR finalDir = SIGNAL_NONE;

   if(m_signalEngine != NULL)
   {
      SignalData sig = m_signalEngine.Evaluate();
      if(sig.direction != SIGNAL_NONE && sig.score >= SignalMinScore)
         finalDir = sig.direction;
   }

   if(finalDir == SIGNAL_NONE && m_signalEngine != NULL)
   {
      ENUM_SIGNAL_DIR trendDir = m_signalEngine.GetCurrentTrend();
      if(trendDir != SIGNAL_NONE) finalDir = trendDir;
   }

   if(finalDir == SIGNAL_NONE)
      finalDir = GetCandleDirection();

   if(finalDir == SIGNAL_NONE)
      finalDir = dirHint;

   if(finalDir == SIGNAL_NONE) return;

   double lot = BaseLotPer1000 * (balance / 1000.0);
   double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > InputMaxLot) lot = InputMaxLot;
   lot = NormalizeDouble(lot, 2);

   string comment = StringFormat("BTFX_%s_%s", m_symbol, reason);
   if(StringLen(comment) > 25) comment = StringSubstr(comment, 0, 25);

   ulong newTicket = m_executor.OpenPosition(finalDir, lot, 0, 0, comment);

   if(newTicket > 0)
   {
      m_mainTicket = newTicket;
      m_spmLayerCount = 0;

      PrintFormat("[PM-%s] YENI ANA: #%d %s Lot=%.2f Sebep=%s",
                  m_symbol, (int)newTicket,
                  (finalDir == SIGNAL_BUY) ? "BUY" : "SELL", lot, reason);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("YENI ANA %s: %s #%d Lot=%.2f",
                                m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL", (int)newTicket, lot));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("YENI ANA %s: %s #%d Lot=%.2f",
                               m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL", (int)newTicket, lot));
   }
}

//+------------------------------------------------------------------+
//| OpenSPM - Yeni SPM ac                                            |
//+------------------------------------------------------------------+
void CPositionManager::OpenSPM(ENUM_SIGNAL_DIR dir, double lot, int layer, ulong parentTicket)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;
   if(m_executor == NULL) return;
   if(dir != SIGNAL_BUY && dir != SIGNAL_SELL) return;

   string comment = StringFormat("BTFX_SPM_%d_%d", layer, (int)parentTicket);
   if(StringLen(comment) > 25) comment = StringSubstr(comment, 0, 25);

   ulong newTicket = m_executor.OpenPosition(dir, lot, 0, 0, comment);

   if(newTicket > 0)
   {
      m_spmLayerCount = layer;
      m_lastSPMTime = TimeCurrent();
      m_spmLimitLogged = false;

      PrintFormat("[PM-%s] SPM%d ACILDI: #%d %s Lot=%.2f Parent=%d",
                  m_symbol, layer, (int)newTicket,
                  (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)parentTicket);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("SPM%d %s: %s Lot=%.2f #%d",
                                layer, m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)newTicket));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("SPM%d %s: %s Lot=%.2f #%d",
                               layer, m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)newTicket));
   }
   else
   {
      PrintFormat("[PM-%s] SPM%d HATA: %s Lot=%.2f Err=%d",
                  m_symbol, layer, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| PromoteOldestSPMToMain                                           |
//+------------------------------------------------------------------+
void CPositionManager::PromoteOldestSPMToMain(string reason)
{
   int bestIdx = -1;
   int bestLayer = 999;
   datetime bestTime = D'2099.01.01';

   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM) continue;
      int layer = m_positions[i].spmLayer;
      datetime openTime = m_positions[i].openTime;
      if(layer < bestLayer || (layer == bestLayer && openTime < bestTime))
      {
         bestIdx = i;
         bestLayer = layer;
         bestTime = openTime;
      }
   }

   if(bestIdx >= 0)
   {
      m_mainTicket = m_positions[bestIdx].ticket;
      m_positions[bestIdx].role = ROLE_MAIN;
      m_spmClosedProfitTotal = 0.0;
      m_spmClosedCount = 0;
      m_spmLayerCount = 0;
      m_spmLimitLogged = false;

      int maxLayer = 0;
      for(int i = 0; i < m_posCount; i++)
         if(m_positions[i].role == ROLE_SPM && m_positions[i].spmLayer > maxLayer)
            maxLayer = m_positions[i].spmLayer;
      m_spmLayerCount = maxLayer;

      PrintFormat("[PM-%s] TERFI: SPM%d (#%d) -> YENI ANA | Sebep=%s",
                  m_symbol, bestLayer, (int)m_mainTicket, reason);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("TERFI %s: SPM%d -> ANA #%d", m_symbol, bestLayer, (int)m_mainTicket));

      m_currentTPLevel = 0;
      m_tp1Hit = false;
      m_tp2Hit = false;
      m_tpExtended = false;
   }
   else
   {
      m_mainTicket = 0;
      PrintFormat("[PM-%s] TERFI: SPM yok, dongu tamamlandi. Sebep=%s", m_symbol, reason);
   }
}

//+------------------------------------------------------------------+
//| ManageTPLevels                                                    |
//+------------------------------------------------------------------+
void CPositionManager::ManageTPLevels()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;
   if(m_tp1Price == 0.0 && m_tp2Price == 0.0 && m_tp3Price == 0.0) return;

   double currentPrice = 0.0;
   if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
      currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   else
      currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   if(currentPrice <= 0.0) return;

   bool isBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);

   // TP1
   if(!m_tp1Hit && m_tp1Price > 0.0)
   {
      bool hit = isBuy ? (currentPrice >= m_tp1Price) : (currentPrice <= m_tp1Price);
      if(hit)
      {
         m_tp1Hit = true;
         m_currentTPLevel = 1;
         PrintFormat("[PM-%s] TP1 HIT: %.5f", m_symbol, currentPrice);
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP1 HIT %s: %.5f", m_symbol, currentPrice));
      }
   }

   // TP2
   if(m_tp1Hit && !m_tp2Hit && m_tp2Price > 0.0)
   {
      bool hit = isBuy ? (currentPrice >= m_tp2Price) : (currentPrice <= m_tp2Price);
      if(hit)
      {
         m_tp2Hit = true;
         m_currentTPLevel = 2;
         PrintFormat("[PM-%s] TP2 HIT: %.5f", m_symbol, currentPrice);
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP2 HIT %s: %.5f", m_symbol, currentPrice));
      }
   }

   // TP3
   if(m_tp2Hit && m_tp3Price > 0.0 && !m_tpExtended)
   {
      bool hit = isBuy ? (currentPrice >= m_tp3Price) : (currentPrice <= m_tp3Price);
      if(hit)
      {
         m_tpExtended = true;
         m_currentTPLevel = 3;
         PrintFormat("[PM-%s] TP3 HIT: %.5f EXTENDED", m_symbol, currentPrice);

         if(m_trendStrength < TREND_STRONG)
         {
            ClosePosWithNotification(mainIdx, "TP3_Kapat");
            m_mainTicket = 0;
            PromoteOldestSPMToMain("MainTP3");
         }

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP3 HIT %s: %.5f", m_symbol, currentPrice));
         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("TP3 HIT %s: %.5f", m_symbol, currentPrice));
      }
   }
}

//+------------------------------------------------------------------+
//| GetCandleDirection                                                |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::GetCandleDirection()
{
   double open1  = iOpen(m_symbol, PERIOD_M15, 1);
   double close1 = iClose(m_symbol, PERIOD_M15, 1);
   if(close1 > open1) return SIGNAL_BUY;
   if(close1 < open1) return SIGNAL_SELL;
   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| GetTotalBuyLots / GetTotalSellLots                                |
//+------------------------------------------------------------------+
double CPositionManager::GetTotalBuyLots()
{
   double total = 0.0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].type == POSITION_TYPE_BUY)
         total += m_positions[i].volume;
   return total;
}

double CPositionManager::GetTotalSellLots()
{
   double total = 0.0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].type == POSITION_TYPE_SELL)
         total += m_positions[i].volume;
   return total;
}

//+------------------------------------------------------------------+
//| PrintDetailedStatus                                               |
//+------------------------------------------------------------------+
void CPositionManager::PrintDetailedStatus()
{
   if(TimeCurrent() - m_lastStatusLog < 30) return;
   m_lastStatusLog = TimeCurrent();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   PrintFormat("============================================================");
   PrintFormat("[PM-%s] DURUM @ %s", m_symbol, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   PrintFormat("[PM-%s] Bakiye=$%.2f | Varlik=$%.2f | Margin=%.1f%%",
               m_symbol, balance, equity, marginLevel);
   PrintFormat("[PM-%s] Pozisyon=%d | Ana=#%d | SPM=%d | Kasa=$%.2f",
               m_symbol, m_posCount, (int)m_mainTicket, m_spmLayerCount, m_totalCashedProfit);
   PrintFormat("[PM-%s] FIFO: KapaliKar=$%.2f | Sayi=%d | Hedef=$%.2f",
               m_symbol, m_spmClosedProfitTotal, m_spmClosedCount, SPM_NetTargetUSD);

   double totalPL = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      string roleStr = (m_positions[i].role == ROLE_MAIN) ? "ANA" :
                        StringFormat("SPM%d", m_positions[i].spmLayer);
      string typeStr = (m_positions[i].type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double peak = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : 0.0;

      PrintFormat("[PM-%s] [%s] #%d %s Vol=%.2f P/L=$%.2f Peak=$%.2f",
                  m_symbol, roleStr, (int)m_positions[i].ticket,
                  typeStr, m_positions[i].volume, m_positions[i].profit, peak);
      totalPL += m_positions[i].profit;
   }

   PrintFormat("[PM-%s] Toplam Acik P/L=$%.2f | Buy=%.2f lot | Sell=%.2f lot",
               m_symbol, totalPL, GetTotalBuyLots(), GetTotalSellLots());

   int mainIdx = FindMainPosition();
   if(mainIdx >= 0 && m_positions[mainIdx].profit < 0.0)
   {
      double mainLoss = MathAbs(m_positions[mainIdx].profit);
      double openSPM = 0.0;
      for(int i = 0; i < m_posCount; i++)
         if(m_positions[i].role == ROLE_SPM) openSPM += m_positions[i].profit;
      double net = m_spmClosedProfitTotal + openSPM - mainLoss;
      PrintFormat("[PM-%s] FIFO: KapaliSPM($%.2f) + AcikSPM($%.2f) - AnaZarar($%.2f) = Net($%.2f) / Hedef($%.2f)",
                  m_symbol, m_spmClosedProfitTotal, openSPM, mainLoss, net, SPM_NetTargetUSD);
   }

   if(m_tradingPaused)
   {
      int remaining = (int)(m_protectionCooldownUntil - TimeCurrent());
      PrintFormat("[PM-%s] KORUMA: Durduruldu | Kalan=%dsn | Tetik=%d",
                  m_symbol, MathMax(remaining, 0), m_protectionTriggerCount);
   }
   PrintFormat("============================================================");
}

//+------------------------------------------------------------------+
//| FindMainPosition                                                  |
//+------------------------------------------------------------------+
int CPositionManager::FindMainPosition()
{
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_MAIN) return i;

   if(m_mainTicket > 0)
      for(int i = 0; i < m_posCount; i++)
         if(m_positions[i].ticket == m_mainTicket)
         {
            m_positions[i].role = ROLE_MAIN;
            return i;
         }
   return -1;
}

//+------------------------------------------------------------------+
//| GetActiveSPMCount                                                 |
//+------------------------------------------------------------------+
int CPositionManager::GetActiveSPMCount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM) count++;
   return count;
}

//+------------------------------------------------------------------+
//| GetHighestLayer                                                   |
//+------------------------------------------------------------------+
int CPositionManager::GetHighestLayer()
{
   int highest = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM && m_positions[i].spmLayer > highest)
         highest = m_positions[i].spmLayer;
   return highest;
}

//+------------------------------------------------------------------+
//| ClosePosWithNotification                                          |
//+------------------------------------------------------------------+
void CPositionManager::ClosePosWithNotification(int idx, string reason)
{
   if(idx < 0 || idx >= m_posCount) return;

   ulong ticket = m_positions[idx].ticket;
   double profit = m_positions[idx].profit;
   double volume = m_positions[idx].volume;
   string roleStr = (m_positions[idx].role == ROLE_MAIN) ? "ANA" :
                     StringFormat("SPM%d", m_positions[idx].spmLayer);
   string typeStr = (m_positions[idx].type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   bool closed = false;
   if(m_executor != NULL)
      closed = m_executor.ClosePosition(ticket);

   if(closed)
   {
      m_dailyProfit += profit;
      PrintFormat("[PM-%s] KAPANDI: %s #%d %s Vol=%.2f P/L=$%.2f Sebep=%s",
                  m_symbol, roleStr, (int)ticket, typeStr, volume, profit, reason);

      string msg = StringFormat("KAPAT %s %s #%d %s $%.2f %s",
                                m_symbol, roleStr, (int)ticket, typeStr, profit, reason);
      if(m_telegram != NULL) m_telegram.SendMessage(msg);
      if(m_discord != NULL)  m_discord.SendMessage(msg);

      if(idx < ArraySize(m_peakProfit))
         m_peakProfit[idx] = 0.0;
   }
   else
   {
      PrintFormat("[PM-%s] KAPAMA HATASI: %s #%d Err=%d", m_symbol, roleStr, (int)ticket, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| CloseMainWithFIFONotification                                     |
//+------------------------------------------------------------------+
void CPositionManager::CloseMainWithFIFONotification(int mainIdx, double spmKar, double mainZarar, double net)
{
   if(mainIdx < 0 || mainIdx >= m_posCount) return;

   string msg = StringFormat("FIFO HEDEF %s: SPM=$%.2f Ana=$%.2f Net=$%.2f >= $%.2f | Kapat=%d | Katman=%d",
      m_symbol, spmKar, mainZarar, net, SPM_NetTargetUSD, m_spmClosedCount, m_spmLayerCount);

   PrintFormat("[PM-%s] %s", m_symbol, msg);
   if(m_telegram != NULL) m_telegram.SendMessage(msg);
   if(m_discord != NULL)  m_discord.SendMessage(msg);
}

//+------------------------------------------------------------------+
//| GetCatName                                                        |
//+------------------------------------------------------------------+
string CPositionManager::GetCatName()
{
   switch(m_category)
   {
      case CAT_FOREX:   return "FOREX";
      case CAT_CRYPTO:  return "CRYPTO";
      case CAT_METAL:   return "METAL";
      case CAT_INDICES: return "INDEX";
      case CAT_ENERGY:  return "ENERGY";
      case CAT_STOCKS:  return "STOCK";
      default:          return "?";
   }
}

//+------------------------------------------------------------------+
//| ResetFIFO                                                         |
//+------------------------------------------------------------------+
void CPositionManager::ResetFIFO()
{
   PrintFormat("[PM-%s] FIFO RESET: Kar=$%.2f Sayi=%d Katman=%d",
               m_symbol, m_spmClosedProfitTotal, m_spmClosedCount, m_spmLayerCount);
   m_spmClosedProfitTotal = 0.0;
   m_spmClosedCount       = 0;
   m_spmLayerCount        = 0;
   m_spmLimitLogged       = false;
   ArrayInitialize(m_peakProfit, 0.0);
   m_currentTPLevel = 0;
   m_tp1Hit = false;
   m_tp2Hit = false;
   m_tpExtended = false;
}

//+------------------------------------------------------------------+
//| CloseAllPositions                                                 |
//+------------------------------------------------------------------+
void CPositionManager::CloseAllPositions(string reason)
{
   PrintFormat("[PM-%s] === TUM KAPAT === Sebep=%s Sayi=%d", m_symbol, reason, m_posCount);

   for(int i = m_posCount - 1; i >= 0; i--)
   {
      ulong ticket = m_positions[i].ticket;
      if(m_executor != NULL)
      {
         bool closed = m_executor.ClosePosition(ticket);
         if(closed)
         {
            m_dailyProfit += m_positions[i].profit;
         }
         else
         {
            Sleep(500);
            m_executor.ClosePosition(ticket);
         }
      }
   }

   m_mainTicket = 0;
   m_posCount = 0;

   string msg = StringFormat("TUM KAPAT %s: %s | GunlukP/L=$%.2f | Kasa=$%.2f",
                             m_symbol, reason, m_dailyProfit, m_totalCashedProfit);
   if(m_telegram != NULL) m_telegram.SendMessage(msg);
   if(m_discord != NULL)  m_discord.SendMessage(msg);
}

//+------------------------------------------------------------------+
//| SetProtectionCooldown                                             |
//+------------------------------------------------------------------+
void CPositionManager::SetProtectionCooldown(string reason)
{
   m_protectionTriggerCount++;
   int mult = MathMin(m_protectionTriggerCount, 5);
   int total = ProtectionCooldownSec * mult;
   m_protectionCooldownUntil = TimeCurrent() + total;
   m_tradingPaused = true;

   PrintFormat("[PM-%s] KORUMA: %s | Bekleme=%dsn (tetik #%d x%d)",
               m_symbol, reason, total, m_protectionTriggerCount, mult);
}

#endif // POSITION_MANAGER_MQH
