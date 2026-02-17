#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH
//+------------------------------------------------------------------+
//|                                             PositionManager.mqh  |
//|                                    Copyright 2026, By T@MER      |
//|                                    https://www.bytamer.com        |
//|                                                                  |
//|              SPM + FIFO SISTEMI (Version: Config.mqh EA_VERSION) |
//+------------------------------------------------------------------+
//|  KURALLAR:                                                       |
//|  1. SL YOK - ASLA                                                |
//|  2. Ana islem zarara gecti (-$3) -> SPM1 ac (ters yon)           |
//|  3. SPM1 zarara gecti (-$3) -> SPM2 ac (SPM1 tersi)             |
//|  4. SPM karda (+$2) -> KAPAT, FIFO'ya ekle                      |
//|  5. FIFO: Kapatilan SPM karlari toplanir                         |
//|  6. SPM_Toplam_Kar - |Ana_Zarar| >= +$5 -> ANA kapatilir        |
//|  7. Ana kapandiysa en eski SPM yeni ANA olur, FIFO sifirlanir   |
//|  8. Yeni ANA: Sinyal->Trend->Mum->Hint onceligi                 |
//|  9. SPM tetik: Cooldown tek engel, mum bekleme YOK              |
//+------------------------------------------------------------------+

#include "Config.mqh"
#include "TradeExecutor.mqh"
#include "SignalEngine.mqh"
#include "CandleAnalyzer.mqh"
#include "TelegramMsg.mqh"
#include "DiscordMsg.mqh"

//+------------------------------------------------------------------+
//| CPositionManager - SPM + FIFO Position Management Engine         |
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
   PositionInfo         m_positions[];       // size MAX_POSITIONS
   int                  m_posCount;

   //--- SPM / FIFO tracking
   int                  m_spmLayerCount;
   double               m_spmClosedProfitTotal;   // Closed SPM profit accumulator
   int                  m_spmClosedCount;

   //--- Candle analysis
   CCandleAnalyzer      m_candle;

   //--- Timing
   datetime             m_lastSPMTime;
   datetime             m_lastStatusLog;
   datetime             m_lastDashLog;

   //--- TP management
   bool                 m_tpExtended;
   int                  m_currentTPLevel;
   double               m_tp1Price, m_tp2Price, m_tp3Price;
   bool                 m_tp1Hit, m_tp2Hit;
   ENUM_TREND_STRENGTH  m_trendStrength;

   //--- Peak profit tracking per position
   double               m_peakProfit[];

   //--- Adoption / main ticket
   bool                 m_adoptionDone;
   ulong                m_mainTicket;

   //--- v1.0 Protection
   double               m_startBalance;
   double               m_dailyProfit;
   datetime             m_dailyResetTime;
   bool                 m_spmLimitLogged;
   datetime             m_protectionCooldownUntil;
   int                  m_protectionTriggerCount;
   bool                 m_tradingPaused;

   //--- Private methods: Position Scanning
   void                 AdoptExistingPositions();
   void                 RefreshPositions();

   //--- Private methods: Protection
   bool                 CheckEquityProtection();
   bool                 CheckCycleLossLimit();
   bool                 CheckMarginEmergency();

   //--- Private methods: Profit Management
   void                 ManageProfitablePositions(bool newBar);

   //--- Private methods: SPM System
   void                 ManageSPMSystem();
   void                 ManageMainInLoss(int mainIdx, double mainProfit);
   void                 ManageActiveSPMs(int mainIdx);

   //--- Private methods: FIFO
   void                 CheckFIFOTarget();

   //--- Private methods: Trade Execution
   void                 OpenNewMainTrade(ENUM_SIGNAL_DIR dirHint, string reason);
   void                 OpenSPM(ENUM_SIGNAL_DIR dir, double lot, int layer, ulong parentTicket);

   //--- Private methods: Promotion
   void                 PromoteOldestSPMToMain(string reason);

   //--- Private methods: TP Levels
   void                 ManageTPLevels();

   //--- Private methods: Lot Calculation
   double               CalcSPMLot(double mainLot, int layer);

   //--- Private methods: Candle Direction
   ENUM_SIGNAL_DIR      GetCandleDirection();

   //--- Private methods: Logging
   void                 PrintDetailedStatus();

   //--- Private helpers
   int                  FindMainPosition();
   int                  GetActiveSPMCount();
   int                  GetHighestLayer();

   //--- Notification helpers
   void                 ClosePosWithNotification(int idx, string reason);
   void                 CloseMainWithFIFONotification(int mainIdx, double spmKar, double mainZarar, double net);

   //--- Category helper
   string               GetCatName();

   //--- Reset helpers
   void                 ResetFIFO();
   void                 CloseAllPositions(string reason);
   void                 SetProtectionCooldown(string reason);

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
//| Constructor - Initialize all members to zero/false/NULL          |
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

   m_lastSPMTime         = 0;
   m_lastStatusLog       = 0;
   m_lastDashLog         = 0;

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
//| Initialize - Wire dependencies and configure                     |
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

   //--- Initialize candle analyzer on M15 timeframe
   m_candle.Initialize(m_symbol, PERIOD_M15);

   PrintFormat("[PM-%s] PositionManager Initialize | Cat=%s | Balance=%.2f | SPM_Trigger=%.2f | SPM_Close=%.2f | SPM_Net=%.2f | MaxLayers=%d",
               m_symbol, GetCatName(), m_startBalance,
               SPM_TriggerLossUSD, SPM_CloseProfitUSD, SPM_NetTargetUSD, SPM_MaxLayers);

   PrintFormat("[PM-%s] Protection: MaxDD=%.1f%% | CycleLoss=%.2f | MinBalance=%.2f | Cooldown=%ds",
               m_symbol, MaxDrawdownPercent, MaxCycleLossUSD, MinBalanceToTrade, ProtectionCooldownSec);

   //--- Adopt any existing positions from prior run
   AdoptExistingPositions();
}

//+------------------------------------------------------------------+
//| OnTick - Main tick processing loop                               |
//+------------------------------------------------------------------+
void CPositionManager::OnTick()
{
   //--- Step 1: Refresh position data
   RefreshPositions();

   //--- Step 2: Handle zero positions
   if(m_posCount == 0)
   {
      //--- Reset FIFO if there was accumulated data
      if(m_spmClosedProfitTotal != 0.0 || m_spmClosedCount > 0)
      {
         PrintFormat("[PM-%s] No positions open, resetting FIFO (was: Profit=%.2f, Count=%d)",
                     m_symbol, m_spmClosedProfitTotal, m_spmClosedCount);
         ResetFIFO();
      }

      //--- Check if cooldown expired
      if(m_tradingPaused)
      {
         if(TimeCurrent() >= m_protectionCooldownUntil)
         {
            m_tradingPaused = false;
            PrintFormat("[PM-%s] Protection cooldown expired. Trading resumed.", m_symbol);
         }
      }
      return;
   }

   //--- Step 3-5: Protection checks (any true = abort tick)
   if(CheckEquityProtection())
      return;

   if(CheckCycleLossLimit())
      return;

   if(CheckMarginEmergency())
      return;

   //--- Step 6: Check for new bar
   bool newBar = m_candle.CheckNewBar();

   //--- Step 7: Manage profitable positions
   ManageProfitablePositions(newBar);

   //--- Step 8: Manage SPM system (hedging/layering)
   ManageSPMSystem();

   //--- Step 9: Check FIFO net target
   CheckFIFOTarget();

   //--- Step 10: Manage TP levels
   ManageTPLevels();

   //--- Step 11: Periodic status logging (every 30 seconds)
   PrintDetailedStatus();
}

