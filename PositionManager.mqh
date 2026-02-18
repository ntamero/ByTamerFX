#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH
//+------------------------------------------------------------------+
//|                                             PositionManager.mqh  |
//|                                    Copyright 2026, By T@MER      |
//|                                    https://www.bytamer.com        |
//|                                                                  |
//|              v2.0.0 - KAZAN-KAZAN Hedge Sistemi                  |
//|              FIFO +$5 Net | DCA | Acil Hedge | Kilitlenme Tespit |
//+------------------------------------------------------------------+
//|  KURALLAR:                                                       |
//|  1. SL YOK - ASLA (MUTLAK)                                      |
//|  2. ANA islem SADECE FIFO ile kapanir (net >= +$5)               |
//|  3. PeakDrop SADECE SPM'lere uygulanir (ANA'ya degil)            |
//|  4. SPM 5+5 yapi: max 5 BUY + 5 SELL                            |
//|  5. SPM yon: 5-oy sistemi (Trend,Sinyal,Mum,MACD,DI)            |
//|     ASLA zarardaki ANA yonunde SPM acma (CheckSameDirectionBlock)|
//|  6. SPM tetik: -$5 | SPM kar: $4 | FIFO net hedef: +$5          |
//|  7. DCA: Zarardaki SPM icin maliyet ortalama (max 1 per pozisyon)|
//|  8. Acil Hedge: Lot oran > 2:1 + zarardaki taraf buyukse hedge   |
//|  9. Kilitlenme: 5dk net degisim < $0.50 → tum kapat             |
//| 10. TERFI (SPM→ANA) KALDIRILDI - kara delik yaratiyor            |
//| 11. Enstruman bazli parametreler (SymbolProfile)                 |
//| 12. HER ZAMAN kar odakli: kucuk karlari topla, kasaya ekle       |
//+------------------------------------------------------------------+

#include "Config.mqh"
#include "TradeExecutor.mqh"
#include "SignalEngine.mqh"
#include "CandleAnalyzer.mqh"
#include "TelegramMsg.mqh"
#include "DiscordMsg.mqh"

//+------------------------------------------------------------------+
//| CPositionManager - v2.0 KAZAN-KAZAN Engine                       |
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

   //--- v2.0: Enstruman profili
   SymbolProfile        m_profile;

   //--- SPM / FIFO tracking
   int                  m_spmLayerCount;
   double               m_spmClosedProfitTotal;
   int                  m_spmClosedCount;
   double               m_totalCashedProfit;     // Kasaya toplanan tum karlar

   //--- Candle analysis
   CCandleAnalyzer      m_candle;

   //--- Timing
   datetime             m_lastSPMTime;
   datetime             m_lastDCATime;           // v2.0: DCA cooldown
   datetime             m_lastHedgeTime;         // v2.0: Hedge cooldown
   datetime             m_lastStatusLog;
   datetime             m_fifoWaitStart;

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

   //--- v2.0: Kilitlenme (Deadlock) tracking
   datetime             m_deadlockCheckStart;
   double               m_deadlockLastNet;
   bool                 m_deadlockActive;
   datetime             m_deadlockCooldownUntil;

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

   //--- v2.0 YENI mekanizmalar
   void ManageDCA();
   void ManageEmergencyHedge();
   void CheckDeadlock();

   //--- Direction logic (5-oy sistemi)
   ENUM_SIGNAL_DIR DetermineSPMDirection(int parentLayer);
   ENUM_SIGNAL_DIR GetCandleDirection();
   bool CheckSameDirectionBlock(ENUM_SIGNAL_DIR proposedDir);
   bool ShouldWaitForANARecovery(int mainIdx);

   //--- v2.0: BUY/SELL katman sayilari
   int  GetBuyLayerCount();
   int  GetSellLayerCount();

   //--- Lot balance
   bool CheckLotBalance(ENUM_SIGNAL_DIR newDir, double newLot);
   double CalcSPMLot(double mainLot, int layer);

   //--- Trade execution
   void OpenNewMainTrade(ENUM_SIGNAL_DIR dirHint, string reason);
   void OpenSPM(ENUM_SIGNAL_DIR dir, double lot, int layer, ulong parentTicket);
   void OpenDCA(int sourceIdx);
   void OpenHedge(ENUM_SIGNAL_DIR dir, double lot);

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
   int    GetActiveDCACount();
   int    GetActiveHedgeCount();
   int    GetHighestLayer();
   string GetCatName();
   void   ResetFIFO();
   void   CloseAllPositions(string reason);
   void   SetProtectionCooldown(string reason);
   void   PrintDetailedStatus();
   double GetTotalBuyLots();
   double GetTotalSellLots();
   double CalcNetResult();

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
   m_lastDCATime         = 0;
   m_lastHedgeTime       = 0;
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

   m_deadlockCheckStart  = 0;
   m_deadlockLastNet     = 0.0;
   m_deadlockActive      = false;
   m_deadlockCooldownUntil = 0;

   m_startBalance        = 0.0;
   m_dailyProfit         = 0.0;
   m_dailyResetTime      = 0;
   m_spmLimitLogged      = false;
   m_protectionCooldownUntil = 0;
   m_protectionTriggerCount  = 0;
   m_tradingPaused       = false;

   m_profile.SetDefault();
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

   //--- v2.0: Enstruman profili yukle
   m_profile = GetSymbolProfile(m_category, m_symbol);

   PrintFormat("[PM-%s] PositionManager v2.1.0 KazanKazan Dinamik | Cat=%s | Profil=%s | Balance=%.2f",
               m_symbol, GetCatName(), m_profile.profileName, m_startBalance);
   PrintFormat("[PM-%s] SPM: Trigger=$%.1f | Close=$%.1f | Net=$%.1f | MaxBuy=%d MaxSell=%d",
               m_symbol, m_profile.spmTriggerLoss, m_profile.spmCloseProfit,
               m_profile.fifoNetTarget, m_profile.spmMaxBuyLayers, m_profile.spmMaxSellLayers);
   PrintFormat("[PM-%s] SPM Lot: Base=%.1f | Inc=%.2f | Cap=%.1f | Cooldown=%ds",
               m_symbol, m_profile.spmLotBase, m_profile.spmLotIncrement,
               m_profile.spmLotCap, m_profile.spmCooldownSec);
   PrintFormat("[PM-%s] v2.1: TP Pips: TP1=%.0f | TP2=%.0f | TP3=%.0f | Hedge(minSPM=%d, minZarar=$%.0f)",
               m_symbol, m_profile.tp1Pips, m_profile.tp2Pips, m_profile.tp3Pips,
               m_profile.hedgeMinSPMCount, m_profile.hedgeMinLossUSD);
   PrintFormat("[PM-%s] v2.1: DCA(dist=%.1f ATR) | Hedge(oran=%.1f, fill=%.0f%%) | Deadlock(%dsn)",
               m_symbol, m_profile.dcaDistanceATR,
               Hedge_RatioTrigger, Hedge_FillPercent * 100.0, Deadlock_TimeoutSec);
   PrintFormat("[PM-%s] KURALLAR: TERFI=YOK | PeakDrop=SADECE_SPM | ANA=SADECE_FIFO | SL=YOK",
               m_symbol);

   AdoptExistingPositions();
}

