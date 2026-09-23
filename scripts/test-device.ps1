[CmdletBinding()]
param([string] $CliHome = $env:HARMONYOS_CLI_HOME, [string] $Device = $env:HDC_DEVICE,
    [switch] $AllowUnavailablePdfKit)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'harmony-env.ps1') -CliHome $CliHome
$projectRoot = Split-Path $PSScriptRoot -Parent
$hdcPath = Join-Path $env:DEVECO_SDK_HOME 'default\openharmony\toolchains\hdc.exe'
$targets = & $hdcPath list targets
if ($targets -match '\[Empty\]' -or -not $targets) { throw 'Connect a HarmonyOS device or start the emulator first.' }
if (-not $Device -or $Device -notin $targets) { throw 'Supply one explicitly connected -Device target.' }
$deviceArguments = @('-t', $Device)
Push-Location (Join-Path $projectRoot 'read-books')
try {
    & hvigorw.bat --mode module -p product=default -p module=entry@ohosTest -p buildMode=debug assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'Native test package build failed.' }
    $installed = & $hdcPath @deviceArguments install -r 'entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap'
    if (($installed -join "`n") -notmatch 'successfully') { throw ($installed -join "`n") }
    # Unit storage uses an isolated QA namespace. Do not resurrect the ordinary
    # reader task in the same process while the storage suite is running.
    & $hdcPath @deviceArguments shell aa force-stop com.healing1.readbooks | Out-Null
    $output = & $hdcPath @deviceArguments shell aa test -b com.healing1.readbooks -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 120000
    $reportPath = Join-Path $projectRoot 'docs/qa/native-tests.txt'
    $output | Set-Content -LiteralPath $reportPath -Encoding utf8
    $result = (($output | Select-String 'OHOS_REPORT_RESULT: stream=Tests run:') -join "`n")
    Write-Output $result
    if (-not $result -or $result -notmatch 'Tests run: (\d+), Failure: 0, Error: 0, Pass: (\d+), Ignore: (\d+)') {
        throw "Native tests failed. See $reportPath"
    }
    $total = [int]$Matches[1]; $passed = [int]$Matches[2]; $ignored = [int]$Matches[3]
    if ($total -ne ($passed + $ignored)) { throw 'Incomplete test report.' }
    if ($ignored -gt 0) { throw "Unexpected ignored tests: $ignored. See $reportPath" }
    if (($output -join "`n") -match 'reportsUnavailablePdfKitWithoutPublishingACopy') {
        if (-not $AllowUnavailablePdfKit) {
            throw "Three PDF cases could not run on this device. See $reportPath"
        }
        Write-Warning 'Three native PDF cases remain unverified: this runtime has no PDF Kit. Run on a supported device without -AllowUnavailablePdfKit for full acceptance.'
    }
} finally {
    Pop-Location
}
