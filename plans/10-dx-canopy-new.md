# Plan 10: `canopy new` Project Scaffolding Command

## Priority: HIGH
## Effort: Medium (1-2 days)
## Risk: Low — new feature, no existing code affected

## Problem

`canopy init` exists but only initializes a canopy.json in the current directory. There's no `canopy new <project-name>` that creates a complete project structure. `Init/Types.hs` has a `_contextProjectName` field that's unused.

### Current Code

**Init entry** (packages/canopy-terminal/src/Init.hs, line 111):
```haskell
run :: () -> () -> IO ()
```

**Unused field** (packages/canopy-terminal/src/Init/Types.hs):
```haskell
data ProjectContext = ProjectContext
  { _contextProjectName :: !Text  -- UNUSED
  , ...
  }
```

## Implementation Plan

### Step 1: Create New.hs command module

**File**: `packages/canopy-terminal/src/New.hs` (NEW)

```haskell
module New (run, Flags(..)) where

data Flags = Flags
  { _newTemplate :: !Template
  , _newNoGit :: !Bool
  }

data Template = AppTemplate | PackageTemplate | WorkerTemplate

run :: String -> Flags -> IO ()
run projectName flags = do
  createProjectDir projectName
  scaffoldProject projectName (flags ^. newTemplate)
  unless (flags ^. newNoGit) (initGitRepo projectName)
  reportSuccess projectName
```

### Step 2: Define project templates

**File**: `packages/canopy-terminal/src/New/Templates.hs` (NEW)

Application template:
```
<project>/
├── canopy.json
├── src/
│   └── Main.can
├── tests/
│   └── Tests.can
├── .gitignore
└── README.md
```

Package template:
```
<project>/
├── canopy.json
├── src/
│   └── <ModuleName>.can
├── tests/
│   └── Tests.can
├── .gitignore
├── LICENSE
└── README.md
```

### Step 3: Generate canopy.json with project name

Use `_contextProjectName` from `Init/Types.hs` to generate proper canopy.json:

```json
{
    "type": "application",
    "source-directories": ["src"],
    "canopy-version": "0.19.1",
    "dependencies": {
        "direct": {
            "elm/core": "1.0.5",
            "elm/html": "1.0.0"
        },
        "indirect": {
            "elm/json": "1.1.3",
            "elm/virtual-dom": "1.0.3"
        }
    }
}
```

### Step 4: Generate starter Main.can

```elm
module Main exposing (main)

import Html

main =
    Html.text "Hello from <project-name>!"
```

### Step 5: Register command in CLI

**File**: `packages/canopy-terminal/src/CLI/Commands.hs`

Register `canopy new` following the existing pattern (Terminal.Command with 7 params):

```haskell
newCommand :: Terminal.Command
newCommand = Terminal.Command
  "new"
  Terminal.Uncommon
  "Create a new Canopy project"
  "canopy new my-app"
  [Terminal.Argument "PROJECT_NAME"]
  [templateFlag, noGitFlag]
  New.run
```

### Step 6: Add .gitignore template

```
canopy-stuff/
elm-stuff/
node_modules/
*.dat
```

### Step 7: Tests

- Test directory creation
- Test canopy.json generation
- Test template selection (app vs package)
- Test --no-git flag
- Test error on existing directory
- Test project name validation (no spaces, special chars)

## Dependencies
- None
