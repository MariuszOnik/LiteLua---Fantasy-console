# Builds LiteLua with the Wonderful toolchain + BlocksDS installed in C:\msys64.
# Usage:
#   .\build.ps1          build, archive to builds\, copy the ROM and the test carts
#                        (tests\carts) to the emulator SD card
#   .\build.ps1 run      the same, then start melonDS with the ROM
#   .\build.ps1 clean    any other arguments are passed to make (no archive/copy)
# Git Bash cannot run this toolchain (missing libstdc++ DLL / mixed msys runtimes),
# so we recreate the environment of wonderful_shell.cmd here.
#
# Paths of the test setup (D17) can be overridden with environment variables:
#   LITELUA_SDCARD  folder synced by melonDS as the DLDI SD card
#   LITELUA_MELONDS melonDS folder
#   LITELUA_TAG     optional word added to the ROM banner (e.g. a test variant)

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

Push-Location $PSScriptRoot
try {
    # The plan point being worked on: the first one marked [~], otherwise the
    # first [ ] (D16). It names the archived ROM and goes into the ROM banner.
    $plan = Get-Content docs\PLAN.md -Encoding UTF8
    $point = $plan | Select-String -Pattern '^- \[~\] \*\*(P\w+)' | Select-Object -First 1
    if (-not $point) {
        $point = $plan | Select-String -Pattern '^- \[ \] \*\*(P\w+)' | Select-Object -First 1
    }
    $name = if ($point) { $point.Matches[0].Groups[1].Value } else { '' }

    $make = "make -j8 $($makeArgs -join ' ')"
    if ($makeArgs.Count -eq 0) {
        # Banner subtitle (shown by loader menus): plan point, optional tag from
        # LITELUA_TAG and build time, so builds on a console can be told apart.
        # The ROM is removed so ndstool always writes the new banner.
        $subtitle = (@($name, $env:LITELUA_TAG, (Get-Date -Format 'MM-dd HH:mm')) |
                     Where-Object { $_ }) -join ' '
        Remove-Item litelua.nds -ErrorAction SilentlyContinue
        $make += " GAME_SUBTITLE='$subtitle'"
    }

    $cmd = 'export WONDERFUL_TOOLCHAIN=/opt/wonderful ' +
           'BLOCKSDS=/opt/wonderful/thirdparty/blocksds/core ' +
           'BLOCKSDSEXT=/opt/wonderful/thirdparty/blocksds/external; ' + $make

    & "$msys\usr\bin\bash.exe" -lc $cmd
    if ($LASTEXITCODE -ne 0 -or $makeArgs.Count -gt 0) {
        exit $LASTEXITCODE
    }

    # Archive the ROM as builds/litelua-P<n>.nds. Builds of earlier points are
    # kept; rebuilds within a point overwrite.
    if ($name) {
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
        # Test carts (tests\carts) and example games (examples\carts) replace
        # their copies on the SD card
        foreach ($cart in @(Get-ChildItem tests\carts, examples\carts -Directory)) {
            $dest = Join-Path $sdcard "litelua\carts\$($cart.Name)"
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Copy-Item $cart.FullName $dest -Recurse
        }
        # The same files test packed as .lcart (ZIP) checks reading from archives
        python tools\litelua.py pack tests\carts\files (Join-Path $sdcard 'litelua\carts\files-zip.lcart') | Out-Null
        Write-Host "  DEPLOY  test and example carts -> litelua\carts (+ files-zip.lcart)"
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
