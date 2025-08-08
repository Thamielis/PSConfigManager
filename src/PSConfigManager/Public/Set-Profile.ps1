#### powershell
<#
.SYNOPSIS
  Session-Policy Toolkit für UAC, RunAs, RDP-Credentials & Clipboard inkl. Report, Backup & Restore.

.DESCRIPTION
  - Stellt "Ausführen als anderer Benutzer" sichtbar und funktionsfähig.
  - Setzt UAC für Admins auf "ohne Nachfrage/Bestätigung".
  - Erlaubt RDP-Auto-Credentials (für z. B. Devolutions RDM), Kennwortspeicherung & Delegation.
  - Erlaubt RDP-Clipboard (Copy/Paste).
  - Erstellt einen detaillierten Report (Console/Markdown/JSON/HTML).
  - Sichert vorherige Werte und kann sie wiederherstellen.

.NOTES
  - Als Administrator ausführen.
  - GPOs können die Settings später übersteuern.
  - EnableLUA wird nicht ausgeschaltet (kein Neustart nötig).

#>

Set-StrictMode -Version Latest

# ------------------ Helpers ------------------

function Set-RegistryDword {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][int]$Value
  )
  try {
    if (-not (Test-Path -Path $Path)) {
      if ($PSCmdlet.ShouldProcess($Path, 'New-Item')) { New-Item -Path $Path -Force | Out-Null }
    }
    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set/New DWORD = $Value")) {
      if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -ErrorAction Stop
      } else {
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
      }
    }
  } catch {
    Write-Error "Set-RegistryDword: Fehler bei $Path\$Name → $Value: $($_.Exception.Message)"
  }
}

function Get-RegistryValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name
  )
  try {
    if (-not (Test-Path -Path $Path)) { return $null }
    $Item = Get-ItemProperty -Path $Path -ErrorAction Stop
    if ($Item.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Item.$Name
  } catch {
    Write-Verbose "Get-RegistryValue: $Path\$Name nicht lesbar: $($_.Exception.Message)"
    return $null
  }
}

function Add-ReportRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows,
    [Parameter(Mandatory)][string]$Area,
    [Parameter(Mandatory)][string]$Setting,
    [Parameter()][string]$Path,
    [Parameter()][string]$Name,
    [Parameter()][object]$Value,
    [Parameter()][string]$Meaning,
    [Parameter()][string]$Notes
  )
  $Rows.Add([pscustomobject]@{
    Area    = $Area
    Setting = $Setting
    Path    = $Path
    Name    = $Name
    Value   = $(if ($null -eq $Value) { '<null>' } else { $Value })
    Meaning = $Meaning
    Notes   = $Notes
  }) | Out-Null
}

# ------------------ Backup / Restore ------------------

$BackupPath = Join-Path $env:ProgramData 'RdmUacSessionBackup.json'

function Save-SecurityInteractionState {
  [CmdletBinding()]
  param()
  try {
    $Targets = @(
      @{Path='HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name='ShowRunAsDifferentUserInStart'}
      @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='HideRunAsVerb'}
      @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='ConsentPromptBehaviorAdmin'}
      @{Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name='PromptOnSecureDesktop'}
      @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; Name='DisableDomainCreds'}
      @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'; Name='DisablePasswordSaving'}
      @{Path='HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'; Name='DisablePasswordSaving'}
      @{Path='HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'; Name='fPromptForPassword'}
      @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; Name='fDisableClip'}
      @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'; Name='AllowSavedCredentials'}
      @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'; Name='AllowSavedCredentialsWhenNTLMOnly'}
      @{Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'; Name='ConcatenateDefaults_AllowSavedNTLMOnly'}
    )

    $ListKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentialsWhenNTLMOnly'
    $SpnList = @()
    if (Test-Path $ListKey) {
      $Props = (Get-ItemProperty -Path $ListKey).PSObject.Properties |
               Where-Object { $_.Name -match '^\d+$' } |
               Sort-Object { [int]$_.Name }
      $SpnList = @($Props | ForEach-Object { $_.Value })
    }

    $ServiceInfo = $null
    $Svc = Get-Service -Name seclogon -ErrorAction SilentlyContinue
    if ($Svc) {
      $ServiceInfo = @{ Status = $Svc.Status; StartType = $Svc.StartType }
    }

    $Backup = @{
      Values = @(
        foreach ($T in $Targets) {
          [pscustomobject]@{
            Path  = $T.Path
            Name  = $T.Name
            Value = Get-RegistryValue -Path $T.Path -Name $T.Name
          }
        }
      )
      CredDelegationSpns = $SpnList
      Seclogon           = $ServiceInfo
    }

    $Backup | ConvertTo-Json -Depth 6 | Set-Content -Path $BackupPath -Encoding UTF8
  } catch {
    Write-Error "Save-SecurityInteractionState: $($_.Exception.Message)"
  }
}

