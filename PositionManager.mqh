#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH
//+------------------------------------------------------------------+
//|                                             PositionManager.mqh  |
//|                                    Copyright 2026, By T@MER      |
//|                                    https://www.bytamer.com        |
//|                                                                  |
//|              v3.4.0 - Bi-Directional Trend-Grid + Akilli Kar     |
//+------------------------------------------------------------------+
//|  SISTEM MANTIGI (v3.4.0 BiDir-Grid):                             |
//|  H1 trend 3-kaynak oylama ile tespit (EMA+MACD+ADX) + ardisik   |
//|  onay (whipsaw korunmasi). Trend degisince:                      |
//|   - Yeni trend yonunde grid acar (AKTIF GRUP)                    |
//|   - Eski yondeki gridler LEGACY olur (karlilar kapatilir)        |
//|   - Legacy gridler FIFO ile ANA'yi kapatir                       |
//|   - Kasa birikim → ANA kapanir → Terfi → dongu devam            |
//|  Volatilite rejimi: LOW/NORMAL/HIGH/EXTREME adaptif grid mesafe  |
//|  Trend gucune gore akilli kar: Zayif=$0.50 Orta=$1.50 Guclu=$3  |
//|  Ters piramit: Her grid lot %5 azalir (risk kontrolu)            |
//|  Haber entegrasyonu: Grid genisleme + yeni grid engelleme        |
//+------------------------------------------------------------------+
//|  KURALLAR:                                                       |
//|  1. SL YOK - ASLA (MUTLAK)                                      |
//|  2. ANA SADECE FIFO ile kapanir (kasa + ANA zarar >= +$5)       |
//|  3. MUM DONUS = HEMEN KAPAT (karda ise beklemeden kapat)         |
//|  4. Grid 10+10 yapi: max 10 BUY + 10 SELL                       |
//|  5. Grid yon: v3.4.0 bi-dir (trend degisince iki yon aktif)     |
//|  6. Grid tetik: Adaptif ATR mesafe (volatilite bazli)            |
//|  7. Grid kar: Trend gucune gore dinamik                          |
//|  8. FIFO net hedef: +$5 (kapanmis grid birikimi)                |
//|  9. HEDGE: v3.5.8 RESCUE HEDGE AKTIF | Margin kapatma: YOK      |
//| 10. TERFI: ANA kapaninca en eski Grid → ANA, kasa sifirlanir    |
//| 11. Grid max: Bakiye bazli (margin call onleme)                  |
//| 12. Enstruman bazli parametreler (SymbolProfile)                 |
//| 13. Killswitch: EnableReverseGrid=false → v3.0.0 davranisi      |
//+------------------------------------------------------------------+

#include "Config.mqh"
#include "TradeExecutor.mqh"
#include "SignalEngine.mqh"
#include "CandleAnalyzer.mqh"
#include "TelegramMsg.mqh"
#include "DiscordMsg.mqh"
#include "NewsManager.mqh"

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
   datetime             m_lastHedgeCloseTime;   // v3.6.6: HEDGE kapandiktan sonra cooldown
   datetime             m_lastStatusLog;
   datetime             m_fifoWaitStart;
   datetime             m_lastFIFOCompletionTime; // v4.0: FIFO tamamlandi zamani (sonraki mum bekleme)

   //--- TP management
   bool                 m_tpExtended;
   int                  m_currentTPLevel;
   double               m_tp1Price, m_tp2Price, m_tp3Price;
   bool                 m_tp1Hit, m_tp2Hit;
   ENUM_TREND_STRENGTH  m_trendStrength;

   //--- Peak profit tracking
   double               m_peakProfit[];
   ulong                m_peakTicket[];       // v3.6.5: Peak'in ait oldugu ticket (index degisince reset)

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
   datetime             m_peakDipCooldownUntil;  // v3.7.1: Tepe/Dip 30sn cooldown

   //--- v2.2.1: SPM log cooldown (tick basi spam onleme)
   datetime             m_lastSPMLogTime;
   bool                 m_spmDirOverridden;  // SAME-DIR BLOCK sonrasi override flag

   //--- v2.2.6: MarginKritik sonrasi toparlanma modu
   bool                 m_recoveryMode;
   double               m_preCrashBalance;
   datetime             m_recoveryModeStart;

   //--- v2.3.0: Trade istatistikleri
   int                  m_totalBuyTrades;     // Toplam BUY islem sayisi
   int                  m_totalSellTrades;    // Toplam SELL islem sayisi
   int                  m_dailyTradeCount;    // Bugun acilan islem sayisi
   double               m_dayStartBalance;    // Gun basi bakiye (% hesabi icin)

   //--- v3.0.0: Trend-Grid sistemi
   ENUM_SIGNAL_DIR      m_gridDirection;      // Grid yonu (H1 trend yonu)
   double               m_gridATR;            // Grid mesafesi icin ATR degeri
   double               m_lastGridPrice;      // Son grid pozisyonun acilis fiyati
   int                  m_gridCount;          // Aktif grid pozisyon sayisi
   int                  m_hATR14;             // H1 ATR handle
   datetime             m_lastTrendCheck;     // Son trend kontrol zamani

   //--- v3.4.0: Bi-Directional Grid sistemi
   ENUM_SIGNAL_DIR      m_activeGridDir;      // Aktif grid yonu (yeni trend)
   ENUM_SIGNAL_DIR      m_legacyGridDir;      // Eski grid yonu (yanlis taraf)
   int                  m_activeGridCount;    // Aktif yon grid sayisi
   int                  m_legacyGridCount;    // Eski yon grid sayisi
   double               m_legacyKasa;         // Eski grup icin ayri kasa
   bool                 m_biDirectionalMode;  // Bi-directional mod aktif mi
   bool                 m_biDirCooldownActive; // v3.5.3: Bi-dir zarar bazli bekleme aktif mi
   bool                 m_biDirLegacyDone;     // v4.1: Legacy=0 oldu, yeni trend degisimini bekle
   ENUM_VOLATILITY_REGIME m_volRegime;        // Mevcut volatilite rejimi
   CNewsManager*        m_newsManager;        // Haber yoneticisi referansi

   //--- v3.6.0: SPM Warmup (EA yuklendikten sonra grid acmayi bekle)
   datetime             m_spmWarmupUntil;      // SPM warmup bitis zamani (ilk 45sn)

   //--- v3.5.4: Adaptif broker spread baseline
   double               m_defaultBrokerSpread; // Adaptif broker spread baseline (her tick guncellenir)
   datetime             m_spreadWarmupUntil;   // Spread warmup bitis zamani (ilk 60sn)

   //--- v3.4.0: Post-Entry Karlilik Motoru
   bool                 m_partialClosed[];    // Kismi kapama yapildi mi (pozisyon bazli)
   bool                 m_breakevenLocked[];  // Breakeven kilidi aktif mi
   double               m_breakevenPrice[];   // Breakeven fiyat (entry price)

   //=================================================================
   // PRIVATE METHODS
   //=================================================================

   //--- Position scanning
   void AdoptExistingPositions();
   void RefreshPositions();

   //--- Core engine
   void ManageKarliPozisyonlar(bool newBar);
   void ManageSPMSystem();
   void ManageMainInLoss(int mainIdx, double mainProfit);
   void ManageActiveSPMs(int mainIdx);

   //--- v3.0.0: Trend-Grid
   void ManageTrendGrid();
   void CheckTrendDirection();
   double GetGridATR();
   int  GetMaxGridByBalance();
   void ManageTrendReversal();
   void CheckFIFOTarget();

   //--- v3.4.0: Bi-Directional Grid
   void ManageBiDirectionalGrid();
   void OpenReverseDirectionGrid();
   void ManageLegacyGroupRecovery();
   double GetAdaptiveGridSpacing();
   double GetSmartCloseTarget(ENUM_POS_ROLE role);
   double GetSmartCandleCloseMin();
   bool IsNewsNearby();

   //--- v3.4.0: Post-Entry Karlilik Motoru
   int  GetADXGridLimit();            // ADX bazli grid katman limiti
   void ManageBreakevenLock();        // Sanal breakeven kilidi
   double GetAdaptiveFIFOTarget();    // Hesap buyuklugune gore FIFO
   int  GetAdaptiveCooldown();        // Volatilite bazli cooldown

   //--- v3.5.0: Net Settlement + Zigzag Grid
   void CheckNetSettlement();          // Kasa - |worst| >= $5 → worst kapat
   void CheckSPMBalance();            // v3.5.7: Devre disi (zigzag dengeliyor)
   void CheckRescueHedge();           // v3.5.7: ANA -$30 → 1.5x lot hedge
   void ManageHedgePositions();       // v3.5.8: HEDGE akilli kapatma (ANA offset)

   //--- v3.6.0: Sinyal bazli SPM yonu
   ENUM_SIGNAL_DIR EvaluateSPMDirection(int mainIdx);  // Signal+Trend+Candle oylama ile SPM yonu
   ENUM_SIGNAL_DIR GetLastSPMDirection(); // Son SPM'in yonu (zigzag icin)
   bool IsSpreadAcceptable();          // Spread kontrolu
   bool IsPeakOrDip();                // Tepe/dip koruma

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
   int  GetSPMCountForSide(ENUM_SIGNAL_DIR side);  // v3.6.7: Sadece SPM/DCA sayar (ANA+HEDGE haric)

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

   //--- Protection
   bool CheckMarginEmergency();
   bool CheckSymbolLossLimit();       // v3.8.0: Sembol bazli toplam kayip limiti

   //--- Notification helpers
   void ClosePosWithNotification(int idx, string reason);
   void CloseMainWithFIFONotification(int mainIdx, double spmKar, double mainZarar, double net);

   //--- v2.3.0: Terfi mekanizmasi
   void PromoteOldestSPM();
   void RenumberSPMLayers();

   //--- Helpers
   int    FindMainPosition();
   int    GetActiveSPMCount();
   int    GetActiveDCACount();
   int    GetActiveHedgeCount();
   int    GetHighestLayer();
   string GetCatName();
   void   ResetFIFO();
   void   CloseAllPositions(string reason);
   void   SmartClosePosition(int idx, ENUM_POS_ROLE role, double profit, string reason);
   void   SetProtectionCooldown(string reason);
   void   PrintDetailedStatus();

   //--- v3.7.0: Kademeli Kurtarma yardimci fonksiyonlari
   bool   HasDirectionSupport(ENUM_SIGNAL_DIR dir);   // trend/sinyal/mum'dan en az 1 destek
   int    FindSPMByLayer(int layer);                   // Layer numarasina gore SPM bul
   void   CloseWorstSPM(string reason);                // En zarardaki SPM'yi kapat (FIFO Path A)

   //--- v4.2.0: Net-Exposure SPM + Grid Reset
   ENUM_SIGNAL_DIR GetNetExposureDirection(int mainIdx);  // BUY/SELL dengesi → SPM yonu
   bool   CheckGridHealth();                              // Grid saglik kontrolu → reset

   //--- v4.3.0: Telegram zengin mesaj yardimcilari
   string GetPositionMapHTML();    // Pozisyon haritasi (HTML)
   string GetCategoryName();      // Kategori adi

   //--- v3.7.1: Tepe/Dip koruma
   bool   CheckPeakDipGate(ENUM_SIGNAL_DIR &dirOverride);  // Tepe/Dip → ADX bazli yon/cooldown
   double GetTotalBuyLots();
   double GetTotalSellLots();
   double CalcNetResult();

public:
                        CPositionManager();
                       ~CPositionManager() {}

   void                 Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat,
                                   CTradeExecutor &executor, CSignalEngine &engine,
                                   CTelegramMsg &telegram, CDiscordMsg &discord,
                                   CNewsManager *newsMgr = NULL);
   void                 OnTick();

   bool                 HasPosition() const;
   bool                 IsTradingPaused() const;
   bool                 IsInRecoveryMode();     // v2.2.6: MarginKritik sonrasi toparlanma
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
   m_lastHedgeCloseTime  = 0;
   m_lastStatusLog       = 0;
   m_fifoWaitStart       = 0;
   m_lastFIFOCompletionTime = 0; // v4.0
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
   ArrayResize(m_peakTicket, MAX_POSITIONS);
   ArrayFill(m_peakTicket, 0, MAX_POSITIONS, 0);

   // v3.4.0: Post-Entry dizileri
   ArrayResize(m_partialClosed, MAX_POSITIONS);
   ArrayInitialize(m_partialClosed, false);
   ArrayResize(m_breakevenLocked, MAX_POSITIONS);
   ArrayInitialize(m_breakevenLocked, false);
   ArrayResize(m_breakevenPrice, MAX_POSITIONS);
   ArrayInitialize(m_breakevenPrice, 0.0);

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
   m_peakDipCooldownUntil = 0;  // v3.7.1
   m_lastSPMLogTime      = 0;
   m_spmDirOverridden    = false;

   m_recoveryMode        = false;
   m_preCrashBalance     = 0.0;
   m_recoveryModeStart   = 0;

   //--- v2.3.0: Trade istatistikleri
   m_totalBuyTrades      = 0;
   m_totalSellTrades     = 0;
   m_dailyTradeCount     = 0;
   m_dayStartBalance     = 0.0;

   //--- v3.0.0: Trend-Grid init
   m_gridDirection       = SIGNAL_NONE;
   m_gridATR             = 0.0;
   m_lastGridPrice       = 0.0;
   m_gridCount           = 0;
   m_hATR14              = INVALID_HANDLE;
   m_lastTrendCheck      = 0;

   //--- v3.4.0: Bi-Directional Grid init
   m_activeGridDir       = SIGNAL_NONE;
   m_legacyGridDir       = SIGNAL_NONE;
   m_activeGridCount     = 0;
   m_legacyGridCount     = 0;
   m_legacyKasa          = 0.0;
   m_biDirectionalMode   = false;
   m_biDirCooldownActive = false;
   m_biDirLegacyDone     = false;
   m_volRegime           = VOL_NORMAL;
   m_newsManager         = NULL;
   m_defaultBrokerSpread = 0.0;
   m_spreadWarmupUntil   = 0;

   m_profile.SetDefault();
}

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
void CPositionManager::Initialize(string symbol, ENUM_SYMBOL_CATEGORY cat,
                                  CTradeExecutor &executor, CSignalEngine &engine,
                                  CTelegramMsg &telegram, CDiscordMsg &discord,
                                  CNewsManager *newsMgr)
{
   m_symbol       = symbol;
   m_category     = cat;
   m_executor     = GetPointer(executor);
   m_signalEngine = GetPointer(engine);
   m_telegram     = GetPointer(telegram);
   m_discord      = GetPointer(discord);
   m_newsManager  = newsMgr;

   m_startBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   m_dayStartBalance = m_startBalance;  // v2.3.0: Gun basi bakiye
   m_dailyResetTime = iTime(m_symbol, PERIOD_D1, 0);

   // v3.6.0: SPM Warmup - EA yuklendikten sonra grid acmayi bekle
   m_spmWarmupUntil = TimeCurrent() + SPM_WarmupSec;
   PrintFormat("[PM-%s] v%s WARMUP: %d saniye SPM beklemesi baslatildi (bitis: %s)",
               m_symbol, EA_VERSION, SPM_WarmupSec,
               TimeToString(m_spmWarmupUntil, TIME_MINUTES | TIME_SECONDS));

   // v3.5.4: Adaptif spread - Initialize'da sadece ilk degeri al, IsSpreadAcceptable'da guncellenir
   m_defaultBrokerSpread = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   m_spreadWarmupUntil   = TimeCurrent() + 60;  // 60sn warmup — baseline oturene kadar
   if(m_defaultBrokerSpread > 0)
      PrintFormat("[PM-%s] SPREAD BASELINE: Baslangic = %.0f (60sn warmup)", m_symbol, m_defaultBrokerSpread);

   m_candle.Initialize(m_symbol, PERIOD_M15);

   //--- v2.0: Enstruman profili yukle
   m_profile = GetSymbolProfile(m_category, m_symbol);

   PrintFormat("[PM-%s] PositionManager v%s BiDir-Grid | Cat=%s | Profil=%s | Balance=%.2f",
               m_symbol, EA_VERSION, GetCatName(), m_profile.profileName, m_startBalance);
   PrintFormat("[PM-%s] GRID: Adaptif ATR | Close=$%.1f | FIFO Net=$%.1f | MaxBuy=%d MaxSell=%d",
               m_symbol, m_profile.spmCloseProfit,
               m_profile.fifoNetTarget, m_profile.spmMaxBuyLayers, m_profile.spmMaxSellLayers);
   PrintFormat("[PM-%s] GRID Lot: Base=%.1f | Inc=%.2f | Cap=%.1f | Cooldown=%ds",
               m_symbol, m_profile.spmLotBase, m_profile.spmLotIncrement,
               m_profile.spmLotCap, m_profile.spmCooldownSec);
   PrintFormat("[PM-%s] v%s: BiDir=%s | TrendCheck=%dsn | Confirm=%d | LotReduce=%.0f%% | VolRegime=ADAPTIF",
               m_symbol, EA_VERSION,
               EnableReverseGrid ? "AKTIF" : "KAPALI",
               TrendCheckIntervalSec, TrendConfirmCount,
               LotReductionPerGrid * 100.0);
   PrintFormat("[PM-%s] v%s: GridATR: Low=%.1fx Norm=%.1fx High=%.1fx | CandleClose: W=$%.2f M=$%.2f S=$%.2f",
               m_symbol, EA_VERSION,
               m_profile.gridATRMultLow, m_profile.gridATRMultNormal, m_profile.gridATRMultHigh,
               m_profile.candleCloseWeak, m_profile.candleCloseModerate, m_profile.candleCloseStrong);
   PrintFormat("[PM-%s] v%s: TrendKarCarpani: Moderate=%.1fx Strong=%.1fx | News=%s Grid+%d%%",
               m_symbol, EA_VERSION,
               m_profile.trendCloseMultModerate, m_profile.trendCloseMultStrong,
               (m_newsManager != NULL) ? "AKTIF" : "YOK",
               NewsGridWidenPercent);
   PrintFormat("[PM-%s] KURALLAR: BIDIR-GRID | TERFI=AKTIF | ANA=SADECE_FIFO | SL=YOK | HEDGE=YOK",
               m_symbol);

   //--- v3.0.0: H1 ATR handle olustur (Trend-Grid mesafe hesabi icin)
   m_hATR14 = iATR(m_symbol, PERIOD_H1, 14);
   if(m_hATR14 == INVALID_HANDLE)
      PrintFormat("[PM-%s] UYARI: H1 ATR handle olusturulamadi! Grid mesafesi fallback kullanilacak.", m_symbol);
   else
      PrintFormat("[PM-%s] v%s: H1 ATR(14) handle=%d | BiDir-Grid sistemi aktif", m_symbol, EA_VERSION, m_hATR14);

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
      
      //--- v4.0: FIFO sonrasi sonraki mum bekleme (sonsuz dongu koruma)
      if(m_lastFIFOCompletionTime > 0)
      {
         datetime currentBarTime = iTime(m_symbol, PERIOD_M15, 0);
         datetime fifoBarTime = iTime(m_symbol, PERIOD_M15, 
                                       iBarShift(m_symbol, PERIOD_M15, m_lastFIFOCompletionTime));
         if(currentBarTime <= fifoBarTime)
            return; // Henuz yeni mum olusmadi, bekle
         
         // Yeni mum olustu, cooldown bitti
         m_lastFIFOCompletionTime = 0;
         PrintFormat("[PM-%s] FIFO cooldown bitti, yeni mum basladi (%s)", 
                     m_symbol, TimeToString(currentBarTime));
      }
      
      return;
   }

   //--- 3. Margin + Equity acil durum (v3.8.0: gercek koruma)
   if(CheckMarginEmergency())
      return;

   //--- 3b. v3.8.0: Sembol bazli toplam kayip limiti
   if(CheckSymbolLossLimit())
      return;

   //--- 4. Yeni bar kontrolu
   bool newBar = m_candle.CheckNewBar();

   //--- 5. KARLI POZISYONLARI YONET (kucuk karlari topla, kasaya ekle)
   ManageKarliPozisyonlar(newBar);

   //--- 5b. v3.4.0: Breakeven kilidi (kazananlari koru)
   ManageBreakevenLock();

   //--- 6. SPM SISTEMI (hedge + ters islem)
   ManageSPMSystem();

   //--- 7. FIFO NET HEDEF kontrolu
   CheckFIFOTarget();

   //--- 8. v3.5.0: Net Settlement (kasa - worst >= $5 → worst kapat)
   CheckNetSettlement();

   //--- 9. v3.5.7: Rescue Hedge (ANA -$30 → 1.5x toplam zararli lot)
   CheckRescueHedge();

   //--- 9a. v3.5.8: HEDGE akilli kapatma (ANA offset kontrol)
   ManageHedgePositions();

   //--- 9b. CheckSPMBalance devre disi - zigzag otomatik dengeliyor
   // CheckSPMBalance();

   //--- 10. v2.0: DCA (Maliyet Ortalama)
   ManageDCA();

   //--- 11. v2.0: Kilitlenme tespit (sadece uyari)
   CheckDeadlock();

   //--- 12. TP seviyeleri yonet
   ManageTPLevels();

   //--- 13. Detayli log (30 saniyede bir)
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
//| IsInRecoveryMode - v2.2.6: MarginKritik sonrasi toparlanma       |
//| Cikis: Bakiye >= crash oncesi %50 VEYA 24 saat gecti             |
//+------------------------------------------------------------------+
bool CPositionManager::IsInRecoveryMode()
{
   if(!m_recoveryMode) return false;

   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Cikis kosulu 1: Bakiye crash oncesinin %50'sine ulasti
   if(currentBalance >= m_preCrashBalance * 0.5)
   {
      PrintFormat("[PM-%s] TOPARLANMA BITTI: Bakiye=$%.2f >= Hedef=$%.2f (%50 of $%.2f)",
                  m_symbol, currentBalance, m_preCrashBalance * 0.5, m_preCrashBalance);
      m_recoveryMode = false;
      return false;
   }

   // Cikis kosulu 2: 24 saat gecti (manuel mudahale bekleniyor)
   if(TimeCurrent() - m_recoveryModeStart > 86400)
   {
      PrintFormat("[PM-%s] TOPARLANMA ZAMAN ASIMI: 24 saat gecti, mod kapatildi",
                  m_symbol);
      m_recoveryMode = false;
      return false;
   }

   return true;  // Hala toparlanma modunda - yeni islem ACMA
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

   // v2.3.0: Net hesap = kasa - ANA zarar (acik SPM P/L DAHIL DEGIL)
   double anaLoss = (mainIdx >= 0 && m_positions[mainIdx].profit < 0.0) ?
                     m_positions[mainIdx].profit : 0.0;
   summary.netResult = m_spmClosedProfitTotal + anaLoss;

   summary.targetUSD    = m_profile.fifoNetTarget;
   summary.isProfitable = (summary.netResult >= m_profile.fifoNetTarget);

   //--- v2.3.0: Dashboard istatistikleri
   summary.dailyProfit     = m_dailyProfit;
   summary.dailyProfitPct  = (m_dayStartBalance > 0.0) ? (m_dailyProfit / m_dayStartBalance * 100.0) : 0.0;
   summary.totalBuyTrades  = m_totalBuyTrades;
   summary.totalSellTrades = m_totalSellTrades;
   summary.dailyTradeCount = m_dailyTradeCount;

   //--- v3.4.0: Bi-directional durum
   summary.biDirectionalMode = m_biDirectionalMode;
   summary.activeGridDirStr  = (m_activeGridDir == SIGNAL_BUY) ? "BUY" :
                                (m_activeGridDir == SIGNAL_SELL) ? "SELL" : "-";
   summary.legacyGridDirStr  = (m_legacyGridDir == SIGNAL_BUY) ? "BUY" :
                                (m_legacyGridDir == SIGNAL_SELL) ? "SELL" : "-";
   summary.activeGridCount   = m_activeGridCount;
   summary.legacyGridCount   = m_legacyGridCount;
   summary.volatilityRegime  = (m_volRegime == VOL_LOW) ? "LOW" :
                                (m_volRegime == VOL_NORMAL) ? "NORMAL" :
                                (m_volRegime == VOL_HIGH) ? "HIGH" : "EXTREME";
   summary.adaptiveSpacing   = m_gridATR;

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
      m_dailyTradeCount = 0;  // v2.3.0: Gunluk islem sayaci sifirla
      m_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);  // v2.3.0: Gun basi bakiye
      m_spmLimitLogged = false;
   }

   //--- v2.2.1: mainTicket hala acik mi kontrol et (TP ile kapanmis olabilir)
   if(m_mainTicket > 0)
   {
      bool mainFound = false;
      for(int j = 0; j < totalPositions; j++)
      {
         ulong tk = PositionGetTicket(j);
         if(tk == m_mainTicket) { mainFound = true; break; }
      }
      if(!mainFound)
      {
         PrintFormat("[PM-%s] ANA #%llu artik yok (TP/SL ile kapanmis). Reset.", m_symbol, m_mainTicket);
         m_mainTicket = 0;
         ResetFIFO();
      }
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
      else if(m_mainTicket == 0)
      {
         //--- v2.2.1: mainTicket yoksa ilk bulunan bilinmeyen pozisyon ANA olur
         m_positions[idx].role = ROLE_MAIN;
         m_positions[idx].spmLayer = 0;
         m_mainTicket = ticket;
         PrintFormat("[PM-%s] ANA atandi: #%llu (mainTicket yoktu)", m_symbol, ticket);
      }
      else
      {
         //--- mainTicket var ama bu pozisyon ne? -> SPM olarak ata
         m_positions[idx].role = ROLE_SPM;
         m_positions[idx].spmLayer = 1;
      }

      // Peak profit - v3.6.5: ticket degisirse peak sifirla (eski pozisyon peak mirasi engelle)
      if(idx < ArraySize(m_peakProfit))
      {
         if(idx < ArraySize(m_peakTicket) && m_peakTicket[idx] != ticket)
         {
            m_peakProfit[idx] = 0.0;    // Yeni pozisyon, eski peak GECERSIZ
            m_peakTicket[idx] = ticket;
         }
         if(m_positions[idx].profit > m_peakProfit[idx])
            m_peakProfit[idx] = m_positions[idx].profit;
      }

      m_posCount++;
   }
}

