# Automated MP vision test (Windows): host + client, split on screen 2, logs in background.
# Usage: powershell -ExecutionPolicy Bypass -File .debug/run_mp_vision_test.ps1

$ErrorActionPreference = "Stop"

$ROOT = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GODOT_DIR = "D:\Godot"
$GODOT_GAME = Join-Path $GODOT_DIR "Godot_v4.6.2-stable_win64.exe"
$GODOT_CONSOLE = Join-Path $GODOT_DIR "Godot_v4.6.2-stable_win64_console.exe"
if (-not (Test-Path $GODOT_GAME)) {
    $GODOT_GAME = $GODOT_CONSOLE
}
if (-not (Test-Path $GODOT_GAME)) {
    throw "Godot not found under $GODOT_DIR"
}

$RUN_ID = Get-Date -Format "yyyyMMddTHHmmss"
$MP_DIR = Join-Path $ROOT ".debug\mp"
$OUT_DIR = Join-Path $MP_DIR "runs\$RUN_ID"
$ROOM_FILE = Join-Path $MP_DIR "room_code.txt"
$LIVE_HOST = Join-Path $MP_DIR "live_server.log"
$LIVE_CLIENT = Join-Path $MP_DIR "live_client.log"
$HOST_LOG = Join-Path $OUT_DIR "host.log"
$HOST_ERR = Join-Path $OUT_DIR "host.err.log"
$CLIENT_LOG = Join-Path $OUT_DIR "client.log"
$CLIENT_ERR = Join-Path $OUT_DIR "client.err.log"
$ORCH_LOG = Join-Path $OUT_DIR "orchestrator.log"

New-Item -ItemType Directory -Force -Path $OUT_DIR | Out-Null

function Log([string]$Msg) {
    $line = "[vision] $Msg"
    Write-Host $line
    Add-Content -Path $ORCH_LOG -Value $line
}

function Stop-DutchGodot {
    Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cmd -and $cmd -like "*$ROOT*") {
                Log "Stopping PID $($_.Id)"
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Get-Process -Name "powershell" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cmd -and $cmd -like "*Dutch_MP_Log_*") {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Start-Sleep -Milliseconds 500
}

function Test-LogPattern {
    param(
        [string[]]$Paths,
        [string]$Pattern
    )
    foreach ($p in $Paths) {
        if ((Test-Path $p) -and (Select-String -Path $p -Pattern $Pattern -Quiet -ErrorAction SilentlyContinue)) {
            return $true
        }
    }
    return $false
}

