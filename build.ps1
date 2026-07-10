param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$versionLine = Get-Content -LiteralPath "$repo/module.prop" |
    Where-Object { $_ -like 'version=*' } |
    Select-Object -First 1
$version = $versionLine.Substring('version='.Length)

if (-not $OutputPath) {
    $OutputPath = Join-Path $repo "Nethunter_for_KernelSU-$version.zip"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repo $OutputPath
}

$manifest = Join-Path $repo 'artifacts.sha256'
foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
        throw "Invalid checksum manifest line: $line"
    }
    $expected = $Matches[1]
    $relative = $Matches[2]
    $path = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required artifact is missing: $relative"
    }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Checksum mismatch: $relative"
    }
}

$members = @(
    'META-INF',
    'common',
    'data',
    'system',
    'tools',
    'action.sh',
    'artifacts.sha256',
    'customize.sh',
    'module.prop',
    'uninstall.sh',
    'kali-nethunter-rootfs-minimal-arm64.tar.xz'
)
$paths = foreach ($member in $members) {
    $path = Join-Path $repo $member
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required module member is missing: $member"
    }
    $path
}

Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
Compress-Archive -LiteralPath $paths -DestinationPath $OutputPath -CompressionLevel Optimal

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $required = @(
        'module.prop',
        'customize.sh',
        'action.sh',
        'uninstall.sh',
        'artifacts.sha256',
        'common/post-fs-data.sh',
        'common/service.sh',
        'data/app/NetHunter.apk',
        'data/app/NetHunterKeX.apk',
        'kali-nethunter-rootfs-minimal-arm64.tar.xz'
    )
    foreach ($entry in $required) {
        if ($entries -notcontains $entry) {
            throw "Built archive is missing: $entry"
        }
    }
    if ($entries -contains 'install.sh') {
        throw 'Built archive contains the obsolete install.sh entry'
    }
} finally {
    $archive.Dispose()
}

$digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash.ToLowerInvariant()
"Built: $OutputPath"
"SHA256: $digest"
