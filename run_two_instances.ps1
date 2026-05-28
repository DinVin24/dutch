param(
  [string]$Instance1Name = "Host",
  [string]$Instance2Name = "Client"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Start-Process powershell -ArgumentList @(
  "-NoExit",
  "-ExecutionPolicy", "Bypass",
  "-Command", "cd `"$repoRoot`"; `$Host.UI.RawUI.WindowTitle = `"$Instance1Name`"; .\\run_godot.ps1"
)

Start-Process powershell -ArgumentList @(
  "-NoExit",
  "-ExecutionPolicy", "Bypass",
  "-Command", "cd `"$repoRoot`"; `$Host.UI.RawUI.WindowTitle = `"$Instance2Name`"; .\\run_godot.ps1"
)

