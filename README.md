# ByTamerFX - Expert Advisor for MetaTrader 5

**BytamerFX v2.2.2** - Professional automated forex trading system with hybrid signal engine.

> **NO SL** | **Never close at a loss** | **SPM+FIFO Strategy** | **Smart Hedge**

---

## Features

### Signal Engine - ByTamer Hybrid Signal System (BHSS)
- **12 indicator handles** (M15 + H1 + H4 multi-timeframe)
- **7-layer scoring system** (0-100 points, min 35 entry threshold)
- EMA Ribbon (8/21/50) + crossover detection
- MACD Momentum + Divergence engine (regular + hidden)
- ADX Trend Strength + DI gap analysis + slope detection
- RSI Level + Multi-TF RSI + Divergence
- Bollinger Bands + Squeeze detection + %B calculation
- Stochastic K/D + Overbought/Oversold zones
- ATR Volatility + Percentile ranking
- Market Structure analysis (HH/HL/LH/LL)
- Candlestick pattern detection (Pin Bar, Engulfing, Doji)
- Momentum shift detection
- H1 + H4 trend filter (multi-timeframe confirmation)

### Position Management - WIN-WIN Hedge System (v2.0+)
- **SPM** (Sub Position Management): 5+5 structure (max 5 BUY + 5 SELL layers)
- **5-Vote System**: SPM direction via H1 Trend + Signal Score + M15 Candle + MACD + DI
- **FIFO** (First In First Out): SPM profits accumulate to offset main loss (net >= +$5)
- **CheckSameDirectionBlock**: Never opens SPM in same direction as losing main, forces opposite
- **DCA**: Dollar cost averaging for losing SPM positions
- **Emergency Hedge**: Auto-hedge when lot ratio exceeds 2:1 imbalance
- **Deadlock Detection**: 5min net change < $0.50 triggers position closure

### Dynamic Profile System (v2.1+)
- **10 instrument profiles**: Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt, Indices, Energy, Metal, Default
- **Pip-Based TP**: Separate TP1/TP2/TP3 pip distances per profile
- **Dynamic Min Lot**: Forex=0.06, BTC/XAG/XAU=0.01, Indices=0.03
- **Profile-Based SPM**: Separate trigger, lot, cooldown parameters per instrument
- **3-Tier Matching**: Symbol-specific > JPY group > Category priority

### Universal News Intelligence (v2.2+)
- **MQL5 Calendar API**: Economic calendar integration (CalendarValueHistory)
- **Impact-Based Blocking**: Trade blocking during CRITICAL/HIGH impact news
- **Currency Detection**: Automatic symbol-to-currency mapping
- **Symbol Filter**: News only displayed on affected symbol charts
- **Full-Width Banner**: Live news info on chart (impact colors, countdown timer)

### Smart Margin Management (v2.2.1)
- **Gradual Closure**: Below 150% only the worst-performing position is closed
- **Critical Emergency**: Below 120% all positions are closed
- **Per-instrument** smart management, not account-wide liquidation

### Minimum Profit Protection (v2.2.2)
- **minCloseProfit**: No SPM/DCA/HEDGE closes below threshold (Forex=$1.0, BTC=$1.5)
- **Emergency SPM**: When SPM loss exceeds 2x trigger, cooldown is skipped entirely
- **No Broker TP on ANA**: Main position only closes via FIFO (net >= +$5), not broker TP
- **ANA Ticket Detection**: Auto-detects when broker closes ANA, properly resets state

### Lot Calculation - 8-Factor Dynamic Engine
- Balance-based base lot
- ATR volatility factor
- Risk factor (0.5-1.5x)
- Margin usage limit
- Drawdown reduction
- Correlation risk
- Streak factor (consecutive win/loss)
- Time factor (low volatility hours)

### Dashboard
- Full-width news banner (impact-colored background + border)
- 4-panel real-time chart dashboard (dark theme)
- Panel 1: Account info, indicator values, status
- Panel 2: 7-layer signal score breakdown + progress bar
- Panel 3: TP1/TP2/TP3 targets + trend strength + indicators
- Panel 4: SPM+FIFO status + net progress

