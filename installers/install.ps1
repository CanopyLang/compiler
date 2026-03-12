# Canopy installer script for Windows
# Usage: irm https://canopy-lang.org/install.ps1 | iex
#    or: .\install.ps1 [-Version VERSION] [-InstallDir DIR]

param(
    [string]$Version = "",
    [string]$InstallDir = "$env:USERPROFILE\.canopy\bin",
    [switch]$ModifyPath,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$Repo = "canopy-lang/canopy"

if ($Help) {
    Write-Host "Usage: install.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Version VERSION    Install a specific version (default: latest)"
    Write-Host "  -InstallDir DIR     Install to DIR (default: ~\.canopy\bin)"
    Write-Host "  -ModifyPath         Add install dir to user PATH"
    Write-Host "  -Help               Show this help"
    exit 0
}

function Get-LatestVersion {
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
    return $response.tag_name -replace '^v', ''
}

function Get-Sha256 {
    param([string]$FilePath)
    $hash = Get-FileHash -Path $FilePath -Algorithm SHA256
    return $hash.Hash.ToLower()
}

function Install-Canopy {
    $arch = "x86_64"
    $platform = "windows-$arch"

    Write-Host "Canopy Installer" -ForegroundColor Cyan
    Write-Host "================"
    Write-Host ""
    Write-Host "Platform: $platform"

    if (-not $Version) {
        Write-Host "Resolving latest version..."
        $Version = Get-LatestVersion
        if (-not $Version) {
            Write-Host "Error: Could not determine latest version" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "Version:  $Version"
    Write-Host "Install:  $InstallDir"
    Write-Host ""

    $archive = "canopy-$Version-$platform.zip"
    $baseUrl = "https://github.com/$Repo/releases/download/v$Version"
    $archiveUrl = "$baseUrl/$archive"
    $checksumUrl = "$baseUrl/SHA256SUMS.txt"

    $tmpDir = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString()))

    try {
        $archivePath = Join-Path $tmpDir $archive
        $checksumPath = Join-Path $tmpDir "SHA256SUMS.txt"

        Write-Host "Downloading $archive..."
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing

        Write-Host "Downloading checksums..."
        Invoke-WebRequest -Uri $checksumUrl -OutFile $checksumPath -UseBasicParsing

        Write-Host "Verifying checksum..."
        $checksumContent = Get-Content $checksumPath -Raw
        $expectedLine = ($checksumContent -split "`n") | Where-Object { $_ -match $archive }

        if ($expectedLine) {
            $expectedHash = ($expectedLine -split '\s+')[0].ToLower()
            $actualHash = Get-Sha256 -FilePath $archivePath
            if ($actualHash -ne $expectedHash) {
                Write-Host "Error: Checksum verification failed" -ForegroundColor Red
                Write-Host "  Expected: $expectedHash"
                Write-Host "  Actual:   $actualHash"
                exit 1
            }
            Write-Host "  Checksum verified." -ForegroundColor Green
        } else {
            Write-Host "Warning: Archive not found in SHA256SUMS.txt, skipping verification" -ForegroundColor Yellow
        }

        Write-Host "Extracting..."
        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }
        Expand-Archive -Path $archivePath -DestinationPath $InstallDir -Force

        Write-Host ""
        Write-Host "Canopy $Version installed to $InstallDir\canopy.exe" -ForegroundColor Green

        if ($ModifyPath) {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$InstallDir*") {
                [Environment]::SetEnvironmentVariable("Path", "$InstallDir;$currentPath", "User")
                Write-Host "  Added $InstallDir to user PATH." -ForegroundColor Green
                Write-Host "  Restart your terminal for changes to take effect."
            } else {
                Write-Host "  $InstallDir is already in PATH."
            }
        } else {
            $envPath = $env:PATH
            if ($envPath -notlike "*$InstallDir*") {
                Write-Host ""
                Write-Host "To add Canopy to your PATH, run:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  `$env:PATH = `"$InstallDir;`$env:PATH`""
                Write-Host ""
                Write-Host "Or re-run with -ModifyPath to update your user PATH permanently."
            }
        }

        Write-Host ""
        Write-Host "Run 'canopy --help' to get started."
    } finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }
}

Install-Canopy
