#Requires -Version 5.0
<#
.SYNOPSIS
    Knowledge Graph installer for Windows.

.DESCRIPTION
    Copies the knowledge-graph skill to .claude/skills/knowledge-graph/,
    merges hooks into .claude/settings.json, and registers the MCP server
    in project .codex/config.toml and .mcp.json.

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

function ConvertTo-TomlString {
    param([string]$Value)
    '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Set-ManagedCodexMcpBlock {
    param(
        [string]$ConfigPath,
        [string]$Block,
        [string]$Begin,
        [string]$End
    )
    $dir = Split-Path $ConfigPath -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if (Test-Path $ConfigPath) {
        $text = Get-Content -Raw $ConfigPath
        $hasBegin = $text.Contains($Begin)
        $hasEnd = $text.Contains($End)
        if ($hasBegin -ne $hasEnd) {
            Fail "Incomplete Knowledge Graph managed block in $ConfigPath"
        }
        if (-not $hasBegin -and $text -match '(?m)^\[mcp_servers\.knowledge-graph(\.|\])') {
            Fail "Unmanaged knowledge-graph MCP config already exists in $ConfigPath; remove that table and reinstall"
        }
        if ($hasBegin) {
            $pattern = [regex]::Escape($Begin) + '[\s\S]*?' + [regex]::Escape($End)
            $text = [regex]::Replace($text, $pattern, { param($m) $Block.Trim() }, 1)
        } elseif ($text.Trim()) {
            $text = $text.TrimEnd() + "`n`n" + $Block.Trim() + "`n"
        } else {
            $text = $Block.Trim() + "`n"
        }
    } else {
        $text = $Block.Trim() + "`n"
    }
    Set-Content -Path $ConfigPath -Value $text -Encoding UTF8
}

function Read-ProjectMcpJson {
    param([string]$McpJson)
    try {
        $doc = Get-Content -Raw $McpJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Fail ".mcp.json must be a JSON object and mcpServers must be an object: $McpJson. Preserving existing .mcp.json unchanged."
    }
    if ($null -eq $doc -or $doc -isnot [System.Management.Automation.PSCustomObject]) {
        Fail ".mcp.json must be a JSON object and mcpServers must be an object: $McpJson. Preserving existing .mcp.json unchanged."
    }
    $mcpServersProp = $doc.PSObject.Properties['mcpServers']
    if ($mcpServersProp -and $null -ne $mcpServersProp.Value -and
        $mcpServersProp.Value -isnot [System.Management.Automation.PSCustomObject]) {
        Fail ".mcp.json must be a JSON object and mcpServers must be an object: $McpJson. Preserving existing .mcp.json unchanged."
    }
    $doc
}

function Ensure-McpServersObject {
    param([System.Management.Automation.PSCustomObject]$Doc)
    $mcpServersProp = $Doc.PSObject.Properties['mcpServers']
    if (-not $mcpServersProp) {
        $Doc | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{}) -Force
    } elseif ($null -eq $mcpServersProp.Value) {
        $Doc.mcpServers = [PSCustomObject]@{}
    }
}

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

