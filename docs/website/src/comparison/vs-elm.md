# Canopy vs Elm

Canopy is a fork of Elm that adds new features while maintaining compatibility. If you know Elm, you'll feel right at home with Canopy.

## What's the Same

Canopy maintains full compatibility with Elm's core features:

- **The Elm Architecture** (Model-View-Update)
- **Pure functional programming**
- **No runtime exceptions**
- **Helpful error messages**
- **Virtual DOM rendering**
- **All core modules** (Html, Json, Http, etc.)

Existing Elm code works in Canopy with minimal modifications (mostly import path changes).

## What's New in Canopy

### 1. Do-Notation for Tasks

**Elm:**
```elm
fetchUserWithPosts : Int -> Task Error UserWithPosts
fetchUserWithPosts userId =
    fetchUser userId
        |> Task.andThen
            (\user ->
                fetchPosts user.id
                    |> Task.andThen
                        (\posts ->
                            Task.succeed
                                { user = user
                                , posts = posts
                                }
                        )
            )
```

**Canopy:**
```canopy
fetchUserWithPosts : Int -> Task Error UserWithPosts
fetchUserWithPosts userId = do
    user <- fetchUser userId
    posts <- fetchPosts user.id
    pure { user = user, posts = posts }
```

Do-notation works with:
- `Task`
- `Maybe`
- `Result`
- Any type with `andThen` and `succeed`/`pure`

### 2. Enhanced FFI System

**Elm:**
```elm
-- Limited to ports
port saveToStorage : String -> Cmd msg
port onStorageChange : (String -> msg) -> Sub msg
```

**Canopy:**
```canopy
-- Capability-based FFI
type alias Storage =
    { getItem : String -> Task Never (Maybe String)
    , setItem : String -> String -> Task Never ()
    , removeItem : String -> Task Never ()
    }


foreign import localStorage : Storage


-- Use like any other function
saveSettings : Settings -> Task Never ()
saveSettings settings =
    Storage.setItem localStorage "settings" (encodeSettings settings)
```

### 3. JSON Codec Derivation

**Elm:**
```elm
-- Manual encoder
encodeUser : User -> Value
encodeUser user =
    Encode.object
        [ ( "name", Encode.string user.name )
        , ( "age", Encode.int user.age )
        , ( "email", Encode.string user.email )
        ]


-- Manual decoder
userDecoder : Decoder User
userDecoder =
    Decode.map3 User
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)
        (Decode.field "email" Decode.string)
```

**Canopy:**
```canopy
type alias User =
    { name : String
    , age : Int
    , email : String
    }
    deriving (Json)


-- Automatically generates encodeUser and userDecoder
```

### 4. Native Arithmetic Operators

**Elm:**
```elm
-- Int and Float have separate operators
intDivision = 10 // 3
floatDivision = 10.0 / 3.0

-- Power requires import
import Basics exposing (^)
squared = 2 ^ 10
```

**Canopy:**
```canopy
-- Unified operators with type inference
intResult = 10 / 3      -- Int division when both are Int
floatResult = 10.0 / 3  -- Float division with any Float

-- Power works intuitively
squared = 2 ^ 10        -- 1024
```

### 5. Source Maps

Canopy generates source maps for debugging:

```bash
canopy make src/Main.can --output=main.js --source-maps
```

Debug your Canopy code directly in browser DevTools.

### 6. ESM Output

**Elm:**
```javascript
// IIFE output only
var Elm = (function() { ... })();
```

**Canopy:**
```javascript
// ES Modules
export { Main };

// Usage
import { Main } from './main.js';
Main.init({ node: document.getElementById('app') });
```

### 7. Improved Testing

Canopy includes an enhanced testing framework:

```canopy
module Tests exposing (suite)

import Test exposing (Test, describe, test, fuzz)
import Expect
import Fuzz


suite : Test
suite =
    describe "User module"
        [ test "creates user with valid data" <|
            \_ ->
                User.create "Alice" "alice@example.com"
                    |> Expect.ok

        , fuzz Fuzz.string "name roundtrips through encoder" <|
            \name ->
                { name = name, age = 30, email = "test@example.com" }
                    |> encodeUser
                    |> Decode.decodeValue userDecoder
                    |> Expect.equal (Ok { name = name, age = 30, email = "test@example.com" })
        ]
```

### 8. Visual and Accessibility Testing

```canopy
import Visual
import Accessibility


visualTests : Test
visualTests =
    Visual.snapshot "button states"
        [ ( "default", viewButton Default )
        , ( "hover", viewButton Hover )
        , ( "disabled", viewButton Disabled )
        ]


a11yTests : Test
a11yTests =
    Accessibility.check "navigation"
        (viewNav model)
```

### 9. Time-Travel Debugger

Built-in debugger with state history:

```canopy
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
        |> Debug.withHistory  -- Enable time-travel debugging
```

## Migration from Elm

### Package Names

```elm
-- Elm
import Browser
import Html exposing (Html)
import Json.Decode as Decode
```

```canopy
-- Canopy (same!)
import Browser
import Html exposing (Html)
import Json.Decode as Decode
```

### Package Manager

```bash
# Elm
elm install elm/http

# Canopy
canopy install canopy/http
```

### Configuration

```json
// elm.json
{
    "type": "application",
    "source-directories": ["src"],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": {
            "elm/browser": "1.0.2",
            "elm/core": "1.0.5"
        }
    }
}
```

```json
// canopy.json (same structure)
{
    "type": "application",
    "source-directories": ["src"],
    "canopy-version": "0.19.2",
    "dependencies": {
        "direct": {
            "canopy/browser": "1.0.0",
            "canopy/core": "1.0.0"
        }
    }
}
```

### Step-by-Step Migration

1. **Install Canopy**
   ```bash
   npm install -g canopy
   ```

2. **Rename configuration**
   ```bash
   mv elm.json canopy.json
   ```

3. **Update package references**
   ```bash
   sed -i 's/elm\//canopy\//g' canopy.json
   ```

4. **Rename file extensions** (optional)
   ```bash
   find src -name "*.elm" -exec rename 's/.elm/.can/' {} \;
   ```

5. **Build and fix any issues**
   ```bash
   canopy make src/Main.can
   ```

## Feature Comparison

| Feature | Elm | Canopy |
|---------|-----|--------|
| Type safety | Yes | Yes |
| No runtime exceptions | Yes | Yes |
| TEA Architecture | Yes | Yes |
| Do-notation | No | Yes |
| Capability-based FFI | No | Yes |
| JSON derivation | No | Yes |
| Source maps | No | Yes |
| ESM output | No | Yes |
| Visual testing | No | Yes |
| Time-travel debugger | Basic | Enhanced |
| Package ecosystem | elm-packages | Canopy packages + compatible Elm packages |

## Community and Ecosystem

- **Canopy packages**: New packages written for Canopy
- **Elm compatibility**: Most Elm packages work with minimal changes
- **Tooling**: VS Code extension, language server, formatter

## Why Canopy?

Choose Canopy if you:

- Love Elm but want additional features
- Need better JavaScript interop
- Want do-notation for cleaner async code
- Need source maps for debugging
- Want automatic JSON codec generation
- Prefer ESM output

Stay with Elm if you:

- Value Elm's stability and slower pace
- Don't need the additional features
- Prefer the established Elm ecosystem
