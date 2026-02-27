# ByTamerFX - Expert Advisor for MetaTrader 5

**BytamerFX v4.4.0** - Professional automated forex trading system with hybrid signal engine.

> **NO SL** | **Never close at a loss** | **Net-Exposure SPM** | **FIFO Strategy** | **Grid Reset Safety**

---

## Core Philosophy

- **SL = YOK (MUTLAK)** — No Stop Loss on any position, ever
- **Zararina Satis YOK** — Normal operation never closes positions at a loss
- **SPM/FIFO Zarar Yonetimi** — Losses managed through SPM accumulation + FIFO offset
- **Net-Exposure Dengeleme** — BUY/SELL balance prevents one-sided accumulation disaster
- **Grid Reset & EQUITY_ACIL** — Extreme safety nets only (last resort, not normal operation)

---

## Features

### Signal Engine - ByTamer Hybrid Signal System (BHSS)
- **12 indicator handles** (M15 + H1 + H4 multi-timeframe)
- **BytamerFX combo scoring** (0-100 points, min 40 entry threshold)
- EMA Ribbon (8/21/50) + MACD + RSI + ADX + Bollinger + Stochastic + ATR
- SuperTrend + Ichimoku + Keltner Channel + MFI + Parabolic SAR
- Candlestick pattern detection (Pin Bar, Engulfing, Doji, Inside Bar)
- Market Structure analysis (HH/HL/LH/LL)
- MACD + RSI divergence engine (regular + hidden)

### Position Management - KazanKazan-Pro (v4.2.0)
- **Net-Exposure SPM**: BUY/SELL count balanced — 3+ same direction IMPOSSIBLE
- **SPM Max 3 Layers**: Deeper recovery with controlled risk
- **FIFO**: SPM profits accumulate to offset main loss (net >= +$5 closes MAIN)
- **Grid Reset**: Total floating loss exceeds threshold → orderly close all
- **EQUITY_ACIL Recovery**: Emergency close triggers recovery mode (24h or 50% balance recovery)
- **SPM Fast Kasa**: 50% lower min close threshold for faster profit accumulation
- **Candle Reversal**: Profitable positions close immediately on candle reversal
- **SPM Terfi**: After FIFO closes MAIN, oldest SPM promotes to new MAIN

### Dynamic Profile System (10 Profiles)
- Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt, Indices, Energy, Metal, Default
- Profile-based: SPM trigger, lot, cooldown, grid reset thresholds
- 3-Tier Matching: Symbol-specific > JPY group > Category priority

### Safety Systems
- **3-Level Margin Protection**: %300 warning → %150 emergency → %30 equity critical
- **Grid Reset**: `-max($30, equity * 25%)` floating loss → orderly grid reset
- **Recovery Mode**: After emergency, no new trades for 24h or until 50% balance recovery
- **News Filter**: Trade blocking during CRITICAL/HIGH impact economic events
- **Spread Control**: ATR-normalized spread × MaxSpreadMultiplier (1.15)

### Notifications
- Telegram (HTML format + emoji + balance/equity info, rate limited)
- Discord (Embed format + color-coded + balance/equity info)
- MT5 Push Notification

### Dashboard
- Full-width news banner (impact-colored)
- 4-panel real-time chart dashboard (dark theme)
- Account info, signal scores, SPM+FIFO status, TP targets

---

## Technical Specifications

| Property | Value |
|----------|-------|
| Platform | MetaTrader 5 (Build 5200+) |
| Language | MQL5 |
| Timeframe | M15 (entry) + H1/H4 (filter) |
| Min Balance | $10 |
| Min Signal Score | 40/100 |
| SPM Max Layers | 3 (per profile, configurable) |
| FIFO Net Target | $5 (adaptive by balance) |
| Grid Reset Threshold | -max($30, 25% equity) |
| Margin Warning | <300% (block new positions) |
| Margin Emergency | <150% (close all) |
| Equity Emergency | <30% (close all + recovery mode) |
| SPM Trigger | Forex: -$4, BTC/Metal: -$7 |
| Min Lot | Forex: 0.03, Metal/Crypto: 0.01 |
| Profile Count | 10 instrument profiles |
| Indicators | 12 (BHSS combo scoring) |

---

## File Structure

```
BytamerFX/
├── BytamerFX.mq5          # Main EA file (v4.2.0)
├── Config.mqh             # Central configuration + 10 SymbolProfiles
├── AccountSecurity.mqh    # Account verification
├── SymbolManager.mqh      # Symbol categorization (6 categories)
├── SpreadFilter.mqh       # ATR-normalized spread control
├── CandleAnalyzer.mqh     # Candle patterns + new bar detection
├── LotCalculator.mqh      # 8-factor dynamic lot calculator
├── SignalEngine.mqh       # 12-indicator hybrid signal system
├── TradeExecutor.mqh      # Trade execution (SL=0 absolute)
├── PositionManager.mqh    # Net-Exposure SPM + FIFO + Grid Reset engine
├── NewsManager.mqh        # Universal News Intelligence
├── TelegramMsg.mqh        # Telegram notifications (rate limited)
├── DiscordMsg.mqh         # Discord webhook notifications
├── ChartDashboard.mqh     # News banner + 4-panel dashboard
├── LicenseManager.mqh     # BTAI license system
├── CHANGELOG.md           # Detailed version history
└── .gitignore
```

---

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed changes.

| Version | Date | Description |
|---------|------|-------------|
| **v4.3.2** | **2026-02-26** | **FIFO Kasa Fix + BE Lock Fix + Min Profit + New Telegram Bot** |
| v4.3.1 | 2026-02-26 | BE Lock Fix + Min $0.80 Profit Threshold + Dashboard MIA v5.1 |
| v4.3.0 | 2026-02-26 | Telegram Rich Messages + Daily Report + Token Validation |
| v4.2.0 | 2026-02-26 | Net-Exposure SPM + Grid Reset + EQUITY_ACIL Fix |
| v4.1.0 | 2026-02-24 | BiDir Fix + Forex 0.03 + FIFO Fix |
| v4.0.0 | 2026-02-23 | KazanKazan-Pro: 12 indicator + Kademeli Kurtarma |
| v3.5.0 | 2026-02-21 | Net Settlement + Zigzag Grid Engine |
| v3.3.0 | 2026-02-21 | Grid Performance (cooldown, lot, thresholds) |
| v3.2.0 | 2026-02-20 | License System Improvements |
| v3.0.0 | 2026-02-20 | Trend-Grid System |
| v2.3.0 | 2026-02-19 | Smart Recovery + FIFO Redesign |
| v2.2.x | 2026-02-18 | Multiple critical fixes |
| v2.0.0 | 2026-02-17 | WIN-WIN Hedge System |
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