//+------------------------------------------------------------------+
//| CheckMarginEmergency - v3.8.0: GERCEK EQUITY + MARGIN KORUMA   |
//| Seviye 1: Equity < %30 bakiye → TUM KAPAT (broker stop-out onle)|
//| Seviye 2: Margin < %150 → TUM KAPAT (acil durum)                |
//| Seviye 3: Margin < %300 → UYARI + yeni pozisyon ENGELLE         |
//+------------------------------------------------------------------+
bool CPositionManager::CheckMarginEmergency()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   if(balance <= 0.0) return false;
   if(m_posCount == 0) return false;  // Acik pozisyon yoksa kontrol gereksiz

   //--- SEVIYE 1: EQUITY KORUMA — equity < %30 bakiye → HERSEY KAPAT
   double equityRatio = (equity / balance) * 100.0;
   if(equityRatio < MaxDrawdownPercent)  // MaxDrawdownPercent = 30.0
   {
      PrintFormat("[PM-%s] !!! EQUITY ACIL !!! Equity=$%.2f / Balance=$%.2f = %.1f%% < %.0f%% → TUM KAPAT",
                  m_symbol, equity, balance, equityRatio, MaxDrawdownPercent);

      string msg = StringFormat("ACIL KAPAT %s: Equity=$%.2f (%.1f%%) < %.0f%% baraj! TUM KAPATILIYOR",
                                 m_symbol, equity, equityRatio, MaxDrawdownPercent);
      if(m_telegram != NULL) m_telegram.SendMessage(msg);
      if(m_discord != NULL)  m_discord.SendMessage(msg);

      CloseAllPositions(StringFormat("EQUITY_ACIL_%.1f%%", equityRatio));
      SetProtectionCooldown("EQUITY_ACIL");

      // v4.2.0 FIX: Recovery mode aktif et (24 saat veya bakiye %50 toparlaninca cikar)
      // EQUITY_ACIL sonrasi olum spiralini engeller — yeni islem ACILMAZ
      m_recoveryMode      = true;
      m_recoveryModeStart = TimeCurrent();
      m_preCrashBalance   = balance;

      PrintFormat("[PM-%s] v4.2.0 RECOVERY MODE: EQUITY_ACIL sonrasi aktif (bakiye=$%.2f, hedef=$%.2f)",
                  m_symbol, balance, balance * 0.5);

      return true;
   }

   //--- SEVIYE 2: MARGIN ACIL — margin < %150 → HERSEY KAPAT
   if(marginLevel > 0.0 && marginLevel < 150.0)
   {
      PrintFormat("[PM-%s] !!! MARGIN ACIL !!! Level=%.1f%% < 150%% → TUM KAPAT",
                  m_symbol, marginLevel);

      string msg = StringFormat("MARGIN ACIL %s: Level=%.1f%% < 150%%! TUM KAPATILIYOR",
                                 m_symbol, marginLevel);
      if(m_telegram != NULL) m_telegram.SendMessage(msg);
      if(m_discord != NULL)  m_discord.SendMessage(msg);

      CloseAllPositions(StringFormat("MARGIN_ACIL_%.0f%%", marginLevel));
      SetProtectionCooldown("MARGIN_ACIL");
      return true;
   }

   //--- SEVIYE 3: MARGIN UYARI — margin < %300 → log + engelleme sinyali
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel)  // MinMarginLevel = 300.0
   {
      static datetime lastWarnTime = 0;
      if(TimeCurrent() - lastWarnTime > 60)
      {
         PrintFormat("[PM-%s] MARGIN UYARI: Level=%.1f%% < %.0f%% → YENI POZISYON ENGELLENDI",
                     m_symbol, marginLevel, MinMarginLevel);
         lastWarnTime = TimeCurrent();
      }
      return false;  // Mevcut pozisyonlari kapatma, ama yeni acma engellenecek
   }

   return false;
}

//+------------------------------------------------------------------+
//| CheckSymbolLossLimit - v3.8.0: Sembol Bazli Toplam Kayip Limiti  |
//| v4.0: DEVRE DISI - SPM/FIFO sistemi kendi kendini yonetir       |
//| Sembol bazli zarar limiti yok. FIFO dongusu calissin.            |
//+------------------------------------------------------------------+
bool CPositionManager::CheckSymbolLossLimit()
{
   // v4.0: DEVRE DISI - SPM sistemi yonetir
   return false;
}

