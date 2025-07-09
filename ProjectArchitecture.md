# PSConfigManager Architecture

## Entity Model

- **Company**: Root entity, owns multiple Branches
- **Branch**: Owned by Company, contains Departments
- **Department**: Contains Systems
- **System**: Physical or virtual infrastructure units, with roles like WebServer, FileServer
- Other entities: Service, Application, Database, NetworkSegment, etc.

## Core Engine

- `ConfigManager` class manages entities CRUD, storage, dependency resolution
- Serialization as JSON, saved per entity with GUID filenames
- Hierarchical traversal implemented recursively
- Validation enforced in class constructors

## CLI Commands

- User-friendly commands like New-CompanyConfig, Add-Branch, Show-ConfigTree, Export-Config
- Commands interact with the global `ConfigManager` instance

## Visualization

- Mermaid diagrams generated from hierarchy for documentation and presentation
- Tree and JSON exports available

## Extensibility

- Entities and templates can be extended with additional fields
- New entity classes can be added following the existing pattern
- Templates stored as JSON and loadable

## Testing

- Pester tests cover entities and core functionality
- Coverage goal ≥80%
