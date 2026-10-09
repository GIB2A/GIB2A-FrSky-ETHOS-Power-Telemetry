$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Root 'GIB2A PW\main.lua'
$Logo = Join-Path $Root 'GIB2A PW\gib2a_logo_ethos_180.png'
$ZipPath = Join-Path $Root 'releases\V26.1.3\GIB2A-POWER-v26.1.3.zip'
$ExpectedHash = 'D551CC3CA48B6483A2239D77457CA23D0649F16CC5C59B4F9DDA5D0DC6686EA2'
$ExpectedLogoHash = '14EDE1DE9DDE6F644000F1481DCA817C6E782E183D1AB7D9314FCA6D99F4FA7B'
$ExpectedInstallFolder = 'GIB2APW'
$TurbineInstallFolder = 'GIB2A'
$Failures = [Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Output "PASS: $Message" }
    else { Write-Output "FAIL: $Message"; $script:Failures.Add($Message) }
}

$Raw = [IO.File]::ReadAllBytes($Source)
$Text = [Text.UTF8Encoding]::new($false, $true).GetString($Raw)
Check ((Get-Content -Raw -LiteralPath (Join-Path $Root 'VERSION')).Trim() -eq '26.1.3') 'version'
Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash -eq $ExpectedHash) 'source SHA-256'
Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $Logo).Hash -eq $ExpectedLogoHash) 'logo SHA-256'
Check ($Raw.Length -eq 74512) 'source size'
Check (([IO.File]::ReadAllLines($Source)).Count -eq 1740) 'source line count'
Check (-not ($Raw.Length -ge 3 -and $Raw[0] -eq 0xEF -and $Raw[1] -eq 0xBB -and $Raw[2] -eq 0xBF)) 'no UTF-8 BOM'
Check (-not ($Raw -contains 13)) 'LF line endings'
Check ($Text.Contains('local WIDGET_VERSION = "V26.1.3"')) 'internal version'
Check ($Text.Contains('key = "GIB2APW"')) 'widget key'
Check ($Text.Contains('name = "GIB2A POWER " .. WIDGET_VERSION')) 'registered title'
Check ($Text.Contains('local LOGO_PATH = "gib2a_logo_ethos_180.png"')) 'required runtime logo path'
Check ($Text.Contains('lcd.drawAnnulusSector(x, y, inner, radius,')) 'native ETHOS annulus-sector renderer'
Check (-not $Text.Contains('ANNULUS_RENDER_MODE') -and -not $Text.Contains('ANNULUS_MASK')) 'experimental PNG mask renderer absent'
Check ($Text.Contains('local DISPLAY_REFRESH_SECONDS = 1.00')) 'display refresh limited to 1 Hz'
Check ($Text.Contains('return value, unit ~= "" and unit or "dB"')) 'RSSI empty-unit dB fallback'
Check ($Text.Contains('rxBatterySource = true,') -and $Text.Contains('local NORMALIZED_TELEMETRY_SOURCE_FIELDS')) 'RX Battery uses normalized standard source engine'
Check ($Text.Contains('if id == "rssi1" or id == "rssi2" then') -and $Text.Contains('raw = readRssiSourceValue(widget, field)')) 'RSSI keeps dedicated source engine'

$PaintStart = $Text.IndexOf('local function paint(widget)')
$PaintEnd = $Text.IndexOf("`nlocal function wakeup(widget)", $PaintStart)
$Paint = if ($PaintStart -ge 0 -and $PaintEnd -gt $PaintStart) { $Text.Substring($PaintStart, $PaintEnd - $PaintStart) } else { '' }
Check ($Paint -ne '' -and $Paint -notmatch 'system\.getSources?\s*\(' -and $Paint -notmatch '[:.]value\s*\(') 'paint reads cached data only'

