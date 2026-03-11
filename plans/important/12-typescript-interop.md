# Plan 12: TypeScript Interop

## Priority: HIGH — Tier 1
## Effort: 6-8 weeks
## Depends on: Plan 01 (ESM output)

> **Status Update (2026-03-11):** Phase 1 (.d.ts generation) is **DONE**.
>
> **What's implemented:**
> - `Generate/TypeScript.hs` — main orchestrator
> - `Generate/TypeScript/Types.hs` — Canopy-to-TypeScript type mapping
> - `Generate/TypeScript/Render.hs` — .d.ts file rendering
> - `Generate/TypeScript/WellKnown.hs` — standard type conversions (String→string, etc.)
> - Golden tests for: simple values, union types, record aliases, generic types, opaque types, well-known conversions
> - Auto-generated alongside .js files on build
> - Nested record type support
>
> **Remaining work:** Phases 2-4 (npm package consumption, Web Component output, testing/docs).

## Problem

Elm's #1 adoption killer was JS interop friction. Ports are async-only, every interaction requires message-passing ceremony, and there are no TypeScript type definitions. Teams couldn't incrementally adopt Elm or use the npm ecosystem.

TypeScript is the #1 language on GitHub (2024). 60M+ weekly npm downloads. A language that ignores TypeScript is choosing to die.

## Solution: Bidirectional TypeScript Integration

### 1. Emit .d.ts Files for Canopy Modules

Every compiled Canopy module automatically generates TypeScript type definitions:

```canopy
-- src/User.can
module User exposing (User, create, fullName, isAdmin)

type alias User =
    { firstName : String
    , lastName : String
    , role : Role
    }

type Role = Admin | Editor | Viewer

create : String -> String -> Role -> User
fullName : User -> String
isAdmin : User -> Bool
```

Generates:

```typescript
// dist/User.d.ts (auto-generated, do not edit)
export interface User {
  firstName: string;
  lastName: string;
  role: Role;
}

export type Role =
  | { $: 'Admin' }
  | { $: 'Editor' }
  | { $: 'Viewer' };

export function create(firstName: string, lastName: string, role: Role): User;
export function fullName(user: User): string;
export function isAdmin(user: User): boolean;
```

### Type Mapping

| Canopy Type | TypeScript Type |
|-------------|----------------|
| `String` | `string` |
| `Int` | `number` |
| `Float` | `number` |
| `Bool` | `boolean` |
| `List a` | `ReadonlyArray<A>` |
| `Maybe a` | `{ $: 'Just', a: A } \| { $: 'Nothing' }` |
| `Result e a` | `{ $: 'Ok', a: A } \| { $: 'Err', a: E }` |
| `Dict k v` | `ReadonlyMap<K, V>` |
| Record `{ x : Int, y : Int }` | `{ readonly x: number; readonly y: number }` |
| Custom type | Discriminated union with `$` tag |
| Opaque type | Opaque branded type |
| `Task e a` | Not exported (internal) |
| `Cmd msg` | Not exported (internal) |

### 2. Consume npm Packages with Typed FFI

Enhance the FFI system to read TypeScript `.d.ts` files and generate safe Canopy bindings:

```canopy
-- foreign import from npm package
foreign import javascript "./node_modules/date-fns/format.d.ts"
    format : Posix -> String -> String
```

The compiler:
1. Reads the `.d.ts` file
2. Validates the Canopy type signature matches the TypeScript type
3. Generates the JS binding wrapper
4. Wraps the result in appropriate Canopy types (nullable → Maybe, union → Result, etc.)

### 3. Canopy Components Usable from React/TypeScript

The ESM output (Plan 01) + .d.ts files means Canopy modules are directly importable from TypeScript:

```typescript
// React component using Canopy logic
import { create, fullName, isAdmin } from './canopy-output/User.js';

function UserBadge({ firstName, lastName, role }) {
  const user = create(firstName, lastName, role);
  return (
    <span className={isAdmin(user) ? 'admin' : 'user'}>
      {fullName(user)}
    </span>
  );
}
```

### 4. Web Component Output for Framework Interop

Canopy components can optionally compile to Web Components:

```canopy
-- canopy.json
{
  "output": {
    "web-components": ["Components.Counter", "Components.UserCard"]
  }
}
```

Generates:

```javascript
// Counter.js
class CanopyCounter extends HTMLElement {
  connectedCallback() {
    const app = Canopy.Components.Counter.init({ node: this });
    // ... mount Canopy component into shadow DOM
  }
  static get observedAttributes() { return ['initial-count']; }
  attributeChangedCallback(name, old, val) { /* update model */ }
}
customElements.define('canopy-counter', CanopyCounter);
```

```typescript
// Counter.d.ts
declare class CanopyCounter extends HTMLElement {
  'initial-count': string;
}
declare global {
  interface HTMLElementTagNameMap {
    'canopy-counter': CanopyCounter;
  }
}
```

Usage from React:

```jsx
// Works in any framework
<canopy-counter initial-count="0" />
```

## Implementation Phases

### Phase 1: .d.ts Generation (Weeks 1-3)
- New module: `Generate/TypeScript.hs`
- Walk the module's exported interface
- Map Canopy types to TypeScript types
- Generate `.d.ts` files alongside `.js` files
- Handle all standard types + custom types + opaque types

### Phase 2: npm Package Consumption (Weeks 4-5)
- Parse `.d.ts` files (use existing TS parser or write minimal one)
- Validate FFI signatures against TS types
- Generate warnings for type mismatches
- Handle common patterns (callbacks, Promises, optional params)

### Phase 3: Web Component Output (Weeks 6-7)
- Web Component wrapper generator
- Shadow DOM mounting
- Attribute → prop mapping
- Event dispatching from Canopy to host

### Phase 4: Testing and Documentation (Week 8)
- Integration tests: use Canopy modules from TypeScript
- Integration tests: use npm packages from Canopy
- Documentation: migration guide "Using Canopy in an existing React project"
- Documentation: "Consuming npm packages from Canopy"

## The Gradual Adoption Story

This is how teams adopt Canopy without rewriting:

1. **Week 1**: Add Canopy to existing React/Next.js project via Vite plugin
2. **Week 2**: Write one utility module in Canopy, import from TypeScript
3. **Month 1**: Extract business logic into Canopy modules (type-safe, zero runtime errors)
4. **Month 3**: Build new features as Canopy components, expose as Web Components
5. **Month 6**: Core application logic in Canopy, React used only as a shell
6. **Month 12**: Full migration to CanopyKit

This is TypeScript's playbook adapted for a functional language.

## Risks

- **Type mapping fidelity**: Some TypeScript types (conditional types, mapped types, template literals) have no Canopy equivalent. These must be handled gracefully (warn, use opaque type).
- **Runtime representation**: The discriminated union encoding (`{ $: 'Tag', ... }`) must be stable and documented. Changing it would break TS consumers.
- **Web Component limitations**: Shadow DOM has known issues with forms, ARIA, and SSR. Document these clearly.
