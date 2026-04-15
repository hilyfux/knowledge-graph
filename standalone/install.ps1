#Requires -Version 5.0
<#
.SYNOPSIS
    Knowledge Graph installer for Windows.

.DESCRIPTION
    Copies the knowledge-graph skill to .claude/skills/knowledge-graph/,
    merges hooks into .claude/settings.json, and registers the MCP server
    in .mcp.json.

    Runtime requires bash + jq. On Windows that typically means Git Bash
    (which ships bash.exe on the PATH) plus jq installed via winget or
    scoop/choco. The installer verifies both are available and prints
    install hints if not.

.PARAMETER TargetPath
    Project directory to install into. Defaults to the current working
    directory.

.EXAMPLE
    .\install.ps1
    .\install.ps1 C:\code\my-project
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$TargetPath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Info  { param([string]$m) Write-Host "[kg] $m" -ForegroundColor Green }
function Warn  { param([string]$m) Write-Host "[kg] $m" -ForegroundColor Yellow }
function Fail  { param([string]$m) Write-Host "[kg] $m" -ForegroundColor Red; exit 1 }

# ── Preflight: bash + jq must be on PATH ─────────────────────────────────────
$bash = Get-Command bash -ErrorAction SilentlyContinue
$jq   = Get-Command jq   -ErrorAction SilentlyContinue

if (-not $bash) {
    Fail @"
bash not found on PATH. Knowledge Graph runs hooks as bash scripts, so you
need Git Bash (or WSL). Install via:
  winget install Git.Git
After installing, restart your shell and re-run this script.
"@
}

if (-not $jq) {
    Fail @"
jq not found on PATH. Install via one of:
  winget install jqlang.jq
  scoop install jq
  choco install jq
After installing, restart your shell and re-run this script.
"@
}

# ── Target validation ────────────────────────────────────────────────────────
$TargetPath = (Resolve-Path $TargetPath).Path
if ((Split-Path $TargetPath -Leaf) -eq '.claude') {
    $TargetPath = Split-Path $TargetPath -Parent
    Warn "Target looked like .claude/; corrected to project root: $TargetPath"
}
if ($TargetPath -eq $HOME) { Fail "Refusing to install into `$HOME" }
if ($TargetPath -eq [System.IO.Path]::GetPathRoot($TargetPath)) {
    Fail "Refusing to install into the drive root"
}
if (-not (Test-Path $TargetPath -PathType Container)) {
    Fail "Target does not exist or is not a directory: $TargetPath"
}

$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillSrc   = Join-Path $InstallDir 'skills\knowledge-graph'
$SkillDst   = Join-Path $TargetPath '.claude\skills\knowledge-graph'
$Settings   = Join-Path $TargetPath '.claude\settings.json'

if (-not (Test-Path $SkillSrc)) {
    Fail "Skill source not found: $SkillSrc (are you running from the repo root?)"
}

# ── Legacy cleanup ───────────────────────────────────────────────────────────
$oldScripts = Join-Path $TargetPath '.claude\scripts\track-activity.sh'
if (Test-Path $oldScripts) {
    Warn 'Detected legacy install (.claude/scripts/) — migrating'
    $oldEvents = Join-Path $TargetPath '.claude\graph-events.jsonl'
    $newData   = Join-Path $SkillDst 'data'
    New-Item -ItemType Directory -Force -Path $newData | Out-Null
    if (Test-Path $oldEvents) {
        Move-Item $oldEvents (Join-Path $newData 'graph-events.jsonl') -Force
        Info 'Migrated graph-events.jsonl'
    }
    Remove-Item -Recurse -Force (Join-Path $TargetPath '.claude\scripts')  -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force (Join-Path $TargetPath '.claude\commands') -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $TargetPath '.claude\graph-analysis.json') -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $TargetPath '.claude\graph-scan.json')    -ErrorAction SilentlyContinue
    Info 'Cleaned legacy scripts'
}

$legacyFiles = @(
    '.claude\graph-changelog.jsonl'
    '.claude\graph-changelog.jsonl.reported'
    '.claude\graph-events-archive.jsonl'
    '.claude\knowledge-graph.md'
    '.claude\knowledge-index.md'
)
foreach ($rel in $legacyFiles) {
    $p = Join-Path $TargetPath $rel
    if (Test-Path $p) { Remove-Item -Force $p; Info "Removed stray file: $(Split-Path $rel -Leaf)" }
}

# ── Create directories ───────────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path (Join-Path $SkillDst 'scripts') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $TargetPath '.knowledge-graph') | Out-Null