function Wait-LogPattern {
    param(
        [string[]]$Paths,
        [string]$Pattern,
        [int]$TimeoutSec = 120
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        foreach ($p in $Paths) {
            if ((Test-Path $p) -and (Select-String -Path $p -Pattern $Pattern -Quiet -ErrorAction SilentlyContinue)) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Start-BackgroundLogConsole {
    param(
        [string]$Title,
        [string]$WatchPath,
        [int]$Left = 0,
        [int]$Top = 40
    )
    $escaped = $WatchPath.Replace("'", "''")
    $script = "`$Host.UI.RawUI.WindowTitle = '$Title'; while (-not (Test-Path '$escaped')) { Start-Sleep -Milliseconds 200 }; Get-Content -Path '$escaped' -Wait -Tail 40"
    try {
        return Start-Process powershell -PassThru -WindowStyle Minimized -ArgumentList @(
            "-NoProfile", "-NoExit", "-Command", $script
        )
    } catch {
        Log "WARN: could not start background log console: $_"
        return $null
    }
}

function Start-GodotGame {
    param(
        [string[]]$ArgumentList,
        [string]$StdoutPath,
        [string]$StderrPath
    )
    return Start-Process -FilePath $GODOT_GAME -ArgumentList $ArgumentList `
        -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath `
        -PassThru -WindowStyle Normal
}

function Write-Report {
    $report = Join-Path $OUT_DIR "report.md"
    $hostHits = @()
    $clientHits = @()
    $hostPaths = @($HOST_LOG, $HOST_ERR, $LIVE_HOST) | Where-Object { Test-Path $_ }
    $clientPaths = @($CLIENT_LOG, $CLIENT_ERR, $LIVE_CLIENT) | Where-Object { Test-Path $_ }
    if ($hostPaths.Count -gt 0) {
        $hostHits = Select-String -Path $hostPaths -Pattern "CHECKPOINT|VISION_RUN|AVATAR|GAME_OVER|ERROR|SCRIPT ERROR" -ErrorAction SilentlyContinue | ForEach-Object { $_.Line }
    }
    if ($clientPaths.Count -gt 0) {
        $clientHits = Select-String -Path $clientPaths -Pattern "CHECKPOINT|VISION_RUN|AVATAR|GAME_OVER|ERROR|SCRIPT ERROR" -ErrorAction SilentlyContinue | ForEach-Object { $_.Line }
    }
    $shots = Get-ChildItem -Path (Join-Path $ROOT "debug\test_runs") -Recurse -Filter "*.png" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 20

    @(
        "# MP Vision Run $RUN_ID (Windows)",
        "",
        "## Host log highlights",
        ($hostHits | Select-Object -First 50 | ForEach-Object { "- $_" }),
        "",
        "## Client log highlights",
        ($clientHits | Select-Object -First 50 | ForEach-Object { "- $_" }),
        "",
        "## Recent Godot screenshots",
        ($shots | ForEach-Object { "- $($_.FullName)" })
    ) | Set-Content -Path $report -Encoding UTF8
    Log "Report -> $report"
    Get-Content $report
}

Log "=== MP vision test $RUN_ID ==="
Log "Godot game: $GODOT_GAME"
Log "Project: $ROOT"

Stop-DutchGodot
if (Test-Path $ROOM_FILE) { Remove-Item $ROOM_FILE -Force }
Remove-Item $LIVE_HOST, $LIVE_CLIENT -ErrorAction SilentlyContinue

$null = Start-BackgroundLogConsole -Title "Dutch_MP_Log_Host" -WatchPath $LIVE_HOST -Left 0 -Top 40
$null = Start-BackgroundLogConsole -Title "Dutch_MP_Log_Client" -WatchPath $LIVE_CLIENT -Left 0 -Top 320

$hostArgs = @("--path", $ROOT, "--", "--host", "--vision-layout")
Log "Starting host (screen 2 left half)..."
$hostProc = Start-GodotGame -ArgumentList $hostArgs -StdoutPath $HOST_LOG -StderrPath $HOST_ERR
Log "Host PID=$($hostProc.Id)"

$code = ""
for ($i = 0; $i -lt 90; $i++) {
    if ((Test-Path $ROOM_FILE) -and (Get-Item $ROOM_FILE).Length -gt 0) {
        $code = (Get-Content $ROOM_FILE -Raw).Trim()
        if ($code.Length -ge 4) { break }
    }
    Start-Sleep -Milliseconds 500
}
if ([string]::IsNullOrWhiteSpace($code)) {
    Log "FAIL: no room code after 45s"
    if (Test-Path $HOST_LOG) { Get-Content $HOST_LOG -Tail 30 | ForEach-Object { Log $_ } }
    Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
Log "Room code: $code"

Start-Sleep -Seconds 2

$clientArgs = @("--path", $ROOT, "--", "--client", "--room-code", $code, "--vision-layout")
Log "Starting client (screen 2 right half)..."
$clientProc = Start-GodotGame -ArgumentList $clientArgs -StdoutPath $CLIENT_LOG -StderrPath $CLIENT_ERR
Log "Client PID=$($clientProc.Id)"

$deadline = (Get-Date).AddSeconds(600)
$hostDone = $false
$clientDone = $false
while ((Get-Date) -lt $deadline) {
    if (-not $hostDone) {
        $hostDone = Test-LogPattern -Paths @($LIVE_HOST) -Pattern "VISION_RUN_COMPLETE"
    }
    if (-not $clientDone) {
        $clientDone = Test-LogPattern -Paths @($LIVE_CLIENT) -Pattern "VISION_RUN_COMPLETE"
    }
    if ($hostDone -and $clientDone) { break }
    Start-Sleep -Milliseconds 500
}

if ($hostDone -and $clientDone) {
    Log "PASS: Both instances reported VISION_RUN_COMPLETE"
} else {
    Log "FAIL: host_done=$hostDone client_done=$clientDone"
}

Start-Sleep -Seconds 2
Stop-Process -Id $hostProc.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $clientProc.Id -Force -ErrorAction SilentlyContinue
Stop-DutchGodot

Write-Report
if (-not ($hostDone -and $clientDone)) { exit 1 }
