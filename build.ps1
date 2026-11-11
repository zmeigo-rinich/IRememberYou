<#
    I remember you! -- local build and release verification.

    One source of truth for the version: the git tag. The script writes that
    version into core/constants.lua and IRememberYou.txt, runs the same static
    checks as CI, and packages the addon so the archive root is the addon
    folder (IRememberYou/IRememberYou.txt).

    Usage:
        .\build.ps1 -Version 0.4.0      # write version, check, build a zip
        .\build.ps1                     # take the version from the tag on HEAD
        .\build.ps1 -VerifyOnly -NoZip  # CI: check only, never write

    The GitHub workflow runs -VerifyOnly, so a tag whose committed files do not
    match it fails before anything is published.
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$VerifyOnly,
    [switch]$NoZip,
    [string]$OutputPath,
    [string]$ReleaseNotesPath,
    [string]$LuacPath,
    [switch]$SkipLuaCheck
)

$ErrorActionPreference = 'Stop'

$RepoRoot      = $PSScriptRoot
$AddonName     = 'IRememberYou'
$ManifestPath  = Join-Path $RepoRoot "$AddonName.txt"
$ConstantsPath = Join-Path $RepoRoot 'core/constants.lua'
$ChangeLogPath = Join-Path $RepoRoot 'CHANGELOG.md'
$LangEnPath    = Join-Path $RepoRoot 'lang/en.lua'
$LangRuPath    = Join-Path $RepoRoot 'lang/ru.lua'

function Fail {
    param([string]$Message)
    throw "[release] $Message"
}

function Info {
    param([string]$Message)
    Write-Host "[release] $Message"
}

function Warn {
    param([string]$Message)
    Write-Host "[release] WARNING: $Message" -ForegroundColor Yellow
}

function Read-TextFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Fail "missing file: $Path" }
    return [IO.File]::ReadAllText($Path)
}

function Write-TextFile {
    param([string]$Path, [string]$Text)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-ManifestField {
    param([string]$Text, [string]$Name)
    $pattern = '(?m)^## ' + [regex]::Escape($Name) + ':[ \t]*([^\r\n]*)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { Fail "$AddonName.txt has no '## ${Name}:' line" }
    return $match.Groups[1].Value.Trim()
}

function Get-LuaVersion {
    param([string]$Text)
    $match = [regex]::Match($Text, '(?m)^IRY\.version[ \t]*=[ \t]*"([^"\r\n]*)"')
    if (-not $match.Success) { Fail 'core/constants.lua has no IRY.version assignment' }
    return $match.Groups[1].Value
}

function Get-TagVersion {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    # Windows PowerShell turns a native command's stderr into an error record;
    # a folder that is not a repository must be a "no tag" answer, not a crash.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $tags = & git -C $RepoRoot tag --points-at HEAD --list 'v*' 2>$null
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousErrorAction }
    if ($exitCode -ne 0 -or -not $tags) { return $null }
    return (@($tags)[0]).Trim().TrimStart('v')
}