$Manifest = Get-Content -Raw -LiteralPath (Join-Path $Root 'packaging\ethos_lua_manifest.json') | ConvertFrom-Json
Check ($Manifest.manifestVersion -eq 1) 'MANIFEST VERSION = 1'
Check ($Manifest.name -eq 'GIB2A POWER - FrSky Neuron ESC Telemetry') 'manifest name'
Check ($Manifest.key -eq 'com.gib2a.ethos.power') 'manifest key'
Check ($Manifest.key -match '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') 'manifest key format'
Check ($Manifest.version -eq '26.1.3') 'manifest package version'
Check ($Manifest.folder -eq $ExpectedInstallFolder) 'FOLDER = GIB2APW'
Check ($Manifest.folder -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') 'FOLDER FORMAT'
Check (-not $Manifest.folder.Contains(' ')) 'FOLDER CONTAINS SPACE: NO'
Check ("RADIO:/scripts/$($Manifest.folder)/" -eq 'RADIO:/scripts/GIB2APW/') 'POWER INSTALL PATH: RADIO:/scripts/GIB2APW/'
Check ("RADIO:/scripts/$TurbineInstallFolder/" -eq 'RADIO:/scripts/GIB2A/') 'TURBINE INSTALL PATH: RADIO:/scripts/GIB2A/'
Check ($Manifest.folder -ne $TurbineInstallFolder) 'POWER / TURBINE DIRECTORY COLLISION: NO'
$ExpectedFiles = @('main.lua','gib2a_logo_ethos_180.png','README.md','CHANGELOG.md','INSTALLATION.md')
Check ((Compare-Object $ExpectedFiles @($Manifest.files)).Count -eq 0 -and @($Manifest.files).Count -eq $ExpectedFiles.Count) 'manifest file list'
Check (@($Manifest.files) -contains 'main.lua') 'MAIN.LUA INCLUDED IN FILES: YES'
Check (Test-Path -LiteralPath (Join-Path $Root 'docs\GIB2A PW.png')) 'publication image exists'
Check (Test-Path -LiteralPath $ZipPath) 'release ZIP exists'

if (Test-Path -LiteralPath $ZipPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $Names = @($Archive.Entries | ForEach-Object FullName)
        $ExpectedEntries = @(
            'CHANGELOG.md',
            'INSTALLATION.md',
            'README.md',
            'ethos_lua_manifest.json',
            'gib2a_logo_ethos_180.png',
            'main.lua'
        )
        $ManifestEntry = $Archive.GetEntry('ethos_lua_manifest.json')
        $NestedManifests = @($Names | Where-Object { $_ -ne 'ethos_lua_manifest.json' -and $_ -match '(^|/)ethos_lua_manifest\.json$' })
        Check ($null -ne $ManifestEntry) 'MANIFEST AT ZIP ROOT'
        Check ($NestedManifests.Count -eq 0) 'NESTED MANIFEST: NO'
        Check ((Compare-Object $ExpectedEntries $Names).Count -eq 0 -and $Names.Count -eq $ExpectedEntries.Count) 'exact ETHOS Suite ZIP structure'
        Check (-not ($Names | Where-Object { $_ -match '/' })) 'all package files at ZIP root'
        Check (-not ($Names | Where-Object { $_ -match '(^|/)\.git/|(^|/)tests?/|\.zip$|\.tmp$|\.bak$|\.orig$' })) 'no development or nested archive entries'
        Check (-not ($Names | Where-Object { $_ -like 'masks/*' })) 'optional pre-rasterized masks excluded'
        $MainEntry = $Archive.GetEntry('main.lua')
        $LogoEntry = $Archive.GetEntry('gib2a_logo_ethos_180.png')
        Check ($null -ne $MainEntry) 'main.lua at ZIP root'
        Check ($null -ne $LogoEntry) 'logo at ZIP root'
        if ($null -ne $MainEntry -and $null -ne $LogoEntry) {
            $MainStream = $MainEntry.Open(); $MainMemory = [IO.MemoryStream]::new()
            try { $MainStream.CopyTo($MainMemory) } finally { $MainStream.Dispose() }
            $LogoStream = $LogoEntry.Open(); $LogoMemory = [IO.MemoryStream]::new()
            try { $LogoStream.CopyTo($LogoMemory) } finally { $LogoStream.Dispose() }
            $Sha = [Security.Cryptography.SHA256]::Create()
            try {
                $MainHash = ([BitConverter]::ToString($Sha.ComputeHash($MainMemory.ToArray()))).Replace('-','')
                $LogoHash = ([BitConverter]::ToString($Sha.ComputeHash($LogoMemory.ToArray()))).Replace('-','')
            } finally { $Sha.Dispose(); $MainMemory.Dispose(); $LogoMemory.Dispose() }
            Check ($MainHash -eq $ExpectedHash) 'ZIP main.lua hash'
            Check ($LogoHash -eq $ExpectedLogoHash) 'ZIP logo hash'
        }
        if ($null -ne $ManifestEntry) {
            $ManifestReader = [IO.StreamReader]::new($ManifestEntry.Open(), [Text.Encoding]::UTF8)
            try { $EmbeddedManifest = $ManifestReader.ReadToEnd() | ConvertFrom-Json }
            finally { $ManifestReader.Dispose() }
            Check ($EmbeddedManifest.folder -eq $ExpectedInstallFolder) 'embedded manifest install folder'
            Check ($EmbeddedManifest.folder -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') 'embedded folder format'
            Check (-not $EmbeddedManifest.folder.Contains(' ')) 'embedded folder contains no space'
            Check ($EmbeddedManifest.folder -ne $TurbineInstallFolder) 'embedded folder does not collide with TURBINE'
            Check ($EmbeddedManifest.key -eq 'com.gib2a.ethos.power') 'embedded package key'
            Check ($EmbeddedManifest.manifestVersion -eq 1) 'embedded manifest version'
            Check ($EmbeddedManifest.name -eq 'GIB2A POWER - FrSky Neuron ESC Telemetry') 'embedded package name'
            Check ($EmbeddedManifest.version -eq '26.1.3') 'embedded package version'
            Check ((Compare-Object $ExpectedFiles @($EmbeddedManifest.files)).Count -eq 0 -and @($EmbeddedManifest.files).Count -eq $ExpectedFiles.Count) 'embedded manifest file list'
            $MissingManifestFiles = @($EmbeddedManifest.files | Where-Object { $null -eq $Archive.GetEntry([string]$_) })
            Check ($MissingManifestFiles.Count -eq 0) 'FILES RESOLVE FROM ZIP ROOT'
        }
    } finally { $Archive.Dispose() }
}

$ChecksumPath = Join-Path $Root 'releases\V26.1.3\SHA256SUMS.txt'
Check (Test-Path -LiteralPath $ChecksumPath) 'checksum file exists'
if ((Test-Path -LiteralPath $ChecksumPath) -and (Test-Path -LiteralPath $ZipPath)) {
    $ExpectedZipHash = ((Get-Content -Raw -LiteralPath $ChecksumPath).Trim() -split '\s+')[0]
    Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash -eq $ExpectedZipHash) 'ZIP checksum'
}

Write-Output 'LOCAL LUA MOCK CHECK: RUN AND REPORT SEPARATELY'
Write-Output 'ETHOS TARGET VALIDATION: 1 HZ MENU RESPONSIVENESS TEST REPORTED ON X20 PRO AW; FULL RELEASE BUILD VALIDATION STILL REQUIRED'
if ($Failures.Count -gt 0) { throw "Validation failed: $($Failures.Count) check(s)" }
Write-Output 'Result: PASS'
