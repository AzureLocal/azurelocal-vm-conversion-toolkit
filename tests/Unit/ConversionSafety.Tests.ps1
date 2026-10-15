#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . $PSScriptRoot/TestSupport.ps1
    Install-ConversionStubs
    Import-SafetyModule
    $script:Tmp = Join-Path ([IO.Path]::GetTempPath()) ('cs-' + [guid]::NewGuid().ToString('N'))
    New-Item $script:Tmp -ItemType Directory | Out-Null
}
AfterAll {
    Uninstall-ConversionStubs
    Get-Module ConversionSafety | Remove-Module -Force
    Remove-Item $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Test-Mbr2GptOsSupport (OS gate)' {
    It 'supports <caption> build <build>' -ForEach @(
        @{ caption = 'Microsoft Windows Server 2019 Standard'; build = 17763 }
        @{ caption = 'Microsoft Windows Server 2022 Datacenter'; build = 20348 }
        @{ caption = 'Microsoft Windows Server 2025 Datacenter'; build = 26100 }
        @{ caption = 'Microsoft Windows 10 Pro'; build = 15063 }
        @{ caption = 'Microsoft Windows 11 Pro'; build = 22631 }
    ) {
        (Test-Mbr2GptOsSupport -Caption $caption -BuildNumber $build).Supported | Should -BeTrue
    }
    It 'rejects <caption> build <build> and says why' -ForEach @(
        @{ caption = 'Microsoft Windows Server 2016 Standard'; build = 14393; why = 'Server 2016 does not include' }
        @{ caption = 'Microsoft Windows Server 2012 R2 Standard'; build = 9600; why = 'predates Windows Server 2019' }
        @{ caption = 'Microsoft Windows 8.1 Pro'; build = 9600; why = 'Windows 7, 8 and 8.1 is not supported' }
        @{ caption = 'Microsoft Windows 7 Professional'; build = 7601; why = 'Windows 7, 8 and 8.1 is not supported' }
        @{ caption = 'Microsoft Windows 10 Pro'; build = 14393; why = 'predates version 1703' }
    ) {
        $r = Test-Mbr2GptOsSupport -Caption $caption -BuildNumber $build
        $r.Supported | Should -BeFalse
        $r.Reason | Should -Match $why
    }
    It 'rejects a 32-bit OS' {
        (Test-Mbr2GptOsSupport -Caption 'Microsoft Windows 10 Pro' -BuildNumber 19045 -AddressWidth 32).Supported | Should -BeFalse
    }
}

Describe 'mbr2gpt.exe availability' {
    It 'is false when the file is missing even on a supported build' {
        Test-Mbr2GptAvailable -Path (Join-Path $script:Tmp 'nope\mbr2gpt.exe') | Should -BeFalse
    }
    It 'is false for an empty file' {
        $p = Join-Path $script:Tmp 'empty.exe'; [IO.File]::WriteAllBytes($p, [byte[]]@())
        Test-Mbr2GptAvailable -Path $p | Should -BeFalse
    }
    It 'is true for a real file' {
        $p = Initialize-TestDisk -Directory $script:Tmp -Name 'mbr2gpt.exe' -Bytes 64
        Test-Mbr2GptAvailable -Path $p | Should -BeTrue
    }
    It 'builds the path under the given system root' {
        Get-Mbr2GptPath -SystemRoot 'X:\Windows' | Should -Match 'X:\\Windows\\(System32|Sysnative)\\mbr2gpt\.exe$'
    }
}

Describe 'Get-BitLockerConversionState' {
    It 'maps <vs>/<ps> to <state> (ready: <ready>)' -ForEach @(
        @{ vs = 'FullyDecrypted'; ps = 'Off'; state = 'NotEncrypted'; ready = $true }
        @{ vs = 'FullyEncrypted'; ps = 'Off'; state = 'Suspended'; ready = $true }
        @{ vs = 'FullyEncrypted'; ps = 'On'; state = 'Protected'; ready = $false }
        @{ vs = 'EncryptionInProgress'; ps = 'On'; state = 'InProgress'; ready = $false }
        @{ vs = 'FullyEncrypted'; ps = 'Unknown'; state = 'Unknown'; ready = $false }
        @{ vs = 'EncryptionInProgress'; ps = 'Off'; state = 'InProgress'; ready = $false }
        @{ vs = 'DecryptionPaused'; ps = 'Off'; state = 'InProgress'; ready = $false }
    ) {
        $r = Get-BitLockerConversionState -Volume ([pscustomobject]@{ VolumeStatus = $vs; ProtectionStatus = $ps })
        $r.State | Should -Be $state
        $r.Ready | Should -Be $ready
    }
    It 'is not ready when there is no volume object' {
        (Get-BitLockerConversionState -Volume $null).Ready | Should -BeFalse
    }
}

