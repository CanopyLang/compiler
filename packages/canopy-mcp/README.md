# Canopy MCP Server

Model Context Protocol (MCP) server for AI-native Canopy development.

## Overview

This MCP server enables AI assistants like Claude to interact with Canopy projects,
providing tools for building, type checking, and navigating code.

## Installation

```bash
npm install @canopy/mcp-server
```

Or build from source:

```bash
cd packages/canopy-mcp
npm install
npm run build
```

## Configuration

Add to your Claude Desktop configuration (`~/.config/claude-desktop/config.json`):

```json
{
  "mcpServers": {
    "canopy": {
      "command": "npx",
      "args": ["@canopy/mcp-server"]
    }
  }
}
```

Or if installed locally:

```json
{
  "mcpServers": {
    "canopy": {
      "command": "node",
      "args": ["/path/to/canopy/packages/canopy-mcp/dist/index.js"]
    }
  }
}
```

## Available Tools

### canopy_build

Build a Canopy project.

```
Arguments:
- path: Project directory (default: current)
- optimize: Enable production optimizations
- output: Output file path
- format: Output format (iife, esm, commonjs)
```

### canopy_check

Type check a project without generating output.

```
Arguments:
- path: Project directory (default: current)
```

### canopy_get_type

Get type information at a location.

```
Arguments:
- file: Source file path
- line: Line number (1-indexed)
- column: Column number (1-indexed)
```

### canopy_find_definition

Find where a symbol is defined.

```
Arguments:
- file: Source file path
- line: Line number (1-indexed)
- column: Column number (1-indexed)
```

### canopy_get_docs

Get documentation for a module or function.

```
Arguments:
- module: Module name (e.g., 'List', 'Maybe')
- function: Function name (optional)
```

### canopy_list_modules

List all modules in a project.

```
Arguments:
- path: Project directory (default: current)
```

## Available Prompts

### canopy_new_module

Generate a new Canopy module with proper structure.

### canopy_tea_component

Generate a TEA (The Elm Architecture) component.

### canopy_fix_error

Help fix a Canopy compilation error.

## Resources

The server provides access to:

- `canopy://project/canopy.json` - Project configuration
- `canopy://docs/syntax` - Syntax quick reference

## Development

```bash
# Install dependencies
npm install

# Build
npm run build

# Run in development mode
npm run dev

# Type check
npm run typecheck
```

## License

BSD-3-Clause