//+------------------------------------------------------------------+
//| OnTick - Ana tick isleme dongusu v2.0                             |
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
      m_deadlockActive = false;
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

   //--- 8. v2.0: DCA (Maliyet Ortalama)
   ManageDCA();

   //--- 9. v2.0: Acil Hedge
   ManageEmergencyHedge();

   //--- 10. v2.0: Kilitlenme tespit
   CheckDeadlock();

   //--- 11. TP seviyeleri yonet
   ManageTPLevels();

   //--- 12. Detayli log (30 saniyede bir)
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
      if(m_positions[i].role == ROLE_SPM || m_positions[i].role == ROLE_DCA || m_positions[i].role == ROLE_HEDGE)
         return true;
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
//| GetFIFOSummary - v2.0: Genisletilmis FIFO ozet                   |
//+------------------------------------------------------------------+
FIFOSummary CPositionManager::GetFIFOSummary()
{
   FIFOSummary summary;
   summary.closedProfitTotal = m_spmClosedProfitTotal;
   summary.closedCount       = m_spmClosedCount;
   summary.activeSPMCount    = GetActiveSPMCount();
   summary.activeDCACount    = GetActiveDCACount();
   summary.activeHedgeCount  = GetActiveHedgeCount();
   summary.buyLayerCount     = GetBuyLayerCount();
   summary.sellLayerCount    = GetSellLayerCount();

   double openSPMProfit = 0.0;
   double openSPMLoss   = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM || m_positions[i].role == ROLE_DCA || m_positions[i].role == ROLE_HEDGE)
      {
         if(m_positions[i].profit >= 0.0)
            openSPMProfit += m_positions[i].profit;
         else
            openSPMLoss += m_positions[i].profit;  // negatif deger
      }
   }
   summary.openSPMProfit = openSPMProfit;
   summary.openSPMLoss   = openSPMLoss;

   int mainIdx = FindMainPosition();
   summary.mainLoss = (mainIdx >= 0) ? m_positions[mainIdx].profit : 0.0;

   // v2.0: Net hesap = kasa + acikKar + acikZarar + anaP/L
   summary.netResult = m_spmClosedProfitTotal + openSPMProfit + openSPMLoss;
   if(mainIdx >= 0 && m_positions[mainIdx].profit < 0.0)
      summary.netResult += m_positions[mainIdx].profit;  // negatif ekleniyor

   summary.targetUSD    = m_profile.fifoNetTarget;
   summary.isProfitable = (summary.netResult >= m_profile.fifoNetTarget);

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

   int totalAdopted = 0, spmAdopted = 0, dcaAdopted = 0, hedgeAdopted = 0;
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
      else if(StringFind(comment, "BTFX_DCA_") >= 0)
         dcaAdopted++;
      else if(StringFind(comment, "BTFX_HEDGE_") >= 0)
         hedgeAdopted++;
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
      // Tum pozisyonlar SPM/DCA/HEDGE - en eski ANA olsun
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
      PrintFormat("[PM-%s] ADOPT: Total=%d SPM=%d DCA=%d Hedge=%d Main=%d",
                  m_symbol, totalAdopted, spmAdopted, dcaAdopted, hedgeAdopted, (int)m_mainTicket);
   }
}

