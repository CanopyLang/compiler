# Abilities

Abilities are Canopy's answer to Haskell's type classes and Rust's traits. They let you define shared behavior that multiple types can implement, enabling polymorphic code without losing type safety.

## Declaring an Ability

An ability defines a set of method signatures that conforming types must implement:

```canopy
ability Printable a where
    toString : a -> String

ability Eq a where
    equal : a -> a -> Bool
```

## Implementing an Ability

Use `impl` to provide an implementation for a specific type:

```canopy
impl Printable Int where
    toString n =
        String.fromInt n

impl Printable String where
    toString s =
        s

impl Eq Int where
    equal a b =
        a == b
```

## Using Abilities in Functions

Constrain function parameters with ability requirements:

```canopy
display : Printable a => a -> Html msg
display value =
    Html.text (toString value)

allEqual : Eq a => List a -> Bool
allEqual items =
    case items of
        [] ->
            True

        x :: rest ->
            List.all (equal x) rest
```

## Super-Abilities

An ability can require another ability as a prerequisite:

```canopy
ability Eq a => Ord a where
    compare : a -> a -> Order
```

Any type implementing `Ord` must also implement `Eq`.

## Deriving Abilities

Canopy can automatically derive common ability implementations:

```canopy
type Color
    = Red
    | Green
    | Blue
    deriving (Eq, JsonEncode, JsonDecode)
```

### Derivable Abilities

| Ability | What it generates |
|---------|------------------|
| `Eq` | Structural equality comparison |
| `JsonEncode` | JSON encoder from type structure |
| `JsonDecode` | JSON decoder from type structure |

## JSON Without Boilerplate

One of the biggest quality-of-life improvements over Elm is automatic JSON serialization. Compare:

**Elm (manual):**
```elm
type alias User =
    { name : String
    , age : Int
    , email : String
    }

userEncoder : User -> Encode.Value
userEncoder user =
    Encode.object
        [ ( "name", Encode.string user.name )
        , ( "age", Encode.int user.age )
        , ( "email", Encode.string user.email )
        ]

userDecoder : Decoder User
userDecoder =
    Decode.map3 User
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)
        (Decode.field "email" Decode.string)
```

**Canopy (derived):**
```canopy
type alias User =
    { name : String
    , age : Int
    , email : String
    }
    deriving (JsonEncode, JsonDecode)

-- That's it! Encoding and decoding are generated automatically.
-- Use them directly:
encodeUser : User -> Json.Value
encodeUser =
    jsonEncode

decodeUser : Json.Decoder User
decodeUser =
    jsonDecode
```

## How It Works

Under the hood, Canopy uses dictionary-passing. When you write a function with an ability constraint like `Printable a =>`, the compiler passes a hidden dictionary argument containing the ability methods for the specific type being used.

This is entirely invisible to you as a developer — the compiler handles all the plumbing.

## Best Practices

1. **Keep abilities small** — each ability should define a focused set of related methods
2. **Use deriving when available** — avoid writing boilerplate implementations
3. **Prefer ability constraints over concrete types** — `Printable a => a -> String` is more reusable than `Int -> String`
4. **Document custom abilities** — explain what implementing the ability means semantically, not just what methods are required
