@echo off
REM ═══════════════════════════════════════════════════════
REM  MIA — BytamerFX Dashboard + Telegram Bot
REM  Kalici baslatma scripti: crash'te otomatik yeniden baslar
REM  Copyright 2026, By T@MER
REM ═══════════════════════════════════════════════════════

title MIA - BytamerFX Agent
cd /d D:\CLAUDE\FXAGENT

REM ── MT5 Terminal kontrolu ──
echo [MIA] MetaTrader 5 kontrol ediliyor...
tasklist /FI "IMAGENAME eq terminal64.exe" 2>NUL | find "terminal64" >NUL
if %ERRORLEVEL% NEQ 0 (
    echo [MIA] MT5 baslatiliyor...
    start "" "C:\Program Files\MetaTrader 5\terminal64.exe"
    timeout /t 10 /nobreak >NUL
    echo [MIA] MT5 baslatildi, 10sn beklendi.
) else (
    echo [MIA] MT5 zaten calisiyor.
)

REM ── Ana dongu: crash olursa yeniden basla ──
:restart
echo.
echo ═══════════════════════════════════════════════
echo [MIA] Baslatiliyor... %date% %time%
echo ═══════════════════════════════════════════════

python main.py

echo.
echo [MIA] !! PROCESS DURDU !! Kod: %ERRORLEVEL%
echo [MIA] 5 saniye sonra yeniden baslatilacak...
echo [MIA] Kapatmak icin bu pencereyi kapatin.
timeout /t 5 /nobreak >NUL
goto restart
