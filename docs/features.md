# BytamerFX - Features

## Trading System
- **Bi-Directional Trend-Grid**: H1 timeframe trend following with ATR-based grid spacing
- **Smart Position Management (SPM)**: Automated hedge positions for loss recovery
- **FIFO Settlement**: Net profit target system with time-based dynamic targets
- **DCA Integration**: Dollar-cost averaging for extended drawdowns

## Risk Management
- **Balance-Based Limits**: Grid count and lot sizing based on account balance
- **Progressive Grid Spacing**: Each grid level widens by 10% to prevent clustering
- **Role-Based Profit Protection**: Different PeakDrop thresholds for MAIN/SPM/DCA positions
- **KASA (Treasury)**: Accumulated closed SPM profits tracked for FIFO calculations

## Signal Engine
- **Multi-Indicator Scoring**: RSI, MACD, Moving Averages, Bollinger Bands, Stochastic
- **Minimum Score Filter**: Configurable signal quality threshold
- **Spread Filter**: Prevents entries during high-spread periods

## Security
- **License Verification**: Online license validation with encrypted API
- **Offline Mode**: 4-hour offline cache for connectivity issues
- **Anti-Tampering**: File integrity verification
- **Encrypted Strings**: XOR-encrypted sensitive data in binary

## Supported Instruments
- Forex (EURUSD, GBPUSD, etc.)
- Metals (XAUUSD, XAGUSD)
- Crypto (BTCUSD, ETHUSD, etc.)
- Indices (US30, NAS100, etc.)
- Energy (USOIL, UKOIL)

## Notifications
- Telegram integration
- Discord webhook support
- MT5 push notifications
