#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Smoke tests: every script parses, destructive scripts are ShouldProcess/High, docs and scripts agree on the OS rule,
# the README links resolve, and nothing carries lab or private-release wording.

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ScriptFiles = Get-ChildItem (Join-Path $root 'scripts') -Recurse -Include *.ps1, *.psm1, *.psd1 |
        ForEach-Object { @{ name = $_.FullName.Substring($root.Length + 1); path = $_.FullName } }
}

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

Describe 'Scripts' {
    It '<name> parses without errors' -ForEach $script:ScriptFiles {
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
        $errs | Should -BeNullOrEmpty
    }
    It '<name> is saved with a BOM so Windows PowerShell 5.1 reads the box-drawing text' -ForEach ($script:ScriptFiles | Where-Object { $_.name -match '0[1-5]-' }) {
        $b = [IO.File]::ReadAllBytes($path)[0..2]
        ($b -join ',') | Should -Be '239,187,191'
    }
    It '<p> has validated, mandatory parameters and ShouldProcess' -ForEach @(
        @{ p = 'scripts\hyperv\02-Convert-MBRtoGPT.ps1'; high = $true }
        @{ p = 'scripts\azurelocal\02-Convert-MBRtoGPT.ps1'; high = $true }
        @{ p = 'scripts\hyperv\03-Convert-Gen1toGen2.ps1'; high = $true }
        @{ p = 'scripts\azurelocal\03-Convert-Gen1toGen2.ps1'; high = $true }
        @{ p = 'scripts\azurelocal\05-Reconnect-AzureLocalVM.ps1'; high = $true }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $p), [ref]$null, [ref]$null)
        $attr = $ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }
        ($attr.NamedArguments | Where-Object ArgumentName -eq 'SupportsShouldProcess') | Should -Not -BeNullOrEmpty
        ($attr.NamedArguments | Where-Object ArgumentName -eq 'ConfirmImpact').Argument.Value | Should -Be 'High'
    }
    It 'script 03 requires VMName, WorkingDirectory, ResourceGroup and SubscriptionId' -ForEach @(
        @{ p = 'scripts\hyperv\03-Convert-Gen1toGen2.ps1'; req = @('VMName', 'WorkingDirectory') }
        @{ p = 'scripts\azurelocal\03-Convert-Gen1toGen2.ps1'; req = @('VMName', 'WorkingDirectory', 'ResourceGroup', 'SubscriptionId') }
    ) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $p), [ref]$null, [ref]$null)
        foreach ($name in $req) {
            $prm = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name }
            $prm | Should -Not -BeNullOrEmpty
            ($prm.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' }).NamedArguments.ArgumentName | Should -Contain 'Mandatory'
        }
    }
}

Describe 'Wording' {
    BeforeAll {
        $script:Texts = Get-ChildItem $script:Root -Recurse -File -Include *.md, *.ps1, *.psm1, *.psd1, *.yml, *.json, *.mts |
            Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|archive|styles|_archived_adoc|\.vitepress)[\\/]' -and $_.Name -ne 'Static.Tests.ps1' }
    }
    It 'has no lab or vendor names and no private release number' {
        ($script:Texts | Select-String -Pattern 'tpl[a]b|tier[p]oint|azrl\.mgmt|\b26[9]0\b') | Should -BeNullOrEmpty
    }
    It 'no longer states the wrong OS rule' {
        $hits = $script:Texts | Where-Object { $_.Name -ne 'CHANGELOG.md' } |
            Select-String -Pattern 'Server 2012 R2\+|Windows Server 2012 R2 / Windows 10 build 14393|Server 2016\+|build 10\.0\.14393\+|Server 2012 R2 \+'
        $hits | Should -BeNullOrEmpty
    }
    It 'README states the 2019 / Windows 10 1703 rule' {
        $r = Get-Content (Join-Path $script:Root 'README.md') -Raw
        $r | Should -Match 'Windows Server 2019'
        $r | Should -Match '1703'
    }
    It 'README carries the internal-tool notice' {
        (Get-Content (Join-Path $script:Root 'README.md') -Raw) | Should -Match 'Status: work in progress'
    }
    It 'prose has no private-preview or invitation wording' {
        ($script:Texts | Where-Object { $_.Name -ne 'CHANGELOG.md' } | Select-String -Pattern 'private[ -]preview|invitation|not available for general|preview[ -]enrolled') | Should -BeNullOrEmpty
    }
    It 'README explains Azure Migrate keeps the source generation' {
        (Get-Content (Join-Path $script:Root 'README.md') -Raw) | Should -Match 'Azure Migrate'
    }
}

Describe 'Markdown links' {
    It 'every relative link in README.md and docs/ resolves' {
        $dead = [System.Collections.Generic.List[string]]::new()
        $files = @(Get-Item (Join-Path $script:Root 'README.md')) + @(Get-ChildItem (Join-Path $script:Root 'docs') -Recurse -Filter *.md |
            Where-Object { $_.FullName -notmatch '_archived_adoc|node_modules' })
        foreach ($f in $files) {
            $inFence = $false
            foreach ($line in [IO.File]::ReadLines($f.FullName)) {
                if ($line -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
                if ($inFence) { continue }
                foreach ($m in [regex]::Matches([regex]::Replace($line, '`[^`]*`', ''), '!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')) {
                    $t = $m.Groups[1].Value
                    if ($t -match '^(https?:|mailto:|#)') { continue }
                    $clean = [uri]::UnescapeDataString((($t -split '[#?]')[0]))
                    if ($clean -and -not (Test-Path -LiteralPath (Join-Path $f.DirectoryName $clean))) { $dead.Add("$($f.Name): $t") }
                }
            }
        }
        $dead | Should -BeNullOrEmpty
    }
}
