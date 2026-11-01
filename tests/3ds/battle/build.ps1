# Builds battle3d.3dsx (devkitPro make under its own msys2), as tests/3ds/army/build.ps1.
# Usage:
#   .\build.ps1          knights from local Medieval II files (../army/make_knight.py, light,
#                        idle/fidget/run/charge) into romfs/, then make
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
$romfs = Join-Path $here "romfs"
New-Item -ItemType Directory -Force $romfs | Out-Null
foreach ($unit in "teutonic", "polish") {
    python (Join-Path $here "..\army\make_knight.py") --unit $unit --anim idle,fidget,run,charge --tris 700 --out $romfs
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
}
# make does not see changes inside romfs/: drop the .3dsx so the models are always packed anew
Remove-Item -ErrorAction SilentlyContinue (Join-Path $here "battle3d.3dsx")
& $bash -lc "$env_ && make"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if ($what -eq "run") {
    $azahar = "D:\Programowanie\azahar-windows-mxe-2127.0-alpha3\azahar-windows-mxe-2127.0-alpha3\azahar.exe"
    Start-Process $azahar -ArgumentList "`"$(Join-Path $here 'battle3d.3dsx')`""
}
