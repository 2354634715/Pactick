param(
    [ValidateSet('windows-amd64', 'linux-amd64', 'windows-386', 'linux-386')]
    [string[]]$Targets = @('windows-amd64', 'linux-amd64', 'windows-386', 'linux-386'),
    [string]$OutputDirectory = ''
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectDirectory 'output/server-tools' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$previousGOOS = $env:GOOS
$previousGOARCH = $env:GOARCH
$previousCGO = $env:CGO_ENABLED
Push-Location -LiteralPath $projectDirectory
try {
    $env:CGO_ENABLED = '0'
    foreach ($target in $Targets) {
        $targetOS, $targetArch = $target.Split('-')
        $env:GOOS = $targetOS
        $env:GOARCH = $targetArch
        $binDirectory = Join-Path $OutputDirectory "$target/bin"
        New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
        foreach ($component in @('server', 'migrate', 'healthcheck', 'admin', 'manager')) {
            $executable = if ($targetOS -eq 'windows') { "$component.exe" } else { $component }
            & go build -trimpath -o (Join-Path $binDirectory $executable) "./cmd/$component"
            if ($LASTEXITCODE -ne 0) { throw "Build failed: $target/$component" }
        }
        Write-Output "$target tools: $binDirectory"
    }
} finally {
    $env:GOOS = $previousGOOS
    $env:GOARCH = $previousGOARCH
    $env:CGO_ENABLED = $previousCGO
    Pop-Location
}
