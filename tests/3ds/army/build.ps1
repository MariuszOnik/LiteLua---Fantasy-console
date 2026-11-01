# Builds army3d.3dsx (devkitPro make under its own msys2), as HeroesDS/3ds/build.ps1.
# Usage:
#   .\build.ps1          make_army.py (soldier from local Imperial Glory files),
#                        make_knight.py (Medieval II knight, when unpacked) + make
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
python (Join-Path $here "make_army.py")
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if (Test-Path "E:\AI\M2TW\tools") {   # the knight only where the Medieval II files are unpacked
    foreach ($unit in "teutonic", "polish") {
        python (Join-Path $here "make_knight.py") --unit $unit
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
    }
}
# make does not see changes inside romfs/: drop the .3dsx so the model is always packed anew
Remove-Item -ErrorAction SilentlyContinue (Join-Path $here "army3d.3dsx")
& $bash -lc "$env_ && make"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if ($what -eq "run") {
    $azahar = "D:\Programowanie\azahar-windows-mxe-2127.0-alpha3\azahar-windows-mxe-2127.0-alpha3\azahar.exe"
    Start-Process $azahar -ArgumentList "`"$(Join-Path $here 'army3d.3dsx')`""
}
