# Plan 26: REPL Improvements

## Priority: MEDIUM
## Effort: Medium (2-3 days)
## Risk: Low — improvements to existing REPL

## Problem

The REPL works but lacks modern quality-of-life features:
- No multiline input support
- No tab completion for module names and functions
- No `:type` command for inspecting types
- No `:browse` command for module exploration
- Limited history management

### Key Files
- `packages/canopy-terminal/src/Repl.hs`
- `packages/canopy-terminal/src/Repl/Types.hs`

## Implementation Plan

### Step 1: Add :type command

Show the type of an expression without evaluating it:

```
> :type List.map
(a -> b) -> List a -> List b

> :type "hello"
String
```

### Step 2: Add :browse command

List all exports of a module:

```
> :browse List
List.map : (a -> b) -> List a -> List b
List.filter : (a -> Bool) -> List a -> List a
List.foldl : (a -> b -> b) -> b -> List a -> b
...
```

### Step 3: Add multiline input

Support `:{` and `:}` delimiters or automatic continuation on incomplete expressions:

```
> :{
| myFunction x =
|   if x > 0
|   then "positive"
|   else "non-positive"
| :}
<function> : Int -> String
```

### Step 4: Tab completion

Integrate with Haskeline's completion system:
- Complete module names after `import`
- Complete function names after `ModuleName.`
- Complete local variable names
- Complete REPL commands after `:`

### Step 5: Add :info command

Show comprehensive info about a name:

```
> :info Maybe
type Maybe a = Nothing | Just a
    -- Defined in Maybe

> :info List.map
List.map : (a -> b) -> List a -> List b
    -- Defined in List
```

### Step 6: Tests

- Test :type output for various expressions
- Test :browse output format
- Test multiline input parsing
- Test completion suggestions

## Dependencies
- None
