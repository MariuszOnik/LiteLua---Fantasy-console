# Builds LiteLua with the Wonderful toolchain + BlocksDS installed in C:\msys64.
# Usage: .\build.ps1 [make arguments], e.g. .\build.ps1 clean
# Git Bash cannot run this toolchain (missing libstdc++ DLL / mixed msys runtimes),
# so we recreate the environment of wonderful_shell.cmd here.

$ErrorActionPreference = 'Stop'
$msys = 'C:\msys64'

$env:MSYSTEM = 'UCRT64'
$env:MSYS2_PATH_TYPE = 'inherit'
$env:CHERE_INVOKING = '1'
$env:PATH = "$msys\opt\wonderful\bin;$env:PATH"

$makeArgs = ($args -join ' ')
$cmd = 'export WONDERFUL_TOOLCHAIN=/opt/wonderful ' +
       'BLOCKSDS=/opt/wonderful/thirdparty/blocksds/core ' +
       'BLOCKSDSEXT=/opt/wonderful/thirdparty/blocksds/external; ' +
       "make -j8 $makeArgs"

Push-Location $PSScriptRoot
try {
    & "$msys\usr\bin\bash.exe" -lc $cmd
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
