@echo off
title MIA - BytamerFX Agent

cd /d "%~dp0"

echo.
echo  ==========================================
echo   MIA - Market Intelligence Agent
echo   BytamerFX v3.8  -  By TaMER
echo   Klasor: %~dp0
echo  ==========================================
echo.

:: Onceki MIA instance varsa kapat
echo Onceki MIA instance kontrol ediliyor...
tasklist /fi "windowtitle eq MIA - BytamerFX Agent" 2>nul | find /i "cmd.exe" > nul
if %errorlevel% == 0 (
    echo [UYARI] Baska bir MIA penceresi acik!
    echo         Lutfen once onu kapatip bu pencerede bir tusa basin.
    pause > nul
)

:: Eski python MIA process varsa oldur
tasklist 2>nul | find /i "python" > nul
if %errorlevel% == 0 (
    echo [INFO] Eski Python process temizleniyor...
    wmic process where "name='python.exe' and commandline like '%%main.py%%'" delete 2>nul
    timeout /t 2 /nobreak > nul
)

:: Python bul
where python > nul 2>&1
if %errorlevel% neq 0 (
    where python3 > nul 2>&1
    if %errorlevel% neq 0 (
        echo [HATA] Python bulunamadi!
        echo        https://python.org adresinden yukleyin
        echo        Kurulumda "Add Python to PATH" secin!
        pause
        exit /b 1
    )
    set PYTHON=python3
) else (
    set PYTHON=python
)

echo Python: & %PYTHON% --version
echo.

echo [1/3] Kutuphaneler kontrol ediliyor...
%PYTHON% -m pip install MetaTrader5 anthropic pandas numpy requests python-telegram-bot --quiet --upgrade
if %errorlevel% neq 0 (
    echo [HATA] Kutuphaneler yuklenemedi!
    pause
    exit /b 1
)
echo       Tamam

echo [2/3] Yapilandirma kontrol ediliyor...
%PYTHON% -c "import config; assert config.ANTHROPIC_API_KEY != 'YOUR_API_KEY_HERE', 'API KEY eksik'; assert config.MT5_PASSWORD != '', 'MT5 sifre eksik'; print('       Tamam')"
if %errorlevel% neq 0 (
    echo.
    echo  config.py dosyasini acin ve doldurun:
    echo    ANTHROPIC_API_KEY = "sk-ant-..."
    echo    MT5_PASSWORD      = "sifreniz"
    echo    MT5_SERVER        = "Exness-MT5Trial16"
    echo.
    notepad config.py
    pause
    exit /b 1
)

echo [3/3] Dashboard: http://localhost:8765
echo.
echo  Telegram: /ac BTC XAG  -- islem baslat
echo            /kapat GBP   -- pozisyon kapat
echo            /durum       -- hesap durumu
echo  Durdurmak icin: Ctrl+C
echo  ==========================================
echo.

tasklist /fi "imagename eq terminal64.exe" 2>nul | find /i "terminal64.exe" > nul
if %errorlevel% neq 0 (
    echo [UYARI] MetaTrader 5 acik degil!
    echo         MT5 acin, hesabiniza giris yapin, sonra bir tusa basin...
    pause > nul
)

%PYTHON% main.py

echo.
echo MIA durduruldu.
pause
