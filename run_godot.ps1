param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$GodotArgs = @()
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $repoRoot "project.godot"

if (-not (Test-Path $projectPath)) {
  throw "project.godot not found at: $projectPath"
}

$godotDir = "D:\Godot"
$candidates = @(
  (Join-Path $godotDir "Godot_v4.6.2-stable_win64.exe"),
  (Join-Path $godotDir "Godot_v4.6.2-stable_win64_console.exe")
)

$godotExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $godotExe) {
  throw "Godot executable not found in $godotDir. Expected one of: $($candidates -join ', ')"
}

$argsList = @("--path", $repoRoot) + $GodotArgs
Start-Process -FilePath $godotExe -ArgumentList $argsList

