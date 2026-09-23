[CmdletBinding()]
param(
    [ValidateSet('Status', 'ReviewLicenses', 'Download', 'Start', 'Stop')]
    [string] $Action = 'Status',
    [string] $HarmonyRoot = (Join-Path $env:USERPROFILE 'DevTools\HarmonyOS'),
    [string] $DevEcoCli = '',
    [string] $EmulatorName = 'MatePad_Pro_12_2_H6',
    [string] $OsVersion = 'HarmonyOS 6.0.2(22)'
)

$ErrorActionPreference = 'Stop'
$cltRoot = Join-Path $HarmonyRoot 'command-line-tools-26.0.0.821\command-line-tools'
$emulatorExe = Join-Path $cltRoot 'emulator\Emulator.exe'
if (-not $DevEcoCli) {
    $launcher = Get-Command 'devecocli.cmd' -ErrorAction SilentlyContinue
    if ($launcher) {
        $DevEcoCli = $launcher.Source
    } else {
        $DevEcoCli = Join-Path $env:USERPROFILE 'Documents\trae_projects\Exeperment\npm-global\devecocli.cmd'
    }
}
$imageRoot = Join-Path $harmonyRoot 'emulator\images'
$instanceRoot = Join-Path $harmonyRoot 'emulator\instances'

if (-not (Test-Path -LiteralPath $emulatorExe -PathType Leaf)) {
    throw "HarmonyOS Emulator was not found: $emulatorExe"
}

$previousSdk = $env:DEVECO_SDK_HOME
$previousClt = $env:DEVECO_CLI_CLT_PATH
$env:DEVECO_SDK_HOME = Join-Path $cltRoot 'sdk'
$env:DEVECO_CLI_CLT_PATH = $cltRoot

try {
    switch ($Action) {
        'Status' {
            & $devecoCli emulator list --format json
        }
        'ReviewLicenses' {
            & $emulatorExe -license
        }
        'Download' {
            New-Item -ItemType Directory -Force -Path $imageRoot | Out-Null
            # Leave Huawei's license confirmation interactive.
            & $emulatorExe -install -deviceType Tablet -osVersion $osVersion -imageRoot $imageRoot
        }
        'Start' {
            $instanceConfig = Join-Path $instanceRoot "$emulatorName\config.ini"
            if (-not (Test-Path -LiteralPath $instanceConfig -PathType Leaf)) {
                throw 'The configured MatePad instance was not found in the HarmonyOS directory.'
            }
            $running = Get-CimInstance Win32_Process -Filter "Name = 'Emulator.exe'" |
                Where-Object { $_.CommandLine -match '-(start|hvd)\s' }
            if ($running) {
                throw 'An emulator is already running. Do not start another instance; inspect or stop the existing one first.'
            }
            # The native path is the instances ROOT, not the individual instance directory.
            # Avoid the deployed junction and preserve userdata with coldboot (never reset).
            # This emulator build can fail to roll a >10 MiB kernel log and flood the startup pipe.
            $kernelLog = Join-Path $instanceRoot "$emulatorName\Log\kernel.log"
            if ((Test-Path -LiteralPath $kernelLog) -and (Get-Item -LiteralPath $kernelLog).Length -ge 8MB) {
                $resolvedLog = (Resolve-Path -LiteralPath $kernelLog).Path
                $resolvedInstance = (Resolve-Path -LiteralPath (Join-Path $instanceRoot $emulatorName)).Path
                if (-not $resolvedLog.StartsWith($resolvedInstance + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Kernel log escaped the selected emulator instance.'
                }
                $logBackup = Join-Path (Split-Path $resolvedLog -Parent) ('kernel-before-start-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
                Move-Item -LiteralPath $resolvedLog -Destination $logBackup
                Write-Output "Preserved oversized kernel log: $logBackup"
            }
            & $emulatorExe -start $emulatorName -instancePath $instanceRoot -imageRoot $imageRoot -bootMode coldboot
        }
        'Stop' {
            & $devecoCli emulator stop $emulatorName
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Emulator $Action failed with exit code $LASTEXITCODE."
    }
} finally {
    $env:DEVECO_SDK_HOME = $previousSdk
    $env:DEVECO_CLI_CLT_PATH = $previousClt
}