//+------------------------------------------------------------------+
//| ManageKarliPozisyonlar - v2.5.0 MUM DONUS KAR AL                |
//| TUM pozisyonlar icin: ANA + SPM + DCA                            |
//| Mum ters dondu + karda → HEMEN KAPAT (bekle yok)                |
//| Mum ayni yonde → PeakDrop ile koru                              |
//| ANA SPM varken FIFO ile kapanir                                  |
//+------------------------------------------------------------------+
void CPositionManager::ManageKarliPozisyonlar(bool newBar)
{
   // Sinyal ve mum yonu - her tick'te 1 kez hesapla (tum pozisyonlar icin ortak)
   bool sigValid = false;
   int sigScore = 0;
   ENUM_SIGNAL_DIR sigDir = SIGNAL_NONE;
   if(m_signalEngine != NULL)
   {
      SignalData sig = m_signalEngine.Evaluate();
      sigValid = true;
      sigScore = sig.score;
      sigDir   = sig.direction;
   }
   ENUM_SIGNAL_DIR candleDir = GetCandleDirection();

   for(int i = m_posCount - 1; i >= 0; i--)
   {
      double profit = m_positions[i].profit;
      if(profit <= 0.0) continue;

      ulong ticket = m_positions[i].ticket;
      ENUM_POS_ROLE role = m_positions[i].role;

      //--- v3.5.8: HEDGE KORUMASI - HEDGE pozisyonlar burada yonetilMEZ
      //--- HEDGE kendi ozel mantigi ile yonetilir (ManageHedgePositions)
      //--- HEDGE erken kapatilirsa ANA korumasiz kalir (XAG -$65 felaketi)
      if(role == ROLE_HEDGE) continue;

      //--- Rol etiketi (log icin) - tum bloklarda kullanilir
      string roleStr = "";
      if(role == ROLE_MAIN)        roleStr = "ANA";
      else if(role == ROLE_SPM)    roleStr = StringFormat("SPM%d", m_positions[i].spmLayer);
      else if(role == ROLE_DCA)    roleStr = "DCA";
      else                         roleStr = "HEDGE";

      // Peak tracking
      if(i < ArraySize(m_peakProfit))
         if(profit > m_peakProfit[i])
            m_peakProfit[i] = profit;

      //=======================================================
      // v3.4.0: KISMI KAPAMA (Partial Close / Scale-Out)
      // SPM/DCA $3 kara ulastiginda %60 lot kapat, %40 devam
      //=======================================================
      if(EnablePartialClose && role != ROLE_MAIN &&
         profit >= PartialCloseTriggerUSD &&
         i < ArraySize(m_partialClosed) && !m_partialClosed[i])
      {
         double currentVol = PositionGetDouble(POSITION_VOLUME);
         double closeVol   = currentVol * (PartialClosePercent / 100.0);

         if(m_executor != NULL && m_executor.ClosePositionPartial(ticket, closeVol))
         {
            m_partialClosed[i] = true;
            double closedProfit = profit * (PartialClosePercent / 100.0);
            m_spmClosedProfitTotal += closedProfit;

            PrintFormat("[PM-%s] KISMI KAPAMA: %s #%d | $%.2f kar | %.0f%% (%.2f lot) kapatildi | Kasa+$%.2f -> $%.2f",
                        m_symbol, roleStr, (int)ticket, profit, PartialClosePercent, closeVol, closedProfit, m_spmClosedProfitTotal);

            // Kalan lotla devam et - profit guncelle
            if(PositionSelectByTicket(ticket))
               m_positions[i].profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         }
      }

      // v2.3.1: ANA SPM varken de AKILLI KAPATMA aktif

      //=======================================================
      // v4.2.0: SPM/DCA MUM DONUS KAR AL — Karli ise HEMEN KAPAT
      // v4.2.0: SPM/DCA icin min close threshold %50 dusuruldu (hizli kasa)
      // TP hedefini bekleme, mum donusu oncelikli (kar koruma)
      //=======================================================
      double minCloseThreshold = m_profile.minCloseProfit;
      if(role == ROLE_SPM || role == ROLE_DCA)
         minCloseThreshold = MathMax(0.5, m_profile.minCloseProfit * 0.5);  // v4.2.0: %50 dusuk esik

      if((role == ROLE_SPM || role == ROLE_DCA) && profit > minCloseThreshold)
      {
         bool spmCandleAgainst = false;
         if(m_positions[i].type == POSITION_TYPE_BUY && candleDir == SIGNAL_SELL)
            spmCandleAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && candleDir == SIGNAL_BUY)
            spmCandleAgainst = true;

         if(spmCandleAgainst)
         {
            PrintFormat("[PM-%s] v3.7.0 MUM_DONUS_TP: %s #%d karda ($%.2f) + mum ters -> HEMEN KAPAT",
                        m_symbol, roleStr, (int)ticket, profit);
            SmartClosePosition(i, role, profit, StringFormat("MumDonus_TP_%s_%.2f", roleStr, profit));
            continue;
         }
      }

      //--- v3.4.0: Akilli kar hedefi (trend gucune gore)
      double closeTarget = GetSmartCloseTarget(role);

      //--- Pozisyon yonu
      ENUM_SIGNAL_DIR posDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

      //=======================================================
      // v3.5.0: AKILLI KAPATMA - Trend Hold + Mum Donus Max Kapat
      //=======================================================
      if(profit >= closeTarget)
      {
         bool mumTers = (candleDir != SIGNAL_NONE && candleDir != posDir);

         // v3.5.0: Trend guclu + pozisyon trend yonunde → HOLD (mum donene kadar)
         ENUM_TREND_STRENGTH trendStr = (m_signalEngine != NULL) ?
            m_signalEngine.GetTrendStrength() : TREND_WEAK;
         ENUM_SIGNAL_DIR confirmedTrend = (m_signalEngine != NULL) ?
            m_signalEngine.GetConfirmedTrend(TrendConfirmCount) : SIGNAL_NONE;

         bool trendHold = (trendStr >= TREND_MODERATE && posDir == confirmedTrend && !mumTers);

         if(trendHold)
         {
            // v3.7.0: SPM/DCA icin TP2 = TP1 × 1.5 (trend gucluyse)
            double tp1 = (role == ROLE_MAIN) ? m_profile.anaCloseProfit : m_profile.spmCloseProfit;
            double tp2 = tp1 * 1.5;  // TP2 hedef
            double peakValH = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : profit;

            // TP2'ye ulasti → KAPAT (trend gucluyken bile artik yeterli kar)
            if((role == ROLE_SPM || role == ROLE_DCA) && profit >= tp2)
            {
               PrintFormat("[PM-%s] v3.7.0 %s TP2 HEDEF: $%.2f >= TP2=$%.2f (TP1=$%.2f × 1.5) -> KAPAT",
                           m_symbol, roleStr, profit, tp2, tp1);
               SmartClosePosition(i, role, profit, StringFormat("TP2_%s_%.2f", roleStr, profit));
               continue;
            }

            // TP1 ile TP2 arasi → %15 siki PeakDrop ile koru (kar erimesini engelle)
            if(profit >= tp1 && peakValH > tp1)
            {
               double dropPctH = (peakValH > 0.0) ? ((peakValH - profit) / peakValH * 100.0) : 0.0;
               double tightPD = 15.0;  // %15 siki PeakDrop (normal %35 yerine)
               if(dropPctH >= tightPD)
               {
                  PrintFormat("[PM-%s] %s TREND-HOLD KAR KILIDI: Peak=$%.2f Now=$%.2f Drop=%.0f%%/%.0f%% -> KAPAT",
                              m_symbol, roleStr, peakValH, profit, dropPctH, tightPD);
                  SmartClosePosition(i, role, profit, StringFormat("PeakLock_%s_%.2f", roleStr, profit));
                  continue;
               }
            }
            // Peak drop tetiklenmedi → hold devam (TP2 bekleniyor)
            continue;
         }

         // Mum ters dondu → HEMEN MAX KAPAT
         if(mumTers)
         {
            PrintFormat("[PM-%s] %s MAX KAR MUM DONUS: $%.2f >= $%.2f | Mum TERS -> MAX KAPAT",
                        m_symbol, roleStr, profit, closeTarget);

            SmartClosePosition(i, role, profit, StringFormat("%s_MaxKar_%.2f", roleStr, profit));
            continue;
         }

         // Trend zayif + mum ayni yon → PeakDrop ile koru
         double peakVal = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : profit;
         if(peakVal >= closeTarget && profit >= closeTarget)
         {
            double dropPct = (peakVal > 0.0) ? ((peakVal - profit) / peakVal * 100.0) : 0.0;
            double rolePD = PeakDropPercent;
            if(role == ROLE_MAIN) rolePD = PeakDropPercent - 10.0;
            else if(role == ROLE_DCA) rolePD = PeakDropPercent + 10.0;
            if(dropPct >= rolePD)
            {
               PrintFormat("[PM-%s] %s PEAK DROP: Peak=$%.2f Now=$%.2f Drop=%.0f%%/%.0f%% -> KAPAT",
                           m_symbol, roleStr, peakVal, profit, dropPct, rolePD);

               SmartClosePosition(i, role, profit, StringFormat("%s_PeakDrop_%.2f", roleStr, profit));
               continue;
            }
            else
            {
               // Mum ayni yonde + peak drop yok → bekle
               if(TimeCurrent() - m_lastSPMLogTime >= 30)
               {
                  PrintFormat("[PM-%s] %s KAR TREND: $%.2f (Peak=$%.2f) Mum OK -> BEKLE",
                              m_symbol, roleStr, profit, peakVal);
                  m_lastSPMLogTime = TimeCurrent();
               }
               continue;
            }
         }

         // Fallback: mum belirsiz → hemen kapat (riske atma)
         PrintFormat("[PM-%s] %s KAR HEDEF: $%.2f >= $%.2f -> KAPAT",
                     m_symbol, roleStr, profit, closeTarget);
         SmartClosePosition(i, role, profit, StringFormat("%s_Kar_%.2f", roleStr, profit));
         continue;
      }

      //=======================================================
      // KAR HEDEFININ ALTINDA AMA KARDA → Erken kapatma kurallari
      // (Kari korumak icin - kucuk birikimler onemli)
      //=======================================================

      // v3.6.2: ANA KORUMASI - ANA SPM varken erken kapatilmaz (FIFO dongusunu koru)
      // SPM varken: ANA FIFO ile kapanir, erken kapatma FIFO kasasini bozar
      // SPM yokken: ANA tek basina, normal kar alma mekanizmalari calisir
      //   (MumDonus, PeakDrop, Engulfing ANA'nin karini korur)
      // ORNEK: BTC ANA peak=$9 → $5'e dustu, SPM yok → PeakDrop kapatir (iyi!)
      //        XAG ANA -$3, SPM=$8 kasa → FIFO: $8+(-$3)=$5 → ANA kapanir (iyi!)
      if(role == ROLE_MAIN && GetActiveSPMCount() > 0) continue;

      //=== Trend ANA yonune donuyor + pozisyon ANA tersi + karda ===
      if(role != ROLE_MAIN && profit >= MathMax(1.0, m_profile.minCloseProfit))
      {
         int mainIdx = FindMainPosition();
         if(mainIdx >= 0)
         {
            ENUM_SIGNAL_DIR trendDir = SIGNAL_NONE;
            if(m_signalEngine != NULL)
               trendDir = m_signalEngine.GetCurrentTrend();

            ENUM_SIGNAL_DIR mainDir = (m_positions[mainIdx].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

            if(trendDir == mainDir && posDir != mainDir)
            {
               PrintFormat("[PM-%s] TREND DONUS: %s karda ($%.2f), trend ANA yonune -> KARLI KAPAT",
                           m_symbol, roleStr, profit);

               SmartClosePosition(i, role, profit, StringFormat("TrendDonus_%s_%.2f", roleStr, profit));
               continue;
            }
         }
      }

      //=== v3.4.0: Mum terse dondu + karda → HEMEN KAPAT (esik trend gucune gore) ===
      double candleCloseMin = GetSmartCandleCloseMin();
      if(newBar && profit >= candleCloseMin)
      {
         bool candleAgainst = false;
         if(m_positions[i].type == POSITION_TYPE_BUY && candleDir == SIGNAL_SELL)
            candleAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && candleDir == SIGNAL_BUY)
            candleAgainst = true;

         if(candleAgainst)
         {
            PrintFormat("[PM-%s] MUM DONUS: %s #%d karda ($%.2f) + mum ters -> KAPAT",
                        m_symbol, roleStr, (int)ticket, profit);

            SmartClosePosition(i, role, profit, StringFormat("MumDonus_%s_%.2f", roleStr, profit));
            continue;
         }
      }

      //=== Engulfing formasyonu + karda (herhangi bir rol) ===
      if(newBar && profit >= m_profile.minCloseProfit)
      {
         int engulfPattern = m_candle.DetectEngulfing();
         bool engulfAgainst = false;

         if(m_positions[i].type == POSITION_TYPE_BUY && engulfPattern == -1)
            engulfAgainst = true;
         else if(m_positions[i].type == POSITION_TYPE_SELL && engulfPattern == +1)
            engulfAgainst = true;

         if(engulfAgainst)
         {
            PrintFormat("[PM-%s] ENGULFING: %s #%d karda ($%.2f) -> KAPAT",
                        m_symbol, roleStr, (int)ticket, profit);

            SmartClosePosition(i, role, profit, StringFormat("Engulfing_%s_%.2f", roleStr, profit));
            continue;
         }
      }

      //=== Genel PeakDrop (kar hedefi altinda bile) - TUM roller ===
      {
         double peakVal = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : profit;
         if(peakVal >= PeakMinProfit && profit >= m_profile.minCloseProfit)
         {
            double dropPct = (peakVal > 0.0) ? ((peakVal - profit) / peakVal * 100.0) : 0.0;
            // v3.3.0: Role bazli PeakDrop
            double rolePD2 = PeakDropPercent;
            if(role == ROLE_MAIN) rolePD2 = PeakDropPercent - 10.0;
            else if(role == ROLE_DCA) rolePD2 = PeakDropPercent + 10.0;
            if(dropPct >= rolePD2)
            {
               PrintFormat("[PM-%s] PEAK DROP: %s #%d Peak=$%.2f Now=$%.2f Drop=%.0f%%/%.0f%% -> KAPAT",
                           m_symbol, roleStr, (int)ticket, peakVal, profit, dropPct, rolePD2);

               SmartClosePosition(i, role, profit, StringFormat("PeakDrop_%s_%.0f%%", roleStr, dropPct));
               continue;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| SmartClosePosition - Tekduze kapatma + muhasebe                  |
//| TUM pozisyon kapatma islemi buradan gecer                        |
//+------------------------------------------------------------------+
void CPositionManager::SmartClosePosition(int idx, ENUM_POS_ROLE role, double profit, string reason)
{
   //--- Muhasebe
   m_totalCashedProfit += profit;
   // v3.6.2: m_dailyProfit buradan KALDIRILDI - ClosePosWithNotification icinde TEK NOKTADA eklenir
   // Eski hali: SmartClose + ClosePosWithNotification = CIFT SAYIM!

   if(role != ROLE_MAIN)
   {
      // SPM/DCA/HEDGE → kasaya ekle (FIFO)
      m_spmClosedProfitTotal += profit;
      m_spmClosedCount++;
      PrintFormat("[PM-%s] FIFO: +$%.2f -> Kasa=$%.2f (Sayi=%d)",
                  m_symbol, profit, m_spmClosedProfitTotal, m_spmClosedCount);
   }

   //--- Bildirim
   string roleStr = (role == ROLE_MAIN) ? "ANA" :
                     (role == ROLE_SPM)  ? "SPM" :
                     (role == ROLE_DCA)  ? "DCA" : "HEDGE";
   string msg = StringFormat("%s KAR %s: $%.2f -> KAPATILDI", roleStr, m_symbol, profit);
   if(m_telegram != NULL) m_telegram.SendMessage(msg);
   if(m_discord != NULL)  m_discord.SendMessage(msg);

   //--- v3.7.0: Kapanan SPM'in layer bilgisini sakla (rotasyon icin)
   int closedLayer = (idx < m_posCount) ? m_positions[idx].spmLayer : 0;

   //--- Pozisyonu kapat
   ClosePosWithNotification(idx, reason);

   //--- v3.7.0: SPM ROTASYONU — SPM1 kapandi + SPM2 varsa → SPM2=yeni SPM1
   if(role == ROLE_SPM && closedLayer == 1)
   {
      RefreshPositions();
      int spm2Idx = FindSPMByLayer(2);
      if(spm2Idx >= 0)
      {
         m_positions[spm2Idx].spmLayer = 1;
         PrintFormat("[PM-%s] v3.7.0 ROTASYON: SPM2 #%llu → yeni SPM1 | Yeni SPM2 sonraki tick'te acilacak",
                     m_symbol, m_positions[spm2Idx].ticket);

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("ROTASYON %s: SPM2→SPM1 #%d", m_symbol, (int)m_positions[spm2Idx].ticket));
         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("ROTASYON %s: SPM2→SPM1 #%d", m_symbol, (int)m_positions[spm2Idx].ticket));

         RenumberSPMLayers();
      }
   }

   //--- ANA ise: Terfi veya 30sn bekleme
   if(role == ROLE_MAIN)
   {
      m_mainTicket = 0;

      // SPM var mi? → Terfi (en eski SPM → yeni ANA)
      RefreshPositions();
      int activeSPMs = GetActiveSPMCount();
      if(activeSPMs > 0)
      {
         PromoteOldestSPM();
         // FIFO kasasina ANA kari ekle (SPM'ler devam edecek)
         m_spmClosedProfitTotal += profit;
         m_spmClosedCount++;
         PrintFormat("[PM-%s] ANA KAR -> TERFI! Kasa=$%.2f SPM=%d devam",
                     m_symbol, m_spmClosedProfitTotal, activeSPMs);
         // 30sn bekleme YOK - SPM yonetimi devam etmeli
      }
      else
      {
         // SPM yok → tam reset + 60sn bekleme (v3.5.0: 30→60sn)
         ResetFIFO();
         m_protectionCooldownUntil = TimeCurrent() + 60;
         m_tradingPaused = true;
         PrintFormat("[PM-%s] KAR SONRASI 60sn BEKLEME", m_symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| ManageSPMSystem - v3.0.0: Trend-Grid yonlendirme                 |
//+------------------------------------------------------------------+
void CPositionManager::ManageSPMSystem()
{
   // v3.0.0: Trend-Grid sistemi
   ManageTrendGrid();
}

//+------------------------------------------------------------------+
//| ManageMainInLoss - v3.5.7: Grid1 = ANA'nin TERSI (Zigzag Grid)  |
//| ANA zarardayken, fiyat ATR mesafe kadar dustuyse Grid1 acar      |
//+------------------------------------------------------------------+
void CPositionManager::ManageMainInLoss(int mainIdx, double mainProfit)
{
   // v3.7.0: SPM1 = ANA YONUNDE DCA
   // Tetik: ANA zarar >= spmTriggerLoss (BTC/Metal: -$7, Forex: -$4)
   // ADX filtresi YOK (hizli mudahale)
   // Max 1 SPM1 (toplam SPM = 0 olmali)
   if(GetActiveSPMCount() > 0) return;

   // Tek tetik: $ zarar bazli (ATR mesafe kaldirildi v3.7.0)
   if(mainProfit > m_profile.spmTriggerLoss) return;

   bool isBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);

   // Bakiye kontrolu
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + GetAdaptiveCooldown()) return;

   // Paused
   if(IsTradingPaused()) return;

   // v3.8.0: Margin guard — margin < %300 ise SPM acma
   {
      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0.0 && ml < MinMarginLevel) return;
   }

   // Toplam hacim kontrolu
   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   // v3.5.0: Spread kontrolu
   if(!IsSpreadAcceptable()) return;

   // v3.7.1: Tepe/Dip koruma — ADX>=45 trend yonu, ADX<=40 30sn cooldown+mum
   ENUM_SIGNAL_DIR peakDipDir = SIGNAL_NONE;
   if(!CheckPeakDipGate(peakDipDir)) return;  // Engellendi (cooldown)

   // v4.2.0: SPM1 YONU = NET-EXPOSURE DENGELEME (eski: ANA yonunde DCA)
   // BUY/SELL dengesi → fazla olan tarafin tersi acilir
   ENUM_SIGNAL_DIR spm1Dir = GetNetExposureDirection(mainIdx);

   // v3.7.1: Tepe/Dip override varsa SPM1 yonunu degistir
   if(peakDipDir != SIGNAL_NONE)
      spm1Dir = peakDipDir;

   // Lot hesapla (layer 1 = 1.0x ANA lot)
   double gridLot = CalcSPMLot(m_positions[mainIdx].volume, 1);

   PrintFormat("[PM-%s] v4.2.0 SPM1 TETIK: ANA zarar $%.2f <= $%.2f → SPM1 %s lot=%.2f%s (NET-EXPOSURE)",
               m_symbol, mainProfit, m_profile.spmTriggerLoss,
               (spm1Dir == SIGNAL_BUY) ? "BUY" : "SELL", gridLot,
               (peakDipDir != SIGNAL_NONE) ? " (TEPE/DIP OVERRIDE)" : "");

   OpenSPM(spm1Dir, gridLot, 1, m_positions[mainIdx].ticket);
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   m_lastGridPrice = currentPrice;
}

//+------------------------------------------------------------------+
//| ManageActiveSPMs - v4.2.0: SPM2+ Kademeli Kurtarma (Net-Exposure)|
//| SPM yonu = Net-Exposure dengeleme (eski: SPM1 tersi sabit)       |
//| Max SPM = profil bazli spmMaxLayers (eski: sabit 2)              |
//| SPM2 tetik: ANA zarar bazli, SPM3 tetik: ANA zarar * 1.5        |
//+------------------------------------------------------------------+
void CPositionManager::ManageActiveSPMs(int mainIdx)
{
   // v4.2.0: Max SPM sayisi profil'den (eski: sabit 2)
   int activeSPMs = GetActiveSPMCount();
   if(activeSPMs >= m_profile.spmMaxLayers) return;

   // En az 1 SPM olmali (SPM1 ManageMainInLoss'ta acilir)
   if(activeSPMs < 1) return;

   // v4.2.0: Tetik = ANA zarari bazli (eski: SPM1 zarari bazli)
   double mainProfit = m_positions[mainIdx].profit;
   int nextLayer = activeSPMs + 1;

   // v4.2.0: SPM2 tetik = spm2TriggerLoss, SPM3 tetik = spm2TriggerLoss * 1.5
   double triggerLoss = m_profile.spm2TriggerLoss;
   if(nextLayer >= 3) triggerLoss = m_profile.spm2TriggerLoss * 1.5;  // Daha derin zarar gerekli

   if(mainProfit > triggerLoss) return;

   bool canLog = (TimeCurrent() - m_lastSPMLogTime >= 30);

   // v4.2.0: SPM yonu = Net-Exposure dengeleme (eski: SPM1 tersi sabit)
   ENUM_SIGNAL_DIR spmDir = GetNetExposureDirection(mainIdx);

   // v3.7.0: Filtre — ADX >= 20 ZORUNLU
   double adxVal = (m_signalEngine != NULL) ? m_signalEngine.GetADX() : 0.0;
   if(adxVal < 20.0)
   {
      if(canLog)
      {
         PrintFormat("[PM-%s] SPM%d ENGEL: ADX=%.1f < 20 — trend zayif (ANA zarar=$%.2f)",
                     m_symbol, nextLayer, adxVal, mainProfit);
         m_lastSPMLogTime = TimeCurrent();
      }
      return;
   }

   // v3.7.0: Filtre — trend/sinyal/mum'dan en az 1'i SPM yonunu desteklemeli
   if(!HasDirectionSupport(spmDir))
   {
      if(canLog)
      {
         PrintFormat("[PM-%s] SPM%d ENGEL: Trend/Sinyal/Mum hicbiri %s yonunu desteklemiyor (ANA zarar=$%.2f)",
                     m_symbol, nextLayer, (spmDir == SIGNAL_BUY) ? "BUY" : "SELL", mainProfit);
         m_lastSPMLogTime = TimeCurrent();
      }
      return;
   }

   // Bakiye + hacim kontrolleri
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   // v3.8.0: Margin guard — margin < %300 ise SPM acma
   {
      double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(ml > 0.0 && ml < MinMarginLevel) return;
   }

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + GetAdaptiveCooldown()) return;
   if(IsTradingPaused()) return;

   // Spread kontrolu
   if(!IsSpreadAcceptable()) return;

   // v3.7.1: Tepe/Dip koruma
   ENUM_SIGNAL_DIR peakDipDir = SIGNAL_NONE;
   if(!CheckPeakDipGate(peakDipDir)) return;

   // Tepe/Dip override varsa SPM yonunu degistir
   if(peakDipDir != SIGNAL_NONE)
      spmDir = peakDipDir;

   // Lot hesapla
   double nextLot = CalcSPMLot(m_positions[mainIdx].volume, nextLayer);

   PrintFormat("[PM-%s] v4.2.0 SPM%d TETIK: ANA zarar $%.2f <= $%.2f → %s lot=%.2f ADX=%.1f%s (NET-EXPOSURE)",
               m_symbol, nextLayer, mainProfit, triggerLoss,
               (spmDir == SIGNAL_BUY) ? "BUY" : "SELL", nextLot, adxVal,
               (peakDipDir != SIGNAL_NONE) ? " (TEPE/DIP)" : "");

   OpenSPM(spmDir, nextLot, nextLayer, m_positions[mainIdx].ticket);
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   m_lastGridPrice = currentPrice;
}

//+------------------------------------------------------------------+
//| ManageTrendGrid - v3.4.0: Bi-Directional Trend-Grid motoru       |
//| H1 trend tespit → trend degisimi → bi-dir mod aktif              |
//| EnableReverseGrid=false → v3.0.0 davranisi (killswitch)          |
//+------------------------------------------------------------------+
void CPositionManager::ManageTrendGrid()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   // v3.6.0: WARMUP - EA yuklenince ilk SPM_WarmupSec saniye SPM acma
   if(TimeCurrent() < m_spmWarmupUntil)
   {
      static datetime lastWarmupLog = 0;
      if(TimeCurrent() - lastWarmupLog >= 15)
      {
         int remaining = (int)(m_spmWarmupUntil - TimeCurrent());
         PrintFormat("[PM-%s] WARMUP: %d saniye kaldi - SPM/Grid BEKLEMEDE", m_symbol, remaining);
         lastWarmupLog = TimeCurrent();
      }
      return;
   }

   // v4.2.0: Grid saglik kontrolu — floating loss esigi asarsa RESET
   if(CheckGridHealth()) return;

   // v3.7.0: HEDGE aktifken SPM'e IZIN VER (kasa doldurma icin)
   // HEDGE aktif olsa bile max 2 SPM acilabilir (kasa dolsun → FIFO calissin)
   // NOT: Zaten max 2 SPM siniri var (ManageMainInLoss + ManageActiveSPMs)
   if(GetActiveHedgeCount() > 0)
   {
      static datetime lastHedgeSPMLog = 0;
      if(TimeCurrent() - lastHedgeSPMLog >= 60)
      {
         PrintFormat("[PM-%s] HEDGE+SPM: HEDGE aktif, SPM=%d — kasa icin devam",
                     m_symbol, GetActiveSPMCount());
         lastHedgeSPMLog = TimeCurrent();
      }
   }

   double mainProfit = m_positions[mainIdx].profit;

   // v3.4.0: Bi-directional mod zaten aktifse → direkt iki yonlu grid yonet
   // (trend donus kontrolune GIRMEZ, tekrar Telegram spam onlenir)
   if(m_biDirectionalMode && EnableReverseGrid)
   {
      ManageBiDirectionalGrid();
      return;
   }

   // Trend kontrol (120sn araliklari, GetConfirmedTrend)
   CheckTrendDirection();

   // Trend donus kontrolu
   if(m_gridDirection != SIGNAL_NONE)
   {
      bool mainIsBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);
      ENUM_SIGNAL_DIR mainDir = mainIsBuy ? SIGNAL_BUY : SIGNAL_SELL;

      if(mainDir != m_gridDirection)
      {
         // v4.1: ManageTrendReversal her tick cagrilabilir (karli pozisyon kapatma icin)
         // AMA: BI-DIR zaten aktifse ManageBiDirectionalGrid halleder
         if(m_biDirectionalMode)
         {
            // BI-DIR aktif → ManageBiDirectionalGrid zaten ust blokta cagrildi
            // Buraya ulasmamali ama guvenlik icin
         }
         else
         {
            ManageTrendReversal();
            return;
         }
      }
   }

   // Ana karda ise grid gerek yok (FIFO veya ManageKarliPozisyonlar halleder)
   if(mainProfit >= 0.0) return;

   // v3.4.0: VOL_EXTREME'de yeni grid acilmaz
   if(m_volRegime == VOL_EXTREME) return;

   // Ana zararda - Grid sistemi devreye
   int activeSPMs = GetActiveSPMCount();

   if(activeSPMs == 0)
      ManageMainInLoss(mainIdx, mainProfit);
   else
      ManageActiveSPMs(mainIdx);
}

//+------------------------------------------------------------------+
//| CheckTrendDirection - v3.4.0: Guclendirilmis trend tespit         |
//| Her TrendCheckIntervalSec'de (120sn) kontrol                      |
//| GetConfirmedTrend: 3 kaynak + ardisik onay (whipsaw korunma)      |
//| Volatilite rejimi her kontrolde guncellenir                        |
//| Trend degisimi → bi-directional mod otomatik aktif                |
//+------------------------------------------------------------------+
void CPositionManager::CheckTrendDirection()
{
   // v3.4.0: 300sn → TrendCheckIntervalSec (default 120sn)
   if(TimeCurrent() - m_lastTrendCheck < TrendCheckIntervalSec) return;
   m_lastTrendCheck = TimeCurrent();

   if(m_signalEngine == NULL)
   {
      m_gridDirection = SIGNAL_NONE;
      return;
   }

   // v3.4.0: Volatilite rejimi her kontrolde guncellenir
   m_volRegime = m_signalEngine.GetVolatilityRegime();

   // v3.4.0: GetConfirmedTrend (3 kaynak oylama + ardisik onay)
   ENUM_SIGNAL_DIR newTrend = m_signalEngine.GetConfirmedTrend(TrendConfirmCount);

   if(newTrend != m_gridDirection && newTrend != SIGNAL_NONE)
   {
      string oldDirStr = (m_gridDirection == SIGNAL_BUY) ? "BUY" :
                          (m_gridDirection == SIGNAL_SELL) ? "SELL" : "YOK";
      string newDirStr = (newTrend == SIGNAL_BUY) ? "BUY" : "SELL";
      string volStr = (m_volRegime == VOL_LOW) ? "LOW" :
                       (m_volRegime == VOL_NORMAL) ? "NORMAL" :
                       (m_volRegime == VOL_HIGH) ? "HIGH" : "EXTREME";

      PrintFormat("[PM-%s] v%s TREND DEGISIM: %s -> %s | Vol=%s | Confirm=%d | BiDir=%s",
                  m_symbol, EA_VERSION, oldDirStr, newDirStr, volStr, TrendConfirmCount,
                  EnableReverseGrid ? "AKTIF" : "KAPALI");

      // v4.1: Yeni trend degisimi → legacyDone flag'ini sifirla (yeni BI-DIR oturumuna izin ver)
      m_biDirLegacyDone = false;
      m_biDirCooldownActive = false;

      /* v3.5.0: Telegram spam kaldirildi
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("TREND %s: %s -> %s Vol=%s BiDir=%s",
                                m_symbol, oldDirStr, newDirStr, volStr,
                                EnableReverseGrid ? "ON" : "OFF"));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("TREND %s: %s -> %s Vol=%s BiDir=%s",
                               m_symbol, oldDirStr, newDirStr, volStr,
                               EnableReverseGrid ? "ON" : "OFF"));
      */
   }

   m_gridDirection = newTrend;
}

//+------------------------------------------------------------------+
//| GetGridATR - v3.4.0: Adaptif ATR mesafe (GetAdaptiveGridSpacing) |
//| Artik volatilite rejimine gore carpan uygular                     |
//+------------------------------------------------------------------+
double CPositionManager::GetGridATR()
{
   return GetAdaptiveGridSpacing();
}