function Restore-SecurityInteractionState {
  [CmdletBinding(SupportsShouldProcess)]
  param()
  if (-not (Test-Path $BackupPath)) {
    Write-Warning "Restore: Kein Backup gefunden unter $BackupPath"
    return
  }
  try {
    $Backup = Get-Content $BackupPath -Raw | ConvertFrom-Json

    foreach ($V in $Backup.Values) {
      if ($null -ne $V.Value) {
        if ($PSCmdlet.ShouldProcess("$($V.Path)\$($V.Name)", "Restore DWORD=$($V.Value)")) {
          Set-RegistryDword -Path $V.Path -Name $V.Name -Value [int]$V.Value
        }
      } else {
        if (Test-Path $V.Path) {
          if ((Get-ItemProperty -Path $V.Path -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains $V.Name) {
            if ($PSCmdlet.ShouldProcess("$($V.Path)\$($V.Name)", "Remove-ItemProperty")) {
              Remove-ItemProperty -Path $V.Path -Name $V.Name -Force -ErrorAction SilentlyContinue
            }
          }
        }
      }
    }

    $Sub = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowSavedCredentialsWhenNTLMOnly'
    if (-not (Test-Path $Sub)) { New-Item -Path $Sub -Force | Out-Null }
    (Get-ItemProperty -Path $Sub -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -match '^\d+$' } |
      ForEach-Object { Remove-ItemProperty -Path $Sub -Name $_.Name -Force -ErrorAction SilentlyContinue }

    $I = 1
    foreach ($Spn in $Backup.CredDelegationSpns) {
      if ($PSCmdlet.ShouldProcess("$Sub\$I", "Restore SPN='$Spn'")) {
        New-ItemProperty -Path $Sub -Name "$I" -PropertyType String -Value $Spn -Force -ErrorAction SilentlyContinue | Out-Null
      }
      $I++
    }

    if ($Backup.Seclogon) {
      try {
        Set-Service -Name seclogon -StartupType $Backup.Seclogon.StartType -ErrorAction Stop
        if ($Backup.Seclogon.Status -eq 'Running') {
          Start-Service -Name seclogon -ErrorAction SilentlyContinue
        } else {
          Stop-Service -Name seclogon -Force -ErrorAction SilentlyContinue
        }
      } catch {
        Write-Warning "Restore: seclogon konnte nicht exakt wiederhergestellt werden: $($_.Exception.Message)"
      }
    }

    Write-Host "Restore abgeschlossen."
  } catch {
    Write-Error "Restore-SecurityInteractionState: $($_.Exception.Message)"
  }
}

# ------------------ Feature Functions ------------------

function Enable-RunAsDifferentUser {
  [CmdletBinding(SupportsShouldProcess)]
  param()
  try {
    Set-RegistryDword -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart' -Value 1
    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb' -Value 0
    try {
      if ($PSCmdlet.ShouldProcess('seclogon', 'Ensure running/manual')) {
        Set-Service -Name seclogon -StartupType Manual -ErrorAction Stop
        if ((Get-Service seclogon).Status -ne 'Running') {
          Start-Service -Name seclogon -ErrorAction Stop
        }
      }
    } catch {
      Write-Warning "Enable-RunAsDifferentUser: seclogon Problem: $($_.Exception.Message)"
    }
  } catch {
    Write-Error "Enable-RunAsDifferentUser: $($_.Exception.Message)"
  }
}

function Set-UacAdminNoPrompt {
  [CmdletBinding(SupportsShouldProcess)]
  param()
  try {
    $UacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-RegistryDword -Path $UacPath -Name 'ConsentPromptBehaviorAdmin' -Value 0
    Set-RegistryDword -Path $UacPath -Name 'PromptOnSecureDesktop' -Value 0
  } catch {
    Write-Error "Set-UacAdminNoPrompt: $($_.Exception.Message)"
  }
}

function Enable-RdpAutoCredentials {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter()][string[]]$SpnList = @('TERMSRV/*')
  )
  try {
    foreach ($Base in @(
      'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client',
      'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
    )) {
      Set-RegistryDword -Path $Base -Name 'DisablePasswordSaving' -Value 0
    }

    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds' -Value 0
    Set-RegistryDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fPromptForPassword' -Value 0

    $Root = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
    Set-RegistryDword -Path $Root -Name 'AllowSavedCredentials' -Value 1
    Set-RegistryDword -Path $Root -Name 'AllowSavedCredentialsWhenNTLMOnly' -Value 1
    Set-RegistryDword -Path $Root -Name 'ConcatenateDefaults_AllowSavedNTLMOnly' -Value 1

    $Sub = Join-Path $Root 'AllowSavedCredentialsWhenNTLMOnly'
    if (-not (Test-Path $Sub)) { New-Item -Path $Sub -Force | Out-Null }
    (Get-ItemProperty -Path $Sub -ErrorAction SilentlyContinue).PSObject.Properties |
      Where-Object { $_.Name -match '^\d+$' } |
      ForEach-Object { Remove-ItemProperty -Path $Sub -Name $_.Name -Force -ErrorAction SilentlyContinue }

    $Idx = 1
    foreach ($Spn in $SpnList) {
      New-ItemProperty -Path $Sub -Name "$Idx" -PropertyType String -Value $Spn -Force -ErrorAction SilentlyContinue | Out-Null
      $Idx++
    }
  } catch {
    Write-Error "Enable-RdpAutoCredentials: $($_.Exception.Message)"
  }
}