//+------------------------------------------------------------------+
//| RefreshPositions - v2.0: DCA + HEDGE rolleri eklendi              |
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
      m_positions[idx].parentTicket = 0;

      string comment = m_positions[idx].comment;

      // Rol belirleme
      if(ticket == m_mainTicket)
      {
         m_positions[idx].role = ROLE_MAIN;
         m_positions[idx].spmLayer = 0;
      }
      else if(StringFind(comment, "BTFX_DCA_") >= 0)
      {
         m_positions[idx].role = ROLE_DCA;
         m_positions[idx].spmLayer = 0;
         // Parent ticket'i comment'ten cikar
         int dcaPos = StringFind(comment, "BTFX_DCA_");
         if(dcaPos >= 0)
         {
            string parentStr = StringSubstr(comment, dcaPos + 9);
            m_positions[idx].parentTicket = (ulong)StringToInteger(parentStr);
         }
      }
      else if(StringFind(comment, "BTFX_HEDGE_") >= 0)
      {
         m_positions[idx].role = ROLE_HEDGE;
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

   if(marginLevel < MinMarginLevel)
   {
      PrintFormat("[PM-%s] !!! MARGIN ACIL DURUM !!! Level=%.1f%% < %.1f%%",
                  m_symbol, marginLevel, MinMarginLevel);

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
//| ManageKarliPozisyonlar - v2.0 KAR ODAKLI                        |
//| PeakDrop SADECE SPM/DCA/HEDGE icin (ANA'yi kapatmaz)            |
//| TERFI (PromoteOldestSPMToMain) KALDIRILDI                       |
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

      //=== KURAL 1: SPM/DCA/HEDGE karda -> HEMEN KAPAT ===
      // Profil bazli kar hedefi kullan
      double closeTarget = m_profile.spmCloseProfit;
      if(role == ROLE_DCA) closeTarget = m_profile.profitTargetPerPos;

      if((role == ROLE_SPM || role == ROLE_DCA || role == ROLE_HEDGE) && profit >= closeTarget)
      {
         string roleStr = (role == ROLE_SPM) ? StringFormat("SPM%d", m_positions[i].spmLayer) :
                          (role == ROLE_DCA) ? "DCA" : "HEDGE";

         PrintFormat("[PM-%s] %s KAR: $%.2f >= $%.2f -> KAPAT + FIFO",
                     m_symbol, roleStr, profit, closeTarget);

         m_spmClosedProfitTotal += profit;
         m_spmClosedCount++;
         m_totalCashedProfit += profit;

         PrintFormat("[PM-%s] FIFO: +$%.2f -> Toplam=$%.2f (Sayi=%d) | Kasa=$%.2f",
                     m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount, m_totalCashedProfit);

         ClosePosWithNotification(i, StringFormat("%s_Kar_%.2f", roleStr, profit));
         continue;
      }

      //=== KURAL 2: Trend ANA tersinde, SPM karda -> KARLI KAPAT ===
      if((role == ROLE_SPM || role == ROLE_DCA || role == ROLE_HEDGE) && profit >= 1.0)
      {
         int mainIdx = FindMainPosition();
         if(mainIdx >= 0)
         {
            ENUM_SIGNAL_DIR trendDir = SIGNAL_NONE;
            if(m_signalEngine != NULL)
               trendDir = m_signalEngine.GetCurrentTrend();

            ENUM_SIGNAL_DIR mainDir = SIGNAL_NONE;
            if(m_positions[mainIdx].type == POSITION_TYPE_BUY) mainDir = SIGNAL_BUY;
            else mainDir = SIGNAL_SELL;

            ENUM_SIGNAL_DIR posDir = SIGNAL_NONE;
            if(m_positions[i].type == POSITION_TYPE_BUY) posDir = SIGNAL_BUY;
            else posDir = SIGNAL_SELL;

            // Trend ANA yonune donuyorsa VE pozisyon ana tersinde ise
            if(trendDir == mainDir && posDir != mainDir && profit >= 1.0)
            {
               string roleStr = (role == ROLE_SPM) ? StringFormat("SPM%d", m_positions[i].spmLayer) :
                                (role == ROLE_DCA) ? "DCA" : "HEDGE";
               PrintFormat("[PM-%s] TREND DONUS: %s karda ($%.2f), trend ANA yonune -> KARLI KAPAT",
                           m_symbol, roleStr, profit);

               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
               m_totalCashedProfit += profit;

               ClosePosWithNotification(i, StringFormat("TrendDonus_%s_Kar_%.2f", roleStr, profit));
               continue;
            }
         }
      }

      //=== KURAL 3: Mum terse dondu + SPM karda -> KARLI KAPAT ===
      // v2.0: SADECE SPM/DCA/HEDGE icin (ANA'yi kapatmaz)
      if(newBar && profit >= 1.5 && role != ROLE_MAIN)
      {
         ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
         bool candleAgainst = false;

         if(m_positions[i].type == POSITION_TYPE_BUY && candleDir == SIGNAL_SELL)
            candleAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && candleDir == SIGNAL_BUY)
            candleAgainst = true;

         if(candleAgainst)
         {
            string roleStr = (role == ROLE_SPM) ? StringFormat("SPM%d", m_positions[i].spmLayer) :
                             (role == ROLE_DCA) ? "DCA" : "HEDGE";
            PrintFormat("[PM-%s] MUM DONUS: %s #%d karda ($%.2f) + mum terse dondu -> KAPAT",
                        m_symbol, roleStr, (int)ticket, profit);

            m_spmClosedProfitTotal += profit;
            m_spmClosedCount++;
            m_totalCashedProfit += profit;
            m_dailyProfit += profit;

            ClosePosWithNotification(i, "MumDonus_Kar_" + DoubleToString(profit, 2));
            continue;
         }
      }

      //=== KURAL 4: Engulfing formasyonu ile karli kapat ===
      // v2.0: SADECE SPM/DCA/HEDGE icin
      if(newBar && profit >= 0.80 && role != ROLE_MAIN)
      {
         int engulfPattern = m_candle.DetectEngulfing();
         bool engulfAgainst = false;

         if(m_positions[i].type == POSITION_TYPE_BUY && engulfPattern == -1)
            engulfAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && engulfPattern == +1)
            engulfAgainst = true;

         if(engulfAgainst)
         {
            string roleStr = (role == ROLE_SPM) ? StringFormat("SPM%d", m_positions[i].spmLayer) :
                             (role == ROLE_DCA) ? "DCA" : "HEDGE";
            PrintFormat("[PM-%s] ENGULFING: %s #%d karda ($%.2f) -> KAPAT",
                        m_symbol, roleStr, (int)ticket, profit);

            m_spmClosedProfitTotal += profit;
            m_spmClosedCount++;
            m_totalCashedProfit += profit;

            ClosePosWithNotification(i, "Engulfing_Kar_" + DoubleToString(profit, 2));
            continue;
         }
      }

      //=== KURAL 5: Peak drop %50 -> Karini koru ===
      // v2.0: SADECE SPM/DCA/HEDGE icin (ANA'yi PeakDrop ile kapatmaz)
      if(role != ROLE_MAIN)
      {
         double peakVal = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : profit;
         if(peakVal >= PeakMinProfit && profit > 0.0)
         {
            double dropPct = (peakVal - profit) / peakVal * 100.0;
            if(dropPct >= PeakDropPercent)
            {
               string roleStr = (role == ROLE_SPM) ? StringFormat("SPM%d", m_positions[i].spmLayer) :
                                (role == ROLE_DCA) ? "DCA" : "HEDGE";
               PrintFormat("[PM-%s] PEAK DROP: %s #%d Peak=$%.2f Now=$%.2f Drop=%.0f%% -> KAPAT",
                           m_symbol, roleStr, (int)ticket, peakVal, profit, dropPct);

               m_spmClosedProfitTotal += profit;
               m_spmClosedCount++;
               m_totalCashedProfit += profit;

               ClosePosWithNotification(i, StringFormat("PeakDrop_%.0f%%", dropPct));
               continue;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ManageSPMSystem - v2.0: 5+5 yapi SPM motoru                      |
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
//| ManageMainInLoss - v2.0: profil bazli tetik                      |
//+------------------------------------------------------------------+
void CPositionManager::ManageMainInLoss(int mainIdx, double mainProfit)
{
   if(GetActiveSPMCount() > 0) return;

   // Profil bazli tetik
   if(mainProfit > m_profile.spmTriggerLoss) return;

   // Bakiye kontrolu
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + m_profile.spmCooldownSec) return;

   // Paused
   if(IsTradingPaused()) return;

   // Margin kontrolu
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel) return;

   // Toplam hacim kontrolu
   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   // v2.0: BUY/SELL katman limiti kontrol
   ENUM_SIGNAL_DIR spmDir = DetermineSPMDirection(0);

   if(spmDir == SIGNAL_NONE)
   {
      // Fallback: ana tersine
      if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
         spmDir = SIGNAL_SELL;
      else
         spmDir = SIGNAL_BUY;
   }

   // Ayni yon bloklama - ASLA zarardaki yonde ikiye katlama
   if(CheckSameDirectionBlock(spmDir))
   {
      PrintFormat("[PM-%s] SPM1 SAME-DIR BLOCK! Override: ANA tersine zorunlu.", m_symbol);
      if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
         spmDir = SIGNAL_SELL;
      else
         spmDir = SIGNAL_BUY;
   }

   // v2.0: BUY/SELL katman limiti
   if(spmDir == SIGNAL_BUY && GetBuyLayerCount() >= m_profile.spmMaxBuyLayers)
   {
      PrintFormat("[PM-%s] SPM1: BUY katman limiti (%d/%d)", m_symbol, GetBuyLayerCount(), m_profile.spmMaxBuyLayers);
      return;
   }
   if(spmDir == SIGNAL_SELL && GetSellLayerCount() >= m_profile.spmMaxSellLayers)
   {
      PrintFormat("[PM-%s] SPM1: SELL katman limiti (%d/%d)", m_symbol, GetSellLayerCount(), m_profile.spmMaxSellLayers);
      return;
   }

   // ANA toparlanma bekleme kontrolu
   if(ShouldWaitForANARecovery(mainIdx))
   {
      PrintFormat("[PM-%s] SPM1 BEKLE: Trend ANA yonune donuyor, toparlanma bekleniyor.", m_symbol);
      return;
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
               m_symbol, mainProfit, m_profile.spmTriggerLoss,
               (spmDir == SIGNAL_BUY) ? "BUY" : "SELL", spmLot);

   OpenSPM(spmDir, spmLot, 1, m_positions[mainIdx].ticket);
}

//+------------------------------------------------------------------+
//| ManageActiveSPMs - v2.0: 5+5 yapi                                |
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
      if(spmLayer == highestLayer && spmProfit <= m_profile.spmTriggerLoss)
      {
         int nextLayer = highestLayer + 1;

         // v2.0: BUY/SELL ayri katman limiti
         ENUM_SIGNAL_DIR nextDir = DetermineSPMDirection(spmLayer);

         // Ayni yon bloklama
         if(CheckSameDirectionBlock(nextDir))
         {
            PrintFormat("[PM-%s] SPM%d SAME-DIR BLOCK! Override: ANA tersine.", m_symbol, nextLayer);
            if(m_positions[mainIdx].type == POSITION_TYPE_BUY)
               nextDir = SIGNAL_SELL;
            else
               nextDir = SIGNAL_BUY;
         }

         // Katman limiti kontrol (5+5 yapi)
         if(nextDir == SIGNAL_BUY && GetBuyLayerCount() >= m_profile.spmMaxBuyLayers)
         {
            if(!m_spmLimitLogged)
            {
               PrintFormat("[PM-%s] SPM%d: BUY katman MAX (%d/%d)", m_symbol, nextLayer,
                           GetBuyLayerCount(), m_profile.spmMaxBuyLayers);
               m_spmLimitLogged = true;
            }
            continue;
         }
         if(nextDir == SIGNAL_SELL && GetSellLayerCount() >= m_profile.spmMaxSellLayers)
         {
            if(!m_spmLimitLogged)
            {
               PrintFormat("[PM-%s] SPM%d: SELL katman MAX (%d/%d)", m_symbol, nextLayer,
                           GetSellLayerCount(), m_profile.spmMaxSellLayers);
               m_spmLimitLogged = true;
            }
            continue;
         }

         // Kontroller
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         if(balance < MinBalanceToTrade) continue;
         if(TimeCurrent() < m_lastSPMTime + m_profile.spmCooldownSec) continue;
         if(IsTradingPaused()) continue;

         double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
         if(marginLevel > 0.0 && marginLevel < MinMarginLevel) continue;

         double totalVol = GetTotalBuyLots() + GetTotalSellLots();
         if(totalVol >= MaxTotalVolume) continue;

         // ANA toparlanma bekleme
         if(ShouldWaitForANARecovery(mainIdx))
         {
            PrintFormat("[PM-%s] SPM%d BEKLE: Trend ANA yonune donuyor.", m_symbol, nextLayer);
            continue;
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
//| ManageDCA - v2.0 YENI: Maliyet Ortalama Mekanizmasi              |
//| Zarardaki SPM icin ayni yonde, ayni lotta yeni pozisyon          |
//| Ortalama maliyet yariladi → kurtarma mesafesi kisaldi             |
//+------------------------------------------------------------------+
void CPositionManager::ManageDCA()
{
   // Cooldown
   if(TimeCurrent() < m_lastDCATime + DCA_CooldownSec) return;

   // Bakiye + margin kontrol
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel) return;
   if(IsTradingPaused()) return;

   // ATR lazim
   double currentATR = 0.0;
   if(m_signalEngine != NULL)
      currentATR = m_signalEngine.GetATR();
   if(currentATR <= 0.0) return;

   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM) continue;
      if(m_positions[i].profit >= 0.0) continue;  // Sadece zarardaki SPM'ler

      // Zarar kontrolu
      if(m_positions[i].profit > m_profile.spmTriggerLoss) continue;

      // Bu SPM'nin zaten DCA'si var mi?
      int dcaCount = 0;
      for(int j = 0; j < m_posCount; j++)
      {
         if(m_positions[j].role == ROLE_DCA && m_positions[j].parentTicket == m_positions[i].ticket)
            dcaCount++;
      }
      if(dcaCount >= DCA_MaxPerPosition) continue;

      // Fiyat mesafesi kontrolu (ATR * DCA_DistanceATR)
      double currentPrice = (m_positions[i].type == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(currentPrice <= 0.0) continue;

      double distance = MathAbs(currentPrice - m_positions[i].openPrice);
      double requiredDistance = currentATR * m_profile.dcaDistanceATR;

      if(distance < requiredDistance) continue;

      // Toplam hacim kontrolu
      double totalVol = GetTotalBuyLots() + GetTotalSellLots();
      if(totalVol + m_positions[i].volume > MaxTotalVolume) continue;

      // DCA yonu = SPM ile ayni yon
      ENUM_SIGNAL_DIR dcaDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

      // Lot denge kontrolu
      if(!CheckLotBalance(dcaDir, m_positions[i].volume)) continue;

      PrintFormat("[PM-%s] DCA TETIK: SPM%d #%d zarar=$%.2f mesafe=%.5f >= %.5f(ATR*%.1f)",
                  m_symbol, m_positions[i].spmLayer, (int)m_positions[i].ticket,
                  m_positions[i].profit, distance, requiredDistance, m_profile.dcaDistanceATR);

      OpenDCA(i);
      return;  // Bir tick'te max 1 DCA
   }
}

//+------------------------------------------------------------------+
//| ManageEmergencyHedge - v2.0.1: Guclendirilmis Acil Hedge         |
//| KOSULLAR:                                                         |
//|  1. En az 2 SPM aktif olmali (tek pozisyonda hedge SACMA)         |
//|  2. Iki tarafta da pozisyon olmali (oran hesabi anlamli olsun)    |
//|  3. Lot oran > 2.0 VE zarardaki taraf buyukse                    |
//|  4. Toplam zarar > SPM tetik esigi (anlamli zarar biriktikten)   |
//+------------------------------------------------------------------+
void CPositionManager::ManageEmergencyHedge()
{
   // Cooldown
   if(TimeCurrent() < m_lastHedgeTime + Hedge_CooldownSec) return;
   if(IsTradingPaused()) return;

   //--- KOSUL 1: En az N SPM aktif olmali (profil bazli)
   // Tek pozisyon veya ANA+1SPM durumunda hedge gereksiz
   // SPM sistemi kendi isini yapiyor, hedge sadece CIDDI dengesizlikte devreye girer
   int activeSPMs = GetActiveSPMCount();
   if(activeSPMs < m_profile.hedgeMinSPMCount) return;

   double totalBuyLot = GetTotalBuyLots();
   double totalSellLot = GetTotalSellLots();

   //--- KOSUL 2: Iki tarafta da pozisyon olmali
   // Tek tarafta pozisyon varken oran hesabi anlamsiz (0.01/0 = sonsuz)
   if(totalBuyLot <= 0.0 || totalSellLot <= 0.0) return;

   double maxSide = MathMax(totalBuyLot, totalSellLot);
   double minSide = MathMin(totalBuyLot, totalSellLot);
   double ratio = maxSide / minSide;

   //--- KOSUL 3: Oran tetigi
   if(ratio <= Hedge_RatioTrigger) return;

   //--- KOSUL 4: Toplam zarar kontrolu - anlamli zarar biriktikten sonra
   double buyPnL = 0.0, sellPnL = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].type == POSITION_TYPE_BUY)
         buyPnL += m_positions[i].profit;
      else
         sellPnL += m_positions[i].profit;
   }

   // Zarardaki tarafin toplam zarari yeterince buyuk olmali (profil bazli)
   double losingPnL = MathMin(buyPnL, sellPnL);  // en cok zarardaki taraf
   if(losingPnL > m_profile.hedgeMinLossUSD) return;  // Yeterince zarar yok (BTC:-$10, XAG:-$8)

   // Hangi taraf buyuk + zarardaki?
   bool zarar_taraf_buyuk = false;

   if(totalBuyLot > totalSellLot && buyPnL < 0.0)
      zarar_taraf_buyuk = true;
   else if(totalSellLot > totalBuyLot && sellPnL < 0.0)
      zarar_taraf_buyuk = true;

   if(!zarar_taraf_buyuk)
   {
      // Karli taraf buyuk → dogal akis, hedge gerekmiyor
      return;
   }

   // Hedge: Eksik tarafta pozisyon ac (karsi yon)
   double fark = MathAbs(totalBuyLot - totalSellLot);
   double hedgeLot = fark * Hedge_FillPercent;

   // Normalize
   double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) hedgeLot = MathFloor(hedgeLot / lotStep) * lotStep;
   if(hedgeLot < minLot) hedgeLot = minLot;
   if(hedgeLot > maxLot) hedgeLot = maxLot;
   hedgeLot = NormalizeDouble(hedgeLot, 2);

   // Toplam hacim kontrolu
   double totalVol = totalBuyLot + totalSellLot;
   if(totalVol + hedgeLot > MaxTotalVolume) return;

   // Margin kontrolu
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel) return;

   // Hedge yonu: buyuk olan tarafin tersine
   ENUM_SIGNAL_DIR hedgeDir;
   if(totalBuyLot > totalSellLot)
      hedgeDir = SIGNAL_SELL;
   else
      hedgeDir = SIGNAL_BUY;

   PrintFormat("[PM-%s] ACIL HEDGE: BUY=%.2f(%s%.2f) SELL=%.2f(%s%.2f) Oran=%.1f > %.1f",
               m_symbol, totalBuyLot, (buyPnL >= 0) ? "+" : "", buyPnL,
               totalSellLot, (sellPnL >= 0) ? "+" : "", sellPnL,
               ratio, Hedge_RatioTrigger);
   PrintFormat("[PM-%s] HEDGE: %s %.2f lot (fark=%.2f * %.0f%%)",
               m_symbol, (hedgeDir == SIGNAL_BUY) ? "BUY" : "SELL",
               hedgeLot, fark, Hedge_FillPercent * 100.0);

   OpenHedge(hedgeDir, hedgeLot);
}

