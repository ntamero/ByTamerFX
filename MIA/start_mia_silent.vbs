' ═══════════════════════════════════════════════════════
'  MIA — Sessiz Baslatma (arka plan)
'  Windows Baslangic'a bu dosyayi ekleyin.
'  Copyright 2026, By T@MER
' ═══════════════════════════════════════════════════════

Set WshShell = CreateObject("WScript.Shell")

' MT5 kontrol — calismiyorsa baslat
Set oExec = WshShell.Exec("tasklist /FI ""IMAGENAME eq terminal64.exe""")
sOutput = oExec.StdOut.ReadAll
If InStr(sOutput, "terminal64") = 0 Then
    WshShell.Run """C:\Program Files\MetaTrader 5\terminal64.exe""", 1, False
    WScript.Sleep 10000  ' 10sn bekle MT5 acilsin
End If

' MIA baslat (minimized pencerede)
WshShell.Run "cmd /c ""D:\CLAUDE\FXAGENT\start_mia.bat""", 7, False
' 7 = minimized pencere, False = bekleme
