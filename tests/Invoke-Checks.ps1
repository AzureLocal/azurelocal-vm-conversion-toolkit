#Requires -Version 7.0
<#
.SYNOPSIS
    Runs the repository checks CI runs: PSScriptAnalyzer, Pester unit tests and the Markdown link check.
.DESCRIPTION
    Nothing here touches Azure, Hyper-V or a cluster. Run it from anywhere:
        pwsh ./tests/Invoke-Checks.ps1 -Check All
.PARAMETER Check
    Analyzer, Pester, Links or All.
#>
[CmdletBinding()]
param(
    [ValidateSet('Analyzer', 'Pester', 'Links', 'All')]
    [string]$Check = 'All'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failed = $false

function Invoke-AnalyzerCheck {
    if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) { throw 'PSScriptAnalyzer is not installed (Install-Module PSScriptAnalyzer).' }
    Import-Module PSScriptAnalyzer
    $settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($p in 'scripts') {
        Invoke-ScriptAnalyzer -Path (Join-Path $root $p) -Recurse -Settings $settings | ForEach-Object { $findings.Add($_) }
    }
    # Unit tests share scenario state through globals on purpose (see the settings file).
    foreach ($f in Get-ChildItem (Join-Path $root 'tests') -Filter *.ps1 -Recurse) {
        Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settings -ExcludeRule PSAvoidGlobalVars, PSAvoidUsingWriteHost, PSUseBOMForUnicodeEncodedFile |
            ForEach-Object { $findings.Add($_) }
    }
    $bad = @($findings | Where-Object Severity -in 'Error', 'Warning')
    $bad | ForEach-Object { Write-Host ("{0}:{1} [{2}] {3}" -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message) }
    Write-Host ("Analyzer: {0} error/warning finding(s), {1} information" -f $bad.Count, ($findings.Count - $bad.Count))
    return ($bad.Count -eq 0)
}

function Invoke-PesterCheck {
    Import-Module Pester -MinimumVersion 5.0
    $c = New-PesterConfiguration
    $c.Run.Path = Join-Path $root 'tests/Unit'
    $c.Run.PassThru = $true
    $c.Output.Verbosity = 'Normal'
    $r = Invoke-Pester -Configuration $c
    return ($r.FailedCount -eq 0 -and $r.FailedContainersCount -eq 0 -and $r.TotalCount -gt 0)
}

# Relative Markdown links must resolve; code blocks and inline code are ignored.
function Invoke-LinkCheck {
    $files = Get-ChildItem $root -Recurse -File -Filter *.md |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|archive|\.vitepress)[\\/]' }
    $checked = 0
    $dead = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        $inFence = $false
        foreach ($line in [IO.File]::ReadLines($f.FullName)) {
            if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }
            $text = [regex]::Replace($line, '`[^`]*`', '')
            foreach ($m in [regex]::Matches($text, '!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')) {
                $target = $m.Groups[1].Value
                if ($target -match '^(https?:|mailto:|#)') { continue }
                $checked++
                $clean = [uri]::UnescapeDataString((($target -split '[#?]')[0]))
                if ($clean -and -not (Test-Path -LiteralPath (Join-Path $f.DirectoryName $clean))) {
                    $dead.Add(("{0}: {1}" -f $f.FullName.Substring($root.Length + 1), $target))
                }
            }
        }
    }
    $dead | ForEach-Object { Write-Host "dead link: $_" }
    Write-Host ("Links: {0} files, {1} relative links checked, {2} dead" -f @($files).Count, $checked, $dead.Count)
    return ($dead.Count -eq 0)
}

foreach ($c in 'Analyzer', 'Pester', 'Link') {
    if ($Check -in "${c}s", $c, 'All') {
        Write-Host "== $c =="
        if (-not (& "Invoke-${c}Check")) { $failed = $true }
    }
}
if ($failed) { exit 1 }