function Resolve-Luac {
    if ($LuacPath) {
        if (-not (Test-Path -LiteralPath $LuacPath)) { Fail "-LuacPath not found: $LuacPath" }
        return (Resolve-Path -LiteralPath $LuacPath).Path
    }
    if ($env:LUAC -and (Test-Path -LiteralPath $env:LUAC)) { return $env:LUAC }

    # The project keeps a Windows Lua 5.1 next to the addon folder; CI installs
    # lua5.1 from apt, which provides luac5.1 on PATH.
    $candidates = @(
        (Join-Path $RepoRoot '..\..\Input\lua-5.1.5_Win64_bin\luac5.1.exe'),
        (Join-Path $RepoRoot '..\..\Input\lua-5.1.5_Win64_bin\luac5.1'),
        (Join-Path $RepoRoot '..\Input\lua-5.1.5_Win64_bin\luac5.1.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    foreach ($name in @('luac5.1', 'luac')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    Fail 'luac not found. Install Lua 5.1, put it on PATH, pass -LuacPath, or use -SkipLuaCheck.'
}

function Get-LangKeys {
    param([string]$Path)
    $text = Read-TextFile $Path
    $keys = @()
    foreach ($match in [regex]::Matches($text, '(?m)^[ \t]*([A-Z][A-Z0-9_]*)[ \t]*=')) {
        $keys += $match.Groups[1].Value
    }
    return @($keys | Sort-Object -Unique)
}

function Get-HelpLineCount {
    param([string]$Path)
    $text = Read-TextFile $Path
    $match = [regex]::Match($text, '(?ms)^[ \t]*HELP[ \t]*=[ \t]*\{(?<body>.*?)^[ \t]*\},')
    if (-not $match.Success) { Fail "no HELP table in $Path" }
    $lines = @($match.Groups['body'].Value -split "\r?\n" | Where-Object { $_ -match '"' })
    return $lines.Count
}

function Invoke-StaticChecks {
    $luaFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.lua' |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
    $xmlFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.xml' |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })

    if (-not $SkipLuaCheck) {
        $luac = Resolve-Luac
        $failed = @()
        foreach ($file in $luaFiles) {
            $output = & $luac -p $file.FullName 2>&1
            if ($LASTEXITCODE -ne 0) { $failed += "$($file.Name): $output" }
        }
        if ($failed.Count -gt 0) { Fail ("luac -p failed:`n  " + ($failed -join "`n  ")) }
        Info "luac -p: $($luaFiles.Count) Lua files OK ($luac)"
    }

    foreach ($file in $xmlFiles) {
        try { $null = [xml](Read-TextFile $file.FullName) }
        catch { Fail "XML parse error in $($file.FullName): $($_.Exception.Message)" }
    }
    Info "XML: $($xmlFiles.Count) files well-formed"

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $textFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
        Where-Object { $_.Extension -in @('.lua', '.xml', '.txt', '.md') -and $_.FullName -notmatch '[\\/]\.git[\\/]' })
    foreach ($file in $textFiles) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Fail "UTF-8 BOM found in $($file.FullName); the game's Lua parser rejects it"
        }
        try { $null = $strictUtf8.GetString($bytes) }
        catch { Fail "not valid UTF-8: $($file.FullName)" }
    }
    Info "encoding: $($textFiles.Count) text files are UTF-8 without BOM"

    $enKeys = Get-LangKeys $LangEnPath
    $ruKeys = Get-LangKeys $LangRuPath
    if ($enKeys.Count -lt 50) { Fail "lang/en.lua exposes only $($enKeys.Count) keys; the parser probably stopped matching" }
    $difference = @(Compare-Object -ReferenceObject $enKeys -DifferenceObject $ruKeys)
    if ($difference.Count -gt 0) {
        $details = @($difference | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
        Fail ("EN/RU key mismatch:`n  " + ($details -join "`n  "))
    }
    $enHelp = Get-HelpLineCount $LangEnPath
    $ruHelp = Get-HelpLineCount $LangRuPath
    if ($enHelp -ne $ruHelp) { Fail "HELP line count differs: en=$enHelp ru=$ruHelp" }
    Info "lang: $($enKeys.Count) keys in EN and RU, HELP has $enHelp lines in both"

    $used = @()
    foreach ($file in $luaFiles) {
        $text = Read-TextFile $file.FullName
        foreach ($match in [regex]::Matches($text, 'IRY\.L\.([A-Z][A-Z0-9_]*)')) {
            $used += $match.Groups[1].Value
        }
    }
    $used = @($used | Sort-Object -Unique)
    $missing = @($used | Where-Object { $enKeys -notcontains $_ })
    if ($missing.Count -gt 0) { Fail "IRY.L keys used but not defined: $($missing -join ', ')" }
    $unused = @($enKeys | Where-Object { $used -notcontains $_ })
    if ($unused.Count -gt 0) { Warn "defined but never used: $($unused -join ', ')" }
    Info "lang: every IRY.L key used in code is defined"

    $manifest = Read-TextFile $ManifestPath
    foreach ($line in ($manifest -split "\r?\n")) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('##')) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $entry))) {
            Fail "manifest lists a missing file: $entry"
        }
    }
    if (-not [regex]::IsMatch($manifest, '(?m)^## APIVersion:')) { Warn 'manifest has no ## APIVersion line' }
    Info 'manifest: every load-order entry exists'
}