### Notifications
- Telegram (HTML format + emoji + balance/equity info)
- Discord (Embed format + color-coded + balance/equity info)
- MT5 Push Notification

### Security
- Account number verification (262230423)
- SL=0 absolute rule (never set stop loss)
- Account re-verification every 5 minutes

---

## Technical Specifications

| Property | Value |
|----------|-------|
| Platform | MetaTrader 5 (Build 5200+) |
| Language | MQL5 |
| Timeframe | M15 (entry) + H1/H4 (filter) |
| Min Balance | $10 |
| Min Signal Score | 35/100 |
| SPM Max Layers | 5 BUY + 5 SELL |
| FIFO Net Target | $5 |
| Margin Warning | <150% (gradual closure) |
| Margin Critical | <120% (full closure) |
| SPM Trigger | Forex: -$3, BTC/XAG/XAU: -$5 |
| Min Lot | Forex: 0.06, Metal/Crypto: 0.01, Indices: 0.03 |
| Profile Count | 10 instrument profiles |

---

## File Structure

```
BytamerFX/
├── BytamerFX.mq5          # Main EA file (v2.2.2)
├── Config.mqh             # Central configuration + 10 SymbolProfiles
├── AccountSecurity.mqh    # Account verification
├── SymbolManager.mqh      # Symbol categorization
├── SpreadFilter.mqh       # Spread control
├── CandleAnalyzer.mqh     # Candle analysis + pattern detection
├── LotCalculator.mqh      # 8-factor dynamic lot calculator
├── SignalEngine.mqh       # ByTamer Hybrid Signal System (BHSS)
├── TradeExecutor.mqh      # Trade execution (SL=0 absolute)
├── PositionManager.mqh    # WIN-WIN Hedge + SPM+FIFO engine
├── NewsManager.mqh        # Universal News Intelligence
├── TelegramMsg.mqh        # Telegram notifications (emoji + balance)
├── DiscordMsg.mqh         # Discord notifications (embed + balance)
├── ChartDashboard.mqh     # News banner + 4-panel dashboard
├── CHANGELOG.md           # Detailed version history
├── compile.ps1            # PowerShell compile script
└── .gitignore
```

---

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed changes.

| Version | Date | Description |
|---------|------|-------------|
| v2.2.2 | 2026-02-18 | Min Profit Threshold, Emergency SPM, No Broker TP on ANA |
| v2.2.1 | 2026-02-18 | SPM SAME-DIR BLOCK fix, Smart Margin, News Filter |
| v2.2.0 | 2026-02-18 | Universal News Intelligence, Dynamic Lot, Emoji |
| v2.1.0 | 2026-02-17 | Dynamic Profile System, Pip-Based TP |
| v2.0.1 | 2026-02-17 | Hedge bug fix |
| v2.0.0 | 2026-02-17 | WIN-WIN Hedge System, 5+5 SPM, FIFO |
| v1.3.0 | 2026-02-17 | SmartSPM, Strong Hedge |
| v1.2.0 | 2026-02-17 | SPM-FIFO Profit-Focused System |
| v1.1.0 | 2026-02-17 | ByTamer Hybrid Signal System |
| v1.0.0 | 2026-02-17 | Initial release |

---

## Installation

1. Copy all files to `MQL5/Experts/BytamerFX/` directory
2. Compile `BytamerFX.mq5` with MetaEditor
3. Drag onto chart in MT5 (M15 timeframe)
4. **Settings** > Tools > Options > Expert Advisors:
   - Check "Allow DLL imports"
   - Enable "Allow WebRequest"
   - Add to URL list:
     - `https://api.telegram.org`
     - `https://discordapp.com`
5. Enter Telegram/Discord credentials in EA settings

---

## Disclaimer

> **This software is not investment advice.** Forex and CFD trading involves high risk. Past performance does not guarantee future results. Make investment decisions based on your own research.

---

**Copyright 2026, By T@MER** | [www.bytamer.com](https://www.bytamer.com)
