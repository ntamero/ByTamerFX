# Changelog - BytamerFX EA

All notable changes to this project are documented in this file.

---

## [v2.2.6] - 2026-02-19

### Critical Fixes
- **HEDGE PeakDrop Muafiyeti**: HEDGE pozisyonlari artik PeakDrop ile KAPATILMIYOR. PeakDrop sadece SPM/DCA icin gecerli. HEDGE margin korumasi sagladigi icin erken kapatilmasi margin cokusu yaratiyordu.
- **SPM Katman Limiti 5→3**: Tum profillerde maxSpmLayers 5→3 dusuruldu. 5 SPM yigilmasi kucuk hesaplarda margin patlamasina neden oluyordu.
- **MarginKritik Sonrasi Toparlanma Modu**: MarginKritik tetiklendikten sonra EA yeni islem ACMIYOR. Bakiye crash oncesinin %50'sine ulasana veya 24 saat gecene kadar bekler. $13 ile islem devam edip $1'e dusme onlendi.

### Root Cause
- 19 Subat 06:34: XAGUSDm'de 5 SPM SELL yigildi, HEDGE BUY PeakDrop ile erken kapandi, margin korumasi kalkti, 7 saniyede $105→$13 dustu. EA $13 ile devam etti→$1.18.

### Changes
- `PositionManager.mqh`: PeakDrop role kosulu (HEDGE muaf), IsInRecoveryMode(), CheckMarginEmergency recovery
- `Config.mqh`: maxSpmLayers 5→3 (tum profiller), versiyon 2.2.6
- `BytamerFX.mq5`: IsInRecoveryMode() kontrolu, versiyon 2.26
- `ChartDashboard.mqh`: Versiyon header 2.2.6

---

## [v2.2.5] - 2026-02-18

### Critical Fixes
- **SPM Lot Carpanlari Duzeltildi**: Tum profillerde spmLotBase 1.5→1.0, spmLotIncrement 0.2→0.1, spmLotCap 2.0→1.5
- SPM artik: 1.0x, 1.1x, 1.2x, 1.3x, 1.4x, 1.5x seklinde gidiyor (onceki: 1.5x, 1.7x, 1.9x - COKLU MARGIN RISKI)
- Ornek: ANA 0.06 lot ise SPM1=0.06, SPM2=0.07, SPM3=0.07 (onceki: 0.09, 0.10, 0.11)

### Changes
- `Config.mqh`: 10 profilin hepsi guncellendi + input default degerleri

---

## [v2.2.4] - 2026-02-18

### Critical Fixes
- **Deadlock Kapatma Kaldirildi**: CheckDeadlock artik pozisyon KAPATMIYOR. Sadece log + Telegram/Discord uyari gonderiyor. Kilitlenme durumunda pozisyon korunur, yeniden izleme baslar.
- **LOT DENGE Limiti Genisletildi**: Oran limiti 2.5:1 → 4.0:1. Daha fazla SPM katmani acilabilir, kilitlenmeye girme riski azalir.
- **EmergencyHedge Kosulu Gevsedi**: `zarar_taraf_buyuk` sarti kaldirildi. Artik toplam net zarar < 0 VE lot orani > 2.0 ise hedge tetiklenir. ANA kucuk lot ile zarardayken bile hedge acilir.
- **LOT DENGE Log Spam Giderildi**: CheckLotBalance fonksiyonundan PrintFormat kaldirildi.

### Changes
- `PositionManager.mqh`: CheckDeadlock sadece uyari, CheckLotBalance 4.0 limit, ManageEmergencyHedge basitlestirildi
- `Config.mqh`: Versiyon 2.2.3 → 2.2.4
- `BytamerFX.mq5`: Versiyon 2.23 → 2.24
- `ChartDashboard.mqh`: Header guncelleme

---

## [v2.2.3] - 2026-02-18

