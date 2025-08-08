
<#
.SYNOPSIS
  Kombiniertes Toolkit für UAC, Passwortspeicherung, RDP-Delegation und "Ausführen als..."
  Enthält einen Report mit aktuellen Werten und Erklärungen.

.NOTES
  - Als Administrator ausführen, um Maschinen-Policies zu setzen.
  - EnableLUA-Änderungen erfordern einen Neustart.
#>

Set-StrictMode -Version Latest

# ---- Registry Helper ----
function Set-RegDword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord
    }
    else {
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    }
}

function Get-RegValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    try {
        (Get-ItemProperty -Path $Path -ErrorAction Stop).$Name
    }
    catch { $null }
}

# ---- UAC ----
$UacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

function Get-UacSettings {
    [CmdletBinding()]
    param()
    $p = Get-ItemProperty -Path $UacPath -ErrorAction SilentlyContinue
    [pscustomobject]@{
        EnableLUA                     = $p.EnableLUA
        ConsentPromptBehaviorAdmin    = $p.ConsentPromptBehaviorAdmin
        ConsentPromptBehaviorUser     = $p.ConsentPromptBehaviorUser
        PromptOnSecureDesktop         = $p.PromptOnSecureDesktop
        FilterAdministratorToken      = (Get-RegValue -Path $UacPath -Name 'FilterAdministratorToken')
        LocalAccountTokenFilterPolicy = (Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'LocalAccountTokenFilterPolicy')
    }
}

function Set-UacCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$EnableLUA)
    Set-RegDword -Path $UacPath -Name 'EnableLUA' -Value ([int]$EnableLUA)
    Write-Warning "EnableLUA geändert. Ein Neustart ist erforderlich."
}

function Set-UacSlider {
    [CmdletBinding()]
    param(
        [ValidateSet('AlwaysNotify', 'Default', 'NoSecureDesktop', 'NeverNotify')]
        [string]$Level = 'Default'
    )
    switch ($Level) {
        'AlwaysNotify' { Set-RegDword -Path $UacPath -Name 'ConsentPromptBehaviorAdmin' -Value 2; Set-RegDword -Path $UacPath -Name 'PromptOnSecureDesktop' -Value 1 }
        'Default' { Set-RegDword -Path $UacPath -Name 'ConsentPromptBehaviorAdmin' -Value 5; Set-RegDword -Path $UacPath -Name 'PromptOnSecureDesktop' -Value 1 }
        'NoSecureDesktop' { Set-RegDword -Path $UacPath -Name 'ConsentPromptBehaviorAdmin' -Value 5; Set-RegDword -Path $UacPath -Name 'PromptOnSecureDesktop' -Value 0 }
        'NeverNotify' { Set-RegDword -Path $UacPath -Name 'ConsentPromptBehaviorAdmin' -Value 0; Set-RegDword -Path $UacPath -Name 'PromptOnSecureDesktop' -Value 0 }
    }
}

# ---- Passwortspeicherung & RDP ----
function Set-CredentialStorage {
    [CmdletBinding()]
    param([ValidateSet('Allow', 'Deny')][string]$Mode = 'Deny')
    $val = @{'Allow' = 0; 'Deny' = 1 }[$Mode]
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds' -Value $val
}

function Set-RdpClientPasswordSaving {
    [CmdletBinding()]
    param(
        [ValidateSet('Allow', 'Deny')][string]$Mode = 'Deny',
        [switch]$PerUser
    )
    $base = ($PerUser) ? 'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
    : 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'
    Set-RegDword -Path $base -Name 'DisablePasswordSaving' -Value (@{'Allow' = 0; 'Deny' = 1 }[$Mode])
}

function Set-RdpServerAlwaysPrompt {
    [CmdletBinding()]
    param([bool]$Enabled = $true)
    Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'fPromptForPassword' -Value ([int]$Enabled)
}

function Enable-RdpSavedCredentialsDelegation {
    [CmdletBinding()]
    param([string[]]$SpnList = @('TERMSRV/*'))
    $root = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    Set-RegDword -Path $root -Name 'AllowSavedCredentials' -Value 1
    Set-RegDword -Path $root -Name 'AllowSavedCredentialsWhenNTLMOnly' -Value 1
    Set-RegDword -Path $root -Name 'ConcatenateDefaults_AllowSavedNTLMOnly' -Value 1

    $sub = Join-Path $root 'AllowSavedCredentialsWhenNTLMOnly'
    if (-not (Test-Path $sub)) { New-Item -Path $sub -Force | Out-Null }

    # alte nummerierte Einträge bereinigen
    Get-Item -Path $sub -ErrorAction SilentlyContinue | ForEach-Object {
        $_ | Get-ItemProperty | Select-Object -ExpandProperty PSObject |
            ForEach-Object { $_.Properties } |
                Where-Object { $_.Name -match '^\d+$' } |
                    ForEach-Object { Remove-ItemProperty -Path $sub -Name $_.Name -Force -ErrorAction SilentlyContinue }
                } | Out-Null

    $i = 1
    foreach ($spn in $SpnList) {
        New-ItemProperty -Path $sub -Name "$i" -PropertyType String -Value $spn -Force | Out-Null
        $i++
    }
}

