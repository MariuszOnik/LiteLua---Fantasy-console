# Builds heroes3d.3dsx (devkitPro make under its own msys2) and keeps a copy as
# builds\heroes3d-<tag>.3dsx: every idea gets its own tag, old builds stay for comparing.
# Usage:
#   .\build.ps1          map3d.bin (tools/make_m3.py) + make + copy
#   .\build.ps1 clean
#   .\build.ps1 run      build, then open in the Azahar emulator
#   -tag m3x             label of the copy and of the app's title (default: the current idea)
#   -gen "--tiles 4 ..." arguments for tools/make_m3.py (which map goes into romfs)
param([string]$what = "", [string]$tag = "m3d", [string]$gen = "")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$bash = "C:\devkitPro\msys2\usr\bin\bash.exe"
$unix = "/" + $here.Substring(0, 1).ToLower() + $here.Substring(2).Replace("\", "/")
$env_ = "export DEVKITPRO=/opt/devkitpro DEVKITARM=/opt/devkitpro/devkitARM; cd '$unix'"
if ($what -eq "clean") {
    & $bash -lc "$env_ && make clean"
    exit $LASTEXITCODE
}
$genArgs = @()
if ($gen) { $genArgs = $gen.Split(" ", [StringSplitOptions]::RemoveEmptyEntries) }
python (Join-Path $here "..\tools\make_m3.py") @genArgs
if ($LASTEXITCODE) { exit $LASTEXITCODE }
# make does not see changes inside romfs/: drop the .3dsx so the map is always packed anew
Remove-Item -ErrorAction SilentlyContinue (Join-Path $here "heroes3d.3dsx"), (Join-Path $here "heroes3d.smdh")
# the tag and the time in the app's title: builds differ in the emulator's list
$title = "HeroesDS $tag " + (Get-Date -Format "MM-dd HH:mm")
& $bash -lc "$env_ && make APP_TITLE='$title'"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Force (Join-Path $here "builds") | Out-Null
$copy = Join-Path $here "builds\heroes3d-$tag.3dsx"
Copy-Item -Force (Join-Path $here "heroes3d.3dsx") $copy
Write-Host "copy: $copy"
if ($what -eq "run") {
    $azahar = "D:\Programowanie\azahar-windows-mxe-2127.0-alpha3\azahar-windows-mxe-2127.0-alpha3\azahar.exe"
    Start-Process $azahar -ArgumentList "`"$copy`""
}