//+------------------------------------------------------------------+
//| GetAdaptiveGridSpacing - v3.4.0: Volatilite bazli grid mesafe     |
//| VOL_LOW: ATR × gridATRMultLow (1.0) - daha sik giris             |
//| VOL_NORMAL: ATR × gridATRMultNormal (1.5) - standart             |
//| VOL_HIGH: ATR × gridATRMultHigh (2.0) - genis, az giris          |
//| VOL_EXTREME: 0 → grid ACILMAZ                                    |
//| Haber yakininda: +NewsGridWidenPercent% genisleme                 |
//+------------------------------------------------------------------+
double CPositionManager::GetAdaptiveGridSpacing()
{
   // VOL_EXTREME: grid acilmaz
   if(m_volRegime == VOL_EXTREME)
   {
      static datetime lastExtremeLog = 0;
      if(TimeCurrent() - lastExtremeLog > 60)
      {
         PrintFormat("[PM-%s] VOL_EXTREME: Grid acilmaz! ATR cok yuksek.", m_symbol);
         lastExtremeLog = TimeCurrent();
      }
      return 0.0;
   }

   // H1 ATR degerini oku
   double h1ATR = 0.0;
   if(m_hATR14 != INVALID_HANDLE)
   {
      double atrBuf[1];
      if(CopyBuffer(m_hATR14, 0, 0, 1, atrBuf) > 0)
         h1ATR = atrBuf[0];
   }

   // Fallback: M15 ATR * 4
   if(h1ATR <= 0.0 && m_signalEngine != NULL)
   {
      double m15atr = m_signalEngine.GetATR();
      if(m15atr > 0.0) h1ATR = m15atr * 4.0;
   }
   if(h1ATR <= 0.0) return 0.0;

   // v3.4.0: Volatilite rejimine gore carpan sec
   double multiplier = m_profile.gridATRMultNormal;  // default 1.5
   switch(m_volRegime)
   {
      case VOL_LOW:    multiplier = m_profile.gridATRMultLow;    break;  // 1.0
      case VOL_NORMAL: multiplier = m_profile.gridATRMultNormal; break;  // 1.5
      case VOL_HIGH:   multiplier = m_profile.gridATRMultHigh;   break;  // 2.0
      default:         multiplier = m_profile.gridATRMultNormal; break;
   }

   double spacing = h1ATR * multiplier;

   // v3.4.0: Haber yakininda grid genisleme
   if(IsNewsNearby())
   {
      double widenFactor = 1.0 + (NewsGridWidenPercent / 100.0);
      spacing *= widenFactor;
      static datetime lastNewsLog = 0;
      if(TimeCurrent() - lastNewsLog > 120)
      {
         PrintFormat("[PM-%s] HABER GENISLEME: Grid +%d%% = ATR*%.2f*%.2f = %.5f",
                     m_symbol, NewsGridWidenPercent, multiplier, widenFactor, spacing);
         lastNewsLog = TimeCurrent();
      }
   }

   m_gridATR = spacing;
   return m_gridATR;
}

//+------------------------------------------------------------------+
//| GetMaxGridByBalance - v3.0.0: Bakiye bazli max grid limiti        |
//| Dusuk bakiye = az grid, yuksek bakiye = cok grid                  |
//| Margin call'i onlemek icin agressif olmayan yapi                  |
//+------------------------------------------------------------------+
int CPositionManager::GetMaxGridByBalance()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Bakiye bazli dinamik grid limiti:
   // $0-50:     max 2 grid (cok dikkatli)
   // $50-100:   max 3 grid
   // $100-200:  max 4 grid
   // $200-500:  max 5 grid
   // $500-1000: max 7 grid
   // $1000+:    max 10 grid

   int maxGrid = 2;  // Minimum 2 grid

   if(balance >= 1000.0)      maxGrid = 10;
   else if(balance >= 500.0)  maxGrid = 7;
   else if(balance >= 200.0)  maxGrid = 5;
   else if(balance >= 100.0)  maxGrid = 4;
   else if(balance >= 50.0)   maxGrid = 3;
   else                       maxGrid = 2;

   // Profil limitini de kontrol et (hangisi daha dusukse)
   int profileMax = m_profile.spmMaxBuyLayers;  // Grid tek yonde, BUY veya SELL
   if(maxGrid > profileMax)
      maxGrid = profileMax;

   return maxGrid;
}

//+------------------------------------------------------------------+
//| ManageTrendReversal - v3.4.0: Bi-Directional Trend Donus         |
//| H1 trend yonu degisti → Karli grid pozisyonlari kapat            |
//| EnableReverseGrid=true: Eski gridler LEGACY olur, yeni yon actif |
//| EnableReverseGrid=false: v3.0.0 davranisi (karli kapat, bekle)   |
//| ASLA zararina kapatma YOK                                         |
//+------------------------------------------------------------------+
void CPositionManager::ManageTrendReversal()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   bool mainIsBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);
   ENUM_SIGNAL_DIR mainDir = mainIsBuy ? SIGNAL_BUY : SIGNAL_SELL;

   // v4.1: Log spam azaltma - sadece ilk cagri veya kapatma olunca logla
   // (Her tick cagrilabilir - karli kapatma icin)

   // 1. Karli grid pozisyonlarini kapat (zarardakilere DOKUNMA)
   int closedCount = 0;
   double closedProfit = 0.0;
   for(int i = m_posCount - 1; i >= 0; i--)
   {
      if(m_positions[i].role != ROLE_SPM) continue;

      if(m_positions[i].profit > m_profile.minCloseProfit)
      {
         closedProfit += m_positions[i].profit;
         m_spmClosedProfitTotal += m_positions[i].profit;
         m_spmClosedCount++;
         m_totalCashedProfit += m_positions[i].profit;
         // v3.6.2: m_dailyProfit ClosePosWithNotification icinde eklenir (cift sayim fix)
         ClosePosWithNotification(i, "TREND_DONUS_KAR");
         closedCount++;
      }
   }

   if(closedCount > 0)
   {
      PrintFormat("[PM-%s] TREND DONUS: %d karli grid kapatildi, Toplam=$%.2f Kasa=$%.2f",
                  m_symbol, closedCount, closedProfit, m_spmClosedProfitTotal);

      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("TREND DONUS %s: %d grid kapatildi $%.2f",
                                m_symbol, closedCount, closedProfit));
   }

   // 2. ANA karda ise ANA'yi da kapat ve yeni yonde ANA ac
   if(m_positions[mainIdx].profit > m_profile.minCloseProfit)
   {
      double anaKar = m_positions[mainIdx].profit;
      ClosePosWithNotification(mainIdx, "TREND_DONUS_ANA_KAR");

      m_totalCashedProfit += anaKar;
      // v3.6.2: m_dailyProfit ClosePosWithNotification icinde eklenir (cift sayim fix)
      m_mainTicket = 0;

      PrintFormat("[PM-%s] TREND DONUS: ANA kapatildi kar=$%.2f -> Yeni ANA %s acilacak",
                  m_symbol, anaKar,
                  (m_gridDirection == SIGNAL_BUY) ? "BUY" : "SELL");

      RefreshPositions();
      if(GetActiveSPMCount() > 0)
         PromoteOldestSPM();
      else
      {
         ResetFIFO();
         OpenNewMainTrade(m_gridDirection, "TREND_DONUS_YeniANA");
      }
      m_biDirectionalMode = false;  // Temiz baslangic
      return;
   }

   // 3. v3.4.0: ANA zararda → Bi-Directional mod aktif et
   if(EnableReverseGrid)
   {
      // v4.1: Legacy bir kez bittiyse (legacy=0 oldu), ayni trend icinde tekrar BI-DIR'e girme
      // Bu flag sadece CheckTrendDirection'da yeni trend degisiminde sifirlanir
      if(m_biDirLegacyDone)
         return;  // Karli kapatma yukarda yapildi, BI-DIR'e tekrar girme

      // v3.5.3: Zarar bazli bi-dir yeniden giris kontrolu
      // Legacy kapandiktan sonra, mevcut SPM'lerin spmTriggerLoss'a ulasmasi gerekir
      if(m_biDirCooldownActive)
      {
         double worstSpmLoss = 0.0;
         int spmCount = 0;
         for(int j = 0; j < m_posCount; j++)
         {
            if(m_positions[j].role != ROLE_SPM) continue;
            spmCount++;
            if(m_positions[j].profit < worstSpmLoss)
               worstSpmLoss = m_positions[j].profit;
         }

         // Henuz SPM yok veya SPM zarar trigger'a ulasmadiysa → bi-dir'e GIRME
         if(spmCount == 0 || worstSpmLoss > m_profile.spmTriggerLoss)
         {
            static datetime lastCooldownLog = 0;
            if(TimeCurrent() - lastCooldownLog > 60)
            {
               PrintFormat("[PM-%s] BI-DIR BEKLEME: SPM=%d worstSPM=$%.2f > trigger=$%.2f → bekle",
                           m_symbol, spmCount, worstSpmLoss, m_profile.spmTriggerLoss);
               lastCooldownLog = TimeCurrent();
            }
            return;
         }

         // SPM zarar trigger'a ulasti → cooldown kaldir, bi-dir'e izin ver
         m_biDirCooldownActive = false;
         PrintFormat("[PM-%s] BI-DIR BEKLEME BITTI: worstSPM=$%.2f <= trigger=$%.2f → bi-dir aktif",
                     m_symbol, worstSpmLoss, m_profile.spmTriggerLoss);
      }

      // Zarardaki mevcut gridler LEGACY olur
      m_legacyGridDir = mainDir;
      m_activeGridDir = m_gridDirection;

      // Legacy ve aktif grid sayilarini hesapla
      m_legacyGridCount = 0;
      m_activeGridCount = 0;
      for(int i = 0; i < m_posCount; i++)
      {
         if(m_positions[i].role != ROLE_SPM) continue;
         ENUM_SIGNAL_DIR posDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         if(posDir == m_legacyGridDir)
            m_legacyGridCount++;
         else if(posDir == m_activeGridDir)
            m_activeGridCount++;
      }

      m_biDirectionalMode = true;
      m_legacyKasa = 0.0;  // Legacy grup icin ayri kasa

      // v4.0: Legacy grid yok ise BI-DIR anlamsiz, hemen kapat
      if(m_legacyGridCount == 0)
      {
         m_biDirectionalMode = false;
         m_legacyGridDir = SIGNAL_NONE;
         m_biDirCooldownActive = true;
         m_biDirLegacyDone = true;  // v4.1: Bu trend icinde bir daha BI-DIR'e girme
         PrintFormat("[PM-%s] BI-DIR: Legacy grid=0, bi-dir iptal (dongu koruma)", m_symbol);
         return;
      }

      PrintFormat("[PM-%s] BI-DIR MOD AKTIF: Aktif=%s(%d) Legacy=%s(%d) ANA zararda=$%.2f",
                  m_symbol,
                  (m_activeGridDir == SIGNAL_BUY) ? "BUY" : "SELL", m_activeGridCount,
                  (m_legacyGridDir == SIGNAL_BUY) ? "BUY" : "SELL", m_legacyGridCount,
                  m_positions[mainIdx].profit);

      /* v3.5.0: Telegram spam kaldirildi
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("BI-DIR %s: Aktif=%s Legacy=%s ANA=$%.2f",
                                m_symbol,
                                (m_activeGridDir == SIGNAL_BUY) ? "BUY" : "SELL",
                                (m_legacyGridDir == SIGNAL_BUY) ? "BUY" : "SELL",
                                m_positions[mainIdx].profit));
      */

      // Hemen yeni yon ilk grid ac
      if(m_volRegime != VOL_EXTREME)
         OpenReverseDirectionGrid();
   }
   // EnableReverseGrid=false → v3.0.0 davranisi: yeni grid acilmaz, FIFO bekler
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

   // Bakiye kontrol
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;

   // v3.8.0: MARGIN GUARD — margin < %300 ise DCA acma (stop-out onleme)
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < MinMarginLevel)  // MinMarginLevel = 300.0
   {
      static datetime lastDCAMarginLog = 0;
      if(TimeCurrent() - lastDCAMarginLog > 120)
      {
         PrintFormat("[PM-%s] DCA ENGEL: Margin=%.1f%% < %.0f%% → DCA acilamaz",
                     m_symbol, marginLevel, MinMarginLevel);
         lastDCAMarginLog = TimeCurrent();
      }
      return;
   }

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
//| ManageEmergencyHedge - v2.4.0: SELL-BUY karsilastirmali hedge    |
//| KOSULLAR:                                                         |
//|  1. Grup toplam P/L <= -$30                                       |
//|  2. Yon: SELL/BUY zarar karsilastirmasi (en cok zarar tersi)      |
//|  3. Lot: zarardaki toplam lot * 1.5                               |
//|  4. SPM katman limiti BYPASS                                      |
//+------------------------------------------------------------------+
void CPositionManager::ManageEmergencyHedge()
{
   // v2.4.3: HEDGE DEVRE DISI
   // Sebep: Kucuk hesaplarda (< $1000) hedge lot'u (zarar*1.5) cok buyuk oluyor
   // SPM sistemi zaten hedge gorevi goruyor (BUY<->SELL dongusu)
   // XAGUSDm $100 hesapda 0.06 lot hedge = 12 dakikada $100 -> $9 (olumcul)
   // SPM'ler 0.01 lot ile kar ediyordu ($4.65 FIFO kasasi), hedge bunu sildi
   return;
}

//+------------------------------------------------------------------+
//| CheckDeadlock - v2.2.4: Sadece LOG + bildirim, ASLA kapatma yok  |
//| SPM acilamiyor + net degisim < $0.50 → uyari ver, FIFO cozecek  |
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
      double lossRatio = MathAbs(currentNet) / MathMax(balance, 1.0);

      if(currentNet < 0.0 && lossRatio > Deadlock_MaxLossRatio)
      {
         // SADECE UYARI - ASLA ZARARDA KAPATMA YOK (FIFO sistemi cozecek)
         PrintFormat("[PM-%s] KILITLENME UYARI: Sure=%dsn Net=$%.2f Degisim=$%.2f < $%.2f Zarar=%.1f%% - FIFO BEKLE",
                     m_symbol, elapsed, currentNet, netChange, Deadlock_MinChange, lossRatio * 100.0);

         /* v3.5.0: Telegram spam kaldirildi
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("KILITLENME %s: Net=$%.2f Zarar=%.1f%% - FIFO bekliyor",
                                   m_symbol, currentNet, lossRatio * 100.0));
         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("KILITLENME %s: Net=$%.2f Zarar=%.1f%% - FIFO bekliyor",
                                  m_symbol, currentNet, lossRatio * 100.0));
         */
      }
   }

   // Tracker sifirla, yeniden izlemeye basla
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
//| DetermineSPMDirection - v2.5.0: KULLLANILMIYOR                   |
//| Zigzag sistemi: SPM yonu DAIMA oncekinin tersi                   |
//| Bu fonksiyon geriye uyumluluk icin korunuyor                     |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::DetermineSPMDirection(int parentLayer)
{
   // v2.5.0: Zigzag sistemi aktif - bu fonksiyon CAGRILMIYOR
   // SPM yonu ManageSPMSystem icinde belirlenir:
   //   SPM1 = ANA tersi
   //   SPM2+ = onceki SPM tersi
   // Geriye uyumluluk: ANA tersini dondur
   int mainIdx = FindMainPosition();
   if(mainIdx >= 0)
   {
      if(m_positions[mainIdx].type == POSITION_TYPE_BUY) return SIGNAL_SELL;
      else return SIGNAL_BUY;
   }
   return SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| CheckSameDirectionBlock - v3.0.0: DEVRE DISI                     |
//| Trend-Grid sistemde grid = ANA ile ayni yon (dip/tepe toplama)   |
//| Bu fonksiyon artik DAIMA false doner                              |
//+------------------------------------------------------------------+
bool CPositionManager::CheckSameDirectionBlock(ENUM_SIGNAL_DIR proposedDir)
{
   // v3.0.0: Trend-Grid sistemde grid ayni yonde acilir
   // Same-direction block artik gecerli degil
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
//| CheckFIFOTarget - v3.7.0: Cift Yollu FIFO                       |
//|                                                                  |
//| YOL A: Mum ANA yonune dondu + ANA zararda                       |
//|   → ANA'yi KAPATMA (karin donmesini bekle)                      |
//|   → En zarardaki SPM'yi kapat (kasadan odemeli)                  |
//|                                                                  |
//| YOL B: ANA zarara devam ediyor                                   |
//|   → SPM toplam kar (acik+kapali+HEDGE) + ANA zarar >= +$5       |
//|   → ANA kapat, en eski SPM → yeni ANA                           |
//|                                                                  |
//| v3.7.0 FARK: Acik SPM/HEDGE karlari da FIFO hesabina dahil      |
//+------------------------------------------------------------------+
void CPositionManager::CheckFIFOTarget()
{
   // v3.3.0: Daginik lisans kontrolu (anti-crack B2a)
   if(!g_LicenseManager.IsValid()) return;

   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   double mainProfit = m_positions[mainIdx].profit;
   double anaLoss = (mainProfit < 0.0) ? mainProfit : 0.0;

   // v3.7.0: ANA yonu ve mum yonu
   bool mainIsBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);
   ENUM_SIGNAL_DIR mainDir = mainIsBuy ? SIGNAL_BUY : SIGNAL_SELL;
   ENUM_SIGNAL_DIR candleDir = GetCandleDirection();

   //=== YOL A: Mum ANA yonune dondu + ANA zararda ===
   // Mum ANA yonune dondu → ANA toparlanabilir → ANA'yi KAPATMA
   // Bunun yerine en zarardaki SPM'yi kapat (kasadan odemeli)
   if(candleDir == mainDir && mainProfit < 0.0 && GetActiveSPMCount() > 0)
   {
      // Kasada yeterli birikim var mi? (en az $2 kasada olmali)
      if(m_spmClosedProfitTotal >= 2.0)
      {
         static datetime lastPathALog = 0;
         if(TimeCurrent() - lastPathALog >= 60)
         {
            PrintFormat("[PM-%s] FIFO YOL-A: Mum ANA %s yonune dondu, ANA=$%.2f → ANA bekle, worst SPM kapat (Kasa=$%.2f)",
                        m_symbol, (mainDir == SIGNAL_BUY) ? "BUY" : "SELL",
                        mainProfit, m_spmClosedProfitTotal);
            lastPathALog = TimeCurrent();
         }

         // En zarardaki SPM'yi kapat
         CloseWorstSPM("FIFO_YolA_MumDonus");
         return;
      }
   }

   //=== YOL B: ANA zarara devam ediyor — FIFO net hesap ===
   // v3.7.0: ACIK SPM/HEDGE karlari da dahil (sadece kasa degil)
   double spmTotalProfit = m_spmClosedProfitTotal;  // Kasa (kapanmis)

   for(int i = 0; i < m_posCount; i++)
   {
      // Acik karli SPM'ler
      if((m_positions[i].role == ROLE_SPM || m_positions[i].role == ROLE_DCA) && m_positions[i].profit > 0)
         spmTotalProfit += m_positions[i].profit;

      // HEDGE kari da sayilir
      if(m_positions[i].role == ROLE_HEDGE && m_positions[i].profit > 0)
         spmTotalProfit += m_positions[i].profit;
   }

   double net = spmTotalProfit + anaLoss;

   // v3.7.0: Sabit FIFO hedef = fifoNetTarget ($5)
   double fifoTarget = m_profile.fifoNetTarget;

   // Hedef ulasilmadi
   if(net < fifoTarget)
   {
      m_fifoWaitStart = 0;
      return;
   }

   //--- HEDEF ULASILDI!
   PrintFormat("[PM-%s] +++ v3.7.0 FIFO YOL-B HEDEF +++ Net=$%.2f (SPMTotal=$%.2f + ANA=$%.2f) >= $%.2f",
               m_symbol, net, spmTotalProfit, anaLoss, fifoTarget);

   // Bildirim
   CloseMainWithFIFONotification(mainIdx, spmTotalProfit, mainProfit, net);

   // SADECE ANA'yi kapat (SPM'ler ACIK KALIR)
   if(m_executor != NULL)
   {
      bool closed = m_executor.ClosePosition(m_positions[mainIdx].ticket);
      if(!closed)
      {
         PrintFormat("[PM-%s] FIFO: ANA kapatma BASARISIZ #%llu", m_symbol, m_positions[mainIdx].ticket);
         return;
      }
   }

   // Kasa guncelle: net kar realize edildi
   m_totalCashedProfit += net;
   m_dailyProfit += net;

   PrintFormat("[PM-%s] FIFO YOL-B: ANA #%llu kapatildi. Net=$%.2f realize edildi.",
               m_symbol, m_positions[mainIdx].ticket, net);

   // v4.3: Zengin FIFO bildirimi
   double fifoMainLoss = m_positions[mainIdx].profit;  // ANA'nin zarari (kapanis oncesi)
   if(m_telegram != NULL)
      m_telegram.SendFIFOEvent(m_symbol, GetCategoryName(), fifoMainLoss,
                                m_spmClosedProfitTotal, net, "");
   if(m_discord != NULL)
      m_discord.SendMessage(StringFormat("FIFO %s: ANA kapatildi Net=$%.2f | TERFI kontrol...",
                                         m_symbol, net));

   m_mainTicket = 0;

   // TERFI - en eski SPM → ANA
   RefreshPositions();
   PromoteOldestSPM();

   // FIFO kasa sifirla - FIFO kasayi HARCADI, yeni dongü basliyor
   m_spmClosedProfitTotal = 0.0;
   m_spmClosedCount = 0;
   m_fifoWaitStart = 0;

   if(FindMainPosition() < 0)
   {
      // Hic SPM kalmadi → temiz bitis
      PrintFormat("[PM-%s] FIFO DONGU TAMAMLANDI - tum pozisyonlar kapatildi", m_symbol);

      // v4.0: SONSUZ DONGU FIX - Hemen yeni ANA ACMA, sonraki mum bekle
      m_lastFIFOCompletionTime = TimeCurrent();
      PrintFormat("[PM-%s] FIFO sonrasi bekleme: sonraki mum bekleniyor (dongu koruma)", m_symbol);
      // Yeni ANA OnTick icerisinde, sonraki bar oluştuktan sonra acilaak
   }
   else
   {
      PrintFormat("[PM-%s] TERFI sonrasi yeni ANA mevcut, dongü devam ediyor.", m_symbol);
   }
}

//+------------------------------------------------------------------+
//| PromoteOldestSPM - v2.3.0: En eski SPM → ANA terfi               |
//| ANA FIFO ile kapandiktan sonra dongü devam etsin                  |
//+------------------------------------------------------------------+
void CPositionManager::PromoteOldestSPM()
{
   // v3.5.7: ZARARDAKI en eski SPM'i bul (oncelik: zararda olan)
   //   Zarardaki en eski SPM → ANA (FIFO ile kurtarilacak)
   //   Hic zarardaki yoksa → en eski SPM (eski davranis)
   int oldestLosingIdx = -1;
   datetime oldestLosingTime = D'2099.01.01';
   int oldestIdx = -1;
   datetime oldestTime = D'2099.01.01';
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM) continue;
      // Genel en eski
      if(m_positions[i].openTime < oldestTime)
      {
         oldestTime = m_positions[i].openTime;
         oldestIdx = i;
      }
      // Zarardaki en eski
      if(m_positions[i].profit < 0.0 && m_positions[i].openTime < oldestLosingTime)
      {
         oldestLosingTime = m_positions[i].openTime;
         oldestLosingIdx = i;
      }
   }

   // Zarardaki varsa onu sec, yoksa en eski
   if(oldestLosingIdx >= 0)
      oldestIdx = oldestLosingIdx;

   if(oldestIdx < 0)
   {
      PrintFormat("[PM-%s] TERFI: Acik SPM yok, yeni dongü bekliyor.", m_symbol);
      return;
   }

   // Role degistir: SPM → MAIN
   ulong promotedTicket = m_positions[oldestIdx].ticket;
   int oldLayer = m_positions[oldestIdx].spmLayer;
   m_positions[oldestIdx].role = ROLE_MAIN;
   m_positions[oldestIdx].spmLayer = 0;
   m_mainTicket = promotedTicket;

   // Kalan SPM'lerin katmanlarini yeniden numarala
   RenumberSPMLayers();

   // v3.6.2: Kasa SIFIRLANMIYOR - birikimis SPM karlari korunur
   // Eski hali: m_spmClosedProfitTotal = 0 → tum kasa kayboluyordu!
   // Ornek: Kasa=$8, ANA kapanir → PromoteOldestSPM → kasa=$0 → $8 kayip!
   // Simdi: Kasa korunur, FIFO path'te CheckFIFOTarget kendisi sifirlar
   // NOT: m_spmClosedCount da korunur (FIFO hesabi icin)

   PrintFormat("[PM-%s] TERFI: SPM%d #%llu -> ANA | Kalan SPM=%d | P/L=$%.2f | Kasa=$%.2f (korundu)",
               m_symbol, oldLayer, promotedTicket, GetActiveSPMCount(),
               m_positions[oldestIdx].profit, m_spmClosedProfitTotal);

   if(m_telegram != NULL)
      m_telegram.SendMessage(StringFormat("TERFI %s: SPM%d #%d -> ANA | SPM=%d",
                             m_symbol, oldLayer, (int)promotedTicket, GetActiveSPMCount()));
   if(m_discord != NULL)
      m_discord.SendMessage(StringFormat("TERFI %s: SPM%d #%d -> ANA | SPM=%d",
                            m_symbol, oldLayer, (int)promotedTicket, GetActiveSPMCount()));
}

