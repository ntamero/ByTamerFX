# BytamerFX - Installation Guide

## Requirements
- MetaTrader 5 (Build 3000+)
- Valid BytamerFX license key
- Active internet connection (for license verification)

## Installation Steps

### 1. Download
Download the latest `BytamerFX.ex5` from the [Releases](../releases/) folder.

### 2. Copy to MT5
Copy `BytamerFX.ex5` to your MT5 Experts folder:
```
C:\Users\[USERNAME]\AppData\Roaming\MetaQuotes\Terminal\[TERMINAL_ID]\MQL5\Experts\
```

Or use MT5: **File > Open Data Folder > MQL5 > Experts**

### 3. Allow WebRequest
In MT5: **Tools > Options > Expert Advisors**
- Check "Allow WebRequest for listed URL"
- Add: `https://bytamer.com`

### 4. Attach to Chart
- Drag BytamerFX from the Navigator panel to any chart
- Enter your **License Key** in the Inputs tab
- The EA will automatically detect your broker account number
- Click OK

### 5. Verify
- Check the Experts tab for "LISANS DOGRULANDI" message
- The chart dashboard should show green license status

## Updating License
Right-click on chart > **Expert Advisors** > **Properties** > **Inputs** > Update License Key

## Troubleshooting
- **License Error**: Verify your key format (BTAI-XXXXX-XXXXX-XXXXX-XXXXX)
- **Connection Error**: Check WebRequest URL permissions
- **Account Mismatch**: Contact support with your broker account number

## Support
- Email: info@bytamer.com
- Telegram: @ByTamerAI_Support
- Website: https://bytamer.com
