# Changelog - BytamerFX EA

All notable changes to this project are documented in this file.

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
