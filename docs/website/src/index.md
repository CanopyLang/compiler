# Canopy

**A modern, type-safe language for building reliable web applications.**

Canopy is a functional programming language that compiles to JavaScript, designed to help you build web applications that are fast, reliable, and maintainable. It draws inspiration from Elm while adding modern features like do-notation, an enhanced FFI system, and improved developer tooling.

## Why Canopy?

### No Runtime Exceptions

Canopy's type system catches errors at compile time, not in production. If your code compiles, it works.

```canopy
-- The compiler ensures you handle all cases
viewUser : Maybe User -> Html Msg
viewUser maybeUser =
    case maybeUser of
        Just user ->
            div [] [ text user.name ]

        Nothing ->
            div [] [ text "No user found" ]
```

### Simple and Predictable

The Canopy Architecture (based on The Elm Architecture) provides a simple pattern for building applications of any size:

```canopy
type alias Model =
    { count : Int }

type Msg
    = Increment
    | Decrement

update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        Decrement ->
            { model | count = model.count - 1 }
```

### Great Developer Experience

- **Helpful Error Messages**: Canopy provides friendly, actionable error messages that guide you to the solution
- **Fast Compilation**: Incremental compilation means quick feedback during development
- **Excellent Tooling**: IDE support with autocomplete, type information, and refactoring

### JavaScript Interop When You Need It

Canopy provides a capability-based FFI system for safe JavaScript interop:

```canopy
foreign import console : Console

log : String -> Task Never ()
log message =
    Console.log console message
```

## Quick Start

Install Canopy and create your first application:

```bash
# Install Canopy
npm install -g canopy

# Create a new project
canopy init my-app
cd my-app

# Start the development server
canopy reactor
```

## What's Next?

- **[Getting Started](./guide/getting-started.md)**: Install Canopy and build your first application
- **[The Canopy Architecture](./guide/architecture.md)**: Learn the core pattern for building applications
- **[Type System](./guide/type-system.md)**: Understand Canopy's powerful type system
- **[Examples](./examples/counter.md)**: See complete working examples

## Community

- [GitHub](https://github.com/canopy-lang/canopy): Report issues, contribute code
- [Discord](https://discord.gg/canopy): Chat with other Canopy developers
- [Forum](https://discourse.canopy-lang.org): Ask questions, share projects

## Coming from Elm?

Canopy is a fork of Elm with additional features. If you know Elm, you'll feel right at home. Check out [Canopy vs Elm](./comparison/vs-elm.md) to see what's new.

## Coming from TypeScript or JavaScript?

Canopy offers a different approach to building web applications. See [Canopy vs TypeScript](./comparison/vs-typescript.md) to understand the tradeoffs and benefits.
