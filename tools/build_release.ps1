$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Version = (Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim()
$ExpectedHash = '0B3D1639F4B4927522B51386D0140F37390088D80F3FD8E1183B2F513D889A05'
$ExpectedSourceLength = 67173
$ExpectedSourceLines = 1544
$ExpectedLogoHash = '14EDE1DE9DDE6F644000F1481DCA817C6E782E183D1AB7D9314FCA6D99F4FA7B'
$Source = Join-Path $Root 'GIB2A PW\main.lua'
$Logo = Join-Path $Root 'GIB2A PW\gib2a_logo_ethos_180.png'
$ManifestPath = Join-Path $Root 'packaging\ethos_lua_manifest.json'
$ReleaseDir = Join-Path $Root 'releases\V26.1.1'
$ZipPath = Join-Path $ReleaseDir 'GIB2A-POWER-v26.1.1.zip'

if ($Version -ne '26.1.1') { throw "Unexpected VERSION: $Version" }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash -ne $ExpectedHash) { throw 'Source hash mismatch' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $Logo).Hash -ne $ExpectedLogoHash) { throw 'Logo hash mismatch' }
$Raw = [IO.File]::ReadAllBytes($Source)
if ($Raw.Length -ne $ExpectedSourceLength -or $Raw -contains 13) { throw 'Source format mismatch' }
if ($Raw.Length -ge 3 -and $Raw[0] -eq 0xEF -and $Raw[1] -eq 0xBB -and $Raw[2] -eq 0xBF) { throw 'Source contains a UTF-8 BOM' }
$null = [Text.UTF8Encoding]::new($false, $true).GetString($Raw)
if (([IO.File]::ReadAllLines($Source)).Count -ne $ExpectedSourceLines) { throw 'Source line count mismatch' }
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if ($Manifest.folder -ne 'GIB2APW') { throw "Unexpected ETHOS install folder: $($Manifest.folder)" }
if ($Manifest.folder -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw 'Invalid ETHOS install folder format' }

New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Add-Type -AssemblyName System.IO.Compression
$Stream = [IO.File]::Open($ZipPath, [IO.FileMode]::CreateNew)
$Archive = [IO.Compression.ZipArchive]::new($Stream, [IO.Compression.ZipArchiveMode]::Create)
$Timestamp = [DateTimeOffset]::new(2026, 9, 24, 0, 0, 0, [TimeSpan]::Zero)
$Entries = [ordered]@{
    'CHANGELOG.md' = (Join-Path $Root 'CHANGELOG.md')
    'INSTALLATION.md' = (Join-Path $Root 'docs\INSTALLATION.md')
    'README.md' = (Join-Path $Root 'README.md')
    'ethos_lua_manifest.json' = $ManifestPath
    'gib2a_logo_ethos_180.png' = $Logo
    'main.lua' = $Source
}
try {
    foreach ($Name in $Entries.Keys) {
        $Entry = $Archive.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
        $Entry.LastWriteTime = $Timestamp
        $Input = [IO.File]::OpenRead($Entries[$Name])
        $Output = $Entry.Open()
        try { $Input.CopyTo($Output) } finally { $Output.Dispose(); $Input.Dispose() }
    }
} finally {
    $Archive.Dispose()
    $Stream.Dispose()
}
$ZipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash
[IO.File]::WriteAllText((Join-Path $ReleaseDir 'SHA256SUMS.txt'), "$ZipHash  GIB2A-POWER-v26.1.1.zip`n", [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $Root 'docs\release-notes\V26.1.1.md') -Destination (Join-Path $ReleaseDir 'GITHUB_RELEASE_NOTES.md') -Force
Write-Output "GIB2A-POWER-v26.1.1.zip: $((Get-Item -LiteralPath $ZipPath).Length) bytes"
Write-Output "SHA-256: $ZipHash"
Write-Output 'Build: PASS'
