# Canopy vs ReScript

Both Canopy and ReScript are ML-family languages that compile to JavaScript. Here's how they compare.

## Overview

| Aspect | Canopy | ReScript |
|--------|--------|----------|
| **Origin** | Fork of Elm | Fork of OCaml (via BuckleScript) |
| **Paradigm** | Purely functional | Functional with imperative features |
| **Architecture** | TEA (Model-View-Update) | Flexible, often with React |
| **JS Interop** | Capability-based FFI | Direct bindings |
| **Runtime Errors** | None | Possible (but rare) |
| **Syntax** | Elm-like | OCaml-like / JavaScript-like |

## Syntax Comparison

### Function Definitions

**ReScript:**
```rescript
// Type annotation
let add = (a: int, b: int): int => a + b

// Type inference
let add = (a, b) => a + b

// Named parameters
let greet = (~name, ~greeting="Hello") => greeting ++ ", " ++ name
```

**Canopy:**
```canopy
-- Type annotation (above function)
add : Int -> Int -> Int
add a b =
    a + b

-- With currying
add : Int -> Int -> Int
add a b = a + b

-- Partial application instead of named params
greet : String -> String -> String
greet greeting name =
    greeting ++ ", " ++ name

greetHello : String -> String
greetHello = greet "Hello"
```

### Pattern Matching

**ReScript:**
```rescript
type status = Active | Inactive | Pending(string)

let statusToString = (status: status): string =>
  switch status {
  | Active => "active"
  | Inactive => "inactive"
  | Pending(reason) => "pending: " ++ reason
  }
```

**Canopy:**
```canopy
type Status
    = Active
    | Inactive
    | Pending String


statusToString : Status -> String
statusToString status =
    case status of
        Active ->
            "active"

        Inactive ->
            "inactive"

        Pending reason ->
            "pending: " ++ reason
```

### Records

**ReScript:**
```rescript
type user = {
  name: string,
  age: int,
  email: string,
}

let alice = {
  name: "Alice",
  age: 30,
  email: "alice@example.com",
}

// Update
let olderAlice = {...alice, age: alice.age + 1}
```

**Canopy:**
```canopy
type alias User =
    { name : String
    , age : Int
    , email : String
    }


alice : User
alice =
    { name = "Alice"
    , age = 30
    , email = "alice@example.com"
    }


-- Update
olderAlice : User
olderAlice =
    { alice | age = alice.age + 1 }
```

### Option/Maybe Types

**ReScript:**
```rescript
let findUser = (id: int): option<user> =>
  users->Belt.Array.getBy(u => u.id == id)

let greet = (maybeUser: option<user>): string =>
  switch maybeUser {
  | Some(user) => "Hello, " ++ user.name
  | None => "User not found"
  }

// Using Option module
let name = maybeUser->Option.map(u => u.name)->Option.getWithDefault("Anonymous")
```

**Canopy:**
```canopy
findUser : Int -> Maybe User
findUser id =
    List.find (\u -> u.id == id) users


greet : Maybe User -> String
greet maybeUser =
    case maybeUser of
        Just user ->
            "Hello, " ++ user.name

        Nothing ->
            "User not found"


-- Using Maybe module
name =
    maybeUser
        |> Maybe.map .name
        |> Maybe.withDefault "Anonymous"
```

## State Management

**ReScript (with React):**
```rescript
@react.component
let make = () => {
  let (count, setCount) = React.useState(() => 0)

  <div>
    <button onClick={_ => setCount(prev => prev - 1)}>
      {React.string("-")}
    </button>
    <span> {React.int(count)} </span>
    <button onClick={_ => setCount(prev => prev + 1)}>
      {React.string("+")}
    </button>
  </div>
}
```

**Canopy (TEA):**
```canopy
type alias Model =
    { count : Int
    }


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


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Decrement ] [ text "-" ]
        , span [] [ text (String.fromInt model.count) ]
        , button [ onClick Increment ] [ text "+" ]
        ]
```

## JavaScript Interop

**ReScript:**
```rescript
// Direct bindings
@val external document: Dom.document = "document"
@send external getElementById: (Dom.document, string) => Nullable.t<Dom.element> = "getElementById"

// Usage
let element = document->getElementById("app")

// External functions
@module("./analytics.js")
external track: (string, Js.Json.t) => unit = "track"

// Inline JS
let add = %raw(`
  function(a, b) {
    return a + b;
  }
