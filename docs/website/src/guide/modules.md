# Modules

Modules organize your code into logical units. Every Canopy file is a module.

## Module Basics

### Declaring a Module

Every file starts with a module declaration:

```canopy
module User exposing (User, create, getName)

-- This module exports:
-- - User (the type)
-- - create (a function)
-- - getName (a function)
```

### Module Names and File Paths

Module names correspond to file paths:

| Module Name | File Path |
|------------|-----------|
| `Main` | `src/Main.can` |
| `User` | `src/User.can` |
| `Page.Home` | `src/Page/Home.can` |
| `Api.User` | `src/Api/User.can` |

### Exposing Values

Control what your module exposes:

```canopy
-- Expose specific items
module User exposing (User, create, getName)

-- Expose everything (not recommended for libraries)
module User exposing (..)

-- Expose type with all constructors
module Status exposing (Status(..))

-- Expose type without constructors (opaque type)
module Email exposing (Email, fromString, toString)
```

## Importing Modules

### Basic Import

```canopy
-- Import entire module
import User

-- Usage: User.create, User.getName
```

### Qualified Import with Alias

```canopy
-- Import with alias
import Data.List as List
import Html.Attributes as Attr
import Json.Decode as Decode

-- Usage: List.map, Attr.class, Decode.string
```

### Exposing Specific Items

```canopy
-- Expose specific values
import Html exposing (Html, div, text)
import Html.Events exposing (onClick)

-- Now use directly: div, text, onClick
```

### Exposing Everything

```canopy
-- Expose all exports (use sparingly)
import Html exposing (..)

-- All Html functions available unqualified
```

### Combining Approaches

```canopy
-- Common pattern: expose types, qualify functions
import Json.Decode exposing (Decoder)
import Json.Decode as Decode

-- Use: Decoder a (type), Decode.string (function)
```

## Organizing a Project

### Recommended Structure

```
src/
├── Main.can           # Entry point
├── Model.can          # Shared model types
├── Msg.can            # All message types
├── Route.can          # URL routing
├── Api/
│   ├── User.can       # User API calls
│   └── Post.can       # Post API calls
├── Page/
│   ├── Home.can       # Home page
│   ├── Profile.can    # Profile page
│   └── Settings.can   # Settings page
├── Component/
│   ├── Header.can     # Header component
│   ├── Footer.can     # Footer component
│   └── Modal.can      # Modal component
└── Util/
    ├── Date.can       # Date utilities
    └── Validation.can # Validation helpers
```

### Module Dependencies

```
         Main.can
             │
    ┌────────┼────────┐
    ▼        ▼        ▼
  Model   Page/*   Route
    │        │
    │    ┌───┴───┐
    │    ▼       ▼
    └──► Api/*  Component/*
```

## Creating Modules

### A Simple Module

```canopy
-- src/User.can
module User exposing
    ( User
    , create
    , getName
    , getEmail
    , updateName
    )

type alias User =
    { name : String
    , email : String
    }


create : String -> String -> User
create name email =
    { name = name
    , email = email
    }


getName : User -> String
getName user =
    user.name


getEmail : User -> String
getEmail user =
    user.email


updateName : String -> User -> User
updateName newName user =
    { user | name = newName }
```

### Using the Module

```canopy
-- src/Main.can
module Main exposing (main)

import User exposing (User)


viewUser : User -> Html msg
viewUser user =
    div []
        [ text (User.getName user)
        , text (User.getEmail user)
        ]
```

## Opaque Types

Hide implementation details by not exposing constructors:

### Defining an Opaque Type

```canopy
-- src/Email.can
module Email exposing
    ( Email          -- Type only, no constructor
    , fromString
    , toString
    )


-- The constructor is NOT exported
type Email
    = Email String


-- Only way to create an Email
fromString : String -> Maybe Email
fromString str =
    if isValidEmail str then
        Just (Email str)
    else
        Nothing


toString : Email -> String
toString (Email str) =
    str


-- Private helper
isValidEmail : String -> Bool
isValidEmail str =
    String.contains "@" str && String.contains "." str
```

### Using an Opaque Type

```canopy
-- In another module
import Email exposing (Email)

-- This works:
createEmail : String -> Maybe Email
createEmail = Email.fromString

-- This does NOT work (Email constructor not exposed):
-- badEmail = Email "not-valid"
```