Describe 'Assert-BackupPolicy' {
    It 'allows a backup' { { Assert-BackupPolicy -BackupVHDX $true } | Should -Not -Throw }
    It 'refuses no backup without the acknowledgement' {
        { Assert-BackupPolicy -BackupVHDX $false } | Should -Throw '*-IUnderstandNoBackup*'
    }
    It 'allows no backup with the acknowledgement' {
        { Assert-BackupPolicy -BackupVHDX $false -IUnderstandNoBackup } | Should -Not -Throw
    }
}

Describe 'Test-FileIntegrity' {
    BeforeEach {
        $script:src = Initialize-TestDisk -Directory (Join-Path $script:Tmp 'i-src') -Name 'a.vhdx' -Bytes 8192
        $script:dst = Join-Path $script:Tmp 'i-dst\a.vhdx'
        New-Item (Split-Path $script:dst) -ItemType Directory -Force | Out-Null
    }
    It 'passes for an identical copy' {
        Copy-Item $script:src $script:dst -Force
        $r = Test-FileIntegrity -Source $script:src -Destination $script:dst
        $r.Ok | Should -BeTrue
        $r.SourceHash | Should -Be $r.DestinationHash
    }
    It 'fails when the copy is missing' {
        Remove-Item $script:dst -ErrorAction SilentlyContinue
        (Test-FileIntegrity -Source $script:src -Destination $script:dst).Reason | Should -Match 'copy is missing'
    }
    It 'fails on a size difference' {
        [IO.File]::WriteAllBytes($script:dst, [byte[]]::new(100))
        (Test-FileIntegrity -Source $script:src -Destination $script:dst).Reason | Should -Match 'size differs'
    }
    It 'fails on a same-size corruption (SHA256)' {
        Copy-Item $script:src $script:dst -Force
        $b = [IO.File]::ReadAllBytes($script:dst); $b[100] = [byte](($b[100] + 1) % 256); [IO.File]::WriteAllBytes($script:dst, $b)
        $r = Test-FileIntegrity -Source $script:src -Destination $script:dst
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Match 'SHA256 differs'
    }
    It 'fails for an empty source' {
        [IO.File]::WriteAllBytes($script:src, [byte[]]@()); [IO.File]::WriteAllBytes($script:dst, [byte[]]@())
        (Test-FileIntegrity -Source $script:src -Destination $script:dst).Ok | Should -BeFalse
    }
}

