[CmdletBinding()]
param(
    [ValidateSet('Build', 'Test', 'Check')]
    [string] $Action = 'Build',
    [string] $CliHome = $env:HARMONYOS_CLI_HOME
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'harmony-env.ps1') -CliHome $CliHome
$projectPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'read-books'
Push-Location $projectPath
try {
    if ($Action -eq 'Check') {
        foreach ($check in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'check-*.cjs')) {
            & (Join-Path $env:DEVECO_NODE_HOME 'node.exe') $check.FullName
            if ($LASTEXITCODE -ne 0) { throw "Check failed: $($check.Name)" }
        }
    } else {
        $task = if ($Action -eq 'Test') { 'test' } else { 'assembleHap' }
        & hvigorw.bat --mode module -p product=default -p module=entry@default -p buildMode=debug $task --no-daemon
        if ($LASTEXITCODE -ne 0) { throw "Hvigor $task failed with exit code $LASTEXITCODE" }
        if ($Action -eq 'Test') {
            $report = Get-Content -LiteralPath 'entry/.test/default/intermediates/test/coverage_data/test_result.txt' -Raw
            if ($report -notmatch 'Tests run: (\d+), Failure: 0, Error: 0, Pass: \1, Ignore: 0') {
                throw 'Unit tests failed or did not produce a complete passing report.'
            }
        }
    }
} finally {
    Pop-Location
}
