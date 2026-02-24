# Frequently Asked Questions

## General

### What is Canopy?

Canopy is a functional programming language that compiles to JavaScript. It's designed for building reliable web applications with no runtime exceptions.

### How does Canopy relate to Elm?

Canopy is a fork of Elm that adds new features while maintaining compatibility. Elm code can be migrated to Canopy with minimal changes. Canopy adds do-notation, enhanced FFI, JSON derivation, and more.

### Is Canopy production-ready?

Yes! Canopy is suitable for production use. It inherits Elm's battle-tested compiler and adds carefully designed extensions.

### What platforms does Canopy support?

Canopy runs on:
- macOS
- Linux
- Windows

The compiled JavaScript runs anywhere JavaScript runs (browsers, Node.js, etc.).

## Installation

### How do I install Canopy?

```bash
npm install -g canopy
```

Or download binaries from the releases page.

### What version of Node.js do I need?

Node.js 16 or later is recommended.

### How do I update Canopy?

```bash
npm update -g canopy
```

## Language

### Does Canopy have null or undefined?

No. Canopy uses the `Maybe` type to represent values that might not exist:

```canopy
findUser : Int -> Maybe User
```

This forces you to handle both cases at compile time.

### How do I handle errors?

Use the `Result` type for operations that can fail:

```canopy
parseConfig : String -> Result ParseError Config
```

Or use `Task` for async operations:

```canopy
fetchUser : Int -> Task Http.Error User
```

### Can I use mutable variables?

No. All values in Canopy are immutable. Instead of mutation, you create new values:

```canopy
-- Instead of mutating
-- user.age = user.age + 1

-- Create a new record
olderUser = { user | age = user.age + 1 }
```

### How do I do loops?

Use recursion or higher-order functions:

```canopy
-- Instead of a for loop
List.map (\x -> x * 2) [1, 2, 3]

-- Instead of forEach
List.foldl (+) 0 [1, 2, 3]
```

### What's the difference between `let` and `where`?

Both define local values. `where` is preferred:

```canopy
-- Preferred: where
calculate x =
    result
  where
    squared = x * x
    result = squared + 1


-- Also valid: let
calculate x =
    let
        squared = x * x
    in
    squared + 1
```

## JavaScript Interop

### How do I use JavaScript libraries?

Use the capability-based FFI system:

```canopy
type alias Console =
    { log : String -> Task Never ()
    }


foreign import console : Console


-- Use it
logMessage : String -> Cmd Msg
logMessage msg =
    Task.perform (\_ -> NoOp) (console.log msg)
```

### Can I write inline JavaScript?

No. Canopy doesn't allow inline JavaScript for safety reasons. All JavaScript interaction goes through typed capabilities.

### How do I use npm packages?

Create typed bindings for the package functionality you need:

```javascript
// In JavaScript
var app = Canopy.Main.init({
    capabilities: {
        dayjs: {
            format: (date, format) => dayjs(date).format(format),
            parse: (str) => dayjs(str).valueOf()
        }
    }
});
```

### What about ports?

Ports are still supported for simple communication:

```canopy
port saveData : String -> Cmd msg
port dataLoaded : (String -> msg) -> Sub msg
```

## Architecture

### What is TEA (The Elm Architecture)?

TEA is the standard pattern for Canopy applications:

1. **Model**: Your application state
2. **Update**: How state changes in response to messages
3. **View**: How to display your state

### Do I have to use TEA?

For applications, yes. TEA provides predictable state management that scales well.

### How do I organize large applications?

Split into focused modules:

```
src/
├── Main.can
├── Route.can
├── Page/
│   ├── Home.can
│   └── Profile.can
├── Api/
│   └── User.can
└── Component/
    └── Header.can
```

Each page can have its own Model, Msg, update, and view.

## Performance

### How fast is Canopy?

Canopy produces highly optimized JavaScript. The virtual DOM is efficient, and the compiler eliminates dead code.

### How do I optimize my application?

1. Use `Html.Lazy` for expensive views
2. Use `Html.Keyed` for lists
3. Keep your Model flat when possible
4. Use `--optimize` flag for production builds

### What's the bundle size?

A minimal application is about 30KB gzipped. Real applications typically range from 50-150KB depending on features used.

## Tooling

### What editor should I use?

VS Code with the Canopy extension is recommended. It provides:
- Syntax highlighting
- Type information on hover
- Error highlighting
- Go to definition
- Auto-completion

### Is there a formatter?

Yes:

```bash
canopy format src/
```

### Is there a linter?

The compiler catches most issues. Additional linting is planned.

### How do I debug?

1. Use `Debug.log` during development
2. Use the time-travel debugger
3. Use browser DevTools with source maps

## Deployment

### How do I build for production?

```bash
canopy make src/Main.can --output=main.js --optimize
```

### How do I deploy?

Canopy produces static JavaScript. Deploy to any static hosting:
- Netlify
- Vercel
- GitHub Pages
- AWS S3
- Your own server

### Do I need a special server?

No. Canopy applications are static files. Any web server works.

## Migration

### Can I migrate from Elm?

Yes! Most Elm code works with minimal changes:

1. Rename `elm.json` to `canopy.json`
2. Update package names (`elm/` to `canopy/`)
3. Rename `.elm` files to `.can` (optional)
4. Build and fix any issues

### Can I use Elm packages?

Many Elm packages work with Canopy. Check the Canopy package registry for compatible versions.

## Getting Help

### Where can I ask questions?

- GitHub Discussions
- Discord server
- Stack Overflow (tag: canopy)

### Where do I report bugs?

Open an issue on GitHub with:
- Canopy version
- Operating system
- Steps to reproduce
- Expected vs actual behavior

### How do I contribute?

See the [Contributing Guide](./contributing.md).