Describe 'Get-VhdChain and Copy-VhdChainWithVerification' {
    BeforeEach {
        $script:dir = Join-Path $script:Tmp ('c-' + [guid]::NewGuid().ToString('N'))
        $script:parent = Initialize-TestDisk -Directory $script:dir -Name 'parent.vhdx' -Bytes 5000
        $script:child = Initialize-TestDisk -Directory $script:dir -Name 'child.avhdx' -Bytes 3000
        $script:other = Initialize-TestDisk -Directory $script:dir -Name 'data.vhdx' -Bytes 2000
        $script:bk = Join-Path $script:dir 'backup'
        $global:T_Parents = @{ $script:child = $script:parent }
        Mock Get-VHD { [pscustomobject]@{ ParentPath = $global:T_Parents[$Path] } } -ModuleName ConversionSafety
        Mock Get-PathFreeBytes { [long]10GB } -ModuleName ConversionSafety
        $script:log = { param($m) }
    }
    It 'walks a differencing chain, leaf first' {
        (Get-VhdChain -Path $script:child) | Should -Be @($script:child, $script:parent)
    }
    It 'detects a loop in the chain' {
        $global:T_Parents = @{ $script:child = $script:parent; $script:parent = $script:child }
        { Get-VhdChain -Path $script:child } | Should -Throw '*Loop*'
    }
    It 'copies the whole chain plus other disks and verifies each file' {
        $r = Copy-VhdChainWithVerification -DiskPath @($script:child, $script:other) -DestinationDirectory $script:bk -Log $script:log
        $r.Count | Should -Be 3
        ($r | Where-Object { -not $_.Ok }) | Should -BeNullOrEmpty
        (Get-ChildItem $script:bk).Name | Should -Contain 'parent.vhdx'
        (Test-Path $script:child) | Should -BeTrue    # source untouched
    }
    It 'stops before copying anything when free space is too small' {
        Mock Get-PathFreeBytes { [long]1000 } -ModuleName ConversionSafety
        { Copy-VhdChainWithVerification -DiskPath @($script:other) -DestinationDirectory $script:bk -Log $script:log } | Should -Throw '*Not enough free space*'
        (Get-ChildItem $script:bk -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }
    It 'refuses to overwrite an existing backup file' {
        New-Item $script:bk -ItemType Directory -Force | Out-Null
        Copy-Item $script:other (Join-Path $script:bk 'data.vhdx')
        { Copy-VhdChainWithVerification -DiskPath @($script:other) -DestinationDirectory $script:bk -Log $script:log } | Should -Throw '*refusing to overwrite*'
    }
    It 'throws when a copy does not verify and leaves the source alone' {
        Mock Copy-Item { [IO.File]::WriteAllBytes($Destination, [byte[]]::new(10)) } -ModuleName ConversionSafety
        { Copy-VhdChainWithVerification -DiskPath @($script:other) -DestinationDirectory $script:bk -Log $script:log } | Should -Throw '*did not verify*'
        (Get-Item $script:other).Length | Should -Be 2000
    }
    It 'keeps two disks with the same file name from different folders' {
        $d2 = Initialize-TestDisk -Directory (Join-Path $script:dir 'other') -Name 'data.vhdx' -Bytes 1500
        $r = Copy-VhdChainWithVerification -DiskPath @($script:other, $d2) -DestinationDirectory $script:bk -Log $script:log
        $r.Count | Should -Be 2
        @(Get-ChildItem $script:bk).Count | Should -Be 2
    }
}

Describe 'Assert-VerifiedBackup' {
    BeforeEach {
        $script:d = Initialize-TestDisk -Directory (Join-Path $script:Tmp 'v') -Name 'x.vhdx' -Bytes 100
        $script:dst = Initialize-TestDisk -Directory (Join-Path $script:Tmp 'v-copy') -Name 'x.vhdx' -Bytes 100
        Mock Get-VHD { [pscustomobject]@{ ParentPath = $null } } -ModuleName ConversionSafety
    }
    It 'passes when every file has a verified record' {
        { Assert-VerifiedBackup -DiskPath @($script:d) -Record @([pscustomobject]@{ Ok = $true; Source = $script:d; Destination = $script:dst }) } | Should -Not -Throw
    }
    It 'throws when the recorded copy has since disappeared' {
        { Assert-VerifiedBackup -DiskPath @($script:d) -Record @([pscustomobject]@{ Ok = $true; Source = $script:d; Destination = (Join-Path $script:Tmp 'gone.vhdx') }) } | Should -Throw '*No verified backup*'
    }
    It 'throws when no disks are supplied' {
        { Assert-VerifiedBackup -DiskPath @() -Record @([pscustomobject]@{ Ok = $true; Source = 'x'; Destination = $script:dst }) } | Should -Throw '*No disks*'
    }
    It 'throws with no records' { { Assert-VerifiedBackup -DiskPath @($script:d) -Record @() } | Should -Throw '*No verified backup*' }
    It 'throws with a null record list' { { Assert-VerifiedBackup -DiskPath @($script:d) -Record $null } | Should -Throw '*No verified backup*' }
    It 'throws when only a failed record exists' {
        { Assert-VerifiedBackup -DiskPath @($script:d) -Record @([pscustomobject]@{ Ok = $false; Source = $script:d }) } | Should -Throw
    }
    It 'throws when one of two disks has no record' {
        { Assert-VerifiedBackup -DiskPath @($script:d, 'C:\other.vhdx') -Record @([pscustomobject]@{ Ok = $true; Source = $script:d; Destination = $script:dst }) } | Should -Throw "*other.vhdx*"
    }
}
