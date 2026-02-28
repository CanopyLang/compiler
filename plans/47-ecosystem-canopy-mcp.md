# Plan 47: MCP Server Enhancement

## Priority: LOW
## Effort: Medium (1-2 days)
## Risk: Low — independent package

## Problem

`packages/canopy-mcp/` exists but its capabilities and integration level are unclear. MCP (Model Context Protocol) servers enable AI assistants to interact with the compiler programmatically.

## Implementation Plan

### Step 1: Audit current MCP implementation

Read through canopy-mcp to understand:
- What tools/resources does it expose?
- How does it interact with the compiler?
- What protocol version does it implement?

### Step 2: Expose compiler operations

Ensure the MCP server exposes key operations:
- `compile` — compile a file and return diagnostics
- `typeCheck` — type check without generating code
- `format` — format source code
- `getType` — get the type of an expression at a position
- `findDefinition` — go to definition
- `getCompletions` — autocomplete at a position
- `lint` — run lint rules

### Step 3: Add project context tools

- `getModuleList` — list all modules in the project
- `getDependencies` — list project dependencies
- `getErrors` — get current compilation errors
- `getOutline` — read canopy.json

### Step 4: Documentation

Document how to configure AI assistants (Claude, etc.) to use the MCP server.

### Step 5: Tests

- Test each MCP tool returns correct data
- Test error handling for invalid inputs
- Test concurrent requests

## Dependencies
- None