//+------------------------------------------------------------------+
//| HasPosition - Check if any positions are open                    |
//+------------------------------------------------------------------+
bool CPositionManager::HasPosition() const
{
   return (m_posCount > 0);
}

//+------------------------------------------------------------------+
//| IsTradingPaused - Check if protection cooldown is active         |
//+------------------------------------------------------------------+
bool CPositionManager::IsTradingPaused() const
{
   return (m_tradingPaused && TimeCurrent() < m_protectionCooldownUntil);
}

//+------------------------------------------------------------------+
//| HasHedge - Check if any SPM position exists                      |
//+------------------------------------------------------------------+
bool CPositionManager::HasHedge() const
{
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| GetSPMCount - Count active SPM positions                         |
//+------------------------------------------------------------------+
int CPositionManager::GetSPMCount() const
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| GetCandleAnalyzer - Return pointer to candle analyzer            |
//+------------------------------------------------------------------+
CCandleAnalyzer* CPositionManager::GetCandleAnalyzer()
{
   return GetPointer(m_candle);
}

//+------------------------------------------------------------------+
//| GetFIFOSummary - Build summary struct for dashboard              |
//+------------------------------------------------------------------+
FIFOSummary CPositionManager::GetFIFOSummary()
{
   FIFOSummary summary;
   summary.closedProfitTotal   = m_spmClosedProfitTotal;
   summary.closedCount         = m_spmClosedCount;
   summary.activeSPMCount      = GetActiveSPMCount();
   summary.spmLayerCount       = m_spmLayerCount;

   //--- Calculate open SPM profit
   double openSPMProfit = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
         openSPMProfit += m_positions[i].profit;
   }
   summary.openSPMProfit = openSPMProfit;

   //--- Calculate main loss
   int mainIdx = FindMainPosition();
   summary.mainLoss = (mainIdx >= 0) ? m_positions[mainIdx].profit : 0.0;

   //--- Net calculation
   summary.netResult = m_spmClosedProfitTotal + openSPMProfit;
   if(mainIdx >= 0 && m_positions[mainIdx].profit < 0.0)
      summary.netResult -= MathAbs(m_positions[mainIdx].profit);

   summary.targetUSD   = SPM_NetTargetUSD;
   summary.isProfitable = (summary.netResult >= SPM_NetTargetUSD);

   return summary;
}

//+------------------------------------------------------------------+
//| GetTPInfo - Return current TP level information                  |
//+------------------------------------------------------------------+
TPLevelInfo CPositionManager::GetTPInfo() const
{
   TPLevelInfo info;
   info.currentLevel   = m_currentTPLevel;
   info.tp1Price       = m_tp1Price;
   info.tp2Price       = m_tp2Price;
   info.tp3Price       = m_tp3Price;
   info.tp1Hit         = m_tp1Hit;
   info.tp2Hit         = m_tp2Hit;
   info.tpExtended     = m_tpExtended;
   info.trendStrength  = m_trendStrength;
   return info;
}

//+------------------------------------------------------------------+
//| SetTPTracking - Configure TP levels and trend strength           |
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

   PrintFormat("[PM-%s] TP Tracking Set: TP1=%.5f TP2=%.5f TP3=%.5f Strength=%d",
               m_symbol, tp1, tp2, tp3, (int)strength);
}

//+------------------------------------------------------------------+
//| AdoptExistingPositions - Find positions from prior EA run        |
//+------------------------------------------------------------------+
void CPositionManager::AdoptExistingPositions()
{
   if(m_adoptionDone)
      return;

   m_adoptionDone = true;

   int totalAdopted  = 0;
   int spmAdopted    = 0;
   ulong oldestNonSPM = 0;
   datetime oldestTime = D'2099.01.01';

   int totalPositions = PositionsTotal();

   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      //--- Check symbol match
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         continue;

      //--- Check magic number match
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != EA_MAGIC)
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      //--- Detect SPM by comment pattern: BTFX_SPM_X_Y
      bool isSPM = false;
      int spmLayer = 0;

      if(StringFind(comment, "BTFX_SPM_") >= 0)
      {
         isSPM = true;

         //--- Parse layer number from comment
         int spmPos = StringFind(comment, "BTFX_SPM_");
         if(spmPos >= 0)
         {
            string layerStr = StringSubstr(comment, spmPos + 9, 1);
            spmLayer = (int)StringToInteger(layerStr);
            if(spmLayer <= 0) spmLayer = 1;
         }
         spmAdopted++;
      }
      else
      {
         //--- Non-SPM: track oldest as potential MAIN
         if(openTime < oldestTime)
         {
            oldestTime = openTime;
            oldestNonSPM = ticket;
         }
      }

      totalAdopted++;
   }

   //--- Set the MAIN ticket
   if(oldestNonSPM > 0)
   {
      m_mainTicket = oldestNonSPM;
      PrintFormat("[PM-%s] ADOPT: Main ticket=%d (oldest non-SPM, opened %s)",
                  m_symbol, (int)m_mainTicket, TimeToString(oldestTime));
   }
   else if(totalAdopted > 0)
   {
      //--- All positions are SPM - oldest SPM becomes MAIN
      datetime spmOldest = D'2099.01.01';
      ulong spmOldestTicket = 0;

      for(int i = 0; i < totalPositions; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != EA_MAGIC) continue;

         datetime t = (datetime)PositionGetInteger(POSITION_TIME);
         if(t < spmOldest)
         {
            spmOldest = t;
            spmOldestTicket = ticket;
         }
      }

      if(spmOldestTicket > 0)
      {
         m_mainTicket = spmOldestTicket;
         PrintFormat("[PM-%s] ADOPT: Oldest SPM promoted to MAIN ticket=%d", m_symbol, (int)m_mainTicket);
      }
   }

   if(totalAdopted > 0)
   {
      m_spmLayerCount = spmAdopted;
      PrintFormat("[PM-%s] ADOPT: Total=%d positions (SPM=%d, Main=%d)",
                  m_symbol, totalAdopted, spmAdopted, (int)m_mainTicket);
   }
   else
   {
      PrintFormat("[PM-%s] ADOPT: No existing positions found for adoption", m_symbol);
   }
}

