# BytamerFX - Expert Advisor for MetaTrader 5

**BytamerFX v3.3.0** - Professional automated trading system with Bi-Directional Trend-Grid technology.

> **Smart Grid** | **FIFO Settlement** | **Multi-Instrument** | **License Protected**

---

## Overview

BytamerFX is a professional-grade Expert Advisor for MetaTrader 5 that combines trend-following signals with an intelligent grid management system. The EA uses a hybrid approach of signal scoring, ATR-based grid spacing, and automated position management to generate consistent returns.

## Key Features

### Bi-Directional Trend-Grid System
- H1 timeframe trend following with ATR-based dynamic grid spacing
- Smart Position Management (SPM) for automated loss recovery
- Progressive grid spacing (+10% per layer to prevent clustering)
- Balance-based grid limits and lot sizing

### FIFO Settlement Engine
- Net profit target system with time-based dynamic targets
- KASA (Treasury) tracking of accumulated closed profits
- Automatic position settlement when targets are reached

### Multi-Indicator Signal Engine
- 12 indicator handles across M15, H1, H4 timeframes
- 7-layer scoring system with configurable minimum threshold
- RSI, MACD, EMA, Bollinger, Stochastic, ADX integration

### Risk Management
- Role-based profit protection (MAIN/SPM/DCA differentiated)
- Smart grid cooldown system
- Spread filtering for entry quality
- No Stop Loss strategy with FIFO-based exits

### 10 Instrument Profiles
- Forex, ForexJPY, Silver, Gold, Crypto, CryptoAlt
- Indices, Energy, Metal, Default
- Each with optimized parameters

### Notifications
- Telegram integration
- Discord webhook support
- MT5 push notifications

---

## Supported Instruments

| Category | Examples |
|----------|----------|
| Forex | EURUSD, GBPUSD, AUDUSD, EURGBP |
| Forex JPY | USDJPY, EURJPY, GBPJPY |
| Metals | XAUUSD (Gold), XAGUSD (Silver) |
| Crypto | BTCUSD, ETHUSD, LTCUSD |
| Indices | US30, NAS100, SPX500 |
| Energy | USOIL, UKOIL |

---

## Installation

1. Download `BytamerFX.ex5` from [Releases](releases/)
2. Copy to your MT5 Experts folder
3. In MT5: **Tools > Options > Expert Advisors** > Allow WebRequest for `https://bytamer.com`
4. Drag EA onto chart and enter your license key

See [Installation Guide](docs/installation.md) for detailed instructions.

---

## License

This is commercial software. A valid license key is required.

Purchase: [bytamer.com](https://bytamer.com)

See [LICENSE](LICENSE) for terms.

---

## Support

- **Email**: info@bytamer.com
- **Telegram**: @ByTamerAI_Support
- **Website**: [bytamer.com](https://bytamer.com)

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| v3.3.0 | 2026-02-20 | Hybrid profitability + Security hardening |
| v3.2.0 | 2026-02-20 | License system + Balance-based trading |
| v3.1.0 | 2026-02-19 | Bi-Directional Trend-Grid system |
| v2.2.5 | 2026-02-18 | SPM lot optimization |
| v2.0.0 | 2026-02-17 | WIN-WIN Hedge System |
| v1.0.0 | 2026-02-17 | Initial release |

---

## Disclaimer

> **This software is not investment advice.** Forex and CFD trading involves high risk. Past performance does not guarantee future results. Make investment decisions based on your own research.

---

**Copyright 2026, By T@MER** | [bytamer.com](https://bytamer.com)
