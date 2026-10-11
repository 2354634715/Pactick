[CmdletBinding()]
param(
    [string] $BundleDir = (Join-Path $PSScriptRoot '..\..'),
    [string] $ConfigFile,
    [switch] $MigrateOnly
)
$ErrorActionPreference = 'Stop'
$bundlePath = (Resolve-Path -LiteralPath $BundleDir).Path
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $bundlePath 'data\api.env'
}
if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
    throw 'Configuration is missing. Initialize native mode in the server manager first, or pass -ConfigFile.'
}
foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $ConfigFile).Path)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        throw 'Invalid configuration line; expected a literal KEY=value assignment.'
    }
    $key = $Matches[1]
    $value = $Matches[2]
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
}
$program = 'server.exe'
if ($MigrateOnly) { $program = 'migrate.exe' }
& (Join-Path $bundlePath "bin\$program")
exit $LASTEXITCODE
