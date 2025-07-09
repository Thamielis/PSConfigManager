$Script:Here = Split-Path -Parent $MyInvocation.MyCommand.Path

BeforeAll {

    $Script:ProjectPath = "$Here\..\..\.." | Convert-Path

    $Script:ManifestPath = Get-ChildItem -Path $ProjectPath -File -Recurse -Include @('*.psd1') | Where-Object {
        ($_.Directory.Name -eq $_.BaseName) -and
        $(
            try {
                Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
            }
            catch {
                $false
            }
        )
    }

    $Script:ModuleName = $ManifestPath.BaseName
    $Script:PathToManifest = $ManifestPath.FullName
    $Script:PathToModule = $PathToManifest -replace '.psd1', '.psm1'

    $mut = Import-Module -Name $PathToManifest -ErrorAction Stop -PassThru -Force #| Where-Object { $_.Path -notmatch 'ScriptsToProcess.Resolve-NodeProperty.ps1' }
    $Script:AllModuleFunctions = &$mut { Get-Command -Module $args[0] -CommandType Function } $ModuleName

}

Describe 'Changelog Management' -Tag 'Changelog' {

    It 'Changelog has been updated' -skip:(
        !(
            [bool](Get-Command git -EA SilentlyContinue) -and
            [bool](&(Get-Process -id $PID).Path -NoProfile -Command 'git rev-parse --is-inside-work-tree 2>$null'))
    ) {

        # Get the list of changed files compared with master
        $HeadCommit = &git rev-parse HEAD
        $MasterCommit = &git rev-parse origin/main
        $FilesChanged = &git @('diff', "$MasterCommit...$HeadCommit", '--name-only')

        if ($HeadCommit -ne $MasterCommit) {
            # if we're not testing same commit (i.e. master..master)
            $FilesChanged.Where{ (Split-Path $_ -Leaf) -match '^changelog' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Changelog format compliant with keepachangelog format' -skip:(![bool](Get-Command git -EA SilentlyContinue)) {
        { Get-ChangelogData -Path ([System.IO.Path]::Combine($ProjectPath, 'CHANGELOG.md')) -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe "Module $ModuleName" -Tag Unit {

    Context "Tests" {
        BeforeAll {
            $script:ManifestEval = $null
        }

        It 'Passes Test-ModuleManifest' {
            { $script:ManifestEval = Test-ModuleManifest -Path $PathToManifest } | Should -Not -Throw
            $? | Should -BeTrue
        } #manifestTest

        It "Root Module $ModuleName.psm1 should exist" {
            $PathToModule | Should -Exist
            $? | Should -BeTrue
        } #psm1Exists

        It "Manifest should contain $ModuleName.psm1" {
            $PathToManifest |
                Should -FileContentMatchExactly "$ModuleName.psm1"
        } #validPSM1

        It 'Should have a matching Module Name in the Manifest' {
            $script:ManifestEval.Name | Should -BeExactly $ModuleName
        } #name

        It 'Should have a valid description in the Manifest' {
            $script:ManifestEval.Description | Should -Not -BeNullOrEmpty
        } #description

        It 'Should have a valid author in the Manifest' {
            $script:ManifestEval.Author | Should -Not -BeNullOrEmpty
        } #author

        It 'Should have a valid version in the Manifest' {
            $script:ManifestEval.Version -as [Version] | Should -Not -BeNullOrEmpty
        } #version

        It 'Should have a valid guid in the Manifest' {
            { [guid]::Parse($script:ManifestEval.Guid) } | Should -Not -Throw
        } #guid

        It 'Should not have any spaces in the Tags' {
            foreach ($tag in $script:ManifestEval.Tags) {
                $tag | Should -Not -Match '\s'
            }
        } #tagSpaces

        #It 'should have a valid project Uri' {
        #$script:manifestEval.ProjectUri | Should -Not -BeNullOrEmpty
        #} #uri

    } #context_ModuleTests

}