function New-AddonZip {
    param([string]$DestinationDirectory, [string]$Version)

    if (-not $DestinationDirectory) {
        # The zip belongs next to the addon folder, not inside it: in this
        # project the addon lives in Output/IRememberYou, so the archive lands
        # in Output/.
        $DestinationDirectory = Split-Path -Parent $RepoRoot
    }
    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    }
    $zipPath = Join-Path $DestinationDirectory "$AddonName-$Version.zip"

    $stageParent = Join-Path ([IO.Path]::GetTempPath()) ("iry-build-" + [Guid]::NewGuid().ToString('N'))
    $stage = Join-Path $stageParent $AddonName
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    try {
        $excluded = @('.git', '.github', '.gitignore', '.gitattributes', 'build.ps1')
        Get-ChildItem -LiteralPath $RepoRoot -Force |
            Where-Object { $excluded -notcontains $_.Name } |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stage -Recurse -Force }

        Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

        # Entries are written by hand instead of CreateFromDirectory: on
        # Windows PowerShell that API stores backslash separators, which Linux
        # unzip tools read as part of the file name.
        $zipStream = [IO.File]::Open($zipPath, [IO.FileMode]::Create)
        try {
            $archive = [System.IO.Compression.ZipArchive]::new(
                $zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)
                foreach ($file in $files) {
                    $relative = $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
                    $entry = $archive.CreateEntry(
                        "$AddonName/$relative", [IO.Compression.CompressionLevel]::Optimal)
                    $entryStream = $entry.Open()
                    try {
                        $fileStream = [IO.File]::OpenRead($file.FullName)
                        try { $fileStream.CopyTo($entryStream) }
                        finally { $fileStream.Dispose() }
                    }
                    finally { $entryStream.Dispose() }
                }
            }
            finally { $archive.Dispose() }
        }
        finally { $zipStream.Dispose() }

        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try { $entries = @($archive.Entries | ForEach-Object { $_.FullName }) }
        finally { $archive.Dispose() }

        $manifestEntry = "$AddonName/$AddonName.txt"
        if ($entries -notcontains $manifestEntry) { Fail "zip has no $manifestEntry at its root" }
        $leaked = @($entries | Where-Object { $_ -match '(^|/)(\.git|\.github|\.gitignore|\.gitattributes|build\.ps1)(/|$)' })
        if ($leaked.Count -gt 0) { Fail "zip contains development files: $($leaked -join ', ')" }
    }
    finally {
        if (Test-Path -LiteralPath $stageParent) { Remove-Item -LiteralPath $stageParent -Recurse -Force }
    }

    $sizeKb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1KB, 1)
    Info "zip: $zipPath ($sizeKb KB, $($entries.Count) entries, root $AddonName/)"
    return $zipPath
}

function Write-ReleaseNotes {
    param([string]$Version, [string]$Destination)

    $text = Read-TextFile $ChangeLogPath
    $pattern = '(?ms)^## \[' + [regex]::Escape($Version) + '\][^\r\n]*\r?\n(?<body>.*?)(?=^## \[|\z)'
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) { Fail "CHANGELOG.md has no '## [$Version]' section" }
    $body = $match.Groups['body'].Value.Trim()
    if (-not $body) { Fail "CHANGELOG.md section '## [$Version]' is empty" }

    $directory = Split-Path -Parent $Destination
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Write-TextFile $Destination $body
    Info "release notes for $Version written to $Destination"
}

# --- version -------------------------------------------------------------

