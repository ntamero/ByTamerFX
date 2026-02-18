$logFile = "D:\CLAUDE\FX BOT\BytamerFX2\compile.log"
if(Test-Path $logFile) { Remove-Item $logFile -Force }

$metaEditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$srcFile = "D:\CLAUDE\FX BOT\BytamerFX2\BytamerFX.mq5"
$incPath = "C:\Users\TAMER\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5"

# Use single string argument with proper quoting
$argStr = "/compile:`"$srcFile`" /log:`"$logFile`" /inc:`"$incPath`""
Write-Host "Running: $metaEditor $argStr"

$proc = Start-Process -FilePath $metaEditor -ArgumentList $argStr -PassThru -Wait
Write-Host "MetaEditor exit code: $($proc.ExitCode)"

Start-Sleep -Seconds 3

if(Test-Path $logFile) {
    Write-Host "=== COMPILE LOG ==="
    Get-Content $logFile -Encoding Unicode -Tail 30
} else {
    Write-Host "Log file not found at: $logFile"
    # Try to find any .log files created recently
    Get-ChildItem "D:\CLAUDE\FX BOT\BytamerFX2\" -Filter "*.log" -ErrorAction SilentlyContinue
    Get-ChildItem "D:\CLAUDE\FX BOT\BytamerFX2\" -Filter "*.ex5" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
}