//+------------------------------------------------------------------+
//| CheckDeadlock - v2.0 YENI: Kilitlenme Tespit + Cikis             |
//| SPM acilamiyor + net degisim < $0.50 → 5dk sonra tum kapat      |
//+------------------------------------------------------------------+
void CPositionManager::CheckDeadlock()
{
   // Cooldown
   if(TimeCurrent() < m_deadlockCooldownUntil) return;

   // En az 2 pozisyon olmali (ANA + SPM)
   if(m_posCount < 2) { m_deadlockActive = false; return; }

   // Deadlock kontrol araligi
   static datetime lastCheck = 0;
   if(TimeCurrent() - lastCheck < Deadlock_CheckSec) return;
   lastCheck = TimeCurrent();

   double currentNet = CalcNetResult();
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(!m_deadlockActive)
   {
      // Kilitlenme izlemeye basla
      m_deadlockActive = true;
      m_deadlockCheckStart = TimeCurrent();
      m_deadlockLastNet = currentNet;
      return;
   }

   // Zaman kontrolu
   int elapsed = (int)(TimeCurrent() - m_deadlockCheckStart);
   if(elapsed < Deadlock_TimeoutSec) return;

   // Net degisim kontrolu
   double netChange = MathAbs(currentNet - m_deadlockLastNet);

   if(netChange < Deadlock_MinChange)
   {
      // Net neredeyse degismedi → POTANSIYEL KILITLENME
      // Zarar kontrolu: bakiyenin %15'inden fazla mi?
      double lossRatio = MathAbs(currentNet) / MathMax(balance, 1.0);

      if(currentNet < 0.0 && lossRatio > Deadlock_MaxLossRatio)
      {
         PrintFormat("[PM-%s] !!! KILITLENME TESPIT !!! Sure=%dsn Net=$%.2f Degisim=$%.2f < $%.2f Zarar=%.1f%%",
                     m_symbol, elapsed, currentNet, netChange, Deadlock_MinChange, lossRatio * 100.0);

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("KILITLENME %s: Net=$%.2f Zarar=%.1f%% - TUM KAPATILDI",
                                   m_symbol, currentNet, lossRatio * 100.0));
         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("KILITLENME %s: Net=$%.2f Zarar=%.1f%% - TUM KAPATILDI",
                                  m_symbol, currentNet, lossRatio * 100.0));

         CloseAllPositions("Kilitlenme_Net=" + DoubleToString(currentNet, 2));
         m_deadlockCooldownUntil = TimeCurrent() + Deadlock_CooldownSec;
         m_deadlockActive = false;
         ResetFIFO();
         SetProtectionCooldown("Kilitlenme");
         return;
      }
   }

   // Degisim yeterli → kilitlenme yok, tracker'i sifirla
   m_deadlockCheckStart = TimeCurrent();
   m_deadlockLastNet = currentNet;
}

