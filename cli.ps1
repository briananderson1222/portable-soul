# Portable Soul CLI (PowerShell)
# For users without Node.js — downloads templates from GitHub.
#
# Usage:
#   .\cli.ps1                # Install
#   .\cli.ps1 -Update        # Update soul-protocol.md to latest
#   .\cli.ps1 -Dir "C:\path" # Install to custom directory
#   .\cli.ps1 -Config FILE   # Use custom config
#   .\cli.ps1 -Symlinks       # Show path status
#   .\cli.ps1 -Symlinks -Sync   # Sync paths
#   .\cli.ps1 -Symlinks -Remove  # Remove paths
#   .\cli.ps1 -DryRun        # Show what would happen without making changes
#   .\cli.ps1 -Mode MODE     # Override link mode (symlink/copy)
#   .\cli.ps1 -Provider PROV # Override sync provider (copy/rsync/git-sync)
#   .\cli.ps1 -Direction DIR # Override sync direction
#   .\cli.ps1 -Help          # Show help

param(
    [switch]$Update,
    [switch]$Help,
    [string]$Dir,
    [switch]$Symlinks,
    [switch]$Sync,
    [switch]$Remove,
    [string]$Config,
    [switch]$DryRun,
    [string]$Mode,
    [string]$Provider,
    [string]$Direction
)

# ── Config ───────────────────────────────────────────────────

$REPO_RAW = "https://raw.githubusercontent.com/briananderson-xyz/portable-soul/main"
$DEFAULT_SOUL_DIR = Join-Path $env:USERPROFILE ".soul"
$CONFIG_DIR = Join-Path $DEFAULT_SOUL_DIR ".config"

# Global sync options
$script:GlobalDryRun = $false
$script:GlobalConfig = @{}

$SYSTEM_FILES = @("soul-protocol.md")
$SEED_FILES = @(
    "identity.md", "soul.md", "user.md", "system.md", "memory.md",
    "lessons.md", "preferences.md", "decisions.md", "continuity.md",
    "followups.md", "bookmarks.md"
)

# ── Colors ───────────────────────────────────────────────────

$esc = [char]27
$colors = @{
    Reset  = "$esc[0m"
    Bright = "$esc[1m"
    Dim    = "$esc[2m"
    Green  = "$esc[32m"
    Blue   = "$esc[34m"
    Yellow = "$esc[33m"
    Cyan   = "$esc[36m"
    Red    = "$esc[31m"
}

function c($str, $color) {
    return "$($colors.$color)$str$($colors.Reset)"
}

# ── Helpers ─────────────────────────────────────────────────────

function Expand-Home($path) {
    return $path -replace '^~/', $env:USERPROFILE
}

function Test-Path($path) {
    return Test-Path $path
}

function EnsureDir($dir) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-File($path, $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -Path $path -Value $content -NoNewline
}

# ── Config loading ─────────────────────────────────────────────

function Get-ConfigPath($customPath) {
    if ($customPath) { return $customPath }

    $hostname = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        $hostname = $env:USERNAME
    }

    $machineConfig = Join-Path $CONFIG_DIR "$hostname.toml"
    $defaultConfig = Join-Path $CONFIG_DIR "default.toml"

    if (Test-Path $machineConfig) { return $machineConfig }
    if (Test-Path $defaultConfig) { return $defaultConfig }
    return $null
}

function Get-Config($configPath) {
    if (-not (Test-Path $configPath)) {
        Log-Message "Config not found: $configPath" "error"
        exit 1
    }

    try {
        $content = Get-Content $configPath -Raw
        return Parse-Toml $content
    } catch {
        return @{}
    }
}

