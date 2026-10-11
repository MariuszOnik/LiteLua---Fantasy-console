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
    if ($LASTEXITCODE -ne 0 -or $args.Count -gt 0) {
        exit $LASTEXITCODE
    }

    # Archive the ROM as builds/litelua-P<n>.nds, where P<n> is the plan point
    # being worked on: the first one marked [~], otherwise the first [ ] (D16).
    # Builds of earlier points are kept; rebuilds within a point overwrite.
    $plan = Get-Content docs\PLAN.md -Encoding UTF8
    $point = $plan | Select-String -Pattern '^- \[~\] \*\*(P\w+)' | Select-Object -First 1
    if (-not $point) {
        $point = $plan | Select-String -Pattern '^- \[ \] \*\*(P\w+)' | Select-Object -First 1
    }
    if ($point) {
        $name = $point.Matches[0].Groups[1].Value
        New-Item -ItemType Directory -Force builds | Out-Null
        Copy-Item litelua.nds "builds\litelua-$name.nds" -Force
        Write-Host "  ARCHIVE builds\litelua-$name.nds"
    }
    exit 0
} finally {
    Pop-Location
}