$tagVersion = Get-TagVersion
if (-not $Version) { $Version = $tagVersion }
if (-not $Version) {
    $Version = Get-ManifestField (Read-TextFile $ManifestPath) 'Version'
    Info "no -Version and no tag on HEAD; using the manifest version $Version"
}
$Version = $Version.Trim().TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "version '$Version' is not x.y.z" }

$parts = $Version.Split('.')
$major = [int]$parts[0]
$minor = [int]$parts[1]
$patch = [int]$parts[2]
if ($major -gt 9999 -or $minor -gt 99 -or $patch -gt 99) {
    Fail "version '$Version' does not fit the AddOnVersion formula (major<=9999, minor/patch<=99)"
}
$addOnVersion = [string]($major * 10000 + $minor * 100 + $patch)

$manifestText  = Read-TextFile $ManifestPath
$constantsText = Read-TextFile $ConstantsPath
$currentVersion  = Get-ManifestField $manifestText 'Version'
$currentAddOn    = Get-ManifestField $manifestText 'AddOnVersion'
$currentLua      = Get-LuaVersion $constantsText

if ($VerifyOnly) {
    $problems = @()
    if ($currentVersion -ne $Version) {
        $problems += "IRememberYou.txt ## Version: is '$currentVersion', expected '$Version'"
    }
    if ($currentLua -ne $Version) {
        $problems += "core/constants.lua IRY.version is '$currentLua', expected '$Version'"
    }
    if ($currentAddOn -ne $addOnVersion) {
        $problems += "IRememberYou.txt ## AddOnVersion: is '$currentAddOn', expected '$addOnVersion'"
    }
    if ($problems.Count -gt 0) {
        Fail ("version metadata does not match the tag:`n  " + ($problems -join "`n  ") +
            "`nRun .\build.ps1 -Version $Version and commit the result, then move the tag.")
    }
    Info "version: $Version (AddOnVersion $addOnVersion) is consistent"
}
else {
    if ($currentLua -ne $Version) {
        $pattern = '(?m)^(IRY\.version[ \t]*=[ \t]*")[^"\r\n]*(")'
        if ([regex]::Matches($constantsText, $pattern).Count -ne 1) {
            Fail 'core/constants.lua: expected exactly one IRY.version line'
        }
        $constantsText = [regex]::Replace($constantsText, $pattern, ('${1}' + $Version + '${2}'))
        Write-TextFile $ConstantsPath $constantsText
        Info "updated core/constants.lua: IRY.version = $Version"
    }
    if ($currentVersion -ne $Version -or $currentAddOn -ne $addOnVersion) {
        $versionPattern = '(?m)^(## Version:[ \t]*)[^\r\n]*'
        $addOnPattern = '(?m)^(## AddOnVersion:[ \t]*)[^\r\n]*'
        if ([regex]::Matches($manifestText, $versionPattern).Count -ne 1 -or
            [regex]::Matches($manifestText, $addOnPattern).Count -ne 1) {
            Fail "$AddonName.txt: expected exactly one '## Version:' and one '## AddOnVersion:' line"
        }
        $manifestText = [regex]::Replace($manifestText, $versionPattern, ('${1}' + $Version))
        $manifestText = [regex]::Replace($manifestText, $addOnPattern, ('${1}' + $addOnVersion))
        Write-TextFile $ManifestPath $manifestText
        Info "updated $AddonName.txt: ## Version: $Version, ## AddOnVersion: $addOnVersion"
    }
    if ($currentLua -eq $Version -and $currentVersion -eq $Version -and $currentAddOn -eq $addOnVersion) {
        Info "version: $Version (AddOnVersion $addOnVersion) already up to date"
    }
}

# --- checks and packaging ------------------------------------------------

Invoke-StaticChecks

if ($ReleaseNotesPath) { Write-ReleaseNotes -Version $Version -Destination $ReleaseNotesPath }

if ($NoZip) {
    Info "done (no zip requested)"
    return
}

$zipPath = New-AddonZip -DestinationDirectory $OutputPath -Version $Version
Info "done: $zipPath"
