# JSON

Canopy provides a robust system for encoding and decoding JSON. The approach is explicit and type-safe, ensuring your data transformations are correct.

## Overview

JSON handling in Canopy uses two concepts:

- **Decoders**: Transform JSON into Canopy values
- **Encoders**: Transform Canopy values into JSON

```canopy
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
```

## Decoding JSON

### Basic Decoders

```canopy
-- Primitive decoders
Decode.string : Decoder String
Decode.int : Decoder Int
Decode.float : Decoder Float
Decode.bool : Decoder Bool
Decode.null : a -> Decoder a
```

Usage:

```canopy
-- Decode a string
Decode.decodeString Decode.string "\"hello\""
-- Ok "hello"

-- Decode an int
Decode.decodeString Decode.int "42"
-- Ok 42

-- Decode a bool
Decode.decodeString Decode.bool "true"
-- Ok True
```

### Decoding Objects

Use `field` to access object fields:

```canopy
-- { "name": "Alice" }
nameDecoder : Decoder String
nameDecoder =
    Decode.field "name" Decode.string


-- { "age": 30 }
ageDecoder : Decoder Int
ageDecoder =
    Decode.field "age" Decode.int


-- Nested: { "user": { "name": "Alice" } }
nestedNameDecoder : Decoder String
nestedNameDecoder =
    Decode.at [ "user", "name" ] Decode.string
```

### Decoding Records

Combine multiple field decoders with `map`:

```canopy
type alias User =
    { name : String
    , age : Int
    }


-- Using map2
userDecoder : Decoder User
userDecoder =
    Decode.map2 User
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)


-- For more fields, use map3, map4, etc.
type alias Post =
    { id : Int
    , title : String
    , body : String
    , published : Bool
    }


postDecoder : Decoder Post
postDecoder =
    Decode.map4 Post
        (Decode.field "id" Decode.int)
        (Decode.field "title" Decode.string)
        (Decode.field "body" Decode.string)
        (Decode.field "published" Decode.bool)
```

### Pipeline Style

For complex records, use the pipeline approach:

```canopy
import Json.Decode.Pipeline exposing (required, optional, hardcoded)


type alias Profile =
    { id : Int
    , name : String
    , email : String
    , bio : Maybe String
    , isAdmin : Bool
    , createdAt : String
    }


profileDecoder : Decoder Profile
profileDecoder =
    Decode.succeed Profile
        |> required "id" Decode.int
        |> required "name" Decode.string
        |> required "email" Decode.string
        |> optional "bio" (Decode.maybe Decode.string) Nothing
        |> optional "is_admin" Decode.bool False
        |> required "created_at" Decode.string
```

### Decoding Lists and Arrays

```canopy
-- List of strings: ["a", "b", "c"]
stringListDecoder : Decoder (List String)
stringListDecoder =
    Decode.list Decode.string


-- List of users
usersDecoder : Decoder (List User)
usersDecoder =
    Decode.list userDecoder


-- Array (indexed access)
firstUserDecoder : Decoder User
firstUserDecoder =
    Decode.index 0 userDecoder
```

### Decoding Maybe Values

```canopy
-- Field might not exist or be null
type alias User =
    { name : String
    , nickname : Maybe String
    }


userDecoder : Decoder User
userDecoder =
    Decode.map2 User
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "nickname" Decode.string))


-- Alternatively, for nullable fields
userDecoder : Decoder User
userDecoder =
    Decode.map2 User
        (Decode.field "name" Decode.string)
        (Decode.field "nickname" (Decode.nullable Decode.string))
```

### Decoding Custom Types

```canopy
type Status
    = Active
    | Inactive
    | Pending


statusDecoder : Decoder Status
statusDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "active" ->
                        Decode.succeed Active

                    "inactive" ->
                        Decode.succeed Inactive

                    "pending" ->
                        Decode.succeed Pending

                    other ->
                        Decode.fail ("Unknown status: " ++ other)
            )
```

### Decoding Union Types

```canopy
type Shape
    = Circle Float
    | Rectangle Float Float


shapeDecoder : Decoder Shape
shapeDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen shapeDataDecoder


shapeDataDecoder : String -> Decoder Shape
shapeDataDecoder shapeType =
    case shapeType of
        "circle" ->
            Decode.map Circle
                (Decode.field "radius" Decode.float)

        "rectangle" ->
            Decode.map2 Rectangle
                (Decode.field "width" Decode.float)
                (Decode.field "height" Decode.float)

        _ ->
            Decode.fail ("Unknown shape type: " ++ shapeType)
```

### Using oneOf

Try multiple decoders:

```canopy
-- Can be string or int
idDecoder : Decoder String
idDecoder =
    Decode.oneOf
        [ Decode.string
        , Decode.int |> Decode.map String.fromInt
        ]


-- Different response formats
responseDecoder : Decoder User
responseDecoder =
    Decode.oneOf
        [ Decode.field "data" userDecoder
        , Decode.field "user" userDecoder
        , userDecoder
        ]
```

## Encoding JSON

### Basic Encoding

```canopy
Encode.string "hello"     -- "hello"
Encode.int 42             -- 42
Encode.float 3.14         -- 3.14
Encode.bool True          -- true
Encode.null               -- null
```

