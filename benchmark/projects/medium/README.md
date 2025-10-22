# Medium Test Project

A realistic multi-module blog application for testing module dependency resolution and type inference.

## Stats

- **Modules:** 4
- **Lines of Code:** 260
- **Dependencies:** elm/core, elm/html

## Structure

```
medium/
├── canopy.json
└── src/
    ├── Main.can (92 lines) - Main application logic and view
    ├── Types.can (49 lines) - User, Post, and Status types
    ├── Utils.can (53 lines) - String and number utilities
    └── Logic.can (66 lines) - Business logic for posts
```

## Module Dependencies

```
Main.can
├── Types.can (no dependencies)
├── Utils.can (no dependencies)
└── Logic.can
    └── Types.can
```

## Features

- **Type Definitions:**
  - User type with id, name, email, active status
  - Post type with title, content, author, status, likes
  - Status enum (Draft, Published, Archived)

- **Utility Functions:**
  - capitalize, truncate, formatNumber, pluralize
  - Email validation

- **Business Logic:**
  - Create, update, like posts
  - Publish and archive functionality
  - Filter posts by status
  - Sort by likes

- **View:**
  - Post list rendering
  - Interactive buttons for creating and liking posts

## Compile

```bash
stack exec -- canopy make src/Main.can --output=/tmp/medium.js
```

## What It Tests

- Multi-module compilation
- Module import resolution
- Type inference across modules
- Record type updates
- Custom type definitions
- Function composition
- List operations
