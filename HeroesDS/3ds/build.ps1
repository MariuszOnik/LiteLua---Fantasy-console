# Builds heroes3d.3dsx (devkitPro make under its own msys2) and keeps a copy as
# builds\heroes3d-<tag>.3dsx: every idea gets its own tag, old builds stay for comparing.
# Usage:
#   .\build.ps1          map3d.bin (tools/make_m3.py) + make + copy
#   .\build.ps1 clean
#   .\build.ps1 run      build, then open in the Azahar emulator
#   -tag m3x             label of the copy (default: the current idea)
param([string]$what = "", [string]$tag = "m3c")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$bash = "C:\devkitPro\msys2\usr\bin\bash.exe"
$unix = "/" + $here.Substring(0, 1).ToLower() + $here.Substring(2).Replace("\", "/")
$env_ = "export DEVKITPRO=/opt/devkitpro DEVKITARM=/opt/devkitpro/devkitARM; cd '$unix'"
if ($what -eq "clean") {
    & $bash -lc "$env_ && make clean"
    exit $LASTEXITCODE
}
python (Join-Path $here "..\tools\make_m3.py")
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& $bash -lc "$env_ && make"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Force (Join-Path $here "builds") | Out-Null
$copy = Join-Path $here "builds\heroes3d-$tag.3dsx"
Copy-Item -Force (Join-Path $here "heroes3d.3dsx") $copy
Write-Host "copy: $copy"
if ($what -eq "run") {
    $azahar = "D:\Programowanie\azahar-windows-mxe-2127.0-alpha3\azahar-windows-mxe-2127.0-alpha3\azahar.exe"
    Start-Process $azahar -ArgumentList "`"$copy`""
}