$mcpJson = Join-Path $TargetPath '.mcp.json'
if (Test-Path $mcpJson) {
    [void](Read-ProjectMcpJson -McpJson $mcpJson)
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

# ── Add Codex operating notes to AGENTS.md ──────────────────────────────────
$agentsPath = Join-Path $TargetPath 'AGENTS.md'
$agentsBegin = '<!-- knowledge-graph:codex begin -->'
$agentsEnd = '<!-- knowledge-graph:codex end -->'
$agentsBlock = @"
$agentsBegin
## Knowledge Graph

- Use the bundled project-level MCP server from .codex/config.toml or .mcp.json when available: start with kg_status, then kg_query or kg_read_node before editing unfamiliar modules.
- Do not install Knowledge Graph as a user-level Codex MCP server; this project is registered only through project-level config.
- Durable module knowledge lives in canonical CLAUDE.md and SKILL.md files. AGENTS.md is only the Codex adapter that tells Codex to read those canonical nodes through MCP.
- Runtime data lives under .knowledge-graph/ and should stay uncommitted.
- If running scripts outside Claude Code, set KG_PROJECT_DIR to this project root; Claude Code may set CLAUDE_PROJECT_DIR instead.
- Before reporting success, include concrete evidence: tests run, files checked, or MCP resources consulted.
$agentsEnd
"@

if (Test-Path $agentsPath) {
    $agentsText = Get-Content -Raw $agentsPath
    $pattern = [regex]::Escape($agentsBegin) + '[\s\S]*?' + [regex]::Escape($agentsEnd)
    if ($agentsText -match [regex]::Escape($agentsBegin)) {
        $agentsText = [regex]::Replace($agentsText, $pattern, $agentsBlock)
    } else {
        $agentsText = $agentsText.TrimEnd() + "`n`n" + $agentsBlock + "`n"
    }
    Set-Content -Path $agentsPath -Value $agentsText -Encoding UTF8
} else {
    Set-Content -Path $agentsPath -Value "# Project Instructions`n`n$agentsBlock`n" -Encoding UTF8
}
Info 'Updated AGENTS.md with Codex Knowledge Graph notes'

# ── Register MCP server in .mcp.json ─────────────────────────────────────────
# Use forward slashes in the args path so the JSON stays sane across shells
$mcpServerPath = ($SkillDst -replace '\\', '/') + '/scripts/mcp-server.sh'
$mcpEnv = [PSCustomObject]@{ KG_PROJECT_DIR = $TargetPath }
$codexMcpStartupTimeoutSec = 60
$codexMcpToolTimeoutSec = 20
if ($env:CODEX_MCP_STARTUP_TIMEOUT_SEC) {
    [int]$parsedTimeout = 0
    if ([int]::TryParse($env:CODEX_MCP_STARTUP_TIMEOUT_SEC, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
        $codexMcpStartupTimeoutSec = $parsedTimeout
    } else {
        Warn 'CODEX_MCP_STARTUP_TIMEOUT_SEC is invalid; using default 60'
    }
}
if ($env:CODEX_MCP_TOOL_TIMEOUT_SEC) {
    [int]$parsedTimeout = 0
    if ([int]::TryParse($env:CODEX_MCP_TOOL_TIMEOUT_SEC, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
        $codexMcpToolTimeoutSec = $parsedTimeout
    } else {
        Warn 'CODEX_MCP_TOOL_TIMEOUT_SEC is invalid; using default 20'
    }
}

if (Test-Path $mcpJson) {
    $existing = Read-ProjectMcpJson -McpJson $mcpJson
    Ensure-McpServersObject -Doc $existing
    if (-not $existing.mcpServers.'knowledge-graph') {
        $kgMcp = [PSCustomObject]@{
            type    = 'stdio'
            command = 'bash'
            args    = @($mcpServerPath)
            env     = $mcpEnv
            startup_timeout_sec = $codexMcpStartupTimeoutSec
            tool_timeout_sec = $codexMcpToolTimeoutSec
        }
        $existing.mcpServers | Add-Member -NotePropertyName 'knowledge-graph' -NotePropertyValue $kgMcp -Force
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpJson -Encoding UTF8
        Info 'Registered knowledge-graph MCP server in .mcp.json'
    } else {
        $existing.mcpServers.'knowledge-graph'.type = 'stdio'
        $existing.mcpServers.'knowledge-graph'.command = 'bash'
        $existing.mcpServers.'knowledge-graph'.args = @($mcpServerPath)
        if ($existing.mcpServers.'knowledge-graph'.PSObject.Properties['startup_timeout_sec']) {
            $existing.mcpServers.'knowledge-graph'.startup_timeout_sec = $codexMcpStartupTimeoutSec
        } else {
            $existing.mcpServers.'knowledge-graph' | Add-Member -NotePropertyName 'startup_timeout_sec' -NotePropertyValue $codexMcpStartupTimeoutSec -Force
        }
        if ($existing.mcpServers.'knowledge-graph'.PSObject.Properties['tool_timeout_sec']) {
            $existing.mcpServers.'knowledge-graph'.tool_timeout_sec = $codexMcpToolTimeoutSec
        } else {
            $existing.mcpServers.'knowledge-graph' | Add-Member -NotePropertyName 'tool_timeout_sec' -NotePropertyValue $codexMcpToolTimeoutSec -Force
        }
        if ($existing.mcpServers.'knowledge-graph'.PSObject.Properties['env']) {
            $existing.mcpServers.'knowledge-graph'.env = $mcpEnv
        } else {
            $existing.mcpServers.'knowledge-graph' | Add-Member -NotePropertyName 'env' -NotePropertyValue $mcpEnv -Force
        }
        $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpJson -Encoding UTF8
        Info 'Updated knowledge-graph MCP server in .mcp.json'
    }
} else {
    $obj = [PSCustomObject]@{
        mcpServers = [PSCustomObject]@{
            'knowledge-graph' = [PSCustomObject]@{
                type    = 'stdio'
                command = 'bash'
                args    = @($mcpServerPath)
                env     = $mcpEnv
                startup_timeout_sec = $codexMcpStartupTimeoutSec
                tool_timeout_sec = $codexMcpToolTimeoutSec
            }
        }
    }
    $obj | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpJson -Encoding UTF8
    Info 'Created .mcp.json and registered knowledge-graph MCP server'
}

$codexConfig = Join-Path $TargetPath '.codex\config.toml'
$codexMcpBegin = '# knowledge-graph:codex-mcp begin'
$codexMcpEnd = '# knowledge-graph:codex-mcp end'
$mcpCommandToml = ConvertTo-TomlString 'bash'
$mcpServerToml = ConvertTo-TomlString $mcpServerPath
$projectToml = ConvertTo-TomlString $TargetPath
$codexBlock = @"
$codexMcpBegin
# Managed by Knowledge Graph installer. Project-level only; no user config writes.
[mcp_servers.knowledge-graph]
command = $mcpCommandToml
args = [$mcpServerToml]
startup_timeout_sec = $codexMcpStartupTimeoutSec
tool_timeout_sec = $codexMcpToolTimeoutSec

[mcp_servers.knowledge-graph.env]
KG_PROJECT_DIR = $projectToml
$codexMcpEnd
"@
Set-ManagedCodexMcpBlock -ConfigPath $codexConfig -Block $codexBlock -Begin $codexMcpBegin -End $codexMcpEnd
Info 'Registered knowledge-graph MCP server in project .codex/config.toml'

Info 'Project-level install only: user-level Codex MCP config was not changed'

# ── Update .gitignore ────────────────────────────────────────────────────────
$gitignore = Join-Path $TargetPath '.gitignore'
if (Test-Path $gitignore) {
    $gi = Get-Content $gitignore
    if ($gi -notcontains '.knowledge-graph/') {
        Add-Content -Path $gitignore -Value '.knowledge-graph/' -Encoding UTF8
        Info 'Appended .knowledge-graph/ to .gitignore'
    }
    if ($gi -notcontains '.codex/config.toml') {
        Add-Content -Path $gitignore -Value '.codex/config.toml' -Encoding UTF8
        Info 'Appended .codex/config.toml to .gitignore'
    }
} else {
    Set-Content -Path $gitignore -Value ".knowledge-graph/`n.codex/config.toml" -Encoding UTF8
    Info 'Created .gitignore with Knowledge Graph local paths'
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ''
Info 'Install complete.'
Write-Host ''
Write-Host "  Installed to: $SkillDst"
Write-Host ''
Write-Host '  Next steps:'
Write-Host '  1. Restart Claude Code (so hooks activate)'
Write-Host '  2. Use project .codex/config.toml from Codex CLI; other MCP clients can use project .mcp.json'
Write-Host '  3. Run /knowledge-graph init to bootstrap'
Write-Host ''
