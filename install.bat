@echo off
rem Builds Overlo4d and installs it on the connected iPhone through xtool in WSL.
rem Before running: plug in the iPhone, unlock it, and open the Apple Devices app.
rem The full build output is saved to install.log next to this file.
setlocal EnableExtensions
cd /d "%~dp0"

set "DISTRO=Ubuntu-24.04"
set "PORT=27015"
set "LOG=install.log"

rem 1. WSL and xtool are there.
wsl -d %DISTRO% -- true >nul 2>&1
if errorlevel 1 (
    echo WSL distro %DISTRO% isn't installed or won't start.
    goto :fail
)
wsl -d %DISTRO% -- bash -lc "command -v xtool" >nul 2>&1
if errorlevel 1 (
    echo xtool isn't installed in %DISTRO%.
    goto :fail
)

rem 2. Get the latest code. Uses Windows Git, because Git in WSL waits for a login.
where git >nul 2>&1
if not errorlevel 1 (
    echo Getting the latest code...
    git pull --ff-only
    if errorlevel 1 (
        echo.
        echo Couldn't update the code. Building the copy that's here instead.
        echo.
    )
)

rem 3. Clear out folders left from the old Tally name. They only hold old build output.
if exist "Packages\TallyCore\.build" if not exist "Packages\TallyCore\Package.swift" rmdir /s /q "Packages\TallyCore"
if exist "xtool\Tally.app" rmdir /s /q "xtool\Tally.app"

rem 4. Find Windows as WSL sees it. The address changes when Windows restarts.
rem wsl.exe hands the command to a shell first, so it avoids $ (it would be expanded there).
set "HOST="
for /f "usebackq delims=" %%i in (`wsl -d %DISTRO% -- sh -c "ip route show default | head -n 1 | cut -d ' ' -f 3"`) do set "HOST=%%i"
if not defined HOST (
    echo Couldn't find the Windows address from WSL.
    goto :fail
)

echo Checking the connection from WSL to the iPhone at %HOST%:%PORT%...
call :probe
if errorlevel 1 (
    echo.
    echo WSL can't reach the iPhone relay at %HOST%:%PORT%.
    echo This usually happens after Windows restarts. Make sure Apple Devices is open.
    echo Overlo4d can point the relay at the new address and restart the IP Helper service.
    echo Windows will ask for admin permission.
    echo.
    choice /m "Fix the relay now"
    if errorlevel 2 goto :fail
    powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command','netsh interface portproxy add v4tov4 listenaddress=%HOST% listenport=%PORT% connectaddress=127.0.0.1 connectport=%PORT%; Restart-Service iphlpsvc'"
    call :probe
    if errorlevel 1 (
        echo Still can't reach the iPhone. Check that it's plugged in, unlocked and trusted,
        echo and that Apple Devices is open.
        goto :fail
    )
)

rem 5. Build and install. pipefail makes a failed build fail the script, not just tee.
echo Building and installing. The first build takes a few minutes...
wsl -d %DISTRO% --cd "%~dp0." -- bash -lc "set -o pipefail; export USBMUXD_SOCKET_ADDRESS=%HOST%:%PORT%; xtool dev 2>&1 | tee %LOG%"
if errorlevel 1 goto :builderrors

echo.
echo Installed. Open Overlo4d on the iPhone.
pause
exit /b 0

:probe
wsl -d %DISTRO% -- bash -c "timeout 5 bash -c 'echo > /dev/tcp/%HOST%/%PORT%'" >nul 2>&1
exit /b %errorlevel%

:builderrors
echo.
echo ---- Errors from the build ----
findstr /c:"error:" "%LOG%"
echo -------------------------------
echo The whole output is in %~dp0%LOG%.
goto :fail

:fail
echo.
echo Install didn't finish.
pause
exit /b 1