//+------------------------------------------------------------------+
//| RenumberSPMLayers - v2.3.0: SPM katmanlarini yeniden numarala     |
//| openTime sirasina gore: en eski = layer 1, sonraki = layer 2...  |
//+------------------------------------------------------------------+
void CPositionManager::RenumberSPMLayers()
{
   // Once tum SPM layer'lari -1 yap (isaretlenmemis)
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM)
         m_positions[i].spmLayer = -1;
   }

   // openTime sirasina gore yeniden numarala
   int layerNum = 1;
   for(int pass = 0; pass < m_posCount; pass++)  // max m_posCount pass
   {
      datetime earliest = D'2099.01.01';
      int earliestIdx = -1;

      for(int i = 0; i < m_posCount; i++)
      {
         if(m_positions[i].role == ROLE_SPM && m_positions[i].spmLayer == -1)
         {
            if(m_positions[i].openTime < earliest)
            {
               earliest = m_positions[i].openTime;
               earliestIdx = i;
            }
         }
      }

      if(earliestIdx < 0) break;  // Tum SPM'ler numaralandi

      m_positions[earliestIdx].spmLayer = layerNum;
      layerNum++;
   }

   m_spmLayerCount = layerNum - 1;
}

//+------------------------------------------------------------------+
//| CheckLotBalance - v3.0.0: Trend-Grid Hacim kontrolu              |
//| Grid tek yonde acilir - sadece toplam hacim limiti kontrol edilir |
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

   // v3.0.0: Trend-Grid sistemde katman dengeleme KALDIRILDI
   // Grid = tek yonde (trend yonunde) acilir, BUY/SELL dengesi gerekmez

   // Toplam hacim kontrolu (en onemli guvenlik)
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
//| CalcSPMLot - v3.6.7: ANA bazli lot + Ters Piramit                |
//| layer=SPM/DCA sayisi+1 (ANA ve HEDGE HARIC)                      |
//| SPM1=1.0x, SPM2=1.1x, SPM3=1.2x, ..., max=1.5x                 |
//| Ters piramit: Grid arttikca lot AZALIR (× %5 dusus)             |
//| ADX > 30: max +%15 bonus                                         |
//+------------------------------------------------------------------+
double CPositionManager::CalcSPMLot(double mainLot, int layer)
{
   // v2.4.1: layer bazli carpan (eskisi gibi)
   int effectiveLayer = MathMin(layer, 5);
   double multiplier = m_profile.spmLotBase + (effectiveLayer - 1) * m_profile.spmLotIncrement;
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

   // v3.4.0: Ters piramit - Grid acildikca lot azalir
   int totalActiveGrids = GetActiveSPMCount();
   double reductionFactor = 1.0 - (totalActiveGrids * LotReductionPerGrid);
   reductionFactor = MathMax(reductionFactor, 0.50);  // Min %50
   lot *= reductionFactor;

   // v3.2.0: Margin bazli lot azaltma KALDIRILDI
   // Bakiye bazli grid limiti + ters piramit yeterli koruma saglar

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
   // v3.3.0: Islem baslangic dogrulama
   if(!IsLicenseValid()) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;

   // v3.2.0: Margin kontrolu KALDIRILDI - bakiye bazli calisir

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

      // v2.3.0: Trade sayaci
      if(finalDir == SIGNAL_BUY) m_totalBuyTrades++;
      else m_totalSellTrades++;
      m_dailyTradeCount++;

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
   // v3.3.0: Grid aciklama kontrolu
   if(!IsLicenseValid()) { if(layer > 0) return; }

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

      // v2.3.0: Trade sayaci
      if(dir == SIGNAL_BUY) m_totalBuyTrades++;
      else m_totalSellTrades++;
      m_dailyTradeCount++;

      PrintFormat("[PM-%s] SPM%d ACILDI: #%d %s Lot=%.2f Parent=%d",
                  m_symbol, layer, (int)newTicket,
                  (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)parentTicket);

      //--- v4.3: Zengin SPM bildirimi
      if(m_telegram != NULL)
      {
         RefreshPositions();
         string posMap = GetPositionMapHTML();
         double mainLoss = 0;
         for(int p = 0; p < m_posCount; p++)
            if(m_positions[p].role == ROLE_MAIN && m_positions[p].profit < 0)
               mainLoss = m_positions[p].profit;
         double fifoTarget = (mainLoss < 0) ? MathAbs(mainLoss) + SPM_NetTargetUSD : 0;
         m_telegram.SendSPMEvent(m_symbol, GetCategoryName(), layer, "ACILDI",
                                  posMap, m_spmClosedProfitTotal, fifoTarget);
      }
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

      // v2.3.0: Trade sayaci
      if(dcaDir == SIGNAL_BUY) m_totalBuyTrades++;
      else m_totalSellTrades++;
      m_dailyTradeCount++;

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

      // v2.3.0: Trade sayaci
      if(dir == SIGNAL_BUY) m_totalBuyTrades++;
      else m_totalSellTrades++;
      m_dailyTradeCount++;

      PrintFormat("[PM-%s] HEDGE ACILDI: #%d %s Lot=%.2f",
                  m_symbol, (int)newTicket,
                  (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot);

      /* v3.5.0: Telegram spam kaldirildi
      if(m_telegram != NULL)
         m_telegram.SendMessage(StringFormat("ACIL HEDGE %s: %s Lot=%.2f #%d",
                                m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)newTicket));
      if(m_discord != NULL)
         m_discord.SendMessage(StringFormat("ACIL HEDGE %s: %s Lot=%.2f #%d",
                               m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, (int)newTicket));
      */
   }
   else
   {
      PrintFormat("[PM-%s] HEDGE HATA: %s Lot=%.2f Err=%d",
                  m_symbol, (dir == SIGNAL_BUY) ? "BUY" : "SELL", lot, GetLastError());
   }
}

//+------------------------------------------------------------------+
//| ManageTPLevels - v2.3.0: TERFI AKTIF (PromoteOldestSPM)          |
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
         /* v3.5.0: Telegram spam kaldirildi
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP1 HIT %s: %.5f", m_symbol, currentPrice));
         */
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
         /* v3.5.0: Telegram spam kaldirildi
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP2 HIT %s: %.5f", m_symbol, currentPrice));
         */
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
         /* v3.5.0: Telegram spam kaldirildi
         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("TP3 HIT %s: %.5f", m_symbol, currentPrice));
         if(m_discord != NULL)
            m_discord.SendMessage(StringFormat("TP3 HIT %s: %.5f", m_symbol, currentPrice));
         */
      }
   }
}

//+------------------------------------------------------------------+
//| GetCandleDirection - v4.0: Gelismis mum algilama                  |
//| Oncelik: Engulfing > Pin Bar > Hammer > Basit yon                |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::GetCandleDirection()
{
   double o1 = iOpen(m_symbol, PERIOD_M15, 1);
   double c1 = iClose(m_symbol, PERIOD_M15, 1);
   double h1 = iHigh(m_symbol, PERIOD_M15, 1);
   double l1 = iLow(m_symbol, PERIOD_M15, 1);
   double o2 = iOpen(m_symbol, PERIOD_M15, 2);
   double c2 = iClose(m_symbol, PERIOD_M15, 2);
   
   if(o1 == 0 || c1 == 0) return SIGNAL_NONE;
   
   double body1 = MathAbs(c1 - o1);
   double range1 = h1 - l1;
   if(range1 <= 0) return SIGNAL_NONE;
   
   //--- Engulfing pattern (en guclu sinyal)
   double body2 = MathAbs(c2 - o2);
   if(body1 > body2 * 1.2 && body2 > 0)
   {
      if(c2 < o2 && c1 > o1) return SIGNAL_BUY;   // Bullish engulfing
      if(c2 > o2 && c1 < o1) return SIGNAL_SELL;   // Bearish engulfing
   }
   
   //--- Pin bar (uzun kuyruklu donus mumu)
   double upperWick = h1 - MathMax(o1, c1);
   double lowerWick = MathMin(o1, c1) - l1;
   
   if(lowerWick > range1 * 0.6 && body1 < range1 * 0.25)
      return SIGNAL_BUY;    // Bullish pin bar
   if(upperWick > range1 * 0.6 && body1 < range1 * 0.25)
      return SIGNAL_SELL;   // Bearish pin bar
   
   //--- Hammer / Shooting Star
   if(body1 > 0)
   {
      if(lowerWick > body1 * 2.0 && upperWick < body1 * 0.3)
         return SIGNAL_BUY;    // Hammer
      if(upperWick > body1 * 2.0 && lowerWick < body1 * 0.3)
         return SIGNAL_SELL;   // Shooting Star
   }
   
   //--- Basit yon (fallback)
   if(c1 > o1) return SIGNAL_BUY;
   if(c1 < o1) return SIGNAL_SELL;
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
//| v3.6.7: SPM/DCA lot layer sayaci (ANA ve HEDGE HARIC)            |
//| SPM lot hesabi icin: ilk SPM=1.0x, ikinci=1.1x, ...             |
//| ANA ve HEDGE sayilmaz - lot sismesini onler                      |
//+------------------------------------------------------------------+
int CPositionManager::GetSPMCountForSide(ENUM_SIGNAL_DIR side)
{
   int count = 0;
   ENUM_POSITION_TYPE targetType = (side == SIGNAL_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].type == targetType &&
         (m_positions[i].role == ROLE_SPM || m_positions[i].role == ROLE_DCA))
         count++;
   }
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
   string volStr = (m_volRegime == VOL_LOW) ? "LOW" :
                    (m_volRegime == VOL_NORMAL) ? "NORMAL" :
                    (m_volRegime == VOL_HIGH) ? "HIGH" : "EXTREME";
   PrintFormat("[PM-%s] v%s DURUM @ %s | Vol=%s BiDir=%s",
               m_symbol, EA_VERSION, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
               volStr, m_biDirectionalMode ? "AKTIF" : "KAPALI");
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

   // v3.4.0: Bi-directional durum
   if(m_biDirectionalMode)
   {
      PrintFormat("[PM-%s] BI-DIR: Aktif=%s(%d) Legacy=%s(%d) LegacyKasa=$%.2f Grid=%.5f",
                  m_symbol,
                  (m_activeGridDir == SIGNAL_BUY) ? "BUY" : "SELL", m_activeGridCount,
                  (m_legacyGridDir == SIGNAL_BUY) ? "BUY" : "SELL", m_legacyGridCount,
                  m_legacyKasa, m_gridATR);
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
//| GetNetExposureDirection - v4.2.0: Net-Exposure Dengeleme          |
//| BUY/SELL sayilarini dengede tut → tek yonlu batma IMKANSIZ        |
//| Fazla BUY varsa → SELL ac, Fazla SELL varsa → BUY ac             |
//| Esit ise → ANA'nin tersi (klasik hedge)                           |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::GetNetExposureDirection(int mainIdx)
{
   int buyCount = 0, sellCount = 0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].type == POSITION_TYPE_BUY)  buyCount++;
      if(m_positions[i].type == POSITION_TYPE_SELL) sellCount++;
   }

   bool mainIsBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);

   if(buyCount > sellCount)
      return SIGNAL_SELL;   // Fazla BUY var → SELL ac
   else if(sellCount > buyCount)
      return SIGNAL_BUY;    // Fazla SELL var → BUY ac
   else
      return mainIsBuy ? SIGNAL_SELL : SIGNAL_BUY;  // Esit → ANA'nin tersi
}

//+------------------------------------------------------------------+
//| CheckGridHealth - v4.2.0: Grid Saglik Kontrolu                    |
//| Toplam floating loss esigi asarsa → karli SPM'leri kasa, kalan kapat|
//| Esik: -max(gridLossMinUSD, equity * gridLossPercent)              |
//+------------------------------------------------------------------+
bool CPositionManager::CheckGridHealth()
{
   if(m_posCount == 0) return false;

   double totalFloating = 0.0;
   for(int i = 0; i < m_posCount; i++)
      totalFloating += m_positions[i].profit;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double pct = m_profile.gridLossPercent;
   double minLoss = m_profile.gridLossMinUSD;
   double gridLossLimit = -MathMax(minLoss, equity * pct);

   if(totalFloating > gridLossLimit)
      return false;  // Normal, devam

   PrintFormat("[PM-%s] GRID RESET: Floating=$%.2f < Limit=$%.2f → RESET BASLADI",
               m_symbol, totalFloating, gridLossLimit);

   // 1. Karli SPM'leri kapat (kasa biriktir)
   for(int i = m_posCount - 1; i >= 0; i--)
   {
      if(m_positions[i].profit > 0 && m_positions[i].role == ROLE_SPM)
      {
         if(m_executor != NULL)
            m_executor.ClosePosition(m_positions[i].ticket);
         m_spmClosedProfitTotal += m_positions[i].profit;
      }
   }

   // 2. Kalan pozisyonlari kapat
   RefreshPositions();
   CloseAllPositions("GRID_RESET");
   m_spmClosedProfitTotal = 0.0;
   m_spmClosedCount = 0;

   // Cooldown
   SetProtectionCooldown("GRID_RESET");

   // v4.3: Zengin Grid Reset bildirimi
   if(m_telegram != NULL)
      m_telegram.SendGridReset(m_symbol, GetCategoryName(), totalFloating, gridLossLimit, "");
   string gridMsg = StringFormat("GRID RESET %s: Floating=$%.2f < $%.2f → Tum kapatildi",
                                  m_symbol, totalFloating, gridLossLimit);
   if(m_discord != NULL) m_discord.SendMessage(gridMsg);

   return true;
}

//+------------------------------------------------------------------+
//| v4.3.0: Pozisyon haritasi (Telegram HTML formatinda)              |
//+------------------------------------------------------------------+
string CPositionManager::GetPositionMapHTML()
{
   string map = "";
   for(int i = 0; i < m_posCount; i++)
   {
      string roleStr = "";
      switch(m_positions[i].role)
      {
         case ROLE_MAIN:  roleStr = "ANA";   break;
         case ROLE_SPM:   roleStr = "SPM" + IntegerToString(m_positions[i].spmLayer); break;
         case ROLE_DCA:   roleStr = "DCA";   break;
         case ROLE_HEDGE: roleStr = "HEDGE"; break;
         default:         roleStr = "???";   break;
      }
      string dirStr = (m_positions[i].type == POSITION_TYPE_BUY) ? "BUY " : "SELL";
      string plStr;
      if(m_positions[i].profit >= 0)
         plStr = "+$" + DoubleToString(m_positions[i].profit, 2);
      else
         plStr = "-$" + DoubleToString(MathAbs(m_positions[i].profit), 2);

      map += "<code>" + roleStr + ": " + dirStr + " " +
             DoubleToString(m_positions[i].volume, 2) + " [" + plStr + "]</code>\n";
   }
   return map;
}

//+------------------------------------------------------------------+
//| v4.3.0: Kategori adi                                              |
//+------------------------------------------------------------------+
string CPositionManager::GetCategoryName()
{
   switch(m_category)
   {
      case CAT_FOREX:   return "Forex";
      case CAT_METAL:   return "Metal";
      case CAT_CRYPTO:  return "Crypto";
      case CAT_INDICES: return "Indices";
      case CAT_STOCKS:  return "Stocks";
      case CAT_ENERGY:  return "Energy";
      default:          return "Default";
   }
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
//| HasDirectionSupport - v3.7.0: trend/sinyal/mum en az 1 destek    |
//| SPM2 filtresi: en az 1 kaynak SPM2 yonunu desteklemeli           |
//+------------------------------------------------------------------+
bool CPositionManager::HasDirectionSupport(ENUM_SIGNAL_DIR dir)
{
   if(dir == SIGNAL_NONE) return false;

   int votes = 0;

   // Kaynak 1: Trend yonu
   if(m_signalEngine != NULL)
   {
      ENUM_SIGNAL_DIR trendDir = m_signalEngine.GetCurrentTrend();
      if(trendDir == dir) votes++;
   }

   // Kaynak 2: Sinyal yonu (skor >= SignalMinScore)
   if(m_signalEngine != NULL)
   {
      SignalData sig = m_signalEngine.Evaluate();
      if(sig.direction == dir && sig.score >= SignalMinScore) votes++;
   }

   // Kaynak 3: Mum yonu
   ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
   if(candleDir == dir) votes++;

   return (votes >= 1);
}

//+------------------------------------------------------------------+
//| FindSPMByLayer - v3.7.0: Layer numarasina gore SPM bul           |
//+------------------------------------------------------------------+
int CPositionManager::FindSPMByLayer(int layer)
{
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role == ROLE_SPM && m_positions[i].spmLayer == layer)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| CloseWorstSPM - v3.7.0: En zarardaki SPM'yi kapat               |
//| FIFO Path A: Mum ANA yonune dondu → en zarardaki SPM kapat       |
//+------------------------------------------------------------------+
void CPositionManager::CloseWorstSPM(string reason)
{
   int worstIdx = -1;
   double worstLoss = 0.0;

   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM && m_positions[i].role != ROLE_DCA) continue;
      if(m_positions[i].profit < worstLoss)
      {
         worstLoss = m_positions[i].profit;
         worstIdx = i;
      }
   }

   if(worstIdx < 0)
   {
      PrintFormat("[PM-%s] FIFO-A: Zarardaki SPM yok", m_symbol);
      return;
   }

   PrintFormat("[PM-%s] FIFO-A: En zarardaki SPM%d #%llu kapatiliyor ($%.2f) — %s",
               m_symbol, m_positions[worstIdx].spmLayer,
               m_positions[worstIdx].ticket, worstLoss, reason);

   SmartClosePosition(worstIdx, m_positions[worstIdx].role, worstLoss, reason);
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

      // v3.6.6: HEDGE kapandiysa cooldown timer'i baslat (carousel engelle)
      if(m_positions[idx].role == ROLE_HEDGE)
         m_lastHedgeCloseTime = TimeCurrent();
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
   ArrayFill(m_peakTicket, 0, ArraySize(m_peakTicket), 0);
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