//+------------------------------------------------------------------+
//| RefreshPositions - Scan all open positions and update arrays      |
//+------------------------------------------------------------------+
void CPositionManager::RefreshPositions()
{
   m_posCount = 0;
   int totalPositions = PositionsTotal();

   //--- Reset daily profit tracking at new day
   datetime today = iTime(m_symbol, PERIOD_D1, 0);
   if(today != m_dailyResetTime)
   {
      m_dailyResetTime = today;
      m_dailyProfit = 0.0;
      m_spmLimitLogged = false;
      PrintFormat("[PM-%s] Daily reset - new trading day", m_symbol);
   }

   for(int i = 0; i < totalPositions && m_posCount < MAX_POSITIONS; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      //--- Check symbol and magic
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != EA_MAGIC)
         continue;

      //--- Fill position info
      int idx = m_posCount;

      m_positions[idx].ticket    = ticket;
      m_positions[idx].symbol    = m_symbol;
      m_positions[idx].type      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      m_positions[idx].volume    = PositionGetDouble(POSITION_VOLUME);
      m_positions[idx].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      m_positions[idx].openTime  = (datetime)PositionGetInteger(POSITION_TIME);
      m_positions[idx].profit    = PositionGetDouble(POSITION_PROFIT) +
                                   PositionGetDouble(POSITION_SWAP);
      m_positions[idx].comment   = PositionGetString(POSITION_COMMENT);
      m_positions[idx].sl        = 0;  // SL YOK - ASLA
      m_positions[idx].tp        = PositionGetDouble(POSITION_TP);

      //--- Determine role
      string comment = m_positions[idx].comment;

      if(ticket == m_mainTicket)
      {
         m_positions[idx].role = ROLE_MAIN;
      }
      else if(StringFind(comment, "BTFX_SPM_") >= 0)
      {
         m_positions[idx].role = ROLE_SPM;

         //--- Parse layer
         int spmPos = StringFind(comment, "BTFX_SPM_");
         if(spmPos >= 0)
         {
            string layerStr = StringSubstr(comment, spmPos + 9, 1);
            m_positions[idx].spmLayer = (int)StringToInteger(layerStr);
            if(m_positions[idx].spmLayer <= 0)
               m_positions[idx].spmLayer = 1;
         }
      }
      else if(m_mainTicket == 0 && m_posCount == 0)
      {
         //--- First found position with no main ticket set = MAIN
         m_positions[idx].role = ROLE_MAIN;
         m_mainTicket = ticket;
      }
      else
      {
         m_positions[idx].role = ROLE_SPM;
         m_positions[idx].spmLayer = 1;
      }

      //--- Peak profit tracking
      if(idx < ArraySize(m_peakProfit))
      {
         if(m_positions[idx].profit > m_peakProfit[idx])
            m_peakProfit[idx] = m_positions[idx].profit;
      }

      m_posCount++;
   }
}

//+------------------------------------------------------------------+
//| CheckEquityProtection - Emergency drawdown protection            |
//+------------------------------------------------------------------+
bool CPositionManager::CheckEquityProtection()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(balance <= 0.0)
      return false;

   double ddPercent = (balance - equity) / balance * 100.0;

   if(ddPercent >= MaxDrawdownPercent)
   {
      PrintFormat("[PM-%s] !!! EQUITY PROTECTION TRIGGERED !!! DD=%.2f%% >= %.2f%% | Balance=%.2f | Equity=%.2f",
                  m_symbol, ddPercent, MaxDrawdownPercent, balance, equity);

      //--- Send alert notifications
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("EQUITY PROTECTION %s: DD=%.1f%% Balance=%.2f Equity=%.2f - ALL CLOSED",
                                             m_symbol, ddPercent, balance, equity));

      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("EQUITY PROTECTION %s: DD=%.1f%% Balance=%.2f Equity=%.2f - ALL CLOSED",
                                            m_symbol, ddPercent, balance, equity));

      //--- Close everything
      CloseAllPositions("EquityProtection_DD=" + DoubleToString(ddPercent, 1) + "%");

      //--- Increment trigger count and set cooldown
      m_protectionTriggerCount++;
      int cooldownMultiplier = MathMin(m_protectionTriggerCount, 6);
      int totalCooldown = ProtectionCooldownSec * cooldownMultiplier;

      m_protectionCooldownUntil = TimeCurrent() + totalCooldown;
      m_tradingPaused = true;

      PrintFormat("[PM-%s] Protection cooldown: %d seconds (trigger #%d, multiplier x%d)",
                  m_symbol, totalCooldown, m_protectionTriggerCount, cooldownMultiplier);

      //--- Reset FIFO
      ResetFIFO();

      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| CheckCycleLossLimit - Check if cycle has exceeded max loss        |
//+------------------------------------------------------------------+
bool CPositionManager::CheckCycleLossLimit()
{
   //--- Calculate total open P/L
   double totalOpenPL = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      totalOpenPL += m_positions[i].profit;
   }

   //--- Cycle loss = closed SPM profit + open P/L
   double cycleLoss = m_spmClosedProfitTotal + totalOpenPL;

   if(cycleLoss <= MaxCycleLossUSD)
   {
      PrintFormat("[PM-%s] !!! CYCLE LOSS LIMIT !!! CycleLoss=%.2f <= %.2f | SPM_Closed=%.2f | OpenPL=%.2f",
                  m_symbol, cycleLoss, MaxCycleLossUSD, m_spmClosedProfitTotal, totalOpenPL);

      //--- Notify
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("CYCLE LOSS %s: %.2f <= %.2f - ALL CLOSED",
                                             m_symbol, cycleLoss, MaxCycleLossUSD));

      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("CYCLE LOSS %s: %.2f <= %.2f - ALL CLOSED",
                                            m_symbol, cycleLoss, MaxCycleLossUSD));

      //--- Close everything
      CloseAllPositions("CycleLossLimit=" + DoubleToString(cycleLoss, 2));

      //--- Set cooldown
      SetProtectionCooldown("CycleLossLimit");

      //--- Reset FIFO
      ResetFIFO();

      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| CheckMarginEmergency - Emergency margin level check              |
//+------------------------------------------------------------------+
bool CPositionManager::CheckMarginEmergency()
{
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   //--- If no positions, margin level is 0 - skip
   if(marginLevel == 0.0)
      return false;

   if(marginLevel < 150.0)
   {
      PrintFormat("[PM-%s] !!! MARGIN EMERGENCY !!! MarginLevel=%.2f%% < 150%% | Equity=%.2f | Margin=%.2f",
                  m_symbol, marginLevel,
                  AccountInfoDouble(ACCOUNT_EQUITY),
                  AccountInfoDouble(ACCOUNT_MARGIN));

      //--- Notify
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("MARGIN EMERGENCY %s: Level=%.1f%% - ALL CLOSED",
                                             m_symbol, marginLevel));

      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("MARGIN EMERGENCY %s: Level=%.1f%% - ALL CLOSED",
                                            m_symbol, marginLevel));

      //--- Close everything
      CloseAllPositions("MarginEmergency_Level=" + DoubleToString(marginLevel, 1) + "%");

      //--- Set cooldown
      SetProtectionCooldown("MarginEmergency");

      //--- Reset FIFO
      ResetFIFO();

      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| ManageProfitablePositions - Handle positions with profit > 0     |