`)
```

**Canopy:**
```canopy
-- Capability-based (no raw JS access)
type alias Analytics =
    { track : String -> Json.Value -> Task Never ()
    }


foreign import analytics : Analytics


-- Usage
trackEvent : String -> List ( String, String ) -> Cmd Msg
trackEvent event properties =
    let
        props =
            Encode.object
                (List.map (\( k, v ) -> ( k, Encode.string v )) properties)
    in
    Task.perform (\_ -> NoOp) (analytics.track event props)
```

**JavaScript side:**
```javascript
// ReScript - direct access
import { make as Counter } from './Counter.bs.js';

// Canopy - capability injection
var app = Canopy.Main.init({
    node: document.getElementById('app'),
    capabilities: {
        analytics: {
            track: (event, props) => window.analytics.track(event, props)
        }
    }
});
```

## Side Effects

**ReScript:**
```rescript
// Side effects can happen anywhere
let loadUser = async (id: int): user => {
  Js.log("Loading user...") // Side effect
  let response = await fetch(`/api/users/${id->Int.toString}`)
  let json = await response->Response.json
  json->parseUser
}
```

**Canopy:**
```canopy
-- Side effects are explicit
loadUser : Int -> Task Http.Error User
loadUser id =
    Http.get
        { url = "/api/users/" ++ String.fromInt id
        , expect = Http.expectJson identity userDecoder
        }


-- Combined with logging
loadUserWithLogging : Int -> Cmd Msg
loadUserWithLogging id =
    Cmd.batch
        [ logMessage "Loading user..."
        , Task.attempt GotUser (loadUser id)
        ]
```

## Error Handling

**ReScript:**
```rescript
type apiError = NetworkError | NotFound | ServerError(int)

let fetchUser = async (id: int): result<user, apiError> => {
  try {
    let response = await fetch(`/api/users/${id->Int.toString}`)
    switch response->Response.status {
    | 404 => Error(NotFound)
    | status if status >= 500 => Error(ServerError(status))
    | _ => Ok(await response->Response.json->parseUser)
    }
  } catch {
  | _ => Error(NetworkError)
  }
}
```

**Canopy:**
```canopy
type ApiError
    = NetworkError
    | NotFound
    | ServerError Int


fetchUser : Int -> Task ApiError User
fetchUser id =
    Http.get
        { url = "/api/users/" ++ String.fromInt id
        , expect = Http.expectStringResponse identity handleResponse
        }


handleResponse : Http.Response String -> Result ApiError User
handleResponse response =
    case response of
        Http.BadStatus_ metadata _ ->
            case metadata.statusCode of
                404 ->
                    Err NotFound

                status ->
                    if status >= 500 then
                        Err (ServerError status)
                    else
                        Err NetworkError

        Http.GoodStatus_ _ body ->
            Decode.decodeString userDecoder body
                |> Result.mapError (\_ -> NetworkError)

        _ ->
            Err NetworkError
```

## Ecosystem

| Aspect | ReScript | Canopy |
|--------|----------|--------|
| **React Support** | First-class | Via ports/FFI |
| **npm Integration** | Direct | Via FFI |
| **Bundle Size** | Very small | Very small |
| **Compile Speed** | Very fast | Fast |
| **Editor Support** | VS Code, Vim | VS Code, others |
| **Community Size** | Medium | Growing |

## When to Choose Each

### Choose Canopy when:

- You want guaranteed no runtime exceptions
- You prefer The Elm Architecture
- You want explicit, controlled side effects
- You value simplicity over flexibility
- You're building standalone web applications

### Choose ReScript when:

- You need tight React integration
- You want more direct JavaScript interop
- You prefer OCaml-style syntax
- You need imperative escape hatches
- You're integrating with existing JS codebases

## Summary

| Feature | Canopy | ReScript |
|---------|--------|----------|
| Runtime safety | No exceptions possible | Very safe, rare exceptions |
| JS Interop | Controlled via capabilities | Direct bindings |
| Side effects | Explicit (Cmd/Task) | Anywhere |
| Learning curve | Moderate | Moderate |
| Architecture | TEA built-in | Flexible |
| React support | Via FFI | Native |
| Syntax | Elm-like | OCaml/JS hybrid |