# ---- "Ausführen als anderer Benutzer" ----
function Enable-RunAsDifferentUser {
    [CmdletBinding()]
    param()
    Set-RegDword -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart' -Value 1
    Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb' -Value 0
    try {
        Set-Service -Name seclogon -StartupType Manual -ErrorAction Stop
        Start-Service -Name seclogon -ErrorAction Stop
    }
    catch {
        Write-Warning "Dienst 'Sekundäre Anmeldung' (seclogon) konnte nicht gestartet/gesetzt werden: $($_.Exception.Message)"
    }
}

# ---- Erklärungstabellen ----
$ExplainAdmin = @{
    0 = 'Erhöhen ohne Nachfrage (unsicher)'
    1 = 'Anmeldedaten erforderlich (Secure Desktop, falls aktiv)'
    2 = 'Zustimmung erforderlich (Secure Desktop, falls aktiv)'
    3 = 'Anmeldedaten erforderlich (kein Secure Desktop erzwungen)'
    4 = 'Zustimmung erforderlich (kein Secure Desktop erzwungen)'
    5 = 'Zustimmung nur für Nicht-Windows-Binärdateien (Standard)'
}
$ExplainUser = @{
    0 = 'Standardbenutzer: Elevation wird automatisch verweigert'
    1 = 'Standardbenutzer: Nach Admin-Anmeldedaten fragen'
}

function Get-UacSliderDerived {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ConsentAdmin, [Parameter(Mandatory)][int]$SecureDesktop, [Parameter(Mandatory)][int]$EnableLUA)
    if ($EnableLUA -eq 0) { return 'UAC deaktiviert (EnableLUA=0)' }
    if ($ConsentAdmin -eq 2 -and $SecureDesktop -eq 1) { return 'AlwaysNotify' }
    if ($ConsentAdmin -eq 5 -and $SecureDesktop -eq 1) { return 'Default' }
    if ($ConsentAdmin -eq 5 -and $SecureDesktop -eq 0) { return 'NoSecureDesktop' }
    if ($ConsentAdmin -eq 0 -and $SecureDesktop -eq 0) { return 'NeverNotify' }
    return "Custom (Admin=$ConsentAdmin, SecureDesktop=$SecureDesktop)"
}