//+------------------------------------------------------------------+
void CPositionManager::ManageProfitablePositions(bool newBar)
{
   //--- We iterate in reverse to safely close positions
   for(int i = m_posCount - 1; i >= 0; i--)
   {
      double profit = m_positions[i].profit;
      if(profit <= 0.0)
         continue;

      ulong ticket = m_positions[i].ticket;
      ENUM_POS_ROLE role = m_positions[i].role;

      //--- Update peak profit tracking
      if(i < ArraySize(m_peakProfit))
      {
         if(profit > m_peakProfit[i])
            m_peakProfit[i] = profit;
      }

      double peakVal = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : profit;

      //--- Quick Profit: If profit >= QuickProfitUSD and candle turning against
      if(profit >= QuickProfitUSD)
      {
         ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
         bool candleAgainst = false;

         if(m_positions[i].type == POSITION_TYPE_BUY && candleDir == SIGNAL_SELL)
            candleAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && candleDir == SIGNAL_BUY)
            candleAgainst = true;

         if(candleAgainst)
         {
            PrintFormat("[PM-%s] QuickProfit: Ticket=%d Profit=%.2f >= %.2f + candle against -> CLOSE",
                        m_symbol, (int)ticket, profit, QuickProfitUSD);

            if(role == ROLE_SPM)
            {
               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
               PrintFormat("[PM-%s] FIFO: SPM closed profit added %.2f -> Total=%.2f (Count=%d)",
                           m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount);
            }

            ClosePosWithNotification(i, "QuickProfit_CandleAgainst");

            if(role == ROLE_MAIN)
            {
               m_mainTicket = 0;
               PromoteOldestSPMToMain("MainClosedQuickProfit");
            }
            continue;
         }
      }

      //--- SPM Net Target: Unconditional close if >= SPM_NetTargetUSD
      if(profit >= SPM_NetTargetUSD)
      {
         PrintFormat("[PM-%s] NetTarget: Ticket=%d Profit=%.2f >= %.2f -> CLOSE",
                     m_symbol, (int)ticket, profit, SPM_NetTargetUSD);

         if(role == ROLE_SPM)
         {
            m_spmClosedProfitTotal += profit;
            m_spmClosedCount++;
            PrintFormat("[PM-%s] FIFO: SPM closed profit added %.2f -> Total=%.2f (Count=%d)",
                        m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount);
         }

         ClosePosWithNotification(i, "NetTargetHit");

         if(role == ROLE_MAIN)
         {
            m_mainTicket = 0;
            PromoteOldestSPMToMain("MainClosedNetTarget");
         }
         continue;
      }

      //--- Peak drop >= 40%: Lock profit before it evaporates
      if(peakVal > 0.5 && profit > 0.0)
      {
         double dropPercent = (peakVal - profit) / peakVal * 100.0;
         if(dropPercent >= 40.0)
         {
            PrintFormat("[PM-%s] PeakDrop: Ticket=%d Peak=%.2f Current=%.2f Drop=%.1f%% >= 40%% -> CLOSE",
                        m_symbol, (int)ticket, peakVal, profit, dropPercent);

            if(role == ROLE_SPM)
            {
               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
               PrintFormat("[PM-%s] FIFO: SPM closed profit added %.2f -> Total=%.2f (Count=%d)",
                           m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount);
            }

            ClosePosWithNotification(i, StringFormat("PeakDrop_%.0f%%", dropPercent));

            if(role == ROLE_MAIN)
            {
               m_mainTicket = 0;
               PromoteOldestSPMToMain("MainClosedPeakDrop");
            }
            continue;
         }
      }

      //--- Engulfing/Reversal detection on new bar only
      if(newBar && profit >= 0.50)
      {
         bool engulfingDetected = false;

         int engulfPattern = m_candle.DetectEngulfing();
         if(m_positions[i].type == POSITION_TYPE_BUY && engulfPattern == -1)
         {
            engulfingDetected = true;  // Bearish engulfing against BUY
         }
         else if(m_positions[i].type == POSITION_TYPE_SELL && engulfPattern == +1)
         {
            engulfingDetected = true;  // Bullish engulfing against SELL
         }

         if(engulfingDetected)
         {
            PrintFormat("[PM-%s] EngulfingReversal: Ticket=%d Profit=%.2f -> CLOSE on reversal candle",
                        m_symbol, (int)ticket, profit);

            if(role == ROLE_SPM)
            {
               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
               PrintFormat("[PM-%s] FIFO: SPM closed profit added %.2f -> Total=%.2f (Count=%d)",
                           m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount);
            }

            ClosePosWithNotification(i, "EngulfingReversal");

            if(role == ROLE_MAIN)
            {
               m_mainTicket = 0;
               PromoteOldestSPMToMain("MainClosedEngulfing");
            }
            continue;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ManageSPMSystem - Core SPM hedge management                      |
//+------------------------------------------------------------------+
void CPositionManager::ManageSPMSystem()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0)
      return;

   double mainProfit = m_positions[mainIdx].profit;

   //--- If main is profitable or breakeven, no SPM needed
   if(mainProfit >= 0.0)
      return;

   //--- Main is in loss - manage SPM system
   int activeSPMs = GetActiveSPMCount();

   if(activeSPMs == 0)
   {
      //--- No SPMs yet - check if we should open first SPM
      ManageMainInLoss(mainIdx, mainProfit);
   }
   else
   {
      //--- SPMs exist - manage them
      ManageActiveSPMs(mainIdx);
   }
}

//+------------------------------------------------------------------+
//| ManageMainInLoss - Handle main position in loss, open first SPM  |
//+------------------------------------------------------------------+
void CPositionManager::ManageMainInLoss(int mainIdx, double mainProfit)
{
   int activeSPMs = GetActiveSPMCount();

   //--- Only open first SPM when none exist
   if(activeSPMs > 0)
      return;

   //--- Check trigger threshold
   if(mainProfit > SPM_TriggerLossUSD)
      return;  // Not deep enough in loss yet

   //--- Check minimum balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade)
   {
      PrintFormat("[PM-%s] SPM blocked: Balance %.2f < MinBalance %.2f",
                  m_symbol, balance, MinBalanceToTrade);
      return;
   }

   //--- Check SPM cooldown
   if(TimeCurrent() < m_lastSPMTime + SPM_CooldownSeconds)
   {
      return;  // Still in cooldown
   }

   //--- Check if trading is paused by protection
   if(IsTradingPaused())
   {
      if(!m_spmLimitLogged)
      {
         PrintFormat("[PM-%s] SPM blocked: Trading paused until %s",
                     m_symbol, TimeToString(m_protectionCooldownUntil));
         m_spmLimitLogged = true;
      }
      return;
   }

   //--- Determine SPM direction (opposite of MAIN)
   ENUM_SIGNAL_DIR spmDir;
   if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
      spmDir = SIGNAL_SELL;
   else
      spmDir = SIGNAL_BUY;

   //--- Calculate SPM lot
   double spmLot = CalcSPMLot(m_positions[mainIdx].volume, 1);

   //--- Open SPM1
   PrintFormat("[PM-%s] SPM1 Trigger: Main loss=%.2f <= %.2f -> Opening SPM1 %s lot=%.2f",
               m_symbol, mainProfit, SPM_TriggerLossUSD,
               (spmDir == SIGNAL_BUY) ? "BUY" : "SELL", spmLot);

   OpenSPM(spmDir, spmLot, 1, m_positions[mainIdx].ticket);
}

//+------------------------------------------------------------------+
//| ManageActiveSPMs - Manage existing SPM positions                 |
//+------------------------------------------------------------------+
void CPositionManager::ManageActiveSPMs(int mainIdx)
{
   int highestLayer = GetHighestLayer();
   int activeSPMs = GetActiveSPMCount();

   //--- Iterate through all SPM positions
   for(int i = m_posCount - 1; i >= 0; i--)
   {
      if(m_positions[i].role != ROLE_SPM)
         continue;

      double spmProfit = m_positions[i].profit;
      int spmLayer = m_positions[i].spmLayer;

      //--- SPM in profit: close and add to FIFO
      if(spmProfit >= SPM_CloseProfitUSD)
      {
         PrintFormat("[PM-%s] SPM%d Profit: %.2f >= %.2f -> CLOSE + FIFO",
                     m_symbol, spmLayer, spmProfit, SPM_CloseProfitUSD);

         m_spmClosedProfitTotal += spmProfit;
         m_spmClosedCount++;

         PrintFormat("[PM-%s] FIFO: SPM%d closed profit added %.2f -> Total=%.2f (Count=%d)",
                     m_symbol, spmLayer, spmProfit, m_spmClosedProfitTotal, m_spmClosedCount);

         ClosePosWithNotification(i, StringFormat("SPM%d_Profit_%.2f", spmLayer, spmProfit));
         continue;
      }

      //--- Highest layer SPM in deep loss: open next layer
      if(spmLayer == highestLayer && spmProfit <= SPM_TriggerLossUSD)
      {
         int nextLayer = highestLayer + 1;

         //--- Check max layers
         if(nextLayer > SPM_MaxLayers)
         {
            if(!m_spmLimitLogged)
            {
               PrintFormat("[PM-%s] SPM MaxLayers reached (%d). No more SPM layers.",
                           m_symbol, SPM_MaxLayers);
               m_spmLimitLogged = true;
            }
            continue;
         }

         //--- Check balance
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance < MinBalanceToTrade)
         {
            PrintFormat("[PM-%s] SPM%d blocked: Balance %.2f < MinBalance %.2f",
                        m_symbol, nextLayer, balance, MinBalanceToTrade);
            continue;
         }

         //--- Check cooldown
         if(TimeCurrent() < m_lastSPMTime + SPM_CooldownSeconds)
            continue;

         //--- Check if trading paused
         if(IsTradingPaused())
            continue;

         //--- Determine direction: opposite of current highest SPM
         ENUM_SIGNAL_DIR nextDir;
         if(m_positions[i].type == POSITION_TYPE_BUY)
            nextDir = SIGNAL_SELL;
         else
            nextDir = SIGNAL_BUY;

         //--- Calculate lot for next layer
         double nextLot = CalcSPMLot(m_positions[mainIdx].volume, nextLayer);

         PrintFormat("[PM-%s] SPM%d Trigger: SPM%d loss=%.2f <= %.2f -> Opening SPM%d %s lot=%.2f",
                     m_symbol, nextLayer, spmLayer, spmProfit, SPM_TriggerLossUSD,
                     nextLayer, (nextDir == SIGNAL_BUY) ? "BUY" : "SELL", nextLot);

         OpenSPM(nextDir, nextLot, nextLayer, m_positions[i].ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| CheckFIFOTarget - Check if FIFO net target is reached            |
//+------------------------------------------------------------------+
void CPositionManager::CheckFIFOTarget()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0)
      return;

   double mainProfit = m_positions[mainIdx].profit;

   //--- Only check FIFO when MAIN is in loss
   if(mainProfit >= 0.0)
      return;

   double mainLoss = MathAbs(mainProfit);

   //--- Calculate open SPM net total
   double openSPMNet = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
         openSPMNet += m_positions[i].profit;
   }

   //--- Net calculation: closedSPM + openSPM - |mainLoss|
   double net = m_spmClosedProfitTotal + openSPMNet - mainLoss;

   //--- Check if net target reached
   if(net >= SPM_NetTargetUSD)
   {
      PrintFormat("[PM-%s] +++ FIFO TARGET REACHED +++ Net=%.2f >= %.2f",
                  m_symbol, net, SPM_NetTargetUSD);
      PrintFormat("[PM-%s] FIFO Detail: ClosedSPM=%.2f + OpenSPM=%.2f - MainLoss=%.2f = Net=%.2f",
                  m_symbol, m_spmClosedProfitTotal, openSPMNet, mainLoss, net);

      //--- Send notification before closing
      CloseMainWithFIFONotification(mainIdx, m_spmClosedProfitTotal + openSPMNet, mainProfit, net);

      //--- Close all positions in the cycle
      CloseAllPositions("FIFOTargetReached_Net=" + DoubleToString(net, 2));

      //--- Reset FIFO
      ResetFIFO();

      //--- Determine direction for new main
      ENUM_SIGNAL_DIR newDir = SIGNAL_NONE;
      if(m_signalEngine != NULL)
      {
         SignalData sig = m_signalEngine.Evaluate();
         newDir = sig.direction;
      }

      if(newDir == SIGNAL_NONE)
         newDir = GetCandleDirection();

      //--- Open new MAIN trade
      if(newDir != SIGNAL_NONE)
      {
         OpenNewMainTrade(newDir, "PostFIFO_NewCycle");
      }
      else
      {
         PrintFormat("[PM-%s] FIFO cycle complete but no signal for new MAIN. Waiting.", m_symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| OpenNewMainTrade - Open a new MAIN position with priority logic  |
//+------------------------------------------------------------------+
void CPositionManager::OpenNewMainTrade(ENUM_SIGNAL_DIR dirHint, string reason)
{
   //--- Check balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade)
   {
      PrintFormat("[PM-%s] OpenNewMain blocked: Balance %.2f < MinBalance %.2f",
                  m_symbol, balance, MinBalanceToTrade);
      return;
   }

   //--- Check if trading paused
   if(IsTradingPaused())
   {
      PrintFormat("[PM-%s] OpenNewMain blocked: Trading paused until %s",
                  m_symbol, TimeToString(m_protectionCooldownUntil));
      return;
   }

   //--- Direction priority: 1.Signal 2.H1Trend 3.CandleDirection 4.dirHint
   ENUM_SIGNAL_DIR finalDir = SIGNAL_NONE;

   //--- Priority 1: Signal Engine
   if(m_signalEngine != NULL)
   {
      SignalData sig = m_signalEngine.Evaluate();
      if(sig.direction != SIGNAL_NONE && sig.score >= 35)
      {
         finalDir = sig.direction;
         PrintFormat("[PM-%s] NewMain direction from SIGNAL: %s (score=%d)",
                     m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL", sig.score);
      }
   }

   //--- Priority 2: H1 Trend
   if(finalDir == SIGNAL_NONE && m_signalEngine != NULL)
   {
      ENUM_SIGNAL_DIR trendDir = m_signalEngine.GetCurrentTrend();
      if(trendDir != SIGNAL_NONE)
      {
         finalDir = trendDir;
         PrintFormat("[PM-%s] NewMain direction from H1 TREND: %s",
                     m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL");
      }
   }

   //--- Priority 3: Candle Direction
   if(finalDir == SIGNAL_NONE)
   {
      finalDir = GetCandleDirection();
      if(finalDir != SIGNAL_NONE)
      {
         PrintFormat("[PM-%s] NewMain direction from CANDLE: %s",
                     m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL");
      }
   }

   //--- Priority 4: Hint direction
   if(finalDir == SIGNAL_NONE)
   {
      finalDir = dirHint;
      if(finalDir != SIGNAL_NONE)
      {
         PrintFormat("[PM-%s] NewMain direction from HINT: %s",
                     m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL");
      }
   }

   //--- Still no direction? Abort
   if(finalDir == SIGNAL_NONE)
   {
      PrintFormat("[PM-%s] OpenNewMain: No direction determined. Cannot open. Reason=%s",
                  m_symbol, reason);
      return;
   }

   //--- Prepare order
   double sl = 0;  // SL YOK - ASLA
   double tp = 0;

   string comment = StringFormat("BTFX_%s_%s", m_symbol, reason);

   //--- Truncate comment if too long
   if(StringLen(comment) > 25)
      comment = StringSubstr(comment, 0, 25);

   if(m_executor != NULL)
   {
      //--- Calculate lot (using base lot since 0.0 would fail)
      double lot = BaseLotPer1000 * (balance / 1000.0);
      double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;
      if(lot < minLot) lot = minLot;
      if(lot > InputMaxLot) lot = InputMaxLot;
      lot = NormalizeDouble(lot, 2);

      ulong newTicket = m_executor.OpenPosition(finalDir, lot, tp, sl, comment);

      if(newTicket > 0)
      {
         m_mainTicket = newTicket;
         m_spmLayerCount = 0;

         PrintFormat("[PM-%s] NEW MAIN OPENED: Ticket=%d Dir=%s Reason=%s",
                     m_symbol, (int)newTicket,
                     (finalDir == SIGNAL_BUY) ? "BUY" : "SELL", reason);

         //--- Notify
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("NEW MAIN %s: %s Ticket=%d Reason=%s",
                                                m_symbol,
                                                (finalDir == SIGNAL_BUY) ? "BUY" : "SELL",
                                                (int)newTicket, reason));

         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("NEW MAIN %s: %s Ticket=%d Reason=%s",
                                               m_symbol,
                                               (finalDir == SIGNAL_BUY) ? "BUY" : "SELL",
                                               (int)newTicket, reason));
      }
      else
      {
         PrintFormat("[PM-%s] OpenNewMain FAILED: Dir=%s Reason=%s Error=%d",
                     m_symbol, (finalDir == SIGNAL_BUY) ? "BUY" : "SELL",
                     reason, GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| OpenSPM - Open a new SPM hedge position                          |
//+------------------------------------------------------------------+
void CPositionManager::OpenSPM(ENUM_SIGNAL_DIR dir, double lot, int layer, ulong parentTicket)
{
   //--- Check balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade)
   {
      PrintFormat("[PM-%s] OpenSPM%d blocked: Balance %.2f < MinBalance %.2f",
                  m_symbol, layer, balance, MinBalanceToTrade);
      return;
   }

   //--- Check if trading paused
   if(IsTradingPaused())
   {
      PrintFormat("[PM-%s] OpenSPM%d blocked: Trading paused", m_symbol, layer);
      return;
   }

   double sl = 0;  // SL YOK - ASLA
   double tp = 0;

   //--- Build comment: BTFX_SPM_Layer_ParentTicket
   string comment = StringFormat("BTFX_SPM_%d_%d", layer, (int)parentTicket);

   //--- Truncate comment if too long
   if(StringLen(comment) > 25)
      comment = StringSubstr(comment, 0, 25);

   if(m_executor == NULL)
   {
      PrintFormat("[PM-%s] OpenSPM%d FAILED: Executor is NULL", m_symbol, layer);
      return;
   }

   if(dir != SIGNAL_BUY && dir != SIGNAL_SELL)
   {
      PrintFormat("[PM-%s] OpenSPM%d FAILED: Invalid direction", m_symbol, layer);
      return;
   }

   ulong newTicket = m_executor.OpenPosition(dir, lot, tp, sl, comment);

   if(newTicket > 0)
   {
      m_spmLayerCount = layer;
      m_lastSPMTime = TimeCurrent();
      m_spmLimitLogged = false;

      PrintFormat("[PM-%s] SPM%d OPENED: Ticket=%d Dir=%s Lot=%.2f Parent=%d",
                  m_symbol, layer, (int)newTicket,
                  (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)parentTicket);

      //--- Notify
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("SPM%d %s: %s Lot=%.2f Ticket=%d",
                                             layer, m_symbol,
                                             (dir == SIGNAL_BUY) ? "BUY" : "SELL",
                                             lot, (int)newTicket));

      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("SPM%d %s: %s Lot=%.2f Ticket=%d",
                                            layer, m_symbol,
                                            (dir == SIGNAL_BUY) ? "BUY" : "SELL",
                                            lot, (int)newTicket));
   }
   else
   {
      PrintFormat("[PM-%s] OpenSPM%d FAILED: Dir=%s Lot=%.2f Error=%d",
                  m_symbol, layer, (dir == SIGNAL_BUY) ? "BUY" : "SELL",
                  lot, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| PromoteOldestSPMToMain - Oldest SPM becomes new MAIN             |
//+------------------------------------------------------------------+
void CPositionManager::PromoteOldestSPMToMain(string reason)
{
   //--- Find oldest SPM (lowest layer number, earliest open time)
   int bestIdx = -1;
   int bestLayer = 999;
   datetime bestTime = D'2099.01.01';

   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM)
         continue;

      int layer = m_positions[i].spmLayer;
      datetime openTime = m_positions[i].openTime;

      //--- Prefer lowest layer, then earliest time
      if(layer < bestLayer || (layer == bestLayer && openTime < bestTime))
      {
         bestIdx = i;
         bestLayer = layer;
         bestTime = openTime;
      }
   }

   if(bestIdx >= 0)
   {
      ulong oldTicket = m_mainTicket;
      m_mainTicket = m_positions[bestIdx].ticket;
      m_positions[bestIdx].role = ROLE_MAIN;

      //--- Reset FIFO counters for new cycle
      m_spmClosedProfitTotal = 0.0;
      m_spmClosedCount = 0;
      m_spmLayerCount = 0;
      m_spmLimitLogged = false;

      //--- Recalculate remaining SPM layers
      int maxLayer = 0;
      for(int i = 0; i < m_posCount; i++)
      {
         if(m_positions[i].role == ROLE_SPM && m_positions[i].spmLayer > maxLayer)
            maxLayer = m_positions[i].spmLayer;
      }
      m_spmLayerCount = maxLayer;

      PrintFormat("[PM-%s] PROMOTED: SPM%d (Ticket=%d) -> NEW MAIN | OldMain=%d | Reason=%s",
                  m_symbol, bestLayer, (int)m_mainTicket, (int)oldTicket, reason);

      //--- Notify
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("PROMOTE %s: SPM%d -> MAIN Ticket=%d Reason=%s",
                                             m_symbol, bestLayer, (int)m_mainTicket, reason));

      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("PROMOTE %s: SPM%d -> MAIN Ticket=%d Reason=%s",
                                            m_symbol, bestLayer, (int)m_mainTicket, reason));

      //--- Reset TP tracking for new main
      m_currentTPLevel = 0;
      m_tp1Hit = false;
      m_tp2Hit = false;
      m_tpExtended = false;
   }
   else
   {
      PrintFormat("[PM-%s] PROMOTE: No SPM available for promotion. Cycle complete. Reason=%s",
                  m_symbol, reason);
      m_mainTicket = 0;
   }
}

//+------------------------------------------------------------------+
//| ManageTPLevels - Track TP1->TP2->TP3 progression                 |
//+------------------------------------------------------------------+
void CPositionManager::ManageTPLevels()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0)
      return;

   //--- Skip if no TP levels set
   if(m_tp1Price == 0.0 && m_tp2Price == 0.0 && m_tp3Price == 0.0)
      return;

   double currentPrice = 0.0;
   if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
      currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   else
      currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

   if(currentPrice <= 0.0)
      return;

   bool isBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);

   //--- TP1 check
   if(!m_tp1Hit && m_tp1Price > 0.0)
   {
      bool tp1Reached = isBuy ? (currentPrice >= m_tp1Price) : (currentPrice <= m_tp1Price);

      if(tp1Reached)
      {
         m_tp1Hit = true;
         m_currentTPLevel = 1;

         PrintFormat("[PM-%s] TP1 HIT: Price=%.5f TP1=%.5f | Trend=%d",
                     m_symbol, currentPrice, m_tp1Price, (int)m_trendStrength);

         //--- On weak trend, consider partial close
         if(m_trendStrength <= TREND_WEAK)
         {
            PrintFormat("[PM-%s] Weak trend at TP1 - monitoring for exit", m_symbol);
         }

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP1 HIT %s: %.5f Trend=%s",
                                                m_symbol, currentPrice,
                                                (m_trendStrength == TREND_STRONG) ? "STRONG" :
                                                (m_trendStrength == TREND_MODERATE) ? "MODERATE" : "WEAK"));
      }
   }

   //--- TP2 check
   if(m_tp1Hit && !m_tp2Hit && m_tp2Price > 0.0)
   {
      bool tp2Reached = isBuy ? (currentPrice >= m_tp2Price) : (currentPrice <= m_tp2Price);

      if(tp2Reached)
      {
         m_tp2Hit = true;
         m_currentTPLevel = 2;

         PrintFormat("[PM-%s] TP2 HIT: Price=%.5f TP2=%.5f | Trend=%d",
                     m_symbol, currentPrice, m_tp2Price, (int)m_trendStrength);

         //--- On moderate trend, lock some profit
         if(m_trendStrength <= TREND_MODERATE)
         {
            PrintFormat("[PM-%s] Moderate/weak trend at TP2 - tightening management", m_symbol);
         }

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP2 HIT %s: %.5f", m_symbol, currentPrice));
      }
   }

   //--- TP3 check (extended target)
   if(m_tp2Hit && m_tp3Price > 0.0 && !m_tpExtended)
   {
      bool tp3Reached = isBuy ? (currentPrice >= m_tp3Price) : (currentPrice <= m_tp3Price);

      if(tp3Reached)
      {
         m_tpExtended = true;
         m_currentTPLevel = 3;

         PrintFormat("[PM-%s] TP3 HIT: Price=%.5f TP3=%.5f | EXTENDED TARGET REACHED",
                     m_symbol, currentPrice, m_tp3Price);

         //--- At TP3 with strong trend, consider holding; otherwise close
         if(m_trendStrength < TREND_STRONG)
         {
            PrintFormat("[PM-%s] TP3 reached with non-strong trend -> closing MAIN",
                        m_symbol);

            ClosePosWithNotification(mainIdx, "TP3_Reached");
            m_mainTicket = 0;
            PromoteOldestSPMToMain("MainClosedTP3");
         }
         else
         {
            PrintFormat("[PM-%s] TP3 reached with STRONG trend -> holding for extended run",
                        m_symbol);
         }

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP3 HIT %s: %.5f EXTENDED", m_symbol, currentPrice));

         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("TP3 HIT %s: %.5f EXTENDED", m_symbol, currentPrice));
      }
   }
}

//+------------------------------------------------------------------+
//| CalcSPMLot - Calculate SPM lot size with layer multiplier        |
//+------------------------------------------------------------------+
double CPositionManager::CalcSPMLot(double mainLot, int layer)
{
   //--- Base calculation: mainLot * SPM_LotMultiplier
   double lot = mainLot * SPM_LotMultiplier;

   //--- Layer scaling: slight increase per layer for faster recovery
   if(layer > 1)
      lot *= (1.0 + (layer - 1) * 0.1);  // +10% per additional layer

   //--- ADX bonus: if strong trend, increase lot slightly
   if(m_signalEngine != NULL)
   {
      double adxValue = m_signalEngine.GetADX();
      if(adxValue > 30.0)
      {
         double adxBonus = 1.0 + (adxValue - 30.0) / 100.0;  // Max ~20% bonus at ADX=50
         adxBonus = MathMin(adxBonus, 1.2);
         lot *= adxBonus;

         PrintFormat("[PM-%s] SPM Lot ADX bonus: ADX=%.1f Bonus=%.2f", m_symbol, adxValue, adxBonus);
      }
   }

   //--- Normalize lot size
   double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;

   if(lot < minLot)
      lot = minLot;

   if(lot > maxLot)
      lot = maxLot;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| GetCandleDirection - Use M15 bar[1] for direction                |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::GetCandleDirection()
{
   double open1  = iOpen(m_symbol, PERIOD_M15, 1);
   double close1 = iClose(m_symbol, PERIOD_M15, 1);

   if(close1 > open1)
      return SIGNAL_BUY;
   else if(close1 < open1)
      return SIGNAL_SELL;

   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| PrintDetailedStatus - Log all positions and FIFO state           |
//+------------------------------------------------------------------+
void CPositionManager::PrintDetailedStatus()
{
   //--- Only log every 30 seconds
   if(TimeCurrent() - m_lastStatusLog < 30)
      return;

   m_lastStatusLog = TimeCurrent();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin  = AccountInfoDouble(ACCOUNT_MARGIN);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   PrintFormat("============================================================");
   PrintFormat("[PM-%s] STATUS @ %s", m_symbol, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   PrintFormat("[PM-%s] Balance=%.2f | Equity=%.2f | Margin=%.2f | Level=%.1f%%",
               m_symbol, balance, equity, margin, marginLevel);
   PrintFormat("[PM-%s] Positions=%d | MainTicket=%d | SPMLayers=%d",
               m_symbol, m_posCount, (int)m_mainTicket, m_spmLayerCount);
   PrintFormat("[PM-%s] FIFO: ClosedProfit=%.2f | ClosedCount=%d | Target=%.2f",
               m_symbol, m_spmClosedProfitTotal, m_spmClosedCount, SPM_NetTargetUSD);

   //--- Log individual positions
   double totalPL = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      string roleStr = (m_positions[i].role == ROLE_MAIN) ? "MAIN" :
                        StringFormat("SPM%d", m_positions[i].spmLayer);

      string typeStr = (m_positions[i].type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

      double peak = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : 0.0;

      PrintFormat("[PM-%s] [%s] #%d %s Vol=%.2f Open=%.5f P/L=%.2f Peak=%.2f %s",
                  m_symbol, roleStr, (int)m_positions[i].ticket,
                  typeStr, m_positions[i].volume,
                  m_positions[i].openPrice, m_positions[i].profit,
                  peak, m_positions[i].comment);

      totalPL += m_positions[i].profit;
   }

   PrintFormat("[PM-%s] Total Open P/L=%.2f", m_symbol, totalPL);

   //--- FIFO net calculation
   int mainIdx = FindMainPosition();
   if(mainIdx >= 0 && m_positions[mainIdx].profit < 0.0)
   {
      double mainLoss = MathAbs(m_positions[mainIdx].profit);
      double openSPM = 0.0;
      for(int i = 0; i < m_posCount; i++)
      {
         if(m_positions[i].role == ROLE_SPM)
            openSPM += m_positions[i].profit;
      }

      double net = m_spmClosedProfitTotal + openSPM - mainLoss;
      PrintFormat("[PM-%s] FIFO NET: ClosedSPM(%.2f) + OpenSPM(%.2f) - MainLoss(%.2f) = Net(%.2f) / Target(%.2f)",
                  m_symbol, m_spmClosedProfitTotal, openSPM, mainLoss, net, SPM_NetTargetUSD);
   }

   //--- Protection status
   if(m_tradingPaused)
   {
      int remaining = (int)(m_protectionCooldownUntil - TimeCurrent());
      PrintFormat("[PM-%s] PROTECTION: Trading PAUSED | Cooldown remaining=%ds | Triggers=%d",
                  m_symbol, MathMax(remaining, 0), m_protectionTriggerCount);
   }

   //--- TP status
   if(m_tp1Price > 0.0)
   {
      PrintFormat("[PM-%s] TP: Level=%d TP1=%.5f(%s) TP2=%.5f(%s) TP3=%.5f(%s) Strength=%d",
                  m_symbol, m_currentTPLevel,
                  m_tp1Price, m_tp1Hit ? "HIT" : "-",
                  m_tp2Price, m_tp2Hit ? "HIT" : "-",
                  m_tp3Price, m_tpExtended ? "HIT" : "-",
                  (int)m_trendStrength);
   }

   PrintFormat("============================================================");
}

//+------------------------------------------------------------------+
//| FindMainPosition - Find MAIN position index                      |
//+------------------------------------------------------------------+
int CPositionManager::FindMainPosition()
{
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_MAIN)
         return i;
   }

   //--- Fallback: if mainTicket is set, find by ticket
   if(m_mainTicket > 0)
   {
      for(int i = 0; i < m_posCount; i++)
      {
         if(m_positions[i].ticket == m_mainTicket)
         {
            m_positions[i].role = ROLE_MAIN;
            return i;
         }
      }
   }

   return -1;
}

//+------------------------------------------------------------------+
//| GetActiveSPMCount - Count active SPM positions                   |
//+------------------------------------------------------------------+
int CPositionManager::GetActiveSPMCount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| GetHighestLayer - Find highest SPM layer number                  |
//+------------------------------------------------------------------+
int CPositionManager::GetHighestLayer()
{
   int highest = 0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
      {
         if(m_positions[i].spmLayer > highest)
            highest = m_positions[i].spmLayer;
      }
   }
   return highest;
}

//+------------------------------------------------------------------+
//| ClosePosWithNotification - Close position + notify               |
//+------------------------------------------------------------------+
void CPositionManager::ClosePosWithNotification(int idx, string reason)
{
   if(idx < 0 || idx >= m_posCount)
      return;

   ulong ticket = m_positions[idx].ticket;
   double profit = m_positions[idx].profit;
   double volume = m_positions[idx].volume;
   string roleStr = (m_positions[idx].role == ROLE_MAIN) ? "MAIN" :
                     StringFormat("SPM%d", m_positions[idx].spmLayer);
   string typeStr = (m_positions[idx].type == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   PrintFormat("[PM-%s] CLOSING %s #%d %s Vol=%.2f Profit=%.2f Reason=%s",
               m_symbol, roleStr, (int)ticket, typeStr, volume, profit, reason);

   bool closed = false;
   if(m_executor != NULL)
   {
      closed = m_executor.ClosePosition(ticket);
   }

   if(closed)
   {
      PrintFormat("[PM-%s] CLOSED %s #%d Profit=%.2f Reason=%s",
                  m_symbol, roleStr, (int)ticket, profit, reason);

      //--- Add to daily profit tracking
      m_dailyProfit += profit;

      //--- Send notifications
      string msg = StringFormat("CLOSE %s %s #%d %s Vol=%.2f P/L=%.2f Reason=%s",
                                m_symbol, roleStr, (int)ticket, typeStr, volume, profit, reason);

      if(m_telegram != NULL)
         m_telegram.SendMessage(msg);

      if(m_discord != NULL)
         m_discord.SendMessage(msg);

      //--- Reset peak profit for this index
      if(idx < ArraySize(m_peakProfit))
         m_peakProfit[idx] = 0.0;
   }
   else
   {
      PrintFormat("[PM-%s] CLOSE FAILED: %s #%d Error=%d",
                  m_symbol, roleStr, (int)ticket, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| CloseMainWithFIFONotification - Special notification for FIFO    |
//+------------------------------------------------------------------+
void CPositionManager::CloseMainWithFIFONotification(int mainIdx, double spmKar, double mainZarar, double net)
{
   if(mainIdx < 0 || mainIdx >= m_posCount)
      return;

   string msg = StringFormat(
      "FIFO TARGET %s: SPM_Kar=%.2f MainZarar=%.2f Net=%.2f >= Target=%.2f | "
      "ClosedSPM=%d | Layers=%d",
      m_symbol, spmKar, mainZarar, net, SPM_NetTargetUSD,
      m_spmClosedCount, m_spmLayerCount);

   PrintFormat("[PM-%s] %s", m_symbol, msg);

   if(m_telegram != NULL)
      m_telegram.SendMessage(msg);

   if(m_discord != NULL)
      m_discord.SendMessage(msg);
}

//+------------------------------------------------------------------+
//| GetCatName - Return category name string                         |
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
      default:                   return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| ResetFIFO - Clear all FIFO accumulators                          |
//+------------------------------------------------------------------+
void CPositionManager::ResetFIFO()
{
   PrintFormat("[PM-%s] FIFO RESET: Was Profit=%.2f Count=%d Layers=%d",
               m_symbol, m_spmClosedProfitTotal, m_spmClosedCount, m_spmLayerCount);

   m_spmClosedProfitTotal = 0.0;
   m_spmClosedCount       = 0;
   m_spmLayerCount        = 0;
   m_spmLimitLogged       = false;

   //--- Reset peak profit tracking
   ArrayInitialize(m_peakProfit, 0.0);

   //--- Reset TP tracking
   m_currentTPLevel = 0;
   m_tp1Hit = false;
   m_tp2Hit = false;
   m_tpExtended = false;
}

//+------------------------------------------------------------------+
//| CloseAllPositions - Close all positions for this symbol          |
//+------------------------------------------------------------------+
void CPositionManager::CloseAllPositions(string reason)
{
   PrintFormat("[PM-%s] === CLOSE ALL POSITIONS === Reason=%s Count=%d",
               m_symbol, reason, m_posCount);

   //--- Close in reverse order (newest first) for cleaner execution
   for(int i = m_posCount - 1; i >= 0; i--)
   {
      ulong ticket = m_positions[i].ticket;
      string roleStr = (m_positions[i].role == ROLE_MAIN) ? "MAIN" :
                        StringFormat("SPM%d", m_positions[i].spmLayer);

      PrintFormat("[PM-%s] CloseAll: Closing %s #%d Profit=%.2f",
                  m_symbol, roleStr, (int)ticket, m_positions[i].profit);

      if(m_executor != NULL)
      {
         bool closed = m_executor.ClosePosition(ticket);
         if(closed)
         {
            m_dailyProfit += m_positions[i].profit;
            PrintFormat("[PM-%s] CloseAll: %s #%d CLOSED P/L=%.2f",
                        m_symbol, roleStr, (int)ticket, m_positions[i].profit);
         }
         else
         {
            PrintFormat("[PM-%s] CloseAll: %s #%d FAILED Error=%d - retrying...",
                        m_symbol, roleStr, (int)ticket, GetLastError());

            //--- Retry once
            Sleep(500);
            closed = m_executor.ClosePosition(ticket);
            if(closed)
            {
               m_dailyProfit += m_positions[i].profit;
               PrintFormat("[PM-%s] CloseAll: %s #%d CLOSED on retry", m_symbol, roleStr, (int)ticket);
            }
            else
            {
               PrintFormat("[PM-%s] CloseAll: %s #%d STILL FAILED Error=%d",
                           m_symbol, roleStr, (int)ticket, GetLastError());
            }
         }
      }
   }

   //--- Reset main ticket
   m_mainTicket = 0;
   m_posCount = 0;

   //--- Notify
   string msg = StringFormat("ALL CLOSED %s: Reason=%s | DailyPL=%.2f", m_symbol, reason, m_dailyProfit);

   if(m_telegram != NULL)
      m_telegram.SendMessage(msg);

   if(m_discord != NULL)
      m_discord.SendMessage(msg);

   PrintFormat("[PM-%s] === ALL POSITIONS CLOSED === Reason=%s", m_symbol, reason);
}

//+------------------------------------------------------------------+
//| SetProtectionCooldown - Apply protection cooldown                |
//+------------------------------------------------------------------+
void CPositionManager::SetProtectionCooldown(string reason)
{
   m_protectionTriggerCount++;
   int cooldownMultiplier = MathMin(m_protectionTriggerCount, 6);
   int totalCooldown = ProtectionCooldownSec * cooldownMultiplier;

   m_protectionCooldownUntil = TimeCurrent() + totalCooldown;
   m_tradingPaused = true;

   PrintFormat("[PM-%s] PROTECTION SET: Reason=%s | Cooldown=%ds (trigger #%d, x%d)",
               m_symbol, reason, totalCooldown, m_protectionTriggerCount, cooldownMultiplier);
}

#endif // POSITION_MANAGER_MQH