### Fixes
- **Emoji-Yazi Bosluk**: Tum dashboard panellerinde emoji ile yazi arasina cift bosluk eklendi
- **BMP Unicode**: Dashboard simgeleri BMP Unicode araligi (U+0000-U+FFFF) ile degistirildi

### Changes
- `ChartDashboard.mqh`: Tum panel etiketleri ve deger stringlerinde cift bosluk
- `BytamerFX.mq5`: Tooltip BMP Unicode guncelleme

---

## [v2.2.2] - 2026-02-18

### Critical Fixes
- **Minimum Profit Threshold**: Added `minCloseProfit` to SymbolProfile. No SPM/DCA/HEDGE position closes below the minimum profit. Prevents trades closing at $0.26-$0.80 that don't cover spread+commission costs. Forex/XAG/XAU=$1.0, BTC=$1.5.
- **SPM Emergency Cooldown Skip**: When SPM loss exceeds 2x the trigger threshold (e.g., -$10 when trigger is -$5), the cooldown for next SPM layer is skipped entirely. Prevents situations where SPM1 reaches -$10.45 but SPM2 can't open for 60 seconds.
- **ANA Position Broker TP Removed**: Broker-side TP is no longer set for main (ANA) positions. ANA ONLY closes via FIFO (net >= +$5). Previously, broker would auto-close ANA at TP price, bypassing FIFO logic and resulting in tiny $0.26 profits.
- **ANA Ticket Detection Fix**: When broker closes ANA via TP/SL, `m_mainTicket` now properly resets. New positions are correctly identified as ANA instead of being misassigned as SPM1.
- **BTC TP Pips Increased 10x**: BTC TP1: 1500→15000, TP2: 2500→30000, TP3: 3500→50000 pips. At 0.01 lot, old values only yielded ~$0.35 profit. New values yield $1.50/$3.00/$5.00+.
- **CryptoAlt TP Pips Increased 10x**: Similar adjustment for altcoins: 500→5000, 1000→10000, 1800→18000 pips.

### Changes
- `Config.mqh`: Added `minCloseProfit` field to SymbolProfile, updated all 10 profiles. Version 2.2.1→2.2.2
- `PositionManager.mqh`: All 5 profit-close rules now respect `minCloseProfit`. Emergency SPM cooldown skip when loss >= 2x trigger. ANA ticket existence check in `RefreshPositions()`. Role assignment fix when `m_mainTicket == 0`.
- `BytamerFX.mq5`: ANA broker TP set to 0 (FIFO-only close). Version 2.21→2.22

---

## [v2.2.1] - 2026-02-18

### Critical Fixes
- **SPM SAME-DIR BLOCK Infinite Loop Fix**: When main position was losing and 5-vote returned same direction, SPM never opened. After override to opposite direction, `ShouldWaitForANARecovery` is now skipped, SPM opens immediately in opposite direction.
- **Smart Margin Management**: `MinMarginLevel` reduced from 200% to 150%. Below 150% only the worst-performing position is closed (gradual). Below 120% all positions are closed (true emergency).
- **SPM Log Spam Prevention**: 30-second cooldown added. Repeated SPM log messages now write at 30s intervals instead of every tick.

