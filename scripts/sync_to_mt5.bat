@echo off
REM ============================================================
REM  sync_to_mt5.bat - Pobierz najnowsza wersje z GitHub,
REM  skopiuj EA i presety do katalogu MT5, skompiluj.
REM ============================================================
REM
REM  KONFIGURACJA - tutaj wpisz swoje sciezki (3 miejsca):
REM  ============================================================

REM [1] Sciezka do katalogu MQL5 w katalogu danych MT5
REM     (Ctrl+Shift+D w MT5 -> kopiujesz adres MQL5 z paska)
set "MT5_MQL5=C:\Users\TwojaNazwa\AppData\Roaming\MetaQuotes\Terminal\HASH_Z_MT5\MQL5"

REM [2] Sciezka do metaeditor64.exe (instalka BossaFX MT5)
set "METAEDITOR=C:\Program Files\BossaFX MT5\metaeditor64.exe"

REM [3] (opcjonalnie) jezeli nie chcesz auto-pull - ustaw =0
set "DO_PULL=1"

REM ============================================================
REM  Ponizej juz nic nie zmieniasz
REM ============================================================

set "REPO_ROOT=%~dp0..\"
set "REPO_EA=%REPO_ROOT%MQL5\Experts\Ichimoku_US30_H4_BossaFX.mq5"
set "REPO_PRESETS=%REPO_ROOT%MQL5\Presets"
set "TARGET_EA=%MT5_MQL5%\Experts\Ichimoku_US30_H4_BossaFX.mq5"
set "TARGET_PRESETS=%MT5_MQL5%\Presets"

if "%DO_PULL%"=="1" (
    echo === [1/4] Pull z GitHub ===
    git -C "%REPO_ROOT%" pull --ff-only
    if errorlevel 1 (
        echo Blad git pull. Przerwano.
        pause
        exit /b 1
    )
)

echo.
echo === [2/4] Kopiowanie EA ===
copy /Y "%REPO_EA%" "%TARGET_EA%"
if errorlevel 1 (
    echo Blad kopiowania EA. Czy MT5_MQL5 jest poprawne i EA nie jest zaladowany?
    pause
    exit /b 1
)

echo.
echo === [3/4] Kopiowanie presetow ===
if not exist "%TARGET_PRESETS%" mkdir "%TARGET_PRESETS%"
copy /Y "%REPO_PRESETS%\*.set" "%TARGET_PRESETS%\"

echo.
echo === [4/4] Kompilacja MetaEditor ===
"%METAEDITOR%" /compile:"%TARGET_EA%" /include:"%MT5_MQL5%" /log
echo.
echo Sprawdz log obok pliku .mq5 (Ichimoku_US30_H4_BossaFX.log).
echo Jezeli OK - MT5 sam podniesie nowy .ex5 (mozesz uruchomic Tester).
echo.
pause