//+------------------------------------------------------------------+
//| CalcNetResult - Toplam net P/L hesapla                            |
//+------------------------------------------------------------------+
double CPositionManager::CalcNetResult()
{
   double net = m_spmClosedProfitTotal;
   for(int i = 0; i < m_posCount; i++)
      net += m_positions[i].profit;
   return net;
}

//+------------------------------------------------------------------+
//| DetermineSPMDirection - 5-OY GERCEK ZAMANLI PIYASA ANALIZI      |
//| TUM katmanlar ayni 5-oy sistemi kullanir                         |
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
                     m_symbol, SPM_WaitMaxSec);
      }

      if(TimeCurrent() - m_spmWaitStart < SPM_WaitMaxSec)
         return true;

      PrintFormat("[PM-%s] SPM BEKLE SURESI DOLDU (%dsn). ANA hala zararda, SPM aciliyor.",
                  m_symbol, SPM_WaitMaxSec);
      m_spmWaitActive = false;
      return false;
   }

   //--- Hizalanma yok → bekleme yok, SPM hemen ac
   m_spmWaitActive = false;
   return false;
}

//+------------------------------------------------------------------+
//| CheckFIFOTarget - v2.0: Karsi kar birikimi ile net hesap         |
//| kasaKar + acikSPMKar + acikSPMZarar + anaP/L >= +$5 → TUM KAPAT|
//| ANA SADECE FIFO ile kapanir (PeakDrop/MumDonus ANA'yi kapatmaz) |
//+------------------------------------------------------------------+
void CPositionManager::CheckFIFOTarget()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   double mainProfit = m_positions[mainIdx].profit;

   // v2.0: ANA karda olsa bile FIFO kontrolu yap
   // (SPM'lerden biriken kasa + ANA kar = toplam net)

   // Acik SPM/DCA/HEDGE P/L
   double openProfit = 0.0;
   double openLoss   = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM || m_positions[i].role == ROLE_DCA || m_positions[i].role == ROLE_HEDGE)
      {
         if(m_positions[i].profit >= 0.0)
            openProfit += m_positions[i].profit;
         else
            openLoss += m_positions[i].profit;  // negatif
      }
   }

   // v2.0 net hesap: kasa + acikKar + acikZarar + anaP/L
   double net = m_spmClosedProfitTotal + openProfit + openLoss + mainProfit;

   // Hedef ulasilmadi
   if(net < m_profile.fifoNetTarget)
   {
      m_fifoWaitStart = 0;
      return;
   }

   //--- HEDEF ULASILDI!
   PrintFormat("[PM-%s] FIFO HEDEF: Net=$%.2f >= $%.2f", m_symbol, net, m_profile.fifoNetTarget);

   //--- v2.0: HEMEN kapat (trend bekleme KALDIRILDI - hedef tutuyorsa hemen al)
   PrintFormat("[PM-%s] +++ FIFO HEDEF ULASILDI +++ Net=$%.2f", m_symbol, net);
   PrintFormat("[PM-%s] FIFO: Kasa=$%.2f + AcikKar=$%.2f + AcikZarar=$%.2f + Ana=$%.2f = $%.2f",
               m_symbol, m_spmClosedProfitTotal, openProfit, openLoss, mainProfit, net);

   // Bildirim
   CloseMainWithFIFONotification(mainIdx, m_spmClosedProfitTotal + openProfit + openLoss, mainProfit, net);

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
      if(sig.direction != SIGNAL_NONE && sig.score >= SignalMinScore)
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
//| CheckLotBalance - v2.0: Lot denge kontrolu                       |
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

   // Tek tarafli birikim korumasi
   double oneSideMax = MaxTotalVolume * 0.6;
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
//| CalcSPMLot - v2.0: Profil bazli lot hesaplama                    |
//+------------------------------------------------------------------+
double CPositionManager::CalcSPMLot(double mainLot, int layer)
{
   double multiplier = m_profile.spmLotBase + (layer - 1) * m_profile.spmLotIncrement;
   if(multiplier > m_profile.spmLotCap) multiplier = m_profile.spmLotCap;
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
//| OpenDCA - v2.0 YENI: DCA (maliyet ortalama) pozisyonu ac         |
//+------------------------------------------------------------------+
void CPositionManager::OpenDCA(int sourceIdx)
{
   if(sourceIdx < 0 || sourceIdx >= m_posCount) return;
   if(m_executor == NULL) return;

   ENUM_SIGNAL_DIR dcaDir = (m_positions[sourceIdx].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
   double dcaLot = m_positions[sourceIdx].volume;  // Ayni lot

   // Normalize
   double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) dcaLot = MathFloor(dcaLot / lotStep) * lotStep;
   if(dcaLot < minLot) dcaLot = minLot;
   dcaLot = NormalizeDouble(dcaLot, 2);

   string comment = StringFormat("BTFX_DCA_%d", (int)m_positions[sourceIdx].ticket);
   if(StringLen(comment) > 25) comment = StringSubstr(comment, 0, 25);

   ulong newTicket = m_executor.OpenPosition(dcaDir, dcaLot, 0, 0, comment);

   if(newTicket > 0)
   {
      m_lastDCATime = TimeCurrent();

      PrintFormat("[PM-%s] DCA ACILDI: #%d %s Lot=%.2f Parent=#%d OrtMaliyet yariladi",
                  m_symbol, (int)newTicket,
                  (dcaDir == SIGNAL_BUY) ? "BUY" : "SELL", dcaLot,
                  (int)m_positions[sourceIdx].ticket);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("DCA %s: %s Lot=%.2f #%d Parent=#%d",
                                m_symbol, (dcaDir == SIGNAL_BUY) ? "BUY" : "SELL", dcaLot,
                                (int)newTicket, (int)m_positions[sourceIdx].ticket));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("DCA %s: %s Lot=%.2f #%d",
                               m_symbol, (dcaDir == SIGNAL_BUY) ? "BUY" : "SELL", dcaLot, (int)newTicket));
   }
}