//+------------------------------------------------------------------+
//| ManageBiDirectionalGrid - v3.4.0: Ana bi-dir orchestrator         |
//| Bi-directional mod aktifken:                                      |
//|  1. Aktif yonde yeni grid'ler ac                                  |
//|  2. Legacy grup karlilarini kapat (kasaya ekle)                    |
//|  3. Legacy hepsi kapandiysa → tek yone don                        |
//|  4. ANA zararda + trend yonunde → normal grid devam               |
//+------------------------------------------------------------------+
void CPositionManager::ManageBiDirectionalGrid()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   // Legacy gruplarin karlilarini kapat
   ManageLegacyGroupRecovery();

   // Pozisyonlari yenile (legacy kapatilmis olabilir)
   RefreshPositions();

   // Legacy ve aktif grid sayilarini guncelle
   m_legacyGridCount = 0;
   m_activeGridCount = 0;
   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM) continue;
      ENUM_SIGNAL_DIR posDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      if(posDir == m_legacyGridDir)
         m_legacyGridCount++;
      else if(posDir == m_activeGridDir)
         m_activeGridCount++;
   }

   // Legacy hepsi kapandiysa → tek yone don
   if(m_legacyGridCount == 0)
   {
      PrintFormat("[PM-%s] BI-DIR: Tum legacy grid'ler kapandi -> Tek yon moda don (zarar bazli bekleme)", m_symbol);
      m_biDirectionalMode = false;
      m_legacyGridDir = SIGNAL_NONE;
      m_legacyKasa = 0.0;
      // v3.5.3: Zarar bazli bekleme - SPM'ler spmTriggerLoss'a ulasana kadar bi-dir tekrar aktif olmaz
      m_biDirCooldownActive = true;
      m_biDirLegacyDone = true;  // v4.1: Bu trend icinde bir daha BI-DIR'e girme
   }

   // VOL_EXTREME: yeni grid acma
   if(m_volRegime == VOL_EXTREME) return;

   // Aktif yonde yeni grid'ler ac (eger ANA zararda veya yeni grid mesafesi dolduysa)
   mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   double mainProfit = m_positions[mainIdx].profit;

   // Aktif yonde grid acilma kosullari
   // Haber aktifse: yeni grid ACILMAZ (sadece mevcut yonetim devam)
   if(m_newsManager != NULL && m_newsManager.IsTradingBlocked()) return;

   double gridATR = GetAdaptiveGridSpacing();
   if(gridATR <= 0.0) return;

   // Son aktif grid'den mesafe kontrolu
   double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
   double lastActivePrice = 0.0;
   int highestActiveLayer = 0;

   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM) continue;
      ENUM_SIGNAL_DIR posDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      if(posDir == m_activeGridDir && m_positions[i].spmLayer > highestActiveLayer)
      {
         highestActiveLayer = m_positions[i].spmLayer;
         lastActivePrice = m_positions[i].openPrice;
      }
   }

   // Hic aktif grid yoksa: ANA fiyatindan hesapla veya hemen ac
   if(lastActivePrice == 0.0)
   {
      // Ilk aktif yon grid'i: hemen ac (trend degisimi onayi sonrasi)
      OpenReverseDirectionGrid();
      return;
   }

   // Mesafe kontrolu
   double distance = 0.0;
   if(m_activeGridDir == SIGNAL_BUY)
      distance = lastActivePrice - currentPrice;  // BUY: fiyat dustuyse mesafe artar
   else
      distance = currentPrice - lastActivePrice;  // SELL: fiyat ciktiysa mesafe artar

   if(distance < gridATR) return;  // Henuz yeterli mesafe yok

   // Grid limit kontrolleri
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   int maxGrid = GetMaxGridByBalance();
   if(m_activeGridCount >= maxGrid) return;

   if(m_activeGridDir == SIGNAL_BUY && GetBuyLayerCount() >= m_profile.spmMaxBuyLayers) return;
   if(m_activeGridDir == SIGNAL_SELL && GetSellLayerCount() >= m_profile.spmMaxSellLayers) return;

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + GetAdaptiveCooldown()) return;
   if(IsTradingPaused()) return;
   if(balance < MinBalanceToTrade) return;

   // v3.2.0: Margin kontrolu KALDIRILDI - bakiye bazli calisir

   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   // Yeni aktif yon grid ac
   OpenReverseDirectionGrid();
}

//+------------------------------------------------------------------+
//| OpenReverseDirectionGrid - v3.4.0: Yeni trend yonunde grid ac    |
//| Lot: Ters piramit (her grid %5 daha kucuk)                       |
//| Bakiye + margin + hacim kontrolleri AYNI                           |
//+------------------------------------------------------------------+
void CPositionManager::OpenReverseDirectionGrid()
{
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   if(m_activeGridDir == SIGNAL_NONE) return;

   // Bakiye kontrolu (v3.2.0: margin kontrolu kaldirildi)
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;

   // Hacim kontrolu
   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   // Grid limit
   int maxGrid = GetMaxGridByBalance();
   if(m_activeGridCount >= maxGrid) return;

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + GetAdaptiveCooldown()) return;

   // Katman limiti
   if(m_activeGridDir == SIGNAL_BUY && GetBuyLayerCount() >= m_profile.spmMaxBuyLayers) return;
   if(m_activeGridDir == SIGNAL_SELL && GetSellLayerCount() >= m_profile.spmMaxSellLayers) return;

   // v3.6.7: Sonraki katman - sadece SPM/DCA sayilir
   int spmSideCount = GetSPMCountForSide(m_activeGridDir);
   int nextLayer = spmSideCount + 1;

   // Lot hesabi (ters piramit uygulanir CalcSPMLot icinde)
   double gridLot = CalcSPMLot(m_positions[mainIdx].volume, nextLayer);

   PrintFormat("[PM-%s] BI-DIR AKTIF GRID%d: %s lot=%.2f (trend yonunde, ters piramit)",
               m_symbol, nextLayer,
               (m_activeGridDir == SIGNAL_BUY) ? "BUY" : "SELL", gridLot);

   OpenSPM(m_activeGridDir, gridLot, nextLayer, m_positions[mainIdx].ticket);
   m_activeGridCount++;
}

//+------------------------------------------------------------------+
//| ManageLegacyGroupRecovery - v3.4.0: Eski yon karli gridle kapat  |
//| Eski yondeki grid'ler karda ise → kapat, kasaya ekle             |
//| Zarardakilere DOKUNMA (SL YOK)                                    |
//| FIFO ile ANA kapanmasina katki saglar                             |
//+------------------------------------------------------------------+
void CPositionManager::ManageLegacyGroupRecovery()
{
   if(m_legacyGridDir == SIGNAL_NONE) return;

   for(int i = m_posCount - 1; i >= 0; i--)
   {
      if(m_positions[i].role != ROLE_SPM) continue;

      ENUM_SIGNAL_DIR posDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      if(posDir != m_legacyGridDir) continue;  // Sadece legacy yondekiler

      double profit = m_positions[i].profit;
      if(profit <= m_profile.minCloseProfit) continue;  // Zarardakilere dokunma

      // Legacy grid karda → kapat ve kasaya ekle
      PrintFormat("[PM-%s] LEGACY KAR: SPM%d #%d %s $%.2f -> KAPAT (kasaya ekle)",
                  m_symbol, m_positions[i].spmLayer, (int)m_positions[i].ticket,
                  (posDir == SIGNAL_BUY) ? "BUY" : "SELL", profit);

      m_spmClosedProfitTotal += profit;
      m_spmClosedCount++;
      m_legacyKasa += profit;
      // v3.6.2: m_dailyProfit ClosePosWithNotification icinde eklenir (cift sayim fix)
      m_totalCashedProfit += profit;

      string msg = StringFormat("LEGACY KAR %s: $%.2f -> Kasa=$%.2f",
                                m_symbol, profit, m_spmClosedProfitTotal);
      if(m_telegram != NULL) m_telegram.SendMessage(msg);

      ClosePosWithNotification(i, StringFormat("LEGACY_KAR_%.2f", profit));
   }
}

//+------------------------------------------------------------------+
//| GetSmartCloseTarget - v3.4.0: Trend gucune gore kar hedefi        |
//| ZAYIF (ADX<25): standart                                          |
//| ORTA (25-35): × trendCloseMultModerate (1.3)                      |
//| GUCLU (ADX>35): × trendCloseMultStrong (1.8)                      |
//+------------------------------------------------------------------+
double CPositionManager::GetSmartCloseTarget(ENUM_POS_ROLE role)
{
   double baseTarget = 0.0;
   if(role == ROLE_MAIN)
      baseTarget = m_profile.anaCloseProfit;
   else if(role == ROLE_DCA)
      baseTarget = MathMax(m_profile.profitTargetPerPos, m_profile.minCloseProfit);
   else
      baseTarget = MathMax(m_profile.spmCloseProfit, m_profile.minCloseProfit);

   // v3.4.0: Trend gucune gore carpan
   if(m_signalEngine != NULL)
   {
      ENUM_TREND_STRENGTH strength = m_signalEngine.GetTrendStrength();
      switch(strength)
      {
         case TREND_MODERATE:
            baseTarget *= m_profile.trendCloseMultModerate;  // 1.3x
            break;
         case TREND_STRONG:
            baseTarget *= m_profile.trendCloseMultStrong;    // 1.8x
            break;
         default:  // TREND_WEAK
            break;  // Standart hedef
      }
   }

   return baseTarget;
}

//+------------------------------------------------------------------+
//| GetSmartCandleCloseMin - v3.4.0: Mum donus min kar esigi          |
//| ZAYIF trend: candleCloseWeak ($0.50) → hemen kapat               |
//| ORTA trend: candleCloseModerate ($1.50) → biraz bekle             |
//| GUCLU trend: candleCloseStrong ($3.00) → buyuk kar kacirma        |
//+------------------------------------------------------------------+
double CPositionManager::GetSmartCandleCloseMin()
{
   if(m_signalEngine != NULL)
   {
      ENUM_TREND_STRENGTH strength = m_signalEngine.GetTrendStrength();
      switch(strength)
      {
         case TREND_MODERATE:
            return m_profile.candleCloseModerate;  // $1.50
         case TREND_STRONG:
            return m_profile.candleCloseStrong;    // $3.00
         default:
            return m_profile.candleCloseWeak;      // $0.50
      }
   }
   return m_profile.candleCloseWeak;
}

