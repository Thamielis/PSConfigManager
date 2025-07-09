

Class CredentialStore {
    [Guid] $Id
    [string] $Name
    [string] $StoreType  # e.g., 'Vault', 'Keyring', 'AzureKeyVault'
    [string] $Description

    CredentialStore([string]$name, [string]$storeType, [string]$description = '') {
        if ([string]::IsNullOrWhiteSpace($name)) { throw "CredentialStore Name is required." }
        if ([string]::IsNullOrWhiteSpace($storeType)) { throw "StoreType is required." }
        $this.Id = [Guid]::NewGuid()
        $this.Name = $name
        $this.StoreType = $storeType
        $this.Description = $description
    }
}
