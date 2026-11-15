@echo off
rem Builds Overlo4d and installs it on the connected iPhone through xtool in WSL.
rem Before running: plug in the iPhone, unlock it, and open the Apple Devices app.
setlocal

set "DISTRO=Ubuntu-24.04"
set "RELAY=172.18.32.1:27015"

echo Checking the connection from WSL to the iPhone...
wsl -d %DISTRO% -- bash -c "timeout 5 bash -c 'echo > /dev/tcp/172.18.32.1/27015'" >nul 2>&1
if errorlevel 1 (
    echo.
    echo WSL can't reach the iPhone relay at %RELAY%.
    echo This usually happens after Windows restarts. Make sure Apple Devices is open,
    echo then restart the IP Helper service. Windows will ask for admin permission.
    echo.
    choice /m "Restart the IP Helper service now"
    if errorlevel 2 goto :fail
    powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command','Restart-Service iphlpsvc'"
    wsl -d %DISTRO% -- bash -c "timeout 5 bash -c 'echo > /dev/tcp/172.18.32.1/27015'" >nul 2>&1
    if errorlevel 1 (
        echo Still can't reach the iPhone. Check that it's plugged in, unlocked and trusted.
        goto :fail
    )
)

echo Building and installing. The first build takes a few minutes...
wsl -d %DISTRO% --cd "%~dp0." -- bash -lc "export USBMUXD_SOCKET_ADDRESS=%RELAY%; xtool dev"
if errorlevel 1 goto :fail

echo.
echo Installed. Open Overlo4d on the iPhone.
pause
exit /b 0

:fail
echo.
echo Install didn't finish.
pause
exit /b 1
