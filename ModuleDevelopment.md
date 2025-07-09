# PSConfigManager

Develop a PowerShell module to dynamically create, manage, and extend hierarchical configurations with category-based templates, dependency rules, and IT-centric real-world structures.

The module should support interactive and automated workflows to define reusable, extensible, and validated configurations for a global enterprise. Focus especially on IT infrastructure, system roles, geographic topology, and business logic, using a model-driven approach. The goal is to represent deeply nested, dependent configurations (e.g., company → branch → department → systems → services), and allow intelligent queries, generation, and relationship tracking.

## Features & Requirements

### Core Capabilities:

* Dynamically **create, save, load, update, delete** configuration objects
* Define **categories** (e.g., `Company`, `Branch`, `ITService`, `Database`, `NetworkSegment`) with:

  * Static structure (strict schema)
  * Suggested structure (guidance for optional fields)
  * Custom structure (user-defined extensions)
* Define **hierarchies** and **relationships**, including:

  * 1:1, 1\:N, 0\:N, and optional constraints
  * Referential links between objects
  * Bidirectional traversal (top-down and bottom-up)
* Support for **templates** and **presets** (e.g. "standard branch IT setup", "cloud-hosted app architecture")
* Introspect and **visualize hierarchical structure**
* Allow recursive **dependency resolution** and traversal
* Configurations should be **file-based** (e.g., JSON, XML, or PowerShell objects) with clear serialization/deserialization
* Implement **validation logic** per object type and structure constraints
* Enable dynamic **extensibility** of config classes and templates

### Technical Capabilities:

* Class-based PowerShell OOP design (PowerShell 5.1+)
* Use of `ValidateScript`, `[ValidatePattern()]`, `[ValidateSet()]` for field validation
* Include **Pester tests** (≥80% coverage)
* Include inline and external help documentation
* Visualize hierarchies using **Tree**, **JSON**, or **Mermaid diagrams**
* Fully modular: each entity and command in its own file

## Steps

1. **Define the Entity Schema Hierarchy**

   * Use real-world entities, such as:

     * Company (1)
     * Headquarters (1)
     * Branch (0-N)
     * Department (1-N per Branch)
     * ITUnit (e.g., Helpdesk, SysAdmin)
     * System (e.g., FileServer, WebServer)
     * Service (e.g., DNS, AD, Backup)
     * NetworkSegment
     * Application (hosted or SaaS)
     * Database (MS SQL, PostgreSQL, etc.)
     * CredentialStores, FirewallZones, etc.
   * Define for each:

     * Fields (name, location, identifiers)
     * Relations (child entities, parent)
     * Constraints (must have at least one x, must be unique, etc.)

2. **Develop a Configuration Engine**

   * Create a central manager for CRUD operations on all entities
   * Support dependency mapping and cascading updates
   * Add link-tracking logic for dependent configurations

3. **Build Example Use Cases & Templates**

   * Global company with:

     * HQ in Germany
     * Branches in US, India, Brazil
     * Shared services vs. region-specific
   * Network layouts (DMZ, VPN, VLANs per site)
   * Services (Active Directory replication, backup plans, email systems)
   * App-DB dependency (e.g., App → connects to DB on internal net)
   * Onboarding flow (adding new branch + IT infra + default services)

4. **Add Display & Introspection Tools**

   * Functions like `Show-ConfigTree -From Branch -Depth 3`
   * `Export-Config -As Mermaid` to visualize relationships
   * Recursive `Get-ConfigDependencies -Of 'Database01'`

5. **Add CLI Wrapper Commands**

   * `New-CompanyConfig`, `Add-Branch`, `Link-DatabaseToApp`, etc.

6. **Implement Storage & State Management**

   * Configs stored as JSON files with GUID-based linking
   * Meta info (timestamps, versions, owner) saved per object

7. **Documentation & Test Coverage**

   * Inline help for all commands and classes
   * `README.md`, `CHANGELOG.md`, `Architecture.md`
   * Pester tests for entity creation, validation, linking

## Output Format

A full PowerShell module repository including:

* `/src` folder with individual class and function files
* `/templates` folder with default structure templates (JSON/YAML)
* `/examples` folder with real-world use case examples
* `/tests` folder with Pester tests
* `README.md`, `CHANGELOG.md`, `Architecture.md` with detailed documentation
* Optional Mermaid diagrams in `/docs` showing relations and config flows

## Examples

### [Example: Define Global Company]

```powershell
$company = New-CompanyConfig -Name 'Globex International' -Country 'Germany'
Add-Branch -Company $company -Name 'Globex India' -Country 'IN'
Add-Branch -Company $company -Name 'Globex US' -Country 'US'

Add-Department -Branch 'Globex India' -Name 'IT' -Roles 'Helpdesk','DevOps'
Add-System -Department 'IT' -Name 'IND-WEB01' -Role 'WebServer' -IP '10.2.1.10'

Link-DatabaseToApp -App 'GlobexCRM' -Database 'IND-CRM-SQL'
```

### [Example: Visualize Structure]

```powershell
Show-ConfigTree -From 'Globex India' -Depth 4
Export-Config -From 'Globex India' -As Mermaid -OutputPath './docs/branch_india_diagram.md'
```

## Notes

* All templates should be auto-extensible by adding custom fields per category.
* Include logic to resolve circular references and orphaned configs.
* Hierarchical queries should be optimized for large config trees.
* Optionally allow import/export from Excel or CSV for initial bulk setup.