//+------------------------------------------------------------------+
//| OpenHedge - v2.0 YENI: Acil hedge pozisyonu ac                   |
//+------------------------------------------------------------------+
void CPositionManager::OpenHedge(ENUM_SIGNAL_DIR dir, double lot)
{
   if(m_executor == NULL) return;
   if(dir != SIGNAL_BUY && dir != SIGNAL_SELL) return;

   string comment = StringFormat("BTFX_HEDGE_%s", (dir == SIGNAL_BUY) ? "B" : "S");
   if(StringLen(comment) > 25) comment = StringSubstr(comment, 0, 25);

   ulong newTicket = m_executor.OpenPosition(dir, lot, 0, 0, comment);

   if(newTicket > 0)
   {
      m_lastHedgeTime = TimeCurrent();

      PrintFormat("[PM-%s] HEDGE ACILDI: #%d %s Lot=%.2f",
                  m_symbol, (int)newTicket,
                  (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("ACIL HEDGE %s: %s Lot=%.2f #%d",
                                m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)newTicket));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("ACIL HEDGE %s: %s Lot=%.2f #%d",
                               m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)newTicket));
   }
   else
   {
      PrintFormat("[PM-%s] HEDGE HATA: %s Lot=%.2f Err=%d",
                  m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ManageTPLevels - v2.0: TERFI KALDIRILDI                          |
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

   // TP3 - v2.0: ANA'yi kapatmaz, sadece log
   if(m_tp2Hit && m_tp3Price > 0.0 && !m_tpExtended)
   {
      bool hit = isBuy ? (currentPrice >= m_tp3Price) : (currentPrice <= m_tp3Price);
      if(hit)
      {
         m_tpExtended = true;
         m_currentTPLevel = 3;
         PrintFormat("[PM-%s] TP3 HIT: %.5f - FIFO ile kapanacak", m_symbol, currentPrice);

         // v2.0: ANA'yi TP3'te kapatmaz (FIFO ile kapanacak)
         // Sadece bildirim gonder
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
//| v2.0: BUY/SELL katman sayilari                                    |
//+------------------------------------------------------------------+
int CPositionManager::GetBuyLayerCount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].type == POSITION_TYPE_BUY)
         count++;
   return count;
}

int CPositionManager::GetSellLayerCount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].type == POSITION_TYPE_SELL)
         count++;
   return count;
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
//| PrintDetailedStatus - v2.0: DCA + HEDGE bilgileri eklendi         |
//+------------------------------------------------------------------+
void CPositionManager::PrintDetailedStatus()
{
   if(TimeCurrent() - m_lastStatusLog < 30) return;
   m_lastStatusLog = TimeCurrent();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   PrintFormat("============================================================");
   PrintFormat("[PM-%s] v2.0 DURUM @ %s", m_symbol, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
   PrintFormat("[PM-%s] Bakiye=$%.2f | Varlik=$%.2f | Margin=%.1f%%",
               m_symbol, balance, equity, marginLevel);
   PrintFormat("[PM-%s] Pozisyon=%d | Ana=#%d | SPM=%d | DCA=%d | Hedge=%d | Kasa=$%.2f",
               m_symbol, m_posCount, (int)m_mainTicket,
               GetActiveSPMCount(), GetActiveDCACount(), GetActiveHedgeCount(),
               m_totalCashedProfit);
   PrintFormat("[PM-%s] BUY=%d(%.2f lot) | SELL=%d(%.2f lot)",
               m_symbol, GetBuyLayerCount(), GetTotalBuyLots(),
               GetSellLayerCount(), GetTotalSellLots());
   PrintFormat("[PM-%s] FIFO: KapaliKar=$%.2f | Sayi=%d | Hedef=$%.2f",
               m_symbol, m_spmClosedProfitTotal, m_spmClosedCount, m_profile.fifoNetTarget);

   double totalPL = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      string roleStr = "???";
      if(m_positions[i].role == ROLE_MAIN) roleStr = "ANA";
      else if(m_positions[i].role == ROLE_SPM) roleStr = StringFormat("SPM%d", m_positions[i].spmLayer);
      else if(m_positions[i].role == ROLE_DCA) roleStr = "DCA";
      else if(m_positions[i].role == ROLE_HEDGE) roleStr = "HEDGE";

      string typeStr = (m_positions[i].type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double peak = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : 0.0;

      PrintFormat("[PM-%s] [%s] #%d %s Vol=%.2f P/L=$%.2f Peak=$%.2f",
                  m_symbol, roleStr, (int)m_positions[i].ticket,
                  typeStr, m_positions[i].volume, m_positions[i].profit, peak);
      totalPL += m_positions[i].profit;
   }

   double net = CalcNetResult();
   PrintFormat("[PM-%s] Toplam Acik P/L=$%.2f | Net(kasa+acik)=$%.2f / Hedef=$%.2f",
               m_symbol, totalPL, net, m_profile.fifoNetTarget);

   if(m_tradingPaused)
   {
      int remaining = (int)(m_protectionCooldownUntil - TimeCurrent());
      PrintFormat("[PM-%s] KORUMA: Durduruldu | Kalan=%dsn | Tetik=%d",
                  m_symbol, MathMax(remaining, 0), m_protectionTriggerCount);
   }

   if(m_deadlockActive)
   {
      int elapsed = (int)(TimeCurrent() - m_deadlockCheckStart);
      PrintFormat("[PM-%s] KILITLENME IZLEME: %d/%dsn",
                  m_symbol, elapsed, Deadlock_TimeoutSec);
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
//| GetActiveSPMCount / GetActiveDCACount / GetActiveHedgeCount       |
//+------------------------------------------------------------------+
int CPositionManager::GetActiveSPMCount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_SPM) count++;
   return count;
}

int CPositionManager::GetActiveDCACount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_DCA) count++;
   return count;
}