# ---- REPORT ----
function Get-SecurityInteractionReport {
    [CmdletBinding()]
    param(
        [ValidateSet('Console', 'Object', 'Json', 'Markdown', 'Csv', 'Html')]
        [string]$Out = 'Console',
        [string]$Path
    )

    $rows = New-Object System.Collections.Generic.List[object]

    # UAC
    $u = Get-UacSettings
    $slider = Get-UacSliderDerived -ConsentAdmin ($u.ConsentPromptBehaviorAdmin ?? -1) -SecureDesktop ($u.PromptOnSecureDesktop ?? -1) -EnableLUA ($u.EnableLUA ?? -1)

    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'EnableLUA'; Path = $UacPath; Name = 'EnableLUA'
            Value = $u.EnableLUA; Meaning = if ($u.EnableLUA -eq 1) { 'UAC aktiv' } elseif ($u.EnableLUA -eq 0) { 'UAC deaktiviert (Neustart nötig nach Änderung)' } else { 'Nicht gesetzt' }
            Notes = 'Globaler UAC-Schalter'
        })
    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'Admin-Prompt'; Path = $UacPath; Name = 'ConsentPromptBehaviorAdmin'
            Value = $u.ConsentPromptBehaviorAdmin
            Meaning = $ExplainAdmin[$u.ConsentPromptBehaviorAdmin]
            Notes = "Abstimmung mit Secure Desktop empfohlen"
        })
    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'Secure Desktop'; Path = $UacPath; Name = 'PromptOnSecureDesktop'
            Value = $u.PromptOnSecureDesktop
            Meaning = if ($u.PromptOnSecureDesktop -eq 1) { 'UAC-Dialog auf Secure Desktop (dunkel)' } elseif ($u.PromptOnSecureDesktop -eq 0) { 'UAC-Dialog ohne Secure Desktop' } else { 'Nicht gesetzt' }
            Notes = 'Härtet gegen UI-Spoofing'
        })
    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'Standardbenutzer-Prompt'; Path = $UacPath; Name = 'ConsentPromptBehaviorUser'
            Value = $u.ConsentPromptBehaviorUser
            Meaning = $ExplainUser[$u.ConsentPromptBehaviorUser]
            Notes = 'Verhalten bei Nicht-Admins'
        })
    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'Built-in Administrator'; Path = $UacPath; Name = 'FilterAdministratorToken'
            Value = $u.FilterAdministratorToken
            Meaning = switch ($u.FilterAdministratorToken) { 1 { 'Admin Approval Mode aktiv' } 0 { 'Nicht im Admin Approval Mode' } default { 'Nicht gesetzt' } }
            Notes = 'Gilt für integriertes Admin-Konto (RID 500)'
        })
    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'Remote UAC (lokale Konten)'; Path = $UacPath; Name = 'LocalAccountTokenFilterPolicy'
            Value = $u.LocalAccountTokenFilterPolicy
            Meaning = switch ($u.LocalAccountTokenFilterPolicy) { 1 { 'UAC-Remoteeinschränkung AUS (weniger sicher)' } 0 { 'UAC-Remoteeinschränkung AN (Standard)' } default { 'Nicht gesetzt' } }
            Notes = 'Beeinflusst Remoting mit lokalen Admin-Konten'
        })
    $rows.Add([pscustomobject]@{
            Area = 'UAC'; Setting = 'UAC-Slider (abgeleitet)'; Path = $UacPath; Name = '(derived)'
            Value = $slider
            Meaning = 'Abgeleitet aus ConsentPromptBehaviorAdmin + PromptOnSecureDesktop + EnableLUA'
            Notes = 'Nur zur Orientierung'
        })

    # Credential Storage
    $disableDomainCreds = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds'
    $rows.Add([pscustomobject]@{
            Area = 'Credentials'; Setting = 'Speichern von Domänen-Creds'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name = 'DisableDomainCreds'
            Value = $disableDomainCreds
            Meaning = switch ($disableDomainCreds) { 1 { 'Speichern VERBOTEN' } 0 { 'Speichern ERLAUBT' } default { 'Nicht gesetzt' } }
            Notes = 'Credential Manager / Domänen-Anmeldedaten'
        })

    # RDP Client Password Saving
    foreach ($scope in @(
            @{Scope = 'Computerweit'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client' },
            @{Scope = 'Benutzer'; Path = 'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client' }
        )) {
        $val = Get-RegValue -Path $scope.Path -Name 'DisablePasswordSaving'
        $rows.Add([pscustomobject]@{
                Area = 'RDP-Client'; Setting = "Kennwort speichern ($($scope.Scope))"; Path = $scope.Path; Name = 'DisablePasswordSaving'
                Value = $val
                Meaning = switch ($val) { 1 { 'Speichern untersagt' } 0 { 'Speichern erlaubt' } default { 'Nicht gesetzt' } }
                Notes = 'mstsc: "Kennwort speichern"'
            })
    }

    # RDP Server Prompt
    $fPrompt = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fPromptForPassword'
    $rows.Add([pscustomobject]@{
            Area = 'RDP-Server'; Setting = 'Immer nach Kennwort fragen'; Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; Name = 'fPromptForPassword'
            Value = $fPrompt
            Meaning = switch ($fPrompt) { 1 { 'Immer Kennwort abfragen' } 0 { 'Gespeicherte Creds zulässig' } default { 'Nicht gesetzt' } }
            Notes = 'Serverseitige Abfrage'
        })

    # Credentials Delegation
    $credRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    $allow1 = Get-RegValue -Path $credRoot -Name 'AllowSavedCredentials'
    $allow2 = Get-RegValue -Path $credRoot -Name 'AllowSavedCredentialsWhenNTLMOnly'
    $listKey = Join-Path $credRoot 'AllowSavedCredentialsWhenNTLMOnly'
    $spnList = @()
    if (Test-Path $listKey) {
        $props = Get-ItemProperty -Path $listKey
        $spnList = $props.PSObject.Properties |
            Where-Object { $_.Name -match '^\d+$' } |
                Sort-Object { [int]$_.Name } |
                    Select-Object -ExpandProperty Value
    }
    $rows.Add([pscustomobject]@{
            Area = 'Cred Delegation'; Setting = 'AllowSavedCredentials'; Path = $credRoot; Name = 'AllowSavedCredentials'
            Value = $allow1
            Meaning = if ($allow1 -eq 1) { 'Gespeicherte Anmeldedaten delegierbar' } elseif ($allow1 -eq 0) { 'Nicht delegierbar' } else { 'Nicht gesetzt' }
            Notes = 'Clientseitige Delegation'
        })
    $rows.Add([pscustomobject]@{
            Area = 'Cred Delegation'; Setting = 'AllowSavedCredentialsWhenNTLMOnly'; Path = $credRoot; Name = 'AllowSavedCredentialsWhenNTLMOnly'
            Value = $allow2
            Meaning = if ($allow2 -eq 1) { 'Delegation auch bei NTLM-only Serverauth' } elseif ($allow2 -eq 0) { 'Nicht erlaubt' } else { 'Nicht gesetzt' }
            Notes = 'NTLM-only Variante'
        })
    $rows.Add([pscustomobject]@{
            Area = 'Cred Delegation'; Setting = 'SPN-Liste'; Path = $listKey; Name = '1..N'
            Value = ($spnList -join ', ')
            Meaning = if ($spnList) { 'Zielserver/Pattern für Delegation' } else { 'Keine Einträge' }
            Notes = 'Typisch: TERMSRV/*'
        })

    # RunAs different user
    $showRun = Get-RegValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart'
    $hideVerb = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb'
    $svc = Get-Service -Name seclogon -ErrorAction SilentlyContinue
    $rows.Add([pscustomobject]@{
            Area = 'RunAs'; Setting = 'Menüpunkt anzeigen (Start)'; Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'ShowRunAsDifferentUserInStart'
            Value = $showRun
            Meaning = switch ($showRun) { 1 { 'Anzeige ERZWUNGEN' } 0 { 'Nicht erzwungen' } default { 'Nicht gesetzt' } }
            Notes = 'Pro Benutzer'
        })
    $rows.Add([pscustomobject]@{
            Area = 'RunAs'; Setting = 'RunAsVerb verstecken'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'HideRunAsVerb'
            Value = $hideVerb
            Meaning = switch ($hideVerb) { 1 { 'RunAs ausgeblendet' } 0 { 'RunAs sichtbar' } default { 'Nicht gesetzt' } }
            Notes = 'Maschinenweit'
        })
    $rows.Add([pscustomobject]@{
            Area = 'RunAs'; Setting = 'Dienst Sekundäre Anmeldung'; Path = 'Service: seclogon'; Name = 'Status'
            Value = if ($svc) { "$($svc.Status) / $($svc.StartType)" } else { 'Nicht vorhanden' }
            Meaning = if ($svc -and $svc.Status -eq 'Running') { 'Erforderlich für RunAs' } else { 'Muss laufen' }
            Notes = 'Service steuert RunAs-Funktionalität'
        })

    switch ($Out) {
        'Object' { return $rows }
        'Json' { ($rows | ConvertTo-Json -Depth 4) | If ($Path) { Set-Content -Path $Path -Encoding UTF8 } else { Write-Output } ; break }
        'Markdown' {
            $md = @()
            $md += '| Area | Setting | Value | Meaning | Notes |'
            $md += '|------|---------|-------|---------|-------|'
            foreach ($r in $rows) {
                $v = ($r.Value -replace '\|', '\|')
                $me = ($r.Meaning -replace '\|', '\|')
                $no = ($r.Notes -replace '\|', '\|')
                $md += "| $($r.Area) | $($r.Setting) | $v | $me | $no |"
            }
            $out = $md -join [Environment]::NewLine
            if ($Path) { Set-Content -Path $Path -Value $out -Encoding UTF8 } else { $out }
            break
        }
        'Csv' { if ($Path) { $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 } else { $rows | ConvertTo-Csv -NoTypeInformation } ; break }
        'Html' {
            $html = $rows | Sort-Object Area, Setting | ConvertTo-Html -Title 'Security Interaction Report' -PreContent "<h2>Security Interaction Report</h2><p>$(Get-Date)</p>"
            if ($Path) { Set-Content -Path $Path -Value $html -Encoding UTF8 } else { $html }
            break
        }
        default { $rows | Sort-Object Area, Setting | Format-Table -AutoSize }
    }
}

# --------- Beispiele ---------
<#
# UAC-Standard setzen:
Set-UacSlider -Level Default

# UAC komplett aus:
Set-UacCore -EnableLUA $false

# Systemweit Credential-Speichern verbieten:
Set-CredentialStorage -Mode Deny

# RDP: Clientseitig Speichern verhindern (Computerweit):
Set-RdpClientPasswordSaving -Mode Deny

# RDP-Server: Immer nach Kennwort fragen:
Set-RdpServerAlwaysPrompt -Enabled $true

# Gespeicherte RDP-Creds delegieren (Client):
Enable-RdpSavedCredentialsDelegation -SpnList @('TERMSRV/*')

# "Ausführen als anderer Benutzer" sicherstellen:
Enable-RunAsDifferentUser

# Report anzeigen (Konsole):
Get-SecurityInteractionReport

# Report als HTML:
Get-SecurityInteractionReport -Out Html -Path "$env:USERPROFILE\Desktop\SecurityInteractionReport.html"
#>
