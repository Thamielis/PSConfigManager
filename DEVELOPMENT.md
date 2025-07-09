# PSConfigManager Development Guide

## Overview

PSConfigManager is a modular PowerShell module designed to model complex hierarchical IT configurations for enterprises.

---

## Repository Structure

- `/src`
  - `/Entities`: PowerShell classes representing configuration entities (Company, Branch, System, etc.).
  - `/Core`: Core engine managing CRUD, serialization, and hierarchy traversal.
  - `/Commands`: Cmdlet wrappers for CLI interaction.
  - `Module.psm1`: Main module file loading all components.

- `/templates`: JSON templates for typical configurations.
- `/examples`: Example scripts demonstrating usage.
- `/tests`: Pester test scripts.
- `/docs`: Documentation files including this guide, README, architecture, and diagrams.

---

## Setup and Usage

1. Import module:

    ```powershell
    Import-Module .\src\Module.psm1
    ```

2. Initialize global config manager (specify a storage folder):

    ```powershell
    Initialize-ConfigManager -StoragePath '.\configs'
    ```

3. Use commands to create and manage configs:

    ```powershell
    $company = New-CompanyConfig -Name 'Globex' -Country 'DE'
    Add-Branch -Company $company -Name 'Globex India' -Country 'IN'
    Show-ConfigTree -From 'Globex' -Depth 3
    ```

4. Save configurations are automatically persisted in JSON files by GUID.

---

## Extending the Module

### Adding New Entities

1. Create a new class file under `/src/Entities`, following the pattern of existing classes.
2. Implement constructors, properties, and validation.
3. Add any necessary methods for relationship management.
4. Create corresponding CLI wrapper functions under `/src/Commands`.
5. Add your new class to `Module.psm1` import list.
6. Write Pester tests in `/tests` for your new entity.

### Adding New Commands

- Use advanced functions with proper parameter validation.
- Access the global `$Global:ConfigManagerInstance` for storage.
- Save entities after creation or modification.

### Serialization

- All entities are serialized with `ConvertTo-Json -Depth 10`.
- Avoid circular references or handle them manually.

### Visualization

- Update `Export-Config` function if new entities have hierarchical children.
- Follow existing Mermaid diagram generation style.

---

## Testing

- Use Pester framework.
- Tests are located in `/tests`.
- Run all tests:

    ```powershell
    Invoke-Pester -Path .\tests
    ```

- Aim for >80% coverage.

---

## Contribution

- Fork repository and create feature branches.
- Write meaningful commit messages.
- Include tests for new features.
- Update documentation accordingly.

---

## Troubleshooting

- Ensure PowerShell 5.1+ is used.
- Use `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` for running scripts if needed.
- If JSON files corrupt, delete and recreate config using commands.

---

## Roadmap

- Implement import/export from CSV or Excel.
- Interactive configuration prompts.
- Advanced dependency and circular reference detection.
- GUI or web interface integration.

---

## Contact

Open issues or pull requests on GitHub repository.

---

*Happy configuring!*