int CPositionManager::GetActiveHedgeCount()
{
   int count = 0;
   for(int i = 0; i < m_posCount; i++)
      if(m_positions[i].role == ROLE_HEDGE) count++;
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

   string roleStr = "???";
   if(m_positions[idx].role == ROLE_MAIN) roleStr = "ANA";
   else if(m_positions[idx].role == ROLE_SPM) roleStr = StringFormat("SPM%d", m_positions[idx].spmLayer);
   else if(m_positions[idx].role == ROLE_DCA) roleStr = "DCA";
   else if(m_positions[idx].role == ROLE_HEDGE) roleStr = "HEDGE";

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

   string msg = StringFormat("FIFO HEDEF %s: SPM=$%.2f Ana=$%.2f Net=$%.2f >= $%.2f | Kapat=%d | BUY=%d SELL=%d",
      m_symbol, spmKar, mainZarar, net, m_profile.fifoNetTarget,
      m_spmClosedCount, GetBuyLayerCount(), GetSellLayerCount());

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
   PrintFormat("[PM-%s] FIFO RESET: Kar=$%.2f Sayi=%d",
               m_symbol, m_spmClosedProfitTotal, m_spmClosedCount);
   m_spmClosedProfitTotal = 0.0;
   m_spmClosedCount       = 0;
   m_spmLayerCount        = 0;
   m_spmLimitLogged       = false;
   ArrayInitialize(m_peakProfit, 0.0);
   m_currentTPLevel = 0;
   m_tp1Hit = false;
   m_tp2Hit = false;
   m_tpExtended = false;
   m_deadlockActive = false;
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
