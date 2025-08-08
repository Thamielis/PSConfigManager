
# --- Helfer ---
function Set-RegDword {
  param([string]$Path, [string]$Name, [int]$Value)
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  if (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue) {
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord
  } else {
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
  }
}

# --- Passwort-Speichern global verbieten/erlauben (Credential Manager) ---
function Set-CredentialStorage {
  param([ValidateSet('Allow','Deny')][string]$Mode = 'Deny')
  $val = @{'Allow'=0; 'Deny'=1}[$Mode]
  Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'DisableDomainCreds' -Value $val
}

# --- RDP-Client: Speichern verhindern/zulassen ---
function Set-RdpClientPasswordSaving {
  param([ValidateSet('Allow','Deny')][string]$Mode = 'Deny',[switch]$PerUser)
  $base = ($PerUser) ? 'HKCU:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
                     : 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client'
  Set-RegDword -Path $base -Name 'DisablePasswordSaving' -Value (@{'Allow'=0;'Deny'=1}[$Mode])
}

# --- RDP-Server: Immer Passwort abfragen (oder nicht) ---
function Set-RdpServerAlwaysPrompt {
  param([bool]$Enabled = $true)
  Set-RegDword -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
               -Name 'fPromptForPassword' -Value ([int]$Enabled)
}

# --- Credentials Delegation (gespeicherte Creds für RDP erlauben) ---
function Enable-RdpSavedCredentialsDelegation {
  param([string[]]$SpnList = @('TERMSRV/*'))
  $root = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
  # Schalter setzen
  Set-RegDword -Path $root -Name 'AllowSavedCredentials' -Value 1
  Set-RegDword -Path $root -Name 'AllowSavedCredentialsWhenNTLMOnly' -Value 1
  Set-RegDword -Path $root -Name 'ConcatenateDefaults_AllowSavedNTLMOnly' -Value 1
  # Liste eintragen (nummerierte Zeichenfolgenwerte unter dem passenden Unterschlüssel)
  $sub = Join-Path $root 'AllowSavedCredentialsWhenNTLMOnly'
  if (-not (Test-Path $sub)) { New-Item -Path $sub -Force | Out-Null }
  # Aufräumen & neu schreiben
  Get-Item -Path $sub | Get-ItemProperty | ForEach-Object {
    $_.PSObject.Properties |
      Where-Object { $_.Name -match '^\d+$' } |
      ForEach-Object { Remove-ItemProperty -Path $sub -Name $_.Name -Force }
  } | Out-Null
  $i=1; foreach($spn in $SpnList){ New-ItemProperty -Path $sub -Name "$i" -PropertyType String -Value $spn -Force | Out-Null; $i++ }
}

# --- "Ausführen als anderer Benutzer" sichtbar machen ---
function Enable-RunAsDifferentUser {
  # Startmenü-Eintrag anzeigen (per-User)
  Set-RegDword -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'ShowRunAsDifferentUserInStart' -Value 1
  # Verb nicht verstecken (maschinenweit)
  Set-RegDword -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideRunAsVerb' -Value 0
  # Sekundäre Anmeldung sicherstellen
  Set-Service -Name seclogon -StartupType Manual -ErrorAction SilentlyContinue
  Start-Service -Name seclogon -ErrorAction SilentlyContinue
}

# --- Beispiele ---
# 1) Systemweit Speichern von Credentials verbieten:
# Set-CredentialStorage -Mode Deny

# 2) RDP-Client: Speichern verbieten (Computerweit):
# Set-RdpClientPasswordSaving -Mode Deny

# 3) RDP-Server: Immer Passwort abfragen:
# Set-RdpServerAlwaysPrompt -Enabled $true

# 4) Gespeicherte RDP-Creds erlauben (Client):
# Enable-RdpSavedCredentialsDelegation -SpnList @('TERMSRV/*')

# 5) "Ausführen als anderer Benutzer" aktivieren:
# Enable-RunAsDifferentUser