### Encoding Objects

```canopy
encodeUser : User -> Value
encodeUser user =
    Encode.object
        [ ( "name", Encode.string user.name )
        , ( "age", Encode.int user.age )
        ]


-- Convert to string
userJson : String
userJson =
    Encode.encode 0 (encodeUser alice)
-- {"name":"Alice","age":30}

-- With indentation
userJsonPretty : String
userJsonPretty =
    Encode.encode 4 (encodeUser alice)
```

### Encoding Lists

```canopy
encodeNumbers : List Int -> Value
encodeNumbers numbers =
    Encode.list Encode.int numbers


encodeUsers : List User -> Value
encodeUsers users =
    Encode.list encodeUser users
```

### Encoding Maybe

```canopy
encodeMaybe : (a -> Value) -> Maybe a -> Value
encodeMaybe encoder maybe =
    case maybe of
        Just value ->
            encoder value

        Nothing ->
            Encode.null


-- Usage
type alias Profile =
    { name : String
    , bio : Maybe String
    }


encodeProfile : Profile -> Value
encodeProfile profile =
    Encode.object
        [ ( "name", Encode.string profile.name )
        , ( "bio", encodeMaybe Encode.string profile.bio )
        ]
```

### Encoding Custom Types

```canopy
encodeStatus : Status -> Value
encodeStatus status =
    case status of
        Active ->
            Encode.string "active"

        Inactive ->
            Encode.string "inactive"

        Pending ->
            Encode.string "pending"


encodeShape : Shape -> Value
encodeShape shape =
    case shape of
        Circle radius ->
            Encode.object
                [ ( "type", Encode.string "circle" )
                , ( "radius", Encode.float radius )
                ]

        Rectangle width height ->
            Encode.object
                [ ( "type", Encode.string "rectangle" )
                , ( "width", Encode.float width )
                , ( "height", Encode.float height )
                ]
```

## Deriving JSON Codecs

Canopy supports automatic derivation of JSON encoders and decoders:

```canopy
type alias User =
    { name : String
    , age : Int
    , email : String
    }
    deriving (Json)


-- Automatically generates:
-- userEncoder : User -> Value
-- userDecoder : Decoder User
```

For custom types:

```canopy
type Status
    = Active
    | Inactive
    | Pending
    deriving (Json)
```

## Working with HTTP

Combine JSON with HTTP requests:

```canopy
import Http
import Json.Decode as Decode


fetchUsers : Cmd Msg
fetchUsers =
    Http.get
        { url = "/api/users"
        , expect = Http.expectJson GotUsers usersDecoder
        }


createUser : User -> Cmd Msg
createUser user =
    Http.post
        { url = "/api/users"
        , body = Http.jsonBody (encodeUser user)
        , expect = Http.expectJson UserCreated userDecoder
        }
```

## Error Handling

Decoding can fail. Handle errors gracefully:

```canopy
parseResponse : String -> Result String User
parseResponse json =
    case Decode.decodeString userDecoder json of
        Ok user ->
            Ok user

        Err error ->
            Err (Decode.errorToString error)


-- In update function
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotUsers result ->
            case result of
                Ok users ->
                    ( { model | users = users }, Cmd.none )

                Err httpError ->
                    ( { model | error = Just (errorToString httpError) }
                    , Cmd.none
                    )
```

## Best Practices

### 1. Keep Decoders Close to Types

```canopy
-- In User.can
module User exposing (User, decoder, encode)

type alias User =
    { name : String
    , age : Int
    }


decoder : Decoder User
decoder =
    Decode.map2 User
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)


encode : User -> Value
encode user =
    Encode.object
        [ ( "name", Encode.string user.name )
        , ( "age", Encode.int user.age )
        ]
```

### 2. Handle API Variations

```canopy
-- API might return different formats
userDecoder : Decoder User
userDecoder =
    Decode.oneOf
        [ -- Try v2 format first
          Decode.map2 User
            (Decode.at [ "data", "attributes", "name" ] Decode.string)
            (Decode.at [ "data", "attributes", "age" ] Decode.int)

        , -- Fall back to v1 format
          Decode.map2 User
            (Decode.field "name" Decode.string)
            (Decode.field "age" Decode.int)
        ]
```

### 3. Validate During Decoding

```canopy
positiveInt : Decoder Int
positiveInt =
    Decode.int
        |> Decode.andThen
            (\n ->
                if n > 0 then
                    Decode.succeed n
                else
                    Decode.fail "Expected positive integer"
            )


emailDecoder : Decoder String
emailDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                if String.contains "@" str then
                    Decode.succeed str
                else
                    Decode.fail "Invalid email format"
            )
```

### 4. Use Type Aliases

```canopy
-- Clearer than raw types
type alias UserId = Int
type alias UserName = String

type alias User =
    { id : UserId
    , name : UserName
    }
```

## Next Steps

- **[HTTP Requests](./http.md)**: Use JSON with HTTP
- **[Error Handling](./error-handling.md)**: Handle decoding errors
- **[Testing](./testing.md)**: Test your decoders
