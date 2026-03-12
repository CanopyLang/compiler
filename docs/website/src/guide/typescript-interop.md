# TypeScript Interop

Canopy provides deep TypeScript integration for consuming Canopy modules
from TypeScript/JavaScript projects and vice versa.

## .d.ts Generation

When you compile a Canopy module, the compiler can generate TypeScript
declaration files alongside the JavaScript output:

```bash
canopy make src/Main.can --output=build/
```

This produces both `build/main.js` and per-module `.d.ts` files. The type
mappings are:

| Canopy Type | TypeScript Type |
|-------------|-----------------|
| `Int`, `Float` | `number` |
| `String` | `string` |
| `Bool` | `boolean` |
| `()` | `void` |
| `List a` | `ReadonlyArray<A>` |
| `Maybe a` | `{ $: 'Just'; a: A } \| { $: 'Nothing' }` |
| `Result e a` | `{ $: 'Ok'; a: A } \| { $: 'Err'; a: E }` |
| Records | `{ readonly field: Type }` |
| Custom types | Discriminated unions with `$` tag |
| Opaque types | Branded types with `__brand: unique symbol` |

## FFI Type Validation

Canopy validates your FFI type declarations against `.d.ts` files at
compile time. If your FFI JavaScript file has an accompanying `.d.ts`:

```
ffi/
  geo.js
  geo.d.ts
```

The compiler parses `geo.d.ts` and checks that your Canopy FFI types
match. For example:

```canopy
-- In your Canopy module:
foreign import javascript "ffi/geo.js" as Geo

getLocation : () -> Task Error Location
getLocation = Geo.getCurrentPosition
```

```typescript
// ffi/geo.d.ts
export function getCurrentPosition(): Promise<{
  readonly latitude: number;
  readonly longitude: number;
}>;
```

If the types don't match, you get a compile-time error:

```
-- TYPE MISMATCH IN FFI --

The FFI function getCurrentPosition has a type mismatch:

    Canopy type:    () => Location
    .d.ts declares: () => Promise<{ latitude: number; longitude: number }>

Make sure your Canopy FFI declaration matches the TypeScript types.
```

## Web Components

Canopy modules can be exported as Custom Elements for use in any
HTML page or framework:

```json
{
    "type": "application",
    "web-components": ["MyApp.Counter", "MyApp.TodoList"]
}
```

This generates Custom Element classes with:

- **Shadow DOM** isolation
- **Attribute-to-flag** mapping (HTML attributes become Canopy flags)
- **Lifecycle hooks** (`connectedCallback`, `disconnectedCallback`)
- **TypeScript declarations** with `HTMLElementTagNameMap` augmentation

Usage in HTML:

```html
<script src="canopy.js"></script>
<my-app-counter initial-count="5"></my-app-counter>
<my-app-todo-list></my-app-todo-list>
```

### Tag Name Convention

Module names are converted to kebab-case HTML tag names:

| Module Name | Tag Name |
|------------|----------|
| `MyApp.Counter` | `<my-app-counter>` |
| `MyApp.TodoList` | `<my-app-todo-list>` |
| `Dashboard` | `<dashboard>` |

### TypeScript Support

The generated `.d.ts` includes global augmentation:

```typescript
declare global {
  interface HTMLElementTagNameMap {
    "my-app-counter": HTMLElement;
    "my-app-todo-list": HTMLElement;
  }
}
```

This gives you type-safe `querySelector`:

```typescript
const counter = document.querySelector("my-app-counter");
// TypeScript knows this is HTMLElement
```

## npm Package Consumption

To consume an npm package's types in your Canopy FFI, create a
`.d.ts` file that re-exports the types you need:

```typescript
// ffi/chart.d.ts
export function createChart(
  element: HTMLElement,
  data: ReadonlyArray<number>
): void;
```

Then reference it from Canopy:

```canopy
foreign import javascript "ffi/chart.js" as Chart

createChart : Html.Element -> List Float -> Cmd msg
createChart element data =
    Chart.createChart element data
```

The compiler validates that `List Float` maps to `ReadonlyArray<number>`
and `Html.Element` maps to `HTMLElement`.
