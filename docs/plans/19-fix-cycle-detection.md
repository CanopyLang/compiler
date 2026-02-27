# Plan 19 — Fix O(n^2) Cycle Detection

**Priority:** Tier 3 (Performance)
**Effort:** 4 hours
**Risk:** Low
**Files:** `packages/canopy-builder/src/Builder/Graph.hs`

---

## Problem

`hasCycle` (Graph.hs:112-123) runs DFS from every module node in `getAllModules`. For N nodes and E edges, this is O(N x (N + E)). At 1,000 modules, ~500,000 DFS operations. Called once per build during graph construction.

## Implementation

### Replace with Tarjan's Algorithm

Tarjan's strongly-connected components (SCC) algorithm is a single DFS pass that detects all cycles in O(V + E):

```haskell
import qualified Data.Graph as Graph

-- | Detect cycles in the module dependency graph.
--
-- Returns Nothing if acyclic, or Just the first cycle found.
findCycle :: ModuleGraph -> Maybe [ModuleName.Raw]
findCycle graph =
  case filter isCyclic (Graph.stronglyConnComp edges) of
    [] -> Nothing
    (Graph.CyclicSCC cycle : _) -> Just (map nodeKey cycle)
    _ -> Nothing
  where
    edges = map toEdge (Map.toList (getAdjacency graph))
    toEdge (name, deps) = (name, name, Set.toList deps)
    nodeKey (name, _, _) = name
    isCyclic (Graph.CyclicSCC _) = True
    isCyclic _ = False
```

`Data.Graph.stronglyConnComp` is in the `containers` package (already a dependency). It performs a single DFS — O(V + E).

### Update hasCycle callers

```haskell
-- Before:
hasCycle :: ModuleGraph -> Bool
hasCycle graph = any (hasCycleFrom graph Set.empty) (getAllModules graph)

-- After:
hasCycle :: ModuleGraph -> Bool
hasCycle graph = Maybe.isJust (findCycle graph)
```

### Improve error reporting

With Tarjan's, we can report the actual cycle:

```haskell
validateAcyclic :: ModuleGraph -> Either [ModuleName.Raw] ()
validateAcyclic graph =
  case findCycle graph of
    Nothing -> Right ()
    Just cycle -> Left cycle
```

The caller can then produce an error message listing the cycle path, which is much more helpful than the current boolean.

## Validation

```bash
make build && make test
```

## Acceptance Criteria

- Cycle detection is O(V + E), not O(V x (V + E))
- Uses `Data.Graph.stronglyConnComp` or equivalent single-pass algorithm
- Error message for cycles includes the actual cycle path
- `make build && make test` passes
