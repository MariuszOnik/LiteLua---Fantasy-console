# Builds heroes3d.3dsx (devkitPro make under its own msys2). Usage:
#   .\build.ps1          map3d.bin (tools/make_m3.py) + make
#   .\build.ps1 clean
#   .\build.ps1 run      build, then open in the Azahar emulator
param([string]$what = "")
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
if ($what -eq "run") {
    $azahar = "D:\Programowanie\azahar-windows-mxe-2127.0-alpha3\azahar-windows-mxe-2127.0-alpha3\azahar.exe"
    Start-Process $azahar -ArgumentList "`"$here\heroes3d.3dsx`""
}
