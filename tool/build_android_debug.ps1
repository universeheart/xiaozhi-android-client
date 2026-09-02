[CmdletBinding()]
param(
    [ValidatePattern('^[D-Zd-z]$')]
    [string]$DriveLetter = 'R'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$asciiOnly = $repoRoot -cmatch '^[\x00-\x7F]+$'
$buildRoot = $repoRoot
$driveRoot = "$($DriveLetter.ToUpperInvariant()):"
$mappingCreated = $false

if (-not $asciiOnly) {
    if (Test-Path -LiteralPath "$driveRoot\") {
        throw "$driveRoot is already in use. Choose another drive letter, for example: -DriveLetter S"
    }

    & subst.exe $driveRoot $repoRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to map $driveRoot to $repoRoot"
    }

    $mappingCreated = $true
    $buildRoot = "$driveRoot\"
}

try {
    Push-Location -LiteralPath $buildRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get failed with exit code $LASTEXITCODE"
        }

        & flutter build apk --debug
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build apk --debug failed with exit code $LASTEXITCODE"
        }

        $apk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-debug.apk'
        if (-not (Test-Path -LiteralPath $apk)) {
            throw "Build reported success but APK was not found: $apk"
        }

        Get-Item -LiteralPath $apk | Select-Object FullName, Length, LastWriteTime
    }
    finally {
        Pop-Location
    }
}
finally {
    if ($mappingCreated) {
        & subst.exe $driveRoot /D
    }
}
