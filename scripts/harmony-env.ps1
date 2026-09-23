param([string] $CliHome = $env:HARMONYOS_CLI_HOME)

$ErrorActionPreference = 'Stop'
if (-not $CliHome) {
    $CliHome = Join-Path $env:USERPROFILE 'DevTools\HarmonyOS\command-line-tools-26.0.0.821\command-line-tools'
}
if (-not (Test-Path -LiteralPath (Join-Path $CliHome 'bin\hvigorw.bat'))) {
    throw 'Set HARMONYOS_CLI_HOME or pass -CliHome to an installed HarmonyOS command-line-tools directory.'
}
$env:HARMONYOS_CLI_HOME = (Resolve-Path -LiteralPath $CliHome).Path
$env:DEVECO_SDK_HOME = Join-Path $CliHome 'sdk'
$env:DEVECO_NODE_HOME = Join-Path $CliHome 'tool\node'
$env:HARMONY_TYPESCRIPT = Join-Path $CliHome 'sdk\default\openharmony\ets\build-tools\ets-loader\node_modules\typescript\lib\typescript.js'
$env:HVIGOR_USER_HOME = Join-Path $env:USERPROFILE 'DevTools\HarmonyOS\.hvigor'
$env:Path = (Join-Path $CliHome 'bin') + ';' + $env:DEVECO_NODE_HOME + ';' + $env:Path
