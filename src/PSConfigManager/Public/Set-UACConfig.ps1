
# Pfad
$UacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

function Get-UacSettings {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$UacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    )

    $p = Get-ItemProperty -Path $UacPath
    [pscustomobject]@{
        EnableLUA                     = $p.EnableLUA
        ConsentPromptBehaviorAdmin    = $p.ConsentPromptBehaviorAdmin
        ConsentPromptBehaviorUser     = $p.ConsentPromptBehaviorUser
        PromptOnSecureDesktop         = $p.PromptOnSecureDesktop
        FilterAdministratorToken      = ($p.PSObject.Properties.Name -contains 'FilterAdministratorToken') ? $p.FilterAdministratorToken : $null
        LocalAccountTokenFilterPolicy = ($p.PSObject.Properties.Name -contains 'LocalAccountTokenFilterPolicy') ? $p.LocalAccountTokenFilterPolicy : $null
    }
}

function Set-RegDword {
    [CmdletBinding()]
    param(
        [string]$Name,
        [int]$Value
    )

    if (-not (Test-Path $UacPath)) { New-Item -Path $UacPath -Force | Out-Null }
    if (Get-ItemProperty -Path $UacPath -Name $Name -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $UacPath -Name $Name -Value $Value -Type DWord
    }
    else {
        New-ItemProperty -Path $UacPath -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    }
}

# UAC-"Slider" wie in der GUI (4 Stufen)
function Set-UacSlider {
    [CmdletBinding()]
    param (
        [ValidateSet('AlwaysNotify', 'Default', 'NoSecureDesktop', 'NeverNotify')]
        [string]$Level = 'Default'
    )

    switch ($Level) {
        'AlwaysNotify' { Set-RegDword 'ConsentPromptBehaviorAdmin' 2; Set-RegDword 'PromptOnSecureDesktop' 1 } # immer benachrichtigen
        'Default' { Set-RegDword 'ConsentPromptBehaviorAdmin' 5; Set-RegDword 'PromptOnSecureDesktop' 1 } # Windows-Standard
        'NoSecureDesktop' { Set-RegDword 'ConsentPromptBehaviorAdmin' 5; Set-RegDword 'PromptOnSecureDesktop' 0 } # ohne Abdunkeln
        'NeverNotify' { Set-RegDword 'ConsentPromptBehaviorAdmin' 0; Set-RegDword 'PromptOnSecureDesktop' 0 } # nie benachrichtigen
    }
}

# UAC global an/aus (Neustart nötig)
function Set-UacCore {
    [CmdletBinding()]
    param(
        [bool]$EnableLUA
    )

    Set-RegDword 'EnableLUA' ([int]$EnableLUA)
    Write-Warning "Das Ändern von EnableLUA erfordert einen Neustart."
}

# Beispiele:
# Set-UacSlider -Level Default
# Set-UacCore -EnableLUA $true
# Standardbenutzer: Nach Admin-Credentials fragen
# Set-RegDword 'ConsentPromptBehaviorUser' 1
# Built-in Administrator in Admin Approval Mode
# Set-RegDword 'FilterAdministratorToken' 1

Get-UacSettings

# EnableLUA                     : 1
# ConsentPromptBehaviorAdmin    : 5
# ConsentPromptBehaviorUser     : 1
# PromptOnSecureDesktop         : 0
# FilterAdministratorToken      : 1
# LocalAccountTokenFilterPolicy :

