@echo off
REM ─────────────────────────────────────────────────────────────────────
REM MiniCalc — Windows wrapper for run.sh
REM
REM Double-click              → verify against tests.txt
REM run.bat c                 → run C only
REM run.bat my.txt            → cross-check the 4 impls on my.txt
REM run.bat -e "echo 1 + 2"   → run a one-off expression
REM run.bat c -e "echo 1 + 2" → run a one-off expression, C only
REM Drag a .txt onto it       → same as `run.bat my.txt`
REM
REM Note: inside an expression, write % as %% (cmd.exe escape).
REM ─────────────────────────────────────────────────────────────────────
setlocal

REM Work from the folder this .bat lives in
cd /d "%~dp0"

REM ── 1. Is Docker installed? ──────────────────────────────────────────
where docker >nul 2>&1
if errorlevel 1 (
    echo [error] Docker is not installed or not on PATH.
    echo         Install Docker Desktop from https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

REM ── 2. Is the Docker daemon running? ─────────────────────────────────
docker info >nul 2>&1
if errorlevel 1 (
    echo [error] Docker Desktop is not running.
    echo         Start Docker Desktop, wait for the whale icon, then retry.
    pause
    exit /b 1
)

REM ── 3. Is the image built? ───────────────────────────────────────────
docker image inspect minicalc >nul 2>&1
if errorlevel 1 (
    echo [info] Building the minicalc image for the first time...
    docker build -t minicalc .
    if errorlevel 1 (
        echo [error] Build failed. See the output above.
        pause
        exit /b 1
    )
)

REM ── 4. Drag-and-drop: use the dropped file's name, copy it here if needed ─
set "ARGS=%*"
if not "%~1"=="" if exist "%~1" if not "%~x1"=="" (
    if not exist "%~nx1" copy "%~1" "%~nx1" >nul
    set "ARGS=%~nx1"
)

REM ── 5. Run inside the container ──────────────────────────────────────
docker run --rm -v "%CD%:/work" -w /work minicalc bash ./run.sh %ARGS%

REM ── 6. Keep the window open after double-click or drag-drop ──────────
if "%~1"=="" goto :pause
if "%~2"=="" if exist "%~1" if not "%~x1"=="" goto :pause
goto :end
:pause
pause
:end