function Enable-RdpClipboard {
  [CmdletBinding(SupportsShouldProcess)]
  param()
  try {
    Set-RegistryDword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fDisableClip' -Value 0
  } catch {
    Write-Error "Enable-RdpClipboard: $($_.Exception.Message)"
  }
}

# ------------------ Report ------------------

function Get-SecurityInteractionReport {
  [CmdletBinding()]
  param(
    [ValidateSet('Console','Markdown','Json','Html')][string]$Output = 'Console',
    [string]$Path
  )
  $Rows = [System.Collections.Generic.List[object]]::new()

  # UAC
  $UacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
  $Cpa = Get-RegistryValue -Path $UacPath -Name 'ConsentPromptBehaviorAdmin'
  $Sdesk = Get-RegistryValue -Path $UacPath -Name 'PromptOnSecureDesktop'

  Add-ReportRow -Rows $Rows -Area 'UAC' -Setting 'Admin Prompt' -Path $UacPath -Name 'ConsentPromptBehaviorAdmin' -Value $Cpa `
    -Meaning (
      switch ($Cpa) {
        '0' {'Erhöhen ohne Nachfrage'}
        '1' {'Anmeldedaten'}
        '2' {'Zustimmung'}
        '3' {'Anmeldedaten'}
        '4' {'Zustimmung'}
        '5' {'Zustimmung nur Nicht-Windows-Binärdateien'}
        default {'Nicht gesetzt'}
      }) `
    -Notes 'Nachfrageverhalten für Admins'
  Add-ReportRow -Rows $Rows -Area 'UAC' -Setting 'Secure Desktop' -Path $UacPath -Name 'PromptOnSecureDesktop' -Value $Sdesk `
    -Meaning (switch ($Sdesk) { 0 {'ohne Secure Desktop'} 1 {'mit Secure Desktop'} default {'Nicht gesetzt'} }) `
    -Notes 'Abdunkeln/Isolieren des UAC-Dialogs'

  # RunAs
  $ShowRun = Get-RegistryValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart'
  $HideVerb = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb'
  $Svc = Get-Service -Name seclogon -ErrorAction SilentlyContinue

  Add-ReportRow -Rows $Rows -Area 'RunAs' -Setting 'Anderer Benutzer sichtbar' -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart' -Value $ShowRun `
    -Meaning (switch ($ShowRun) { 1 {'Sichtbar (erzwingen)'} 0 {'Nicht erzwungen'} default {'Nicht gesetzt'} }) -Notes 'Pro Benutzer'
  Add-ReportRow -Rows $Rows -Area 'RunAs' -Setting 'RunAsVerb versteckt' -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb' -Value $HideVerb `
    -Meaning (switch ($HideVerb) { 1 {'Ausgeblendet'} 0 {'Sichtbar'} default {'Nicht gesetzt'} }) -Notes 'Maschinenweit'
  Add-ReportRow -Rows $Rows -Area 'RunAs' -Setting 'Dienst Sekundäre Anmeldung' -Path 'Service' -Name 'seclogon' `
    -Value ($(if ($Svc) { "$($Svc.Status)/$($Svc.StartType)" } else { '<null>' })) `
    -Meaning ($(if ($Svc -and $Svc.Status -eq 'Running') { 'Erforderlich für RunAs' } else { 'Muss laufen' })) `
    -Notes 'Service muss vorhanden & aktiv sein'

  # Credentials & RDP Client
  $Lsa = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds'
  Add-ReportRow -Rows $Rows -Area 'Credentials' -Setting 'Domänen-Creds speichern' -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds' -Value $Lsa `
    -Meaning (switch ($Lsa) { 1 {'VERBOTEN'} 0 {'ERLAUBT'} default {'Nicht gesetzt'} }) -Notes 'Credential Manager'

  foreach ($Scope in @(
    @{Label='Computerweit'; Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'},
    @{Label='Benutzer';     Path='HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'}
  )) {
    $Dps = Get-RegistryValue -Path $Scope.Path -Name 'DisablePasswordSaving'
    Add-ReportRow -Rows $Rows -Area 'RDP-Client' -Setting "Kennwort speichern ($($Scope.Label))" -Path $Scope.Path -Name 'DisablePasswordSaving' -Value $Dps `
      -Meaning (switch ($Dps) { 1 {'Speichern untersagt'} 0 {'Speichern erlaubt'} default {'Nicht gesetzt'} }) -Notes 'mstsc/RDM'
  }

  # RDP Server
  $Fpp = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fPromptForPassword'
  Add-ReportRow -Rows $Rows -Area 'RDP-Server' -Setting 'Always prompt for password' -Path '...RDP-Tcp' -Name 'fPromptForPassword' -Value $Fpp `
    -Meaning (switch ($Fpp) { 1 {'Immer fragen'} 0 {'Nicht immer fragen'} default {'Nicht gesetzt'} }) -Notes 'Muss 0 sein für Auto-Creds'

  # Clipboard
  $Clip = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name 'fDisableClip'
  Add-ReportRow -Rows $Rows -Area 'RDP' -Setting 'Clipboard-Weiterleitung' -Path '...Terminal Services' -Name 'fDisableClip' -Value $Clip `
    -Meaning (switch ($Clip) { 1 {'Clipboard blockiert'} 0 {'Clipboard erlaubt'} default {'Nicht gesetzt'} }) -Notes 'Copy/Paste erlauben'

  # Cred Delegation
  $CredRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
  $A1 = Get-RegistryValue -Path $CredRoot -Name 'AllowSavedCredentials'
  $A2 = Get-RegistryValue -Path $CredRoot -Name 'AllowSavedCredentialsWhenNTLMOnly'
  $A3 = Get-RegistryValue -Path $CredRoot -Name 'ConcatenateDefaults_AllowSavedNTLMOnly'
  Add-ReportRow -Rows $Rows -Area 'Cred Delegation' -Setting 'AllowSavedCredentials' -Path $CredRoot -Name 'AllowSavedCredentials' -Value $A1 `
    -Meaning (switch ($A1) { 1 {'An'} 0 {'Aus'} default {'Nicht gesetzt'} }) -Notes 'Gespeicherte Creds delegieren'
  Add-ReportRow -Rows $Rows -Area 'Cred Delegation' -Setting 'AllowSavedCredentialsWhenNTLMOnly' -Path $CredRoot -Name 'AllowSavedCredentialsWhenNTLMOnly' -Value $A2 `
    -Meaning (switch ($A2) { 1 {'An'} 0 {'Aus'} default {'Nicht gesetzt'} }) -Notes 'Auch bei NTLM-only'
  Add-ReportRow -Rows $Rows -Area 'Cred Delegation' -Setting 'Concat Defaults (NTLMOnly)' -Path $CredRoot -Name 'ConcatenateDefaults_AllowSavedNTLMOnly' -Value $A3 `
    -Meaning (switch ($A3) { 1 {'An'} 0 {'Aus'} default {'Nicht gesetzt'} }) -Notes 'Default + Liste'

  $Sub = Join-Path $CredRoot 'AllowSavedCredentialsWhenNTLMOnly'
  $Spns = @()
  if (Test-Path $Sub) {
    $Spns = (Get-ItemProperty -Path $Sub).PSObject.Properties |
            Where-Object { $_.Name -match '^\d+$' } |
            Sort-Object { [int]$_.Name } |
            ForEach-Object { $_.Value }
  }
  Add-ReportRow -Rows $Rows -Area 'Cred Delegation' -Setting 'SPN-Liste (NTLMOnly)' -Path $Sub -Name '1..N' -Value ($Spns -join ', ') `
    -Meaning ($(if ($Spns) { 'Zielserver/Patterns' } else { 'Keine' })) -Notes 'Bsp.: TERMSRV/*'

  switch ($Output) {
    'Markdown' {
      $Md = @(
        '# Session Security Report',
        '',
        '| Area | Setting | Value | Meaning | Notes |',
        '|------|---------|-------|---------|-------|'
      )
      foreach ($R in $Rows) {
        $Val = ($R.Value -replace '\|','\|')
        $Md += "| $($R.Area) | $($R.Setting) | $Val | $($R.Meaning) | $($R.Notes) |"
      }
      $Text = $Md -join [Environment]::NewLine
      if ($Path) { Set-Content -Path $Path -Value $Text -Encoding UTF8 } else { $Text }
    }
    'Json' {
      $Json = $Rows | ConvertTo-Json -Depth 4
      if ($Path) { Set-Content -Path $Path -Value $Json -Encoding UTF8 } else { $Json }
    }
    'Html' {
      $Html = $Rows | Sort-Object Area,Setting |
              ConvertTo-Html -Title 'Session Security Report' -PreContent "<h2>Session Security Report</h2><p>$(Get-Date)</p>"
      if ($Path) { Set-Content -Path $Path -Value $Html -Encoding UTF8 } else { $Html }
    }
    default { $Rows | Sort-Object Area,Setting | Format-Table -AutoSize }
  }
}

# ------------------ Orchestrator ------------------

function Set-RdmFriendlySessionProfile {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [Parameter()][string[]]$SpnList = @('TERMSRV/*'),
    [switch]$ReportOnly
  )
  if (-not $ReportOnly) {
    Save-SecurityInteractionState
    Enable-RunAsDifferentUser
    Set-UacAdminNoPrompt
    Enable-RdpAutoCredentials -SpnList $SpnList
    Enable-RdpClipboard
  }
  Get-SecurityInteractionReport -Output 'Console'
}

# --------------- Beispiele ---------------
<#
# Anwenden + Report:
Set-RdmFriendlySessionProfile

# Report als HTML:
Get-SecurityInteractionReport -Output Html -Path "$env:USERPROFILE\Desktop\SessionSecurityReport.html"

# Zurückrollen:
Restore-SecurityInteractionState
#>
