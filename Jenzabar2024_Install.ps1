& {
    "\\ucjenzabar\J1_Shared\J1_2024.3.0.147_AllFiles\J1_Desktop_2024.3.0.147_Setup.exe" /s /v"/qn SETUPFILE=\"\\ucjenzabar\J1_Shared\Script_Files\Parameters24.dat\""
@echo off
SETLOCAL

REM Path to the executable or program you want to create a shortcut for
set "PROGRAM_PATH=C:\Program Files (x86)\Jenzabar\J1 2024\Desktop\Programs\J12024.exe"
set "PROGRAM_NAME=Jenzabar One Desktop 2024"

REM Path to the public desktop (this will make the shortcut available to all users)
set "DESKTOP_PATH=%Public%\Desktop"
set "SHORTCUT_NAME=%PROGRAM_NAME%.lnk"

REM Create shortcut on the desktop for all users
echo Creating shortcut on the desktop for all users...
powershell -command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%DESKTOP_PATH%\%SHORTCUT_NAME%'); $s.TargetPath = '%PROGRAM_PATH%'; $s.Save()"

ENDLOCAL
exit /b
}