//+------------------------------------------------------------------+
//| IsNewsNearby - v3.4.0: Haber yakininda mi?                        |
//| Haber oncesi 60dk icinde ise true doner                           |
//| Grid mesafesi genisleme icin kullanilir                            |
//+------------------------------------------------------------------+
bool CPositionManager::IsNewsNearby()
{
   if(m_newsManager == NULL) return false;
   if(!EnableNewsFilter) return false;

   // Haber blok aktifse veya aktif haber varsa
   if(m_newsManager.IsTradingBlocked()) return true;
   if(m_newsManager.HasActiveNews()) return true;

   // Sonraki haber 60dk icinde mi?
   string title, currency;
   ENUM_NEWS_IMPACT impact;
   datetime eventTime;
   int minutesLeft;
   if(m_newsManager.GetNextNewsInfo(title, currency, impact, eventTime, minutesLeft))
   {
      if(minutesLeft > 0 && minutesLeft <= 60) return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| v3.5.0: ADX Grid Kalite Filtresi                                 |
//| ADX < 25 = grid ACILMAZ (guclu trend gerekli)                   |
//| v3.6.9: ADX filtresi — kurtarma modunda bypass                   |
//| Normal: ADX >= 38 zorunlu (SPM_MinADX)                           |
//| Kurtarma: ANA zarar >= spmTriggerLoss ise ADX ENGEL YOK          |
//| SPM acilmazsa kasa dolmaz → FIFO calismaz → ANA -$30'a duser     |
//+------------------------------------------------------------------+
int CPositionManager::GetADXGridLimit()
{
   if(m_signalEngine == NULL) return 10;  // fallback: filtre yok

   double adx = m_signalEngine.GetADX();

   // v3.6.9: ANA zararda ise ADX filtresini bypass et
   // SPM ACILMAZSA → kasa dolmaz → FIFO calismaz → ANA sonsuza kadar zarar eder
   int mainIdx = FindMainPosition();
   if(mainIdx >= 0 && m_positions[mainIdx].profit <= m_profile.spmTriggerLoss)
   {
      // ANA zarar esikten kotu → SPM ACILMALI (ADX filtresi devre disi)
      if(adx < 15.0) return 2;    // Cok dusuk ADX: max 2 SPM (ihtiyatli)
      if(adx < 25.0) return 3;    // Dusuk ADX: max 3 SPM
      return 10;                    // Normal+ ADX: tam kapasite
   }

   // Normal mod: ADX >= SPM_MinADX zorunlu
   if(adx < (double)SPM_MinADX) return 0;   // ADX < 38: SPM ACILMAZ
   return 10;                                 // ADX >= 38: tam kapasite
}

//+------------------------------------------------------------------+
//| v3.4.0: Sanal Breakeven Kilidi                                   |
//| SPM/DCA +$2 kara ulasinca breakeven kilitler                     |
//| Fiyat entry'ye donerse zarar yerine BE'de kapatir                |
//| Broker SL KULLANMAZ (SL=YOK kurali korunur)                     |
//+------------------------------------------------------------------+
void CPositionManager::ManageBreakevenLock()
{
   if(!EnableBreakevenLock) return;

   for(int i = m_posCount - 1; i >= 0; i--)
   {
      double profit = m_positions[i].profit;
      ENUM_POS_ROLE role = m_positions[i].role;

      // Sadece SPM ve DCA (ANA FIFO ile kapanir, HEDGE ManageHedgePositions ile)
      if(role == ROLE_MAIN) continue;
      if(role == ROLE_HEDGE) continue;  // v3.6.0: HEDGE burada yonetilMEZ

      // Breakeven kilidi aktiflesir
      if(!m_breakevenLocked[i] && profit >= BreakevenTriggerUSD)
      {
         m_breakevenLocked[i] = true;
         m_breakevenPrice[i] = m_positions[i].openPrice;

         string roleStr = (role == ROLE_SPM) ? "SPM" : "DCA";
         PrintFormat("[PM-%s] BE KILIDI: %s #%d kar=$%.2f → BE at %.5f",
                     m_symbol, roleStr, (int)m_positions[i].ticket,
                     profit, m_breakevenPrice[i]);
      }

      // Breakeven tetigi - fiyat entry'ye dondu
      // v3.5.2: BE kapamayi minCloseProfit'in altina duserse tetikle (eski $0.30 BTC'de spread noise'unu yakaliyordu)
      // Mantik: Pozisyon once yuksek karda idi, simdi minimum kar seviyesine dustu → kaybi durdur
      if(m_breakevenLocked[i])
      {
         double beCloseLevel = m_profile.minCloseProfit;  // BTC: $3 (eski: $0.30 breakeven)
         // v3.6.2: BE ASLA ZARARDA KAPATMAZ - profit >= 0.0 zorunlu
         // Eski: profit >= -1.0 → SPM'ler -$0.80'de "breakeven" olarak kapatiliyordu = ZARAR!
         if(profit <= beCloseLevel && profit >= 0.0)
         {
            string roleStr = (role == ROLE_SPM) ? "SPM" : "DCA";
            PrintFormat("[PM-%s] BE KAPAMA: %s #%d kar=$%.2f <= minClose=$%.2f → KORUMA KAPAT",
                        m_symbol, roleStr, (int)m_positions[i].ticket, profit, beCloseLevel);

            SmartClosePosition(i, role, profit,
                StringFormat("BE_Lock_%s_%.2f", roleStr, profit));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| v3.4.0: Adaptif FIFO Hedefi                                     |
//| Kucuk hesaplar daha dusuk FIFO hedefi → hizli sermaye devri      |
//| Zaman bazli decay (v3.3.0) bunun uzerine uygulanir               |
//+------------------------------------------------------------------+
double CPositionManager::GetAdaptiveFIFOTarget()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double baseTarget;

   // Hesap boyutuna gore temel hedef
   if(balance < 200.0)       baseTarget = 3.0;
   else if(balance < 500.0)  baseTarget = 4.0;
   else if(balance < 1000.0) baseTarget = 5.0;
   else                      baseTarget = 6.0;

   // v3.3.0 zaman bazli decay hala uygulanir
   int mainIdx = FindMainPosition();
   if(mainIdx >= 0)
   {
      int holdMinutes = (int)((TimeCurrent() - m_positions[mainIdx].openTime) / 60);
      if(holdMinutes > 240)
         baseTarget = MathMax(baseTarget * 0.40, 2.0);   // 4+ saat: %40
      else if(holdMinutes > 120)
         baseTarget = MathMax(baseTarget * 0.60, 2.0);   // 2-4 saat: %60
      else if(holdMinutes > 60)
         baseTarget = MathMax(baseTarget * 0.80, 2.0);   // 1-2 saat: %80
   }

   return baseTarget;
}

//+------------------------------------------------------------------+
//| v3.4.0: Volatilite Bazli Grid Cooldown                          |
//| Yavas piyasa → uzun bekleme, hizli piyasa → kisa bekleme        |
//+------------------------------------------------------------------+
int CPositionManager::GetAdaptiveCooldown()
{
   int baseCooldown = m_profile.spmCooldownSec;  // 30s default

   switch(m_volRegime)
   {
      case VOL_LOW:     return (int)(baseCooldown * 1.5);  // 45s
      case VOL_NORMAL:  return baseCooldown;                // 30s
      case VOL_HIGH:    return (int)(baseCooldown * 0.5);  // 15s
      case VOL_EXTREME: return 999999;                      // bloklu
   }
   return baseCooldown;
}

//+------------------------------------------------------------------+
//| v3.5.0: GetLastSPMDirection - Son SPM'in yonu (zigzag icin)     |
//| En yuksek layer'daki SPM'in yonunu dondurur                      |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::GetLastSPMDirection()
{
   int highestLayer = 0;
   ENUM_SIGNAL_DIR lastDir = SIGNAL_NONE;

   for(int i = 0; i < m_posCount; i++)
   {
      if(m_positions[i].role != ROLE_SPM) continue;
      if(m_positions[i].spmLayer > highestLayer)
      {
         highestLayer = m_positions[i].spmLayer;
         lastDir = (m_positions[i].type == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      }
   }
   return lastDir;
}

//+------------------------------------------------------------------+
//| v3.5.4: IsSpreadAcceptable - ADAPTIF Spread kontrolu              |
//| Broker spread baseline'i her tick guncellenir (max observed)       |
//| Boylece BTC=1800, EURUSD=12 gibi gercek degerler otomatik alinir  |
//| Mevcut spread, baseline'in %15 ustune kadar kabul edilir           |
//+------------------------------------------------------------------+
bool CPositionManager::IsSpreadAcceptable()
{
   long currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   if(currentSpread <= 0) return true;  // Spread bilgisi yoksa engelleme

   //--- v3.5.4: ADAPTIF BASELINE - her tick guncelle
   //--- Baseline = gozlenen en yuksek NORMAL spread (yumusak guncelleme)
   //--- Ilk 60 saniye = warmup, trade engellenmez (baseline oturur)
   double curSpreadDbl = (double)currentSpread;

   if(m_defaultBrokerSpread <= 0.0)
   {
      // Ilk deger: mevcut spread'i al
      m_defaultBrokerSpread = curSpreadDbl;
      m_spreadWarmupUntil = TimeCurrent() + 60;  // 60sn warmup
      PrintFormat("[PM-%s] SPREAD BASELINE: Ilk deger = %.0f", m_symbol, curSpreadDbl);
      return true;
   }

   //--- Baseline'i guncelle: mevcut spread baseline'dan yuksekse, baseline'i yukari cek
   //--- (broker'in normal spread'i yuksekse baseline o seviyeye ciksin)
   //--- Ama cok ani spike'lar baseline'i bozmasin: max 3x mevcut baseline
   if(curSpreadDbl > m_defaultBrokerSpread && curSpreadDbl <= m_defaultBrokerSpread * 3.0)
   {
      // Yumusak guncelleme: %80 yeni deger, %20 eski (hizli yakalama)
      m_defaultBrokerSpread = curSpreadDbl * 0.8 + m_defaultBrokerSpread * 0.2;
   }

   //--- Warmup suresi: baseline oturene kadar trade engelleme
   if(TimeCurrent() < m_spreadWarmupUntil)
      return true;

   //--- Max izin verilen = baseline * MaxSpreadMultiplier (default 1.15 = %15 ustu)
   double baseline = m_defaultBrokerSpread;
   double maxAllowed = baseline * MaxSpreadMultiplier;

   if(currentSpread > (long)maxAllowed)
   {
      static datetime lastSpreadLog = 0;
      if(TimeCurrent() - lastSpreadLog > 60)
      {
         PrintFormat("[PM-%s] SPREAD YUKSEK: %d > %.0f (baseline=%.0f x %.2f) = ISLEM ENGELLENDI",
                     m_symbol, (int)currentSpread, maxAllowed, baseline, MaxSpreadMultiplier);
         lastSpreadLog = TimeCurrent();
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| v3.7.1: CheckPeakDipGate - Tepe/Dip Koruma                      |
//| RSI > 75 (tepe) veya RSI < 25 (dip) tespit edildiginde:         |
//|   ADX >= 45 → guclu trend → trend yonunde islem (override)      |
//|   ADX <= 40 → zayif trend → 30sn cooldown + mum yonu            |
//|   ADX 40-45 → gecis bolgesi → trend yonune yonlendir            |
//| Return: true=islem devam, false=ENGELLE (cooldown)               |
//| dirOverride: SIGNAL_NONE=override yok, BUY/SELL=bu yonde ac     |
//+------------------------------------------------------------------+
bool CPositionManager::CheckPeakDipGate(ENUM_SIGNAL_DIR &dirOverride)
{
   dirOverride = SIGNAL_NONE;
   if(m_signalEngine == NULL) return true;

   double rsi = m_signalEngine.GetRSI();
   double adx = m_signalEngine.GetADX();

   bool isPeak = (rsi > 75.0);
   bool isDip  = (rsi < 25.0);
   if(!isPeak && !isDip)
   {
      // Normal RSI (25-75) → Tepe/Dip degil, cooldown reset
      m_peakDipCooldownUntil = 0;
      return true;
   }

   // Tepe/Dip TESPIT edildi
   ENUM_SIGNAL_DIR trendDir = m_signalEngine.GetCurrentTrend();
   string pdStr = isPeak ? "TEPE" : "DIP";

   if(adx >= 45.0)
   {
      // Guclu trend → trend yonunde islem (engelleme yok)
      dirOverride = trendDir;
      m_peakDipCooldownUntil = 0;  // Cooldown reset
      static datetime lastPDLog1 = 0;
      if(TimeCurrent() - lastPDLog1 >= 30)
      {
         PrintFormat("[PM-%s] %s: RSI=%.1f ADX=%.1f >= 45 → TREND %s YONUNDE DEVAM",
                     m_symbol, pdStr, rsi, adx,
                     (trendDir == SIGNAL_BUY) ? "BUY" : "SELL");
         lastPDLog1 = TimeCurrent();
      }
      return true;
   }
   else if(adx <= 40.0)
   {
      // Zayif trend → 30sn cooldown, sonra mum yonu
      if(m_peakDipCooldownUntil == 0)
      {
         // Ilk tespit: cooldown baslat
         m_peakDipCooldownUntil = TimeCurrent() + 30;
         PrintFormat("[PM-%s] %s: RSI=%.1f ADX=%.1f <= 40 → 30sn COOLDOWN BASLADI",
                     m_symbol, pdStr, rsi, adx);
         return false;
      }

      if(TimeCurrent() < m_peakDipCooldownUntil)
      {
         // Cooldown devam ediyor → ENGELLE
         static datetime lastPDLog2 = 0;
         if(TimeCurrent() - lastPDLog2 >= 10)
         {
            int remaining = (int)(m_peakDipCooldownUntil - TimeCurrent());
            PrintFormat("[PM-%s] %s: RSI=%.1f ADX=%.1f <= 40 → COOLDOWN %dsn kaldi",
                        m_symbol, pdStr, rsi, adx, remaining);
            lastPDLog2 = TimeCurrent();
         }
         return false;
      }

      // 30sn gecti → mum yonune gore karar
      ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
      dirOverride = candleDir;
      m_peakDipCooldownUntil = 0;  // Reset
      PrintFormat("[PM-%s] %s: RSI=%.1f ADX=%.1f <= 40 → 30sn BITTI, MUM=%s",
                  m_symbol, pdStr, rsi, adx,
                  (candleDir == SIGNAL_BUY) ? "BUY" : (candleDir == SIGNAL_SELL) ? "SELL" : "YOK");
      return (candleDir != SIGNAL_NONE);
   }
   else
   {
      // ADX 40-45 arasi → gecis bolgesi, trend yonune yonlendir
      dirOverride = trendDir;
      m_peakDipCooldownUntil = 0;
      static datetime lastPDLog3 = 0;
      if(TimeCurrent() - lastPDLog3 >= 30)
      {
         PrintFormat("[PM-%s] %s: RSI=%.1f ADX=%.1f (40-45 gecis) → TREND %s",
                     m_symbol, pdStr, rsi, adx,
                     (trendDir == SIGNAL_BUY) ? "BUY" : "SELL");
         lastPDLog3 = TimeCurrent();
      }
      return true;
   }
}

//+------------------------------------------------------------------+
//| IsPeakOrDip - v3.5.0: Eski fonksiyon (backward compat)           |
//| v3.7.1'de CheckPeakDipGate() kullanilir                          |
//+------------------------------------------------------------------+
bool CPositionManager::IsPeakOrDip()
{
   ENUM_SIGNAL_DIR dummy = SIGNAL_NONE;
   return !CheckPeakDipGate(dummy);  // true = peak/dip engelli
}

//+------------------------------------------------------------------+
//| v3.5.0: CheckNetSettlement - Kasa ile zarardaki en kotuyu kapat  |
//| Kasa + worstLoss >= +$5 → en zarardakini kapat, net kar realize  |
//| FIFO'dan FARKLI: FIFO sadece ANA kapatir, bu HERHANGi pozisyonu |
//+------------------------------------------------------------------+
void CPositionManager::CheckNetSettlement()
{
   // Kasa minimum birikimi
   if(m_spmClosedProfitTotal < 3.0) return;

   // Cooldown
   static datetime lastSettleTime = 0;
   if(TimeCurrent() - lastSettleTime < 10) return;  // 10sn min araligi

   // En zarardaki pozisyonu bul (HEDGE MUAF - hedge koruma gorevi gorur)
   int worstIdx = -1;
   double worstLoss = 0.0;
   for(int i = 0; i < m_posCount; i++)
   {
      // v3.5.8: HEDGE pozisyonlar net settlement'tan MUAF
      // HEDGE ANA'yi korumak icin acildi, erken kapatilmamali
      if(m_positions[i].role == ROLE_HEDGE) continue;

      // v3.6.2: ANA net settlement'tan MUAF
      // ANA SADECE FIFO ile kapanir - CheckNetSettlement ANA'yi kapatirsa
      // PromoteOldestSPM cagrilmaz ve sistem bozulur
      if(m_positions[i].role == ROLE_MAIN) continue;

      if(m_positions[i].profit < worstLoss)
      {
         worstLoss = m_positions[i].profit;
         worstIdx = i;
      }
   }

   // Zarardaki yok veya zarar cok kucuk
   if(worstIdx < 0 || worstLoss >= -0.50) return;

   // Net hesap: kasa + worstLoss (negatif)
   double netResult = m_spmClosedProfitTotal + worstLoss;

   // +$5 net kar gerekliligi (profil'den fifoNetTarget kullan)
   double settleTarget = m_profile.fifoNetTarget;

   if(netResult < settleTarget) return;

   // KAPAT!
   ulong worstTicket = m_positions[worstIdx].ticket;
   ENUM_POS_ROLE worstRole = m_positions[worstIdx].role;

   string roleStr = "";
   if(worstRole == ROLE_MAIN)     roleStr = "ANA";
   else if(worstRole == ROLE_SPM) roleStr = StringFormat("SPM%d", m_positions[worstIdx].spmLayer);
   else if(worstRole == ROLE_DCA) roleStr = "DCA";
   else                           roleStr = "HEDGE";

   PrintFormat("[PM-%s] +++ NET SETTLE +++ Kasa=$%.2f + Worst=$%.2f = Net=$%.2f >= $%.2f -> %s #%llu KAPAT",
               m_symbol, m_spmClosedProfitTotal, worstLoss, netResult, settleTarget, roleStr, worstTicket);

   if(m_executor != NULL)
   {
      bool closed = m_executor.ClosePosition(worstTicket);
      if(closed)
      {
         m_totalCashedProfit += netResult;
         m_dailyProfit += netResult;
         m_spmClosedProfitTotal = 0.0;
         m_spmClosedCount = 0;
         lastSettleTime = TimeCurrent();

         PrintFormat("[PM-%s] NET SETTLE BASARILI: %s #%llu kapatildi | Net=$%.2f realize",
                     m_symbol, roleStr, worstTicket, netResult);

         if(m_telegram != NULL)
            m_telegram.SendMessage(StringFormat("NET SETTLE %s: %s kapatildi Net=$%.2f Kasa sifir",
                                    m_symbol, roleStr, netResult));

         // ANA kapatildiysa terfi gerekli
         if(worstRole == ROLE_MAIN)
         {
            m_mainTicket = 0;
            RefreshPositions();
            if(GetActiveSPMCount() > 0)
               PromoteOldestSPM();
         }
         else
         {
            RefreshPositions();
         }
      }
      else
      {
         PrintFormat("[PM-%s] NET SETTLE HATA: %s #%llu kapatilamadi", m_symbol, roleStr, worstTicket);
      }
   }
}

//+------------------------------------------------------------------+
//| v3.5.7: CheckRescueHedge - AGIR ZARAR KURTARMA                  |
//| ANA zarar >= rescueHedgeThreshold (-$30) olunca:                 |
//|   - Zarardaki toplam lot hesapla                                  |
//|   - ANA'nin TERSI yonde 1.5x toplam lot ile hedge ac             |
//|   - Tek seferlik tetik (cooldown ile tekrar kontrollu)            |
//+------------------------------------------------------------------+
void CPositionManager::CheckRescueHedge()
{
   // v3.7.0: HEDGE TETIK = SPM2 bireysel zarar >= rescueHedgeThreshold (-$7)
   // KURALSIZ: Smart Rescue Filter KALDIRILDI
   // Lot: ANA × 1.3 (rescueHedgeLotMult)
   // Yon: trend+sinyal+mum oylama, yoksa ANA tersi

   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   // WARMUP kontrolu
   if(TimeCurrent() < m_spmWarmupUntil) return;

   // Zaten aktif hedge var mi?
   if(GetActiveHedgeCount() > 0)
   {
      static datetime lastRescueLog2 = 0;
      if(TimeCurrent() - lastRescueLog2 >= 120)
      {
         PrintFormat("[PM-%s] RESCUE: Zaten aktif hedge var (%d), yeni acilmayacak",
                     m_symbol, GetActiveHedgeCount());
         lastRescueLog2 = TimeCurrent();
      }
      return;
   }

   // v3.7.0: SPM2'yi bul — HEDGE tetigi SPM2 bireysel zararina bagli
   int spm2Idx = -1;
   for(int j = 0; j < m_posCount; j++)
   {
      if(m_positions[j].role == ROLE_SPM && m_positions[j].spmLayer == 2)
      {
         spm2Idx = j;
         break;
      }
   }
   if(spm2Idx < 0) return;  // SPM2 yok → HEDGE tetiklenemez

   double spm2Loss = m_positions[spm2Idx].profit;
   if(spm2Loss > m_profile.rescueHedgeThreshold) return;  // SPM2 henuz esige ulasmadi

   // MUTLAK COOLDOWN - HEDGE kapandiktan sonra 180sn bekle
   if(m_lastHedgeCloseTime > 0 && TimeCurrent() - m_lastHedgeCloseTime < 180)
   {
      static datetime lastCoolLog = 0;
      if(TimeCurrent() - lastCoolLog >= 60)
      {
         int remaining = 180 - (int)(TimeCurrent() - m_lastHedgeCloseTime);
         PrintFormat("[PM-%s] RESCUE COOLDOWN: %dsn kaldi | SPM2 zarar=$%.2f",
                     m_symbol, remaining, spm2Loss);
         lastCoolLog = TimeCurrent();
      }
      return;
   }

   // v3.7.0: KURALSIZ — Smart Rescue Filter KALDIRILDI
   //   HEDGE ACILSIN, sinyal/trend/oylama filtresi YOK

   // Bakiye/paused kontrolleri
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;

   // Margin kontrolu
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(marginLevel > 0.0 && marginLevel < 150.0)
   {
      PrintFormat("[PM-%s] RESCUE: Margin cok dusuk (%.1f%%), hedge acilamadi", m_symbol, marginLevel);
      return;
   }

   // v3.7.0: HEDGE lot = ANA lot × 1.3
   double anaLot = m_positions[mainIdx].volume;
   double rescueLot = anaLot * m_profile.rescueHedgeLotMult;  // 1.3x

   // Normalize
   double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0) rescueLot = MathFloor(rescueLot / lotStep) * lotStep;
   if(rescueLot < minLot) rescueLot = minLot;
   if(rescueLot > maxLot) rescueLot = maxLot;

   // Hacim limiti ESNEK (acil durum)
   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol + rescueLot > MaxTotalVolume * 1.5)
   {
      rescueLot = MaxTotalVolume - totalVol;
      if(rescueLot < minLot)
      {
         PrintFormat("[PM-%s] RESCUE: Hacim limiti asildi, hedge acilamadi", m_symbol);
         return;
      }
   }

   // v3.8.0: HEDGE YON MANTIGI — trend + ADX bazli akilli yon
   //   Sorun: ANA BUY iken guclu yuselis trendinde SELL HEDGE acildi → -$57 kayip
   //   Cozum:
   //     ADX >= 30 + trend = ANA yonu → HEDGE ACMA (ANA toparlanacak, hedge gereksiz)
   //     ADX >= 30 + trend = ANA tersi → HEDGE ANA tersi (dogru koruma)
   //     ADX < 30 (zayif trend) → oylama ile karar ver
   bool isBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);
   ENUM_SIGNAL_DIR mainDir = isBuy ? SIGNAL_BUY : SIGNAL_SELL;
   ENUM_SIGNAL_DIR hedgeDir = isBuy ? SIGNAL_SELL : SIGNAL_BUY;  // Default: ANA tersi

   if(m_signalEngine != NULL)
   {
      ENUM_SIGNAL_DIR confirmedTrend = m_signalEngine.GetConfirmedTrend(TrendConfirmCount);
      double adxVal = m_signalEngine.GetADX();

      // v3.8.0: Guclu trend ANA yonunde → HEDGE ACMA (gereksiz)
      if(adxVal >= 30.0 && confirmedTrend == mainDir)
      {
         PrintFormat("[PM-%s] HEDGE IPTAL: ADX=%.1f >= 30 + Trend=%s = ANA=%s → ANA toparlanacak, HEDGE gereksiz",
                     m_symbol, adxVal,
                     (confirmedTrend == SIGNAL_BUY) ? "BUY" : "SELL",
                     isBuy ? "BUY" : "SELL");
         return;
      }

      // Trend ANA tersi veya zayif → HEDGE yon belirleme
      SignalData sig = m_signalEngine.Evaluate();
      ENUM_SIGNAL_DIR candleDir = GetCandleDirection();

      int buyVotes = 0, sellVotes = 0;
      if(confirmedTrend == SIGNAL_BUY) buyVotes++; else if(confirmedTrend == SIGNAL_SELL) sellVotes++;
      if(sig.score >= SignalMinScore && sig.direction == SIGNAL_BUY) buyVotes++; else if(sig.score >= SignalMinScore && sig.direction == SIGNAL_SELL) sellVotes++;
      if(candleDir == SIGNAL_BUY) buyVotes++; else if(candleDir == SIGNAL_SELL) sellVotes++;

      if(buyVotes >= 2) hedgeDir = SIGNAL_BUY;
      else if(sellVotes >= 2) hedgeDir = SIGNAL_SELL;
      // else default ANA tersi kalir

      // v3.8.0: HEDGE ANA ile ayni yonde OLMAMALI (hedging mantigi bozulur)
      // Eger oylama ANA yonunu gosteriyorsa → hedge ACMA
      if(hedgeDir == mainDir)
      {
         PrintFormat("[PM-%s] HEDGE IPTAL: Oylama ANA yonu (%s) gosteriyor → HEDGE gereksiz",
                     m_symbol, isBuy ? "BUY" : "SELL");
         return;
      }
   }

   double mainProfit = m_positions[mainIdx].profit;
   PrintFormat("[PM-%s] !!! v3.7.0 RESCUE HEDGE !!! SPM2 zarar=$%.2f <= $%.2f | ANA=$%.2f | HEDGE %s %.2f lot (ANA×%.1fx KURALSIZ)",
               m_symbol, spm2Loss, m_profile.rescueHedgeThreshold,
               mainProfit,
               (hedgeDir == SIGNAL_BUY) ? "BUY" : "SELL", rescueLot, m_profile.rescueHedgeLotMult);

   OpenHedge(hedgeDir, rescueLot);

   //--- v4.3: Zengin Hedge bildirimi
   if(m_telegram != NULL)
   {
      RefreshPositions();
      string hedgePosMap = GetPositionMapHTML();
      m_telegram.SendHedgeEvent(m_symbol, GetCategoryName(), "ACILDI",
                                 (hedgeDir == SIGNAL_BUY) ? "BUY" : "SELL", rescueLot, hedgePosMap);
   }
   if(m_discord != NULL)
      m_discord.SendMessage(StringFormat("RESCUE HEDGE %s: SPM2=$%.2f | %s %.2f lot",
                             m_symbol, spm2Loss,
                             (hedgeDir == SIGNAL_BUY) ? "BUY" : "SELL", rescueLot));
}

//+------------------------------------------------------------------+
//| v3.5.8+: ManageHedgePositions - HEDGE akilli kapatma             |
//| HEDGE su durumlarda kapanir:                                     |
//|   1. ANA artik yok → HEDGE'i karla kapat                        |
//|   2. ANA + HEDGE net toplam >= +$5                               |
//|   3. Trend = ANA yonu + ANA toparlanma + HEDGE karda             |
//|   4. v3.6.4: HEDGE PeakDrop - tepe kar duserse kapat             |
//+------------------------------------------------------------------+
void CPositionManager::ManageHedgePositions()
{
   if(GetActiveHedgeCount() == 0) return;

   int mainIdx = FindMainPosition();

   for(int i = m_posCount - 1; i >= 0; i--)
   {
      if(m_positions[i].role != ROLE_HEDGE) continue;

      double hedgeProfit = m_positions[i].profit;

      //--- Durum 1: ANA artik yok → HEDGE yeni ANA olur
      //   v3.6.6: HEDGE ASLA zararda kapatilmaz!
      //   Karda ise: kapat, kari kasaya ekle
      //   Zararda ise: HEDGE → ANA terfi (pozisyon korunur, yeni dongu baslar)
      if(mainIdx < 0)
      {
         if(hedgeProfit >= m_profile.minCloseProfit)
         {
            // HEDGE karda → kapat ve kari kasaya ekle
            PrintFormat("[PM-%s] HEDGE KAPAT (ANA yok, KARDA): #%d Kar=$%.2f -> kapat",
                        m_symbol, (int)m_positions[i].ticket, hedgeProfit);

            m_totalCashedProfit += hedgeProfit;
            m_spmClosedProfitTotal += hedgeProfit;
            m_spmClosedCount++;

            string msg = StringFormat("HEDGE KAR %s: $%.2f -> KAPATILDI (ANA yok)", m_symbol, hedgeProfit);
            if(m_telegram != NULL) m_telegram.SendMessage(msg);
            if(m_discord != NULL)  m_discord.SendMessage(msg);

            ClosePosWithNotification(i, StringFormat("HEDGE_AnaYok_%.2f", hedgeProfit));
         }
         else
         {
            // v3.6.6: HEDGE zararda veya dusuk karda → ANA'ya TERFI ET
            // HEDGE'in korudugu pozisyon yok → zararda kapatmak anlamsiz
            // Yeni ANA olarak devam eder, SPM acilabilir, FIFO calisir
            m_positions[i].role = ROLE_MAIN;
            m_positions[i].spmLayer = 0;
            m_mainTicket = m_positions[i].ticket;

            // Yeni dongu: kasa ve FIFO sifirla
            m_spmClosedProfitTotal = 0.0;
            m_spmClosedCount = 0;
            m_fifoWaitStart = 0;

            bool isBuy = (m_positions[i].type == POSITION_TYPE_BUY);
            PrintFormat("[PM-%s] HEDGE->ANA TERFI: #%llu %s P/L=$%.2f -> Yeni ANA (zararda kapatilmaz, yeni dongu)",
                        m_symbol, m_positions[i].ticket,
                        isBuy ? "BUY" : "SELL", hedgeProfit);

            string msg = StringFormat("TERFI %s: HEDGE #%d -> ANA ($%.2f) Yeni dongu basliyor",
                                       m_symbol, (int)m_positions[i].ticket, hedgeProfit);
            if(m_telegram != NULL) m_telegram.SendMessage(msg);
            if(m_discord != NULL)  m_discord.SendMessage(msg);
         }
         continue;
      }

      //--- ANA mevcut - offset kontrol
      double mainProfit = m_positions[mainIdx].profit;

      //--- Durum 2: ANA + HEDGE net toplam >= +$5 (minimum kar hedefi)
      double hedgeNetTarget = 5.0;  // ANA+HEDGE min +$5 net kar
      double netTotal = mainProfit + hedgeProfit;
      if(netTotal >= hedgeNetTarget && hedgeProfit > 0.0)
      {
         PrintFormat("[PM-%s] HEDGE+ANA NET KAR: ANA=$%.2f + HEDGE=$%.2f = Net=$%.2f >= +$%.0f -> HEDGE kapat",
                     m_symbol, mainProfit, hedgeProfit, netTotal, hedgeNetTarget);

         m_totalCashedProfit += hedgeProfit;
         // v3.6.2: m_dailyProfit ClosePosWithNotification icinde eklenir (cift sayim fix)
         m_spmClosedProfitTotal += hedgeProfit;
         m_spmClosedCount++;

         string msg = StringFormat("HEDGE OFFSET %s: ANA=$%.2f HEDGE=$%.2f Net=$%.2f", m_symbol, mainProfit, hedgeProfit, netTotal);
         if(m_telegram != NULL) m_telegram.SendMessage(msg);
         if(m_discord != NULL)  m_discord.SendMessage(msg);

         ClosePosWithNotification(i, StringFormat("HEDGE_Offset_%.2f", netTotal));
         continue;
      }

      //--- Durum 3: v3.6.1 Trend ANA yonune dondu → HEDGE kapat (ANA toparlanacak)
      //   v3.6.2: HEDGE ASLA ZARARDA KAPATILMAZ - sadece karda veya sifirda
      //   Kosullar:
      //     1. Onaylanmis trend = ANA yonu (piyasa ANA yonunde)
      //     2. ANA zarari iyilesmeye basladi (> spmTriggerLoss / 2)
      //     3. HEDGE karDA veya sifirda (ASLA zararda kapatma!)
      if(m_signalEngine != NULL)
      {
         ENUM_SIGNAL_DIR confirmedTrend = m_signalEngine.GetConfirmedTrend(TrendConfirmCount);
         bool mainIsBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);
         ENUM_SIGNAL_DIR mainDir = mainIsBuy ? SIGNAL_BUY : SIGNAL_SELL;

         // v3.6.2: Daha siki kosullar
         //   ANA zarari spmTriggerLoss/2'den iyi olmali (gercek toparlanma)
         //   HEDGE karda veya sifirda olmali (ASLA zararda kapatma)
         double recoveryLevel = m_profile.spmTriggerLoss / 2.0;  // XAG: -$2.5
         if(confirmedTrend == mainDir && mainProfit > recoveryLevel && hedgeProfit >= 0.0)
         {
            PrintFormat("[PM-%s] HEDGE TREND KAPAT: Trend=%s = ANA=%s | ANA=$%.2f (esik=$%.1f) | HEDGE=$%.2f (KARDA) → HEDGE kapat",
                        m_symbol,
                        (confirmedTrend == SIGNAL_BUY) ? "BUY" : "SELL",
                        mainIsBuy ? "BUY" : "SELL",
                        mainProfit, recoveryLevel, hedgeProfit);

            m_totalCashedProfit += hedgeProfit;
            m_spmClosedProfitTotal += hedgeProfit;
            m_spmClosedCount++;

            string msg = StringFormat("HEDGE TREND %s: ANA=$%.2f HEDGE=$%.2f kapatildi (trend=%s)",
                                      m_symbol, mainProfit, hedgeProfit,
                                      (confirmedTrend == SIGNAL_BUY) ? "BUY" : "SELL");
            if(m_telegram != NULL) m_telegram.SendMessage(msg);
            if(m_discord != NULL)  m_discord.SendMessage(msg);

            ClosePosWithNotification(i, StringFormat("HEDGE_TrendKapat_%.2f", hedgeProfit));
            continue;
         }
      }

      //--- Durum 4: v3.6.4 HEDGE PeakDrop - Tepe kar duserse kapat
      //   HEDGE $36 tepeye ulasti ama hic kapanmadi, $21'e dustu → $15 kayip!
      //   Peak >= HedgePeakMinProfit ($8) VE profit < peak * (1 - HedgePeakDropPercent/100)
      //   Ornek: Peak=$36.85, %25 dusus → $36.85 * 0.75 = $27.64 altina dusunce kapat
      {
         // HEDGE peak tracking (ManageKarliPozisyonlar HEDGE'i skip eder)
         if(i < ArraySize(m_peakProfit))
         {
            if(hedgeProfit > m_peakProfit[i])
               m_peakProfit[i] = hedgeProfit;
         }

         double hedgePeak = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : 0.0;

         if(hedgePeak >= HedgePeakMinProfit && hedgeProfit > 0.0)
         {
            double dropThreshold = hedgePeak * (1.0 - HedgePeakDropPercent / 100.0);

            if(hedgeProfit <= dropThreshold)
            {
               double dropPct = (hedgePeak > 0.0) ? ((hedgePeak - hedgeProfit) / hedgePeak * 100.0) : 0.0;
               PrintFormat("[PM-%s] HEDGE PEAKDROP: #%d Peak=$%.2f -> Simdiki=$%.2f (-%.1f%%) | Esik=$%.2f (%.0f%% dusus) -> HEDGE KAPAT",
                           m_symbol, (int)m_positions[i].ticket, hedgePeak, hedgeProfit, dropPct, dropThreshold, HedgePeakDropPercent);

               m_totalCashedProfit += hedgeProfit;
               m_spmClosedProfitTotal += hedgeProfit;
               m_spmClosedCount++;

               string msg = StringFormat("HEDGE PEAKDROP %s: Peak=$%.2f -> $%.2f (-%.1f%%) KAPATILDI +$%.2f",
                                          m_symbol, hedgePeak, hedgeProfit, dropPct, hedgeProfit);
               if(m_telegram != NULL) m_telegram.SendMessage(msg);
               if(m_discord != NULL)  m_discord.SendMessage(msg);

               ClosePosWithNotification(i, StringFormat("HEDGE_PeakDrop_%.2f", hedgeProfit));
               continue;
            }
         }
      }

      //--- Durum 5: v3.8.0 HEDGE DEADLOCK KORUMA — max sure + max kayip
      //   Sorun: HEDGE sonsuza kadar acik kalip -$57 kaybetti (hesap sifir)
      //   Kural 1: HEDGE 10dk'dan fazla acik + zararda → KAPAT
      //   Kural 2: HEDGE kaybi > bakiyenin %20'si → HEMEN KAPAT
      {
         datetime hedgeOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(hedgeOpenTime == 0)
         {
            // PositionSelect ile dene
            if(PositionSelectByTicket(m_positions[i].ticket))
               hedgeOpenTime = (datetime)PositionGetInteger(POSITION_TIME);
         }

         int hedgeAgeSec = (hedgeOpenTime > 0) ? (int)(TimeCurrent() - hedgeOpenTime) : 0;
         double hedgeMaxTime = 600;  // 10 dakika = 600 saniye
         double hedgeMaxLossRatio = 0.20;  // Bakiyenin %20'si
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);

         // Kural 2: Kayip > %20 bakiye → HEMEN kapat (sure bakmaz)
         if(hedgeProfit < 0.0 && balance > 0.0)
         {
            double lossRatio = MathAbs(hedgeProfit) / balance;
            if(lossRatio > hedgeMaxLossRatio)
            {
               PrintFormat("[PM-%s] !!! HEDGE KAYIP LIMIT !!! #%d Kayip=$%.2f (%.1f%% bakiye) > %.0f%% → HEDGE KAPAT",
                           m_symbol, (int)m_positions[i].ticket, hedgeProfit,
                           lossRatio * 100.0, hedgeMaxLossRatio * 100.0);

               string msg = StringFormat("HEDGE KAYIP %s: #%d $%.2f (%.1f%% bakiye) → KAPATILDI",
                                          m_symbol, (int)m_positions[i].ticket,
                                          hedgeProfit, lossRatio * 100.0);
               if(m_telegram != NULL) m_telegram.SendMessage(msg);
               if(m_discord != NULL)  m_discord.SendMessage(msg);

               m_lastHedgeCloseTime = TimeCurrent();
               ClosePosWithNotification(i, StringFormat("HEDGE_MaxKayip_%.2f", hedgeProfit));
               continue;
            }
         }

         // Kural 1: 10dk acik + zararda → kapat
         if(hedgeAgeSec > (int)hedgeMaxTime && hedgeProfit < -1.0)
         {
            PrintFormat("[PM-%s] !!! HEDGE SURE LIMIT !!! #%d Sure=%dsn > %dsn | Kayip=$%.2f → HEDGE KAPAT",
                        m_symbol, (int)m_positions[i].ticket, hedgeAgeSec,
                        (int)hedgeMaxTime, hedgeProfit);

            string msg = StringFormat("HEDGE TIMEOUT %s: #%d %ddk acik, $%.2f kayip → KAPATILDI",
                                       m_symbol, (int)m_positions[i].ticket,
                                       hedgeAgeSec / 60, hedgeProfit);
            if(m_telegram != NULL) m_telegram.SendMessage(msg);
            if(m_discord != NULL)  m_discord.SendMessage(msg);

            m_lastHedgeCloseTime = TimeCurrent();
            ClosePosWithNotification(i, StringFormat("HEDGE_Timeout_%dsn_%.2f", hedgeAgeSec, hedgeProfit));
            continue;
         }
      }

      //--- HEDGE devam ediyor (log 60sn'de bir)
      static datetime lastHedgeLog = 0;
      if(TimeCurrent() - lastHedgeLog >= 60)
      {
         // v3.6.0+: Trend + peak bilgisi logla
         string trendStr = "YOK";
         if(m_signalEngine != NULL)
         {
            ENUM_SIGNAL_DIR ct = m_signalEngine.GetConfirmedTrend(TrendConfirmCount);
            trendStr = (ct == SIGNAL_BUY) ? "BUY" : (ct == SIGNAL_SELL) ? "SELL" : "YOK";
         }
         bool mainIsBuyLog = (m_positions[mainIdx].type == POSITION_TYPE_BUY);
         string mainDirStr = mainIsBuyLog ? "BUY" : "SELL";
         double hedgePeakLog = (i < ArraySize(m_peakProfit)) ? m_peakProfit[i] : 0.0;
         string waitStr = (trendStr == mainDirStr) ? "TREND=ANA (kapat bekle)" : "BEKLE";
         PrintFormat("[PM-%s] HEDGE AKTIF: #%d P/L=$%.2f | Peak=$%.2f | ANA=$%.2f | Net=$%.2f | Trend=%s ANA=%s -> %s | Sure=%dsn",
                     m_symbol, (int)m_positions[i].ticket, hedgeProfit, hedgePeakLog, mainProfit, mainProfit + hedgeProfit,
                     trendStr, mainDirStr, waitStr,
                     (int)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME)));
         lastHedgeLog = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| v3.6.0: EvaluateSPMDirection - Sinyal Bazli SPM Yonu             |
//| Kor zigzag yerine piyasa analizi ile SPM yonu belirler           |
//| v4.0: AGIRLIKLI 5-KAYNAK OYLAMA                                 |
//|   Kaynak 1: GetConfirmedTrend()  → H1 trend yonu (AGIRLIK 2.0) |
//|   Kaynak 2: MACD Histogram       → Momentum     (AGIRLIK 1.5)  |
//|   Kaynak 3: GetCandleDirection()  → M15 mum yonu (AGIRLIK 1.0) |
//|   Kaynak 4: DI Crossover (+DI/-DI)               (AGIRLIK 1.0) |
//|   Kaynak 5: RSI Counter-trend (oversold/overbought) (AGIRLIK 1.0)|
//| OYLAMA: Agirlikli cogunluk → o yone ac                          |
//| Hic sinyal yoksa → Fallback: ANA'nin tersi (guvenlik agi)       |
//+------------------------------------------------------------------+
ENUM_SIGNAL_DIR CPositionManager::EvaluateSPMDirection(int mainIdx)
{
   if(mainIdx < 0) return SIGNAL_NONE;

   bool isBuy = (m_positions[mainIdx].type == POSITION_TYPE_BUY);

   double buyWeight = 0.0;
   double sellWeight = 0.0;

   // Kaynak 1: GetConfirmedTrend() — H1 onayli trend yonu (AGIRLIK 2.0)
   ENUM_SIGNAL_DIR trendDir = SIGNAL_NONE;
   if(m_signalEngine != NULL)
   {
      trendDir = m_signalEngine.GetConfirmedTrend(TrendConfirmCount);
      if(trendDir == SIGNAL_BUY)       buyWeight += 2.0;
      else if(trendDir == SIGNAL_SELL)  sellWeight += 2.0;
   }

   // Kaynak 2: MACD Histogram — Momentum (AGIRLIK 1.5)
   if(m_signalEngine != NULL)
   {
      double macdHist = m_signalEngine.GetMACDHist();
      if(macdHist > 0)      buyWeight += 1.5;
      else if(macdHist < 0) sellWeight += 1.5;
   }

   // Kaynak 3: GetCandleDirection() — M15 mum yonu (AGIRLIK 1.0)
   ENUM_SIGNAL_DIR candleDir = GetCandleDirection();
   if(candleDir == SIGNAL_BUY)       buyWeight += 1.0;
   else if(candleDir == SIGNAL_SELL)  sellWeight += 1.0;

   // Kaynak 4: DI Crossover (+DI vs -DI) (AGIRLIK 1.0)
   if(m_signalEngine != NULL)
   {
      double plusDI  = m_signalEngine.GetPlusDI();
      double minusDI = m_signalEngine.GetMinusDI();
      if(plusDI > minusDI)       buyWeight += 1.0;
      else if(minusDI > plusDI)  sellWeight += 1.0;
   }

   // Kaynak 5: RSI Counter-trend (AGIRLIK 1.0)
   if(m_signalEngine != NULL)
   {
      double rsiVal = m_signalEngine.GetRSI();
      if(rsiVal < 35)       buyWeight += 1.0;   // Asiri satim → toparlanma
      else if(rsiVal > 65)  sellWeight += 1.0;   // Asiri alim → dusus
   }

   ENUM_SIGNAL_DIR result = SIGNAL_NONE;

   // Agirlikli cogunluk karari
   if(buyWeight > sellWeight)
      result = SIGNAL_BUY;
   else if(sellWeight > buyWeight)
      result = SIGNAL_SELL;
   // Esitlik: Trend yonu
   else if(trendDir != SIGNAL_NONE)
      result = trendDir;
   // Hic sinyal yok → Fallback: ANA'nin tersi (eski zigzag guvenlik agi)
   else if(buyWeight == 0 && sellWeight == 0)
   {
      result = isBuy ? SIGNAL_SELL : SIGNAL_BUY;
      PrintFormat("[PM-%s] SPM YON: Tum kaynaklar BOSSA → FALLBACK zigzag (ANA=%s → SPM=%s)",
                  m_symbol, isBuy ? "BUY" : "SELL",
                  (result == SIGNAL_BUY) ? "BUY" : "SELL");
   }
   else
   {
      // v4.0: Sinyal cakismiyor — ANA kurtarma modundaysa zigzag fallback
      double mainLoss = m_positions[mainIdx].profit;
      if(mainLoss <= m_profile.spmTriggerLoss)
      {
         result = isBuy ? SIGNAL_SELL : SIGNAL_BUY;
         PrintFormat("[PM-%s] SPM YON: BUY=%.1f SELL=%.1f → CAKISMIYOR ama ANA KURTARMA (%.2f<=%.2f) → FALLBACK SPM=%s",
                     m_symbol, buyWeight, sellWeight,
                     mainLoss, m_profile.spmTriggerLoss,
                     (result == SIGNAL_BUY) ? "BUY" : "SELL");
      }
      else
      {
         // Normal mod: sinyal cakismiyor → BEKLE
         bool canLogDir = (TimeCurrent() - m_lastSPMLogTime >= 60);
         if(canLogDir)
         {
            PrintFormat("[PM-%s] SPM YON: BUY=%.1f SELL=%.1f → CAKISMIYOR, SPM BEKLE",
                        m_symbol, buyWeight, sellWeight);
            m_lastSPMLogTime = TimeCurrent();
         }
         return SIGNAL_NONE;
      }
   }

   // Detayli log
   bool sameAsMain = (result == SIGNAL_BUY && isBuy) || (result == SIGNAL_SELL && !isBuy);
   PrintFormat("[PM-%s] SPM YON(v4): BUY=%.1f SELL=%.1f → SPM=%s (%s)",
               m_symbol, buyWeight, sellWeight,
               (result == SIGNAL_BUY) ? "BUY" : "SELL",
               sameAsMain ? "DCA" : "DOGAL-HEDGE");

   return result;
}

//+------------------------------------------------------------------+
//| v3.5.0: CheckSPMBalance - Tek tarafli birikim dengesi            |
//| v3.5.7: DEVRE DISI - Zigzag grid otomatik dengeliyor             |
//| BUY/SELL dengesizligi var + trend guclu degilse → karsi yonde ac |
//| Grid sistemi tek tarafa yuklenmemeli (margin dengesi)             |
//+------------------------------------------------------------------+
void CPositionManager::CheckSPMBalance()
{
   // v3.5.7: DEVRE DISI - Zigzag grid her SPM'i ters yonde acar, otomatik dengeli
   return;

   // Min 3 SPM olmali (dengesizlik anlamli olsun)
   if(GetActiveSPMCount() < 3) return;

   // Cooldown
   if(TimeCurrent() < m_lastSPMTime + GetAdaptiveCooldown()) return;

   int buyCnt = GetBuyLayerCount();
   int sellCnt = GetSellLayerCount();
   double buyLots = GetTotalBuyLots();
   double sellLots = GetTotalSellLots();

   // Dengesizlik tespiti: Bir taraf 2+ fazla VEYA lot 2x+
   bool imbalanced = false;
   ENUM_SIGNAL_DIR balanceDir = SIGNAL_NONE;

   if(buyCnt >= sellCnt + 2 || (sellLots > 0 && buyLots > sellLots * 2.0))
   {
      imbalanced = true;
      balanceDir = SIGNAL_SELL;  // BUY fazla → SELL ekle
   }
   else if(sellCnt >= buyCnt + 2 || (buyLots > 0 && sellLots > buyLots * 2.0))
   {
      imbalanced = true;
      balanceDir = SIGNAL_BUY;   // SELL fazla → BUY ekle
   }

   if(!imbalanced || balanceDir == SIGNAL_NONE) return;

   // Trend guclu mu? Gucluyse dengesizlik OK (trend takip ediliyor)
   if(m_signalEngine != NULL)
   {
      ENUM_TREND_STRENGTH strength = m_signalEngine.GetTrendStrength();
      if(strength >= TREND_MODERATE) return;  // ADX >= 25 = trend guclu, karisma
   }

   // Diger kontroller
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < MinBalanceToTrade) return;
   if(IsTradingPaused()) return;
   if(!IsSpreadAcceptable()) return;

   double totalVol = GetTotalBuyLots() + GetTotalSellLots();
   if(totalVol >= MaxTotalVolume) return;

   // Grid limit
   int maxGrid = GetMaxGridByBalance();
   if(GetActiveSPMCount() >= maxGrid) return;

   // Lot hesabi
   int mainIdx = FindMainPosition();
   if(mainIdx < 0) return;

   // v3.6.7: Sadece SPM/DCA sayilir (ANA+HEDGE haric)
   int spmSideCount = GetSPMCountForSide(balanceDir);
   int lotLayer = spmSideCount + 1;
   double balanceLot = CalcSPMLot(m_positions[mainIdx].volume, lotLayer);

   PrintFormat("[PM-%s] DENGE SPM: Buy=%d(%0.2f) Sell=%d(%.2f) -> %s %.2f lot (dengeleme)",
               m_symbol, buyCnt, buyLots, sellCnt, sellLots,
               (balanceDir == SIGNAL_BUY) ? "BUY" : "SELL", balanceLot);

   OpenSPM(balanceDir, balanceLot, GetHighestLayer() + 1, m_positions[mainIdx].ticket);
}

#endif // POSITION_MANAGER_MQH