# ── Copy skill files ─────────────────────────────────────────────────────────
Info 'Copying skill to .claude/skills/knowledge-graph/'
Copy-Item (Join-Path $SkillSrc 'SKILL.md')   $SkillDst -Force
Copy-Item (Join-Path $SkillSrc 'scripts\*.sh') (Join-Path $SkillDst 'scripts') -Force
if (Test-Path (Join-Path $SkillSrc 'plugin.json')) {
    Copy-Item (Join-Path $SkillSrc 'plugin.json') $SkillDst -Force
}
# Include the scripts-level CLAUDE.md if present
if (Test-Path (Join-Path $SkillSrc 'scripts\CLAUDE.md')) {
    Copy-Item (Join-Path $SkillSrc 'scripts\CLAUDE.md') (Join-Path $SkillDst 'scripts') -Force
}

# ── Build hooks object ───────────────────────────────────────────────────────
# Note: hook commands use $CLAUDE_PROJECT_DIR (bash env var, injected by
# Claude Code at run time), not a PowerShell variable — leave the `$` quoted.
$cmdPrefix = 'bash "$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts'
$hookSpec = @{
    PreToolUse = @(
        @{ matcher = 'Read';        hooks = @(@{ type='command'; command="$cmdPrefix/track.sh`" read";      timeout=3 }) }
        @{ matcher = 'Write|Edit';  hooks = @(@{ type='command'; command="$cmdPrefix/track.sh`" pre-write"; timeout=3 }) }
    )
    PostToolUse = @(
        @{ matcher = 'Write|Edit';  hooks = @(@{ type='command'; command="$cmdPrefix/track.sh`" write";     timeout=3 }) }
    )
    PostToolUseFailure = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/track.sh`" failure";   timeout=2 }) }
    )
    InstructionsLoaded = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/track.sh`" instructions"; timeout=2 }) }
    )
    SessionStart = @(
        @{ matcher = 'startup|clear'; hooks = @(@{ type='command'; command="$cmdPrefix/context.sh`" startup"; timeout=5 }) }
        @{ matcher = 'compact';       hooks = @(@{ type='command'; command="$cmdPrefix/context.sh`" compact"; timeout=5 }) }
        @{ matcher = 'resume';        hooks = @(@{ type='command'; command="$cmdPrefix/context.sh`" resume";  timeout=5 }) }
    )
    SubagentStart = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/context.sh`" subagent";   timeout=3 }) }
    )
    PreCompact = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/context.sh`" precompact"; timeout=3 }) }
    )
    PostCompact = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/context.sh`" postcompact"; timeout=5 }) }
    )
    Stop = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/analyze.sh`" stop";     timeout=3 }) }
    )
    UserPromptSubmit = @(
        @{ matcher = '*';           hooks = @(@{ type='command'; command="$cmdPrefix/prompt-trigger.sh`"";   timeout=2 }) }
    )
}

Info 'Merging hooks into .claude/settings.json'
New-Item -ItemType Directory -Force -Path (Split-Path $Settings) | Out-Null

if (-not (Test-Path $Settings)) {
    @{ hooks = $hookSpec } | ConvertTo-Json -Depth 10 | Set-Content -Path $Settings -Encoding UTF8
} else {
    $existing = Get-Content -Raw $Settings | ConvertFrom-Json
    if (-not $existing.hooks) {
        $existing | Add-Member -NotePropertyName 'hooks' -NotePropertyValue (New-Object PSObject) -Force
    }

    foreach ($hookType in $hookSpec.Keys) {
        $new = $hookSpec[$hookType]
        $current = $existing.hooks.$hookType
        if ($null -eq $current) {
            $merged = $new
        } else {
            # Drop prior kg entries matching known legacy paths, then append new
            $filtered = @($current | Where-Object {
                $cmd = if ($_.hooks) { $_.hooks[0].command } else { '' }
                -not (
                    $cmd -match 'track-activity\.sh' -or
                    $cmd -match 'track-failure\.sh' -or
                    $cmd -match 'track-instructions\.sh' -or
                    $cmd -match 'inject-' -or
                    $cmd -match 'on-compact' -or
                    $cmd -match 'on-stop' -or
                    $cmd -match 'inject-subagent' -or
                    $cmd -match 'knowledge-graph/scripts/(track|context|analyze|prompt-trigger)\.sh'
                )
            })
            $merged = @($filtered + $new)
        }
        if ($existing.hooks.PSObject.Properties[$hookType]) {
            $existing.hooks.$hookType = $merged
        } else {
            $existing.hooks | Add-Member -NotePropertyName $hookType -NotePropertyValue $merged -Force
        }
    }

    $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $Settings -Encoding UTF8
}

# ── Init runtime data dir ────────────────────────────────────────────────────
$kgData = Join-Path $TargetPath '.knowledge-graph'
New-Item -ItemType Directory -Force -Path $kgData | Out-Null
$eventsFile = Join-Path $kgData 'graph-events.jsonl'
if (-not (Test-Path $eventsFile)) { New-Item -ItemType File -Path $eventsFile -Force | Out-Null }

# Migrate data from old SkillDst/data/ location if it exists
$oldData = Join-Path $SkillDst 'data'
if ((Test-Path $oldData) -and (Test-Path (Join-Path $oldData 'graph-events.jsonl'))) {
    Info "Migrating data from $oldData → $kgData"
    Get-ChildItem $oldData -File | ForEach-Object {
        Move-Item $_.FullName (Join-Path $kgData $_.Name) -Force
    }
    Remove-Item $oldData -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Add @include to .claude/CLAUDE.md ────────────────────────────────────────
$includeLine = '@.knowledge-graph/knowledge-index.md'
$oldInclude  = '@.claude/skills/knowledge-graph/data/knowledge-index.md'
$dotClaudeMd = Join-Path $TargetPath '.claude\CLAUDE.md'

if (Test-Path $dotClaudeMd) {
    $content = Get-Content -Raw $dotClaudeMd
    if ($content -match [regex]::Escape($oldInclude)) {
        ($content -replace [regex]::Escape($oldInclude), $includeLine) |
            Set-Content -Path $dotClaudeMd -NoNewline -Encoding UTF8
    }
    if (-not ((Get-Content -Raw $dotClaudeMd) -match [regex]::Escape($includeLine))) {
        Add-Content -Path $dotClaudeMd -Value "`n$includeLine" -Encoding UTF8
        Info 'Added knowledge-index @include to .claude/CLAUDE.md'
    }
} else {
    Set-Content -Path $dotClaudeMd -Value $includeLine -Encoding UTF8
    Info 'Created .claude/CLAUDE.md with knowledge-index @include'
}

# ── Register MCP server in .mcp.json ─────────────────────────────────────────
$mcpJson       = Join-Path $TargetPath '.mcp.json'
# Use forward slashes in the args path so the JSON stays sane across shells
$mcpServerPath = ($SkillDst -replace '\\', '/') + '/scripts/mcp-server.sh'

if (Test-Path $mcpJson) {
    $existing = Get-Content -Raw $mcpJson | ConvertFrom-Json
    if (-not $existing.mcpServers) {
        $existing | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue (New-Object PSObject) -Force
    }
    if (-not $existing.mcpServers.'knowledge-graph') {
        $kgMcp = [PSCustomObject]@{
            type    = 'stdio'
            command = 'bash'
            args    = @($mcpServerPath)
        }
        $existing.mcpServers | Add-Member -NotePropertyName 'knowledge-graph' -NotePropertyValue $kgMcp -Force
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpJson -Encoding UTF8
        Info 'Registered knowledge-graph MCP server in .mcp.json'
    }
} else {
    $obj = [PSCustomObject]@{
        mcpServers = [PSCustomObject]@{
            'knowledge-graph' = [PSCustomObject]@{
                type    = 'stdio'
                command = 'bash'
                args    = @($mcpServerPath)
            }
        }
    }
    $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpJson -Encoding UTF8
    Info 'Created .mcp.json and registered knowledge-graph MCP server'
}

# ── Update .gitignore ────────────────────────────────────────────────────────
$gitignore = Join-Path $TargetPath '.gitignore'
if (Test-Path $gitignore) {
    $gi = Get-Content $gitignore
    if ($gi -notcontains '.knowledge-graph/') {
        Add-Content -Path $gitignore -Value '.knowledge-graph/' -Encoding UTF8
        Info 'Appended .knowledge-graph/ to .gitignore'
    }
} else {
    Set-Content -Path $gitignore -Value '.knowledge-graph/' -Encoding UTF8
    Info 'Created .gitignore with .knowledge-graph/'
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ''
Info 'Install complete.'
Write-Host ''
Write-Host "  Installed to: $SkillDst"
Write-Host ''
Write-Host '  Next steps:'
Write-Host '  1. Restart Claude Code (so hooks activate)'
Write-Host '  2. Run /knowledge-graph init to bootstrap'
Write-Host ''