# Simple TOML parser
function Parse-Toml($content) {
    $result = @{}
    $currentSection = $null

    $lines = $content -split "`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        $sectionMatch = $trimmed -match '^\[(.+)\]$'
        if ($sectionMatch) {
            $currentSection = $sectionMatch[1].Trim()
            $result[$currentSection] = @{}
            continue
        }
        if (-not $currentSection) { continue }

        if ($trimmed.StartsWith('#') -or [string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $equalIdx = $trimmed.IndexOf('=')
        if ($equalIdx -eq -1) { continue }

        $key = $trimmed.Substring(0, $equalIdx).Trim()
        $value = $trimmed.Substring($equalIdx + 1).Trim()

        # Array values: "item" = ["one", "two"]
        $arrayMatch = $value -match '^\[(.+)\]$'
        if ($arrayMatch) {
            $value = $arrayMatch[1].Split(',') | ForEach-Object {
                $_.Trim() -replace '^["'']?["'']?$', ''
            }
        }
        # Boolean values
        elseif ($value -eq 'true') {
            $value = $true
        }
        elseif ($value -eq 'false') {
            $value = $false
        }
        # String values: remove quotes
        elseif ($value.StartsWith('"') -or $value.StartsWith("'")) {
            $value = $value.Substring(1, $value.Length - 1)
        }

        $result[$currentSection][$key] = $value
    }

    return $result
}

# Set dry run flag
function Set-DryRun([bool]$enabled) {
    $script:GlobalDryRun = $enabled
    if ($enabled) {
        Log-Message "$(c 'DRY RUN: No changes will be made' 'Yellow')" "warn"
    }
}

function Get-DryRun() {
    return $script:GlobalDryRun
}

# Set global config
function Set-Config($config) {
    $script:GlobalConfig = $config
}

function Get-Config() {
    return $script:GlobalConfig
}

# Get link mode from config
function Get-LinkMode() {
    $config = Get-Config
    if ($config.ContainsKey('sync') -and $config['sync'].ContainsKey('link_mode')) {
        return $config['sync']['link_mode']
    }
    return 'symlink'
}

function Should-UseCopy() {
    return (Get-LinkMode) -eq 'copy'
}

# Path matching for excludes and wildcards
function Test-MatchPattern($filePath, $pattern) {
    $pattern = Expand-Home $pattern

    # Handle **/* patterns
    if ($pattern -match '\*\*') {
        $regex = $pattern -replace '\*\*', '.*' -replace '\*', '[^/]*'
        $regex = "^$regex$"
        return $filePath -match $regex
    }

    # Handle simple wildcard
    if ($pattern -match '\*') {
        $baseDir = Split-Path $pattern -Parent
        if (-not $baseDir) { $baseDir = "." }
        $patternName = [System.IO.Path]::GetFileName($pattern) -replace '\*', '[^/]*'
        $regex = "^$([System.IO.Path]::GetFullPath($baseDir))/$patternName$"
        return $filePath -match $regex
    }

    # Exact match
    return $filePath -eq $pattern
}

function Test-Excluded($filePath, $excludePatterns) {
    if (-not $excludePatterns -or $excludePatterns.Count -eq 0) { return $false }
    $absPath = Resolve-Path $filePath -ErrorAction SilentlyContinue
    if (-not $absPath) { $absPath = $filePath }

    foreach ($pattern in $excludePatterns) {
        if (Test-MatchPattern $absPath $pattern) {
            return $true
        }
    }
    return $false
}

# Sync providers
function Sync-Rsync($source, $target, $direction = 'source-to-target', $options = @{}) {
    $dryRun = if ($options.ContainsKey('dryRun')) { $options['dryRun'] } else { Get-DryRun }
    $exclude = if ($options.ContainsKey('exclude')) { $options['exclude'] } else { @() }

    if (-not (Test-Path $source)) {
        Log-Message "Source does not exist: $source" "error"
        return $false
    }

    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $excludeArgs = ""
    foreach ($pattern in $exclude) {
        $excludeArgs += " --exclude='$pattern'"
    }

    $rsyncCmd = ""
    switch ($direction) {
        'source-to-target' {
            $rsyncCmd = "rsync -av --update$excludeArgs `"$source/`" `"$target`""
        }
        'target-to-source' {
            $rsyncCmd = "rsync -av --update$excludeArgs `"$target/`" `"$source`""
        }
        'bidirectional' {
            Log-Message "Bidirectional rsync: syncing newer files in both directions" "info"
            $forward = "rsync -av --update$excludeArgs `"$source/`" `"$target`""
            $backward = "rsync -av --update$excludeArgs `"$target/`" `"$source`""
            if (-not $dryRun) {
                try {
                    Invoke-Expression $forward | Out-Null
                    Invoke-Expression $backward | Out-Null
                } catch {
                    Log-Message "Rsync failed: $_" "error"
                    return $false
                }
            } else {
                Log-Message "[DRY RUN] Would run: $forward" "info"
                Log-Message "[DRY RUN] Would run: $backward" "info"
            }
            return $true
        }
        default {
            Log-Message "Invalid direction: $direction" "error"
            return $false
        }
    }

    if ($dryRun) {
        Log-Message "[DRY RUN] Would run: $rsyncCmd" "info"
        return $true
    }

    try {
        Invoke-Expression $rsyncCmd | Out-Null
        return $true
    } catch {
        Log-Message "Rsync failed: $_" "error"
        return $false
    }
}

function Sync-Copy($source, $target, $direction = 'source-to-target', $options = @{}) {
    $dryRun = if ($options.ContainsKey('dryRun')) { $options['dryRun'] } else { Get-DryRun }
    $exclude = if ($options.ContainsKey('exclude')) { $options['exclude'] } else { @() }

    if (-not (Test-Path $source)) {
        Log-Message "Source does not exist: $source" "error"
        return $false
    }

    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    function Copy-Directory($src, $dst) {
        if (Test-Path $src -PathType Container) {
            if (-not (Test-Path $dst)) {
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
            }
            Get-ChildItem $src -Force | ForEach-Object {
                if (Test-Excluded $_.FullName $exclude) { return }
                Copy-Directory $_.FullName (Join-Path $dst $_.Name)
            }
        } else {
            if (Test-Excluded $src $exclude) { return }

            $srcStat = Get-Item $src -Force
            if (-not (Test-Path $dst)) {
                if (-not $dryRun) { Copy-Item $src $dst -Force }
            } elseif ($srcStat.LastWriteTime -gt (Get-Item $dst -Force).LastWriteTime) {
                if (-not $dryRun) { Copy-Item $src $dst -Force }
            }
        }
    }

    switch ($direction) {
        'bidirectional' {
            Log-Message "Bidirectional copy: syncing newer files in both directions" "info"
            if (-not $dryRun) {
                $tempDir1 = Join-Path $env:TEMP "soul-sync-$([DateTimeOffset]::Now.ToUnixTimeSeconds())-1"
                $tempDir2 = Join-Path $env:TEMP "soul-sync-$([DateTimeOffset]::Now.ToUnixTimeSeconds())-2"
                try {
                    New-Item -ItemType Directory -Path $tempDir1 -Force | Out-Null
                    New-Item -ItemType Directory -Path $tempDir2 -Force | Out-Null
                    Copy-Item $source $tempDir1 -Recurse -Force
                    Copy-Item $target $tempDir2 -Recurse -Force
                    Copy-Directory $tempDir1 $target
                    Copy-Directory $tempDir2 $source
                } finally {
                    Remove-Item $tempDir1 -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item $tempDir2 -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                Log-Message "[DRY RUN] Would bidirectionally sync $source <-> $target" "info"
            }
            return $true
        }
        default {
            $src, $dst = if ($direction -eq 'source-to-target') { $source, $target } else { $target, $source }
            Copy-Directory $src $dst
            return $true
        }
    }
}

function Sync-Git($source, $target, $direction = 'source-to-target', $options = @{}) {
    $dryRun = if ($options.ContainsKey('dryRun')) { $options['dryRun'] } else { Get-DryRun }
    $exclude = if ($options.ContainsKey('exclude')) { $options['exclude'] } else { @() }

    Log-Message "Git-sync mode: Using git to track and sync changes" "info"

    if (-not (Test-Path $source)) {
        Log-Message "Source does not exist: $source" "error"
        return $false
    }

    $targetDir = Split-Path $target -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (-not (Test-Path $target)) {
        if (-not $dryRun) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            git -C $target init 2>$null | Out-Null
            git -C $target commit --allow-empty -m "Initial commit" 2>$null | Out-Null
        }
    }

    switch ($direction) {
        'bidirectional' {
            Log-Message "Bidirectional git-sync: merge changes between repos" "info"
            if (-not $dryRun) {
                try {
                    git -C $target remote add soul-source $source 2>$null | Out-Null
                    git -C $target fetch soul-source 2>$null | Out-Null
                    git -C $target merge soul-source/main -X theirs --no-edit 2>$null | Out-Null
                } catch {
                    Log-Message "Git-sync warning: $_" "warn"
                }
            } else {
                Log-Message "[DRY RUN] Would bidirectionally git-sync $source <-> $target" "info"
            }
        }
        default {
            $src, $dst = if ($direction -eq 'source-to-target') { $source, $target } else { $target, $source }
            if (-not $dryRun) {
                try {
                    git -C $dst remote add soul-source $src 2>$null | Out-Null
                    git -C $dst fetch soul-source 2>$null | Out-Null
                    git -C $dst merge soul-source/main -X theirs --no-edit 2>$null | Out-Null
                } catch {
                    Log-Message "Git-sync warning: $_" "warn"
                }
            } else {
                Log-Message "[DRY RUN] Would git-sync $src -> $dst" "info"
            }
        }
    }

    return $true
}

function Invoke-Sync($source, $target, $syncConfig) {
    $provider = if ($syncConfig.ContainsKey('provider')) { $syncConfig['provider'] } else { 'copy' }
    $direction = if ($syncConfig.ContainsKey('direction')) { $syncConfig['direction'] } else { 'source-to-target' }
    $exclude = if ($syncConfig.ContainsKey('exclude')) { $syncConfig['exclude'] } else { @() }

    if (Test-Excluded $source $exclude) {
        Log-Message "Source excluded by pattern: $source" "info"
        return $true
    }

    $options = @{ dryRun = Get-DryRun; exclude = $exclude }

    switch ($provider) {
        'rsync' {
            return Sync-Rsync $source $target $direction $options
        }
        'git-sync' {
            return Sync-Git $source $target $direction $options
        }
        'copy' {
            return Sync-Copy $source $target $direction $options
        }
        default {
            return Sync-Copy $source $target $direction $options
        }
    }
}

function Get-SymlinkConfig($soulDir) {
    $configPath = Get-ConfigPath $null
    if (-not $configPath) { return @{} }

    $paths = @{}
    $config = Get-Config $configPath
    if ($config.ContainsKey('paths')) {
        $paths = $config['paths']
    }
    return $paths
}

# ── Symlink management ─────────────────────────────────────

function Get-SymlinkStatus($source, $target, $soulDir) {
    if (-not (Test-Path $target)) {
        return @{ status = 'missing'; message = "$(c '-> new' 'Blue')" }
    }
    if (-not (Test-Path $source)) {
        return @{ status = 'source-missing'; message = "$(c 'x source missing' 'Red')" }
    }

    # If using copy mode, check if files match
    if (Should-UseCopy) {
        if (Test-Path $target -PathType Container) {
            return @{ status = 'directory'; message = "$(c '- directory' 'Dim')" }
        }
        try {
            $srcContent = Get-Content $source -Raw -AsByteStream
            $tgtContent = Get-Content $target -Raw -AsByteStream
            if ([System.Linq.Enumerable]::SequenceEqual($srcContent, $tgtContent)) {
                return @{ status = 'ok'; message = "$(c '+ copy ok' 'Green')" }
            }
            return @{ status = 'mismatch'; message = "$(c '- copy outdated' 'Yellow')" }
        } catch {
            return @{ status = 'error'; message = "$(c 'x copy error' 'Red')" }
        }
    }

    $item = Get-Item $target -Force
    if ($item.TargetType -eq 'SymbolicLink') {
        $linkTarget = $item.Target
        $absLink = Join-Path (Split-Path $target) $linkTarget
        $absSource = Join-Path $soulDir $source

        if ($absLink -eq $absSource) {
            return @{ status = 'ok'; message = "$(c '+ ok' 'Green')" }
        }
        return @{ status = 'mismatch'; message = "$(c 'x wrong target' 'Red')" }
    }
    return @{ status = 'file-not-link'; message = "$(c '- not a symlink' 'Dim')" }
}

function New-Symlink($source, $target, $soulDir) {
    $sourceAbs = Join-Path $soulDir $source
    $targetAbs = Resolve-Path $target -ErrorAction SilentlyContinue
    if (-not $targetAbs) { $targetAbs = $target }
    $targetDir = Split-Path $targetAbs -Parent

    EnsureDir $targetDir

    # If using copy mode, copy file/directory
    if (Should-UseCopy) {
        try {
            if (-not (Get-DryRun)) {
                if (Test-Path $sourceAbs -PathType Container) {
                    Copy-Item $sourceAbs $targetAbs -Recurse -Force
                } else {
                    Copy-Item $sourceAbs $targetAbs -Force
                }
                Log-Message "Copied: $source → $target" "success"
            } else {
                Log-Message "[DRY RUN] Would copy: $source → $target" "info"
            }
            return $true
        } catch {
            Log-Message "Failed to copy: $_" "error"
            return $false
        }
    }

    # Symlink mode
    try {
        Remove-Item $targetAbs -Force -ErrorAction Stop
    } catch { }

    try {
        if (-not (Get-DryRun)) {
            New-Item -ItemType SymbolicLink -Path $targetAbs -Value $sourceAbs | Out-Null
        } else {
            Log-Message "[DRY RUN] Would create symlink: $sourceAbs → $targetAbs" "info"
        }
        return $true
    } catch {
        Log-Message "Failed to create symlink: $_" "error"
        return $false
    }
}

function Show-SymlinkStatus($soulDir) {
    $config = Get-SymlinkConfig $soulDir
    $globalCfg = Get-Config
    $syncConfig = if ($globalCfg.ContainsKey('sync')) { $globalCfg['sync'] } else { @{} }

    $sources = $config.Keys

    if ($sources.Count -eq 0) {
        Log-Message "No paths configured" "info"
        $defaultPath = Join-Path $CONFIG_DIR "default.toml"
        Write-Host "  Edit $defaultPath to add [paths]"
        Write-Host ""
        return
    }

    Log-Message "Path status:" "info"
    Write-Host ""

    $linkMode = if ($syncConfig.ContainsKey('link_mode')) { $syncConfig['link_mode'] } else { 'symlink' }
    Write-Host "  Mode: $(c $linkMode 'Cyan')"
    if ($syncConfig.ContainsKey('auto_sync') -and $syncConfig['auto_sync']) {
        Write-Host "  Auto-sync: $(c 'enabled' 'Green')"
    }
    if ($syncConfig.ContainsKey('provider') -and $syncConfig['provider'] -ne 'copy') {
        Write-Host "  Sync provider: $(c $syncConfig['provider'] 'Cyan')"
        $direction = if ($syncConfig.ContainsKey('direction')) { $syncConfig['direction'] } else { 'source-to-target' }
        Write-Host "  Sync direction: $(c $direction 'Cyan')"
    }
    Write-Host ""

    foreach ($source in $sources) {
        $sourceAbs = Join-Path $soulDir $source
        $targets = $config[$source]

        if ($targets -is [string]) {
            $targets = @($targets)
        }

        $status = Get-SymlinkStatus $sourceAbs (Expand-Home $targets[0]) $soulDir
        Write-Host "  $(c $source 'Bright')"
        Write-Host "    $($status.message)"

        if ($targets.Count -gt 1) {
            Write-Host "    targets:"
            for ($i = 0; $i -lt $targets.Count; $i++) {
                $abs = Expand-Home $targets[$i]
                $isCurrent = if ($i -eq 0) { ' (current)' } else { '' }
                Write-Host "      $(c $abs 'Dim')$isCurrent"
            }
        }
        Write-Host ""
    }

    if ($syncConfig.ContainsKey('exclude') -and $syncConfig['exclude'].Count -gt 0) {
        $excludeCount = if ($syncConfig['exclude'] -is [array]) { $syncConfig['exclude'].Count } else { 1 }
        Log-Message "Excludes: $excludeCount pattern(s)" "info"
        $excludes = $syncConfig['exclude']
        if ($excludes -is [string]) { $excludes = @($excludes) }
        foreach ($pattern in $excludes) {
            Write-Host "    $(c $pattern 'Dim')"
        }
        Write-Host ""
    }
}

function Sync-Symlinks($soulDir) {
    $config = Get-SymlinkConfig $soulDir
    $globalCfg = Get-Config
    $syncConfig = if ($globalCfg.ContainsKey('sync')) { $globalCfg['sync'] } else { @{} }

    $sources = $config.Keys

    if ($sources.Count -eq 0) {
        Log-Message "No paths configured" "info"
        $defaultPath = Join-Path $CONFIG_DIR "default.toml"
        Write-Host "  Edit $defaultPath to add [paths]"
        Write-Host ""
        return
    }

    $linkMode = if ($syncConfig.ContainsKey('link_mode')) { $syncConfig['link_mode'] } else { 'symlink' }
    $syncProvider = if ($syncConfig.ContainsKey('provider')) { $syncConfig['provider'] } else { $null }
    $syncDirection = if ($syncConfig.ContainsKey('direction')) { $syncConfig['direction'] } else { 'source-to-target' }
    $exclude = if ($syncConfig.ContainsKey('exclude')) { $syncConfig['exclude'] } else { @() }

    Write-Host ""
    Log-Message "Sync mode: $(c $linkMode 'Cyan')" "info"
    if ($syncProvider) {
        Log-Message "Sync provider: $(c $syncProvider 'Cyan'), direction: $(c $syncDirection 'Cyan')" "info"
    }
    if ($exclude.Count -gt 0) {
        $excludeCount = if ($exclude -is [array]) { $exclude.Count } else { 1 }
        Log-Message "Excludes: $excludeCount pattern(s)" "info"
    }
    Write-Host ""

    $created = 0
    $updated = 0
    $failed = 0

    foreach ($source in $sources) {
        $sourceAbs = Join-Path $soulDir $source
        $targets = $config[$source]

        if ($targets -is [string]) {
            $targets = @($targets)
        }

        if (-not (Test-Path $sourceAbs)) {
            Log-Message "Source missing: $source" "error"
            $failed++
            continue
        }

        foreach ($target in $targets) {
            $targetAbs = Resolve-Path $target -ErrorAction SilentlyContinue
            if (-not $targetAbs) { $targetAbs = $target }
            $status = Get-SymlinkStatus $sourceAbs $targetAbs $soulDir

            # Skip if already OK
            if ($status.status -eq 'ok') { continue }

            # If using sync provider, do sync instead of symlink
            if ($syncProvider) {
                $result = Invoke-Sync $sourceAbs $targetAbs @{
                    provider = $syncProvider
                    direction = $syncDirection
                    exclude = $exclude
                }
                if ($result) {
                    $updated++
                    Log-Message "Synced: $(c $source 'Bright') $(c '↔' 'Dim') $(c $targetAbs 'Dim')" "success"
                } else {
                    $failed++
                }
            } else {
                # Use symlink or copy
                if (New-Symlink $source $target $soulDir) {
                    $action = if ($linkMode -eq 'copy') { 'Copied' } else { 'Created symlink' }
                    $created++
                    Log-Message "$action : $(c $source 'Bright') → $(c $targetAbs 'Dim')" "success"
                } else {
                    $failed++
                }
            }
        }
    }

    Write-Host ""
    $action = if ($linkMode -eq 'copy') { 'Copied' } else { 'Created' }
    if ($created -gt 0) { Log-Message "$action $created path(s)" "success" }
    if ($updated -gt 0) { Log-Message "Synced $updated path(s)" "success" }
    if ($failed -gt 0) { Log-Message "Failed $failed path(s)" "error" }
}

function Remove-Symlinks($soulDir) {
    $config = Get-SymlinkConfig $soulDir
    $sources = $config.Keys

    if ($sources.Count -eq 0) {
        Log-Message "No symlinks configured" "info"
        return
    }

    $confirm = Read-Question "Remove all symlinks?" "y/N"
    if ($confirm -ne 'y' -and $confirm -ne 'yes') {
        Log-Message "Cancelled" "info"
        return
    }

    $removed = 0
    foreach ($source in $sources) {
        $targets = $config[$source]

        if ($targets -is [string]) {
            $targets = @($targets)
        }

        foreach ($target in $targets) {
            $targetAbs = Resolve-Path $target
            if (Test-Path $targetAbs) {
                try {
                    $item = Get-Item $targetAbs -Force
                    if ($item.TargetType -eq 'SymbolicLink') {
                        Remove-Item $targetAbs -Force | Out-Null
                        $removed++
                        Log-Message "Removed: $(c $targetAbs 'Dim')" "info"
                    }
                } catch { }
            }
        }
    }

    Write-Host ""
    Log-Message "Removed $removed symlink(s)" "success"
}

function Write-DefaultConfig($soulDir) {
    $configPath = Join-Path $CONFIG_DIR "default.toml"
    if (Test-Path $configPath) {
        Log-Message "Config already exists" "info"
        return
    }

    EnsureDir $CONFIG_DIR

    $content = @"
# Portable Soul Configuration
# ~/.soul/.config/default.toml is used if no machine-specific config exists
# Create ~/.soul/.config/`${env:COMPUTERNAME}.toml for per-machine overrides

[paths]
# Path mappings: source file in .soul/ → target location
# Arrays support multiple targets for the same source
# Paths support ~ expansion
# The sync mode (symlink/copy) is controlled by [sync.link_mode]

"soul-protocol.md" = [
    "~/.claude/rules",
    "~/Documents/soul-protocol.md"
]

"identity.md" = "~/.cursorrules"

# Example: map knowledge directory to cloud storage
# "knowledge/**/*.md" = "C:/OneDrive/knowledge"

[sync]
# Link mode: how paths are connected to targets
# Options: "symlink" (default), "copy"
# symlink - creates symbolic links (fast, space-efficient, requires elevated privileges on Windows)
# copy - copies files/directories (slower, uses more space, no special permissions needed)
link_mode = "symlink"

# Sync provider: advanced bidirectional sync options
# Options: "copy" (default), "rsync", "git-sync"
# copy - simple file copy with newer-file-wins logic
# rsync - uses rsync for efficient sync (requires rsync installed)
# git-sync - uses git for tracking and merging changes
provider = "copy"

# Sync direction: which way to sync changes
# Options: "source-to-target" (default), "target-to-source", "bidirectional"
# source-to-target - changes in .soul/ push to targets
# target-to-source - changes in targets pull back to .soul/
# bidirectional - sync newer files in both directions (requires provider with bidirectional support)
direction = "source-to-target"

# Auto-sync: automatically run sync when paths change
# Options: true, false (default)
auto_sync = false

# Exclude patterns: files/globs to exclude from sync
# Supports glob patterns like "*.tmp", "**/*.log", "node_modules/**"
exclude = [
    "*.tmp",
    "*.log",
    ".DS_Store",
    "Thumbs.db"
]

# Example excludes for specific paths (commented):
# exclude = [
#     "*.tmp",
#     "**/*.log",
#     "**/node_modules/**",
#     "**/.git/**",
#     "**/.obsidian/workspace.json",
#     "**/.obsidian/workspace-mobile.json"
# ]
"@

    Set-Content -Path $configPath -Value $content
    Log-Message "Created default config: $configPath" "success"
}

# ── Banner ──────────────────────────────────────────────────────────

function Print-Banner {
    Write-Host ""
    Write-Host "$(c '  +============================================+' 'Cyan')"
    Write-Host "$(c '  |' 'Cyan')$(c '  Portable Soul  ' 'Bright')$(c 'Identity * Memory * Continuity' 'Dim')     $(c '|' 'Cyan')"
    Write-Host "$(c '  +============================================+' 'Cyan')"
    Write-Host ""
}

function Log-Message {
    param(
        [string]$Message,
        [ValidateSet('info', 'success', 'warn', 'error')]
        [string]$Type = 'info'
    )

    $icons = @{
        info    = $(c '●' 'Blue')
        success = $(c '✓' 'Green')
        warn    = $(c '!' 'Yellow')
        error   = $(c '✗' 'Red')
    }
    $icon = if ($icons.ContainsKey($Type)) { $icons[$Type] } else { $icons['info'] }
    Write-Host "  $icon $Message"
}

function Read-Question {
    param([string]$Prompt, [string]$Default = $null)

    $hint = if ($Default) { " [$(c $Default 'Dim')]" } else { "" }
    $response = Read-Host "  $(c '?' 'Cyan') $Prompt$hint" | ForEach-Object {
        $_.Trim()
    }

    if ([string]::IsNullOrEmpty($response)) { return $Default }
    return $response
}

function Read-Confirm {
    param([string]$Prompt, [bool]$Default = $false)

    $hint = if ($Default) { "Y/n" } else { "y/N" }
    $response = Read-Question $Prompt $hint

    if ([string]::IsNullOrEmpty($response)) { return $Default }
    $responseLower = $response.ToLower()

    if ($responseLower -eq 'y' -or $responseLower -eq 'yes') { return $true }
    if ($responseLower -eq 'n' -or $responseLower -eq 'no') { return $false }
    return $Default
}

# ── Download helper ──────────────────────────────────────────

function Download-File {
    param([string]$Url, [string]$Dest)

    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Download-Template {
    param([string]$FileName, [string]$Dest)
    $url = "$REPO_RAW/templates/full/$FileName"
    return Download-File $url $Dest
}

# ── Install ─────────────────────────────────────────────────

function Invoke-Install {
    param([string]$soulDir)

    Print-Banner
    Log-Message "Let's set up your portable AI soul!"
    Write-Host ""

    # Check git
    try { git --version 2>$null | Out-Null } catch {
        Log-Message "Git is required. Please install Git first." "error"
        exit 1
    }

    # Ask directory
    $chosenDir = Read-Question "Soul directory" $soulDir
    $soulDir = [System.IO.Path]::GetFullPath($chosenDir)

    # Detect existing install
    $gitCheck = $null
    try {
        $gitCheck = git -C $soulDir rev-parse --git-dir 2>$null
    } catch { }

    if ((Test-Path $soulDir) -and $gitCheck -and (Test-Path (Join-Path $soulDir "soul-protocol.md"))) {
        Log-Message "Soul already installed at $soulDir" "warn"
        Log-Message "Use -Update to update soul-protocol.md to the latest version." "info"
        Log-Message "Manage symlinks with: .\cli.ps1 -Symlinks" "info"
        return
    }

    # Ask Obsidian
    $useObsidian = Read-Confirm "Configure for Obsidian?" $true

    Write-Host ""
    Log-Message "Setup plan:" "info"
    Write-Host "  Directory:     $(c $soulDir 'Bright')"
    Write-Host "  Obsidian:      $(if ($useObsidian) { 'Yes' } else { 'No' })"
    Write-Host ""

    $proceed = Read-Confirm "Continue?" $true
    if (-not $proceed) { Log-Message "Cancelled." "warn"; return }

    Write-Host ""

    # 1. Create directory
    if (-not (Test-Path $soulDir)) {
        New-Item -ItemType Directory -Path $soulDir -Force | Out-Null
    }
    Log-Message "Created $soulDir" "success"

    # 2. Git init
    $gitInitCheck = $null
    try {
        $gitInitCheck = git -C $soulDir rev-parse --git-dir 2>$null
    } catch { }

    if (-not $gitInitCheck) {
        git -C $soulDir init 2>$null | Out-Null
        Log-Message "Initialized git repo" "success"
    } else {
        Log-Message "Git repo already initialized" "success"
    }

    # 3. Download system files
    foreach ($file in $SYSTEM_FILES) {
        $dest = Join-Path $soulDir $file
        if (Download-Template $file $dest) {
            Log-Message "Downloaded $file" "success"
        } else {
            Log-Message "Failed to download $file" "error"
            exit 1
        }
    }

    # 4. Download seed files (skip existing)
    foreach ($file in $SEED_FILES) {
        $dest = Join-Path $soulDir $file
        if (Test-Path $dest) {
            Log-Message "Skipped $file (already exists)" "info"
        } else {
            if (Download-Template $file $dest) {
                Log-Message "Downloaded $file" "success"
            } else {
                Log-Message "Failed to download $file — skipping" "warn"
            }
        }
    }

    # 5. Download soul.config.yml (skip existing)
    $configDest = Join-Path $soulDir "soul.config.yml"
    if (Test-Path $configDest) {
        Log-Message "Skipped soul.config.yml (already exists)" "info"
    } else {
        if (Download-File "$REPO_RAW/soul.config.yml" $configDest) {
            Log-Message "Downloaded soul.config.yml" "success"
        } else {
            Log-Message "Failed to download soul.config.yml — skipping" "warn"
        }
    }

    # 6. Create journal/ stub
    $journalDir = Join-Path $soulDir "journal"
    if (-not (Test-Path $journalDir)) {
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $journalReadme = Join-Path $journalDir "README.md"
        Download-Template "journal/README.md" $journalReadme | Out-Null
        Log-Message "Created journal/" "success"
    } else {
        Log-Message "Skipped journal/ (already exists)" "info"
    }

    # 7. Obsidian config
    if ($useObsidian) {
        $obsDir = Join-Path $soulDir ".obsidian"
        if (-not (Test-Path $obsDir)) {
            New-Item -ItemType Directory -Path $obsDir -Force | Out-Null
        }
        $appConfig = @{ showLineNumber = $true; strictLineBreaks = $true; useMarkdownLinks = $false }
        $appConfig | ConvertTo-Json | Set-Content (Join-Path $obsDir "app.json") -NoNewline
        Set-Content (Join-Path $soulDir ".obsidianignore") ".git`n"

        # Update soul.config.yml for Obsidian
        $configPath = Join-Path $soulDir "soul.config.yml"
        if (Test-Path $configPath) {
            $content = Get-Content $configPath -Raw
            $content = $content -replace '(?m)^(\s*provider:\s*)plain\b', '${1}obsidian'
            $content = $content -replace '(?m)^(\s*)#\s*(features:\s*\[wikilinks.*\])\s*$', '${1}${2}'
            Set-Content $configPath $value $content -NoNewline
        }

        Log-Message "Configured for Obsidian" "success"
    }

    # 8. .gitignore
    $gitignoreLines = @()
    if (-not $useObsidian) {
        $gitignoreLines += ".obsidian/"
        $gitignoreLines += ""
    }
    $gitignoreLines += "# Obsidian"
    $gitignoreLines += ".obsidian/workspace.json"
    $gitignoreLines += ".obsidian/workspace-mobile.json"
    $gitignoreLines += ".obsidian/graph.json"
    $gitignoreLines += ".trash/"
    $gitignoreLines += ""
    $gitignoreLines += "# OS"
    $gitignoreLines += ".DS_Store"
    $gitignoreLines += "Thumbs.db"
    Set-Content (Join-Path $soulDir ".gitignore") ($gitignoreLines -join "`n") -NoNewline
    Log-Message "Wrote .gitignore" "success"

    # 9. Write default config
    Write-DefaultConfig $soulDir

    # 10. Initial commit
    git -C $soulDir add -A 2>$null | Out-Null
    git -C $soulDir commit -m "Initial soul setup" 2>$null | Out-Null
    Log-Message "Created initial commit" "success"

    # 11. Next steps
    Write-Host ""
    Write-Host "$(c '  -- Next steps ----------------------------------' 'Cyan')"
    Write-Host ""
    Log-Message "Open $(c $soulDir 'Bright') in your editor"
    Log-Message "Edit core files to define your AI:"
    Write-Host "     $(c 'identity.md' 'Bright')   - personality, voice, values"
    Write-Host "     $(c 'soul.md' 'Bright')       - philosophy and purpose"
    Write-Host "     $(c 'user.md' 'Bright')       - your preferences and goals"
    Write-Host "     $(c 'system.md' 'Bright')     - capabilities and rules"
    Write-Host ""
    if ($useObsidian) {
        Log-Message "Open $(c $soulDir 'Bright') as an Obsidian vault"
        Write-Host ""
    }
    Log-Message "Symlinks:"
    Log-Message "  .\cli.ps1 -Symlinks         - Show status"
    Log-Message "  .\cli.ps1 -Symlinks -Sync   - Create symlinks"
    Write-Host ""
    Log-Message "Update anytime: $(c '.\cli.ps1 -Update' 'Bright')"
    Write-Host ""
}

# ── Update ──────────────────────────────────────────────────────────

function Invoke-Update {
    param([string]$soulDir)

    Print-Banner

    if (-not (Test-Path $soulDir)) {
        Log-Message "Soul directory not found: $soulDir" "error"
        Log-Message "Run .\cli.ps1 first to install." "info"
        exit 1
    }

    if (-not (Test-Path (Join-Path $soulDir "soul-protocol.md"))) {
        Log-Message "No soul-protocol.md found. Is this a soul directory?" "error"
        exit 1
    }

    # 1. Replace soul-protocol.md
    $dest = Join-Path $soulDir "soul-protocol.md"
    $oldContent = Get-Content $dest -Raw

    $tempFile = [System.IO.Path]::GetTempFileName()
    if (Download-Template "soul-protocol.md" $tempFile) {
        $newContent = Get-Content $tempFile -Raw
        if ($oldContent -eq $newContent) {
            Log-Message "soul-protocol.md is already up to date" "success"
        } else {
            Copy-Item $tempFile $dest -Force
            Log-Message "Updated soul-protocol.md" "success"
        }
        Remove-Item $tempFile -Force
    } else {
        Log-Message "Failed to download soul-protocol.md" "error"
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    # 2. Check for new seed templates
    $newFiles = @()
    foreach ($file in $SEED_FILES) {
        if (-not (Test-Path (Join-Path $soulDir $file))) {
            $newFiles += $file
        }
    }

    if ($newFiles.Count -gt 0) {
        Write-Host ""
        Log-Message "Found $($newFiles.Count) new template(s) not in your vault:"
        foreach ($f in $newFiles) {
            Write-Host "     $(c $f 'Bright')"
        }
        Write-Host ""
        $shouldCopy = Read-Confirm "Copy new templates?" $true
        if ($shouldCopy) {
            foreach ($f in $newFiles) {
                $fdest = Join-Path $soulDir $f
                if (Download-Template $f $fdest) {
                    Log-Message "Downloaded $f" "success"
                } else {
                    Log-Message "Failed to download $f — skipping" "warn"
                }
            }
        }
    }

    # 3. Commit if changes
    $status = git -C $soulDir status --porcelain 2>$null
    if ($status) {
        git -C $soulDir add -A 2>$null | Out-Null
        git -C $soulDir commit -m "soul: update soul-protocol.md" 2>$null | Out-Null
        Log-Message "Committed changes" "success"
    } else {
        Log-Message "No changes to commit" "info"
    }

    Write-Host ""
    Log-Message "Your personal files are unchanged." "info"
    Write-Host ""
}

# ── Help ─────────────────────────────────────────────────────────────

function Show-Help {
    Print-Banner
    Write-Host "  Usage:"
    Write-Host ""
    Write-Host "    $(c '.\cli.ps1' 'Bright')                Install (create ~/.soul/)"
    Write-Host "    $(c '.\cli.ps1 -Update' 'Bright')        Update soul-protocol.md"
    Write-Host "    $(c '.\cli.ps1 -Dir PATH' 'Bright')      Install to custom directory"
    Write-Host "    $(c '.\cli.ps1 -Config FILE' 'Bright')   Use custom config"
    Write-Host "    $(c '.\cli.ps1 -Symlinks' 'Bright')      Show path status"
    Write-Host "    $(c '.\cli.ps1 -Symlinks -Sync' 'Bright')   Sync paths"
    Write-Host "    $(c '.\cli.ps1 -Symlinks -Remove' 'Bright')  Remove paths"
    Write-Host ""
    Write-Host "  Sync options:"
    Write-Host ""
    Write-Host "    $(c '-DryRun' 'Bright')         Show what would happen without making changes"
    Write-Host "    $(c '-Mode MODE' 'Bright')     Override link mode (symlink/copy)"
    Write-Host "    $(c '-Provider PROV' 'Bright') Override sync provider (copy/rsync/git-sync)"
    Write-Host "    $(c '-Direction DIR' 'Bright') Override sync direction (source-to-target/target-to-source/bidirectional)"
    Write-Host ""
    Write-Host "  Config file options (~/.soul/.config/default.toml):"
    Write-Host ""
    Write-Host "    [sync]"
    Write-Host "      link_mode = `"symlink`"      # symlink or copy"
    Write-Host "      provider = `"copy`"           # copy, rsync, or git-sync"
    Write-Host "      direction = `"source-to-target`" # source-to-target, target-to-source, or bidirectional"
    Write-Host "      auto_sync = false           # automatically sync on changes"
    Write-Host "      exclude = [`"*.tmp`", `"*.log`"] # glob patterns to exclude"
    Write-Host ""
    Write-Host "    $(c '.\cli.ps1 -Help' 'Bright')          Show this message"
    Write-Host ""
}

# ── Symlinks command ───────────────────────────────────────────

function Invoke-Symlinks {
    param([string]$soulDir)

    if (-not (Test-Path $soulDir)) {
        Log-Message "Soul directory not found: $soulDir" "error"
        exit 1
    }

    # Handle subcommands
    if ($Sync) {
        Sync-Symlinks $soulDir
        return
    }

    if ($Remove) {
        Remove-Symlinks $soulDir
        return
    }

    # Default: show status
    Show-SymlinkStatus $soulDir
}

# ── Main ─────────────────────────────────────────────────────────────

$soulDir = if ($Dir) { [System.IO.Path]::GetFullPath($Dir) } else { $DEFAULT_SOUL_DIR }

# Apply global options
if ($DryRun) {
    Set-DryRun $true
}

# Load config if soul dir exists
if (Test-Path $soulDir) {
    $configPath = Get-ConfigPath $Config
    if ($configPath) {
        $cfg = Get-Config $configPath
        Set-Config $cfg
    }
}

# Apply CLI overrides
if ($Mode -or $Provider -or $Direction) {
    $currentConfig = Get-Config
    $currentSyncConfig = if ($currentConfig.ContainsKey('sync')) { $currentConfig['sync'] } else { @{} }
    if ($Mode) { $currentSyncConfig['link_mode'] = $Mode }
    if ($Provider) { $currentSyncConfig['provider'] = $Provider }
    if ($Direction) { $currentSyncConfig['direction'] = $Direction }
    $newConfig = @{}
    foreach ($key in $currentConfig.Keys) {
        if ($key -eq 'sync') {
            $newConfig['sync'] = $currentSyncConfig
        } else {
            $newConfig[$key] = $currentConfig[$key]
        }
    }
    if (-not $newConfig.ContainsKey('sync')) {
        $newConfig['sync'] = $currentSyncConfig
    }
    Set-Config $newConfig
}

if ($Help) {
    Show-Help
} elseif ($Update) {
    Invoke-Update $soulDir
} elseif ($Symlinks) {
    Invoke-Symlinks $soulDir
} else {
    Invoke-Install $soulDir
}