### New Features
- **News Banner Symbol Filter**: News now only appears on the chart of the affected symbol (e.g., GBP news won't show on XAG chart).
- **News Banner Colors**: Background colors made much brighter and more visible (CRITICAL=red, HIGH=orange, MEDIUM=yellow). Border width set to 2px.
- **Dynamic Min Lot**: Category-based minimum lot: Forex=0.06, BTC/XAG/XAU=0.01, Indices=0.03.
- **Symbol-Based Trade Blocking**: Only news affecting the current symbol will block trading.

### Changes
- `Config.mqh`: Added `minLotOverride` field to SymbolProfile, updated all 10 profiles
- `LotCalculator.mqh`: Added `profileMinLot` parameter to `Initialize()`
- `PositionManager.mqh`: Added `m_lastSPMLogTime` and `m_spmDirOverridden` fields
- `NewsManager.mqh`: Added `onlyRelevant` filter to `GetActiveNewsInfo/GetNextNewsInfo`
- `ChartDashboard.mqh`: Replaced Panel 5 with full-width top news banner (24px, dynamic width)

---

## [v2.2.0] - 2026-02-18

### New Features
- **Universal News Intelligence**: MQL5 CalendarValueHistory API integration for economic calendar
- **Dynamic Lot Calculation**: 8-factor lot engine (balance, volatility, risk, margin, DD, correlation, streak, time)
- **Emoji Notifications**: Automatic emoji and balance/equity info in Telegram + Discord messages
- **Dashboard News Panel**: Live news info on chart (impact colors, countdown timer)

### Changes
- Added `NewsManager.mqh`: News loader, currency detection, impact-based trade blocking
- `ChartDashboard.mqh`: 5-panel dashboard (news panel added)
- `TelegramMsg.mqh` / `DiscordMsg.mqh`: Emoji + balance/equity info

---

## [v2.1.0] - 2026-02-17

### New Features
- **Dynamic Profile System**: 10 instrument profiles (Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt, Indices, Energy, Metal, Default)
- **Pip-Based TP**: Separate TP1/TP2/TP3 pip distances per profile
- **3-Tier Symbol Matching**: Symbol-specific > JPY group > Category priority

### Changes
- `Config.mqh`: SymbolProfile struct + 10 profile methods + GetSymbolProfile()
- `PositionManager.mqh`: Profile-based SPM trigger, lot, cooldown parameters

---

## [v2.0.1] - 2026-02-17

### Fixes
- **Hedge Bug Fix**: Fixed hedge position being closed immediately after opening
- Hedge system now waits until next SPM check cycle after opening

---

## [v2.0.0] - 2026-02-17

### Major Release - WIN-WIN Hedge System
- **5+5 SPM Structure**: Max 5 BUY + 5 SELL separate layer limits
- **5-Vote System**: SPM direction via H1 Trend + Signal Score + M15 Candle + MACD Histogram + DI Crossover
- **FIFO Net Target**: closedProfit + openSPMProfit + openSPMLoss + mainP/L >= +$5 triggers full close
- **DCA Mechanism**: Dollar cost averaging for losing SPM positions (max 1 per position)
- **Emergency Hedge**: Auto-hedge when lot ratio > 2:1 and losing side is larger
- **Deadlock Detection**: 5min net change < $0.50 triggers full position closure
- **CheckSameDirectionBlock**: Never opens SPM in same direction as losing main position

### Removed
- Promotion (SPM->MAIN) system removed (was creating black hole effect)
- DD-based equity protection removed (per user request)

---

## [v1.3.0] - 2026-02-17

### New Features
- **SmartSPM**: Intelligent SPM direction determination
- **Strong Hedge**: One-sided risk detection + automatic hedge

---

## [v1.2.0] - 2026-02-17

### New Features
- **SPM-FIFO Profit-Focused System**: Small profit accumulation strategy
- PeakDrop now applies only to SPM positions (not to main)

---

## [v1.1.0] - 2026-02-17

### New Features
- **ByTamer Hybrid Signal System**: 7-layer advanced signal engine
- MACD + RSI divergence engine (regular + hidden)
- Market structure analysis (HH/HL/LH/LL)
- Bollinger squeeze detection
- Candlestick pattern scoring
- Multi-timeframe confirmation (H1 + H4)
- ATR percentile ranking

### Fixes
- Discord embed description JSON escape fix
- Telegram SendMessage public access fix

---

## [v1.0.0] - 2026-02-17

### Initial Release
- 7-layer base signal engine (EMA+MACD+ADX+RSI+BB+Stoch+ATR)
- SPM+FIFO position management system
- Escalating protection system
- 4-panel chart dashboard
- Telegram + Discord notification system
- Account security verification
- Dynamic lot calculation
