# Builds LiteLua with the Wonderful toolchain + BlocksDS installed in C:\msys64.
# Usage:
#   .\build.ps1          build, archive to builds\, copy to the emulator SD card
#   .\build.ps1 run      the same, then start melonDS with the ROM
#   .\build.ps1 clean    any other arguments are passed to make (no archive/copy)
# Git Bash cannot run this toolchain (missing libstdc++ DLL / mixed msys runtimes),
# so we recreate the environment of wonderful_shell.cmd here.
#
# Paths of the test setup (D17) can be overridden with environment variables:
#   LITELUA_SDCARD  folder synced by melonDS as the DLDI SD card
#   LITELUA_MELONDS melonDS folder

$ErrorActionPreference = 'Stop'
$msys = 'C:\msys64'
$sdcard = if ($env:LITELUA_SDCARD) { $env:LITELUA_SDCARD } else { 'D:\Programowanie\sdcard' }
$melon = if ($env:LITELUA_MELONDS) { $env:LITELUA_MELONDS } else { 'D:\Programowanie\melonDS-1.1-windows-x86_64' }

$run = $false
$makeArgs = @($args)
if ($makeArgs.Count -gt 0 -and $makeArgs[0] -eq 'run') {
    $run = $true
    $makeArgs = @($makeArgs | Select-Object -Skip 1)
}

$env:MSYSTEM = 'UCRT64'
$env:MSYS2_PATH_TYPE = 'inherit'
$env:CHERE_INVOKING = '1'
$env:PATH = "$msys\opt\wonderful\bin;$env:PATH"

$cmd = 'export WONDERFUL_TOOLCHAIN=/opt/wonderful ' +
       'BLOCKSDS=/opt/wonderful/thirdparty/blocksds/core ' +
       'BLOCKSDSEXT=/opt/wonderful/thirdparty/blocksds/external; ' +
       "make -j8 $($makeArgs -join ' ')"

Push-Location $PSScriptRoot
try {
    & "$msys\usr\bin\bash.exe" -lc $cmd
    if ($LASTEXITCODE -ne 0 -or $makeArgs.Count -gt 0) {
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

    # Deploy to the emulator SD card (D17), creating the D6 folder layout
    if (Test-Path $sdcard) {
        foreach ($dir in 'litelua\carts', 'litelua\lib', 'litelua\saves') {
            New-Item -ItemType Directory -Force (Join-Path $sdcard $dir) | Out-Null
        }
        Copy-Item litelua.nds (Join-Path $sdcard 'litelua.nds') -Force
        Write-Host "  DEPLOY  $sdcard\litelua.nds"
    } else {
        Write-Host "  (no emulator SD card at $sdcard, skipping deploy)"
    }

    if ($run) {
        $exe = Join-Path $melon 'melonDS.exe'
        if (Get-Process melonDS -ErrorAction SilentlyContinue) {
            Write-Host '  melonDS is already running: reset the ROM there to load the new build'
        } else {
            Start-Process $exe -ArgumentList "`"$(Join-Path $sdcard 'litelua.nds')`"" -WorkingDirectory $melon
            Write-Host '  RUN     melonDS'
        }
    }
    exit 0
} finally {
    Pop-Location
}