Benefits of opaque types:

- **Validation**: Ensure invariants are maintained
- **Encapsulation**: Hide implementation details
- **Flexibility**: Change internals without breaking users

## Re-exporting

Expose items from other modules:

```canopy
-- src/Api.can
module Api exposing
    ( User
    , fetchUser
    , Post
    , fetchPosts
    )

import Api.User as User exposing (User)
import Api.Post as Post exposing (Post)


fetchUser = User.fetch
fetchPosts = Post.fetchAll
```

Now consumers can import from a single module:

```canopy
import Api exposing (User, Post)
```

## Circular Dependencies

Canopy does not allow circular dependencies. If module A imports module B, then B cannot import A.

### Solution: Extract Shared Types

```canopy
-- BEFORE: Circular dependency
-- User.can imports Post (for user's posts)
-- Post.can imports User (for post author)

-- AFTER: Extract shared types
-- src/Types.can
module Types exposing (UserId, PostId)

type alias UserId = Int
type alias PostId = Int


-- src/User.can
module User exposing (User)

import Types exposing (UserId, PostId)

type alias User =
    { id : UserId
    , name : String
    , postIds : List PostId
    }


-- src/Post.can
module Post exposing (Post)

import Types exposing (UserId, PostId)

type alias Post =
    { id : PostId
    , authorId : UserId
    , content : String
    }
```

## Module Best Practices

### 1. Explicit Exports

Always list exports explicitly:

```canopy
-- Good: Clear what's public
module User exposing (User, create, update)

-- Avoid: Unclear API, easy to break
module User exposing (..)
```

### 2. Group Related Functions

Keep related functionality together:

```canopy
-- Good: User module has all User operations
module User exposing
    ( User
    , create
    , update
    , delete
    , encode
    , decoder
    )
```

### 3. Use Qualified Imports

Prefer qualified imports for clarity:

```canopy
-- Good: Clear where functions come from
import Dict
import Set

Dict.empty
Set.fromList


-- Less clear: Where does 'empty' come from?
import Dict exposing (empty)
import Set exposing (fromList)
```

### 4. Consistent Naming

Follow naming conventions:

```canopy
-- Types: PascalCase
type alias UserProfile = ...

-- Values/functions: camelCase
getUserProfile : ...

-- Modules: PascalCase matching file path
module Page.UserProfile exposing (...)
```

### 5. Documentation

Document public functions:

```canopy
module Email exposing (Email, fromString, toString)

{-| An email address that has been validated.
-}
type Email
    = Email String


{-| Create an Email from a String.

Returns Nothing if the string is not a valid email address.

    fromString "user@example.com" == Just (Email "user@example.com")
    fromString "invalid" == Nothing

-}
fromString : String -> Maybe Email
fromString str =
    ...
```

## Common Patterns

### Page Modules

```canopy
-- src/Page/Profile.can
module Page.Profile exposing (Model, Msg, init, update, view)

type alias Model =
    { userId : String
    , user : Maybe User
    , loading : Bool
    }


type Msg
    = GotUser (Result Http.Error User)


init : String -> ( Model, Cmd Msg )
init userId =
    ( { userId = userId
      , user = Nothing
      , loading = True
      }
    , fetchUser userId
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotUser result ->
            ( { model
                | user = Result.toMaybe result
                , loading = False
              }
            , Cmd.none
            )


view : Model -> Html Msg
view model =
    ...
```

### API Modules

```canopy
-- src/Api/User.can
module Api.User exposing (fetch, create, update)

import Http
import Json.Decode as Decode
import Json.Encode as Encode


fetch : Int -> (Result Http.Error User -> msg) -> Cmd msg
fetch id toMsg =
    Http.get
        { url = "/api/users/" ++ String.fromInt id
        , expect = Http.expectJson toMsg userDecoder
        }


create : NewUser -> (Result Http.Error User -> msg) -> Cmd msg
create newUser toMsg =
    Http.post
        { url = "/api/users"
        , body = Http.jsonBody (encodeNewUser newUser)
        , expect = Http.expectJson toMsg userDecoder
        }
```

## Next Steps

- **[Pattern Matching](./pattern-matching.md)**: Advanced pattern matching
- **[JSON](./json.md)**: Encoding and decoding JSON
- **[Testing](./testing.md)**: Test your modules
