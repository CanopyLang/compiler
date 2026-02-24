# Json Module

The Json modules provide encoding and decoding of JSON data.

## Json.Decode

Transform JSON into Canopy values.

### Primitive Decoders

```canopy
string : Decoder String
int : Decoder Int
float : Decoder Float
bool : Decoder Bool
null : a -> Decoder a
```

**Example:**

```canopy
Decode.decodeString Decode.string "\"hello\""  -- Ok "hello"
Decode.decodeString Decode.int "42"            -- Ok 42
Decode.decodeString Decode.bool "true"         -- Ok True
```

### Object Decoders

```canopy
-- Access a field
field : String -> Decoder a -> Decoder a

-- Access nested fields
at : List String -> Decoder a -> Decoder a

-- Decode the entire object
value : Decoder Value

-- Optional field
maybe : Decoder a -> Decoder (Maybe a)

-- Nullable field (null or value)
nullable : Decoder a -> Decoder (Maybe a)
```

**Example:**

```canopy
-- { "name": "Alice" }
Decode.field "name" Decode.string

-- { "user": { "profile": { "name": "Alice" } } }
Decode.at [ "user", "profile", "name" ] Decode.string

-- Field that might not exist
Decode.maybe (Decode.field "nickname" Decode.string)

-- Field that might be null
Decode.field "nickname" (Decode.nullable Decode.string)
```

### Array/List Decoders

```canopy
list : Decoder a -> Decoder (List a)
array : Decoder a -> Decoder (Array a)
index : Int -> Decoder a -> Decoder a
```

**Example:**

```canopy
-- [1, 2, 3]
Decode.list Decode.int  -- Ok [1, 2, 3]

-- ["a", "b", "c"]
Decode.list Decode.string  -- Ok ["a", "b", "c"]

-- Get element at index
Decode.index 0 Decode.string  -- First element as string
```

### Mapping and Combining

```canopy
map : (a -> b) -> Decoder a -> Decoder b
map2 : (a -> b -> c) -> Decoder a -> Decoder b -> Decoder c
map3 : ...
map4 : ...
map5 : ...
map6 : ...
map7 : ...
map8 : ...
```

**Example:**

```canopy
type alias User =
    { name : String
    , age : Int
    }


userDecoder : Decoder User
userDecoder =
    Decode.map2 User
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)


type alias Profile =
    { id : Int
    , name : String
    , email : String
    , isAdmin : Bool
    }


profileDecoder : Decoder Profile
profileDecoder =
    Decode.map4 Profile
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "is_admin" Decode.bool)
```

### Chaining Decoders

```canopy
andThen : (a -> Decoder b) -> Decoder a -> Decoder b
```

**Example:**

```canopy
-- Decode based on a type field
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
            Decode.fail ("Unknown shape: " ++ shapeType)
```

### Alternative Decoders

```canopy
oneOf : List (Decoder a) -> Decoder a
```

**Example:**

```canopy
-- ID can be string or int
idDecoder : Decoder String
idDecoder =
    Decode.oneOf
        [ Decode.string
        , Decode.int |> Decode.map String.fromInt
        ]
```

### Success and Failure

```canopy
succeed : a -> Decoder a
fail : String -> Decoder a
```

**Example:**

```canopy
-- Always succeed with a value
Decode.succeed "default"

-- Fail with an error message
if invalidCondition then
    Decode.fail "Invalid data"
else
    Decode.succeed result
```

### Decoding

```canopy
decodeString : Decoder a -> String -> Result Error a
decodeValue : Decoder a -> Value -> Result Error a
errorToString : Error -> String
```

---

## Json.Decode.Pipeline

Fluent pipeline style for building decoders.

```canopy
import Json.Decode.Pipeline exposing (required, optional, hardcoded)


type alias User =
    { id : Int
    , name : String
    , email : String
    , bio : Maybe String
    , isAdmin : Bool
    , role : String
    }


userDecoder : Decoder User
userDecoder =
    Decode.succeed User
        |> required "id" Decode.int
        |> required "name" Decode.string
        |> required "email" Decode.string
        |> optional "bio" (Decode.nullable Decode.string) Nothing
        |> optional "is_admin" Decode.bool False
        |> hardcoded "member"
```

### Pipeline Functions

```canopy
-- Required field (fails if missing)
required : String -> Decoder a -> Decoder (a -> b) -> Decoder b

-- Optional field with default
optional : String -> Decoder a -> a -> Decoder (a -> b) -> Decoder b

-- Optional field with Maybe
optionalMaybe : String -> Decoder a -> Decoder (Maybe a -> b) -> Decoder b

-- Hardcoded value
hardcoded : a -> Decoder (a -> b) -> Decoder b

-- Custom transformation
custom : Decoder a -> Decoder (a -> b) -> Decoder b
```

---

## Json.Encode

Transform Canopy values into JSON.

### Primitive Encoders

```canopy
string : String -> Value
int : Int -> Value
float : Float -> Value
bool : Bool -> Value
null : Value
```

**Example:**

```canopy
Encode.string "hello"  -- "hello"
Encode.int 42          -- 42
Encode.bool True       -- true
Encode.null            -- null
```

### Object Encoding

```canopy
object : List ( String, Value ) -> Value
```

**Example:**

```canopy
encodeUser : User -> Value
encodeUser user =
    Encode.object
        [ ( "name", Encode.string user.name )
        , ( "age", Encode.int user.age )
        , ( "email", Encode.string user.email )
        ]
```

### Array Encoding

```canopy
list : (a -> Value) -> List a -> Value
array : (a -> Value) -> Array a -> Value
set : (a -> Value) -> Set a -> Value
```

**Example:**

```canopy
encodeNumbers : List Int -> Value
encodeNumbers =
    Encode.list Encode.int


encodeUsers : List User -> Value
encodeUsers =
    Encode.list encodeUser
```

### Encoding to String

```canopy
encode : Int -> Value -> String
```

**Example:**

```canopy
-- Compact (no indentation)
Encode.encode 0 (encodeUser alice)
-- {"name":"Alice","age":30}

-- Pretty printed (4 spaces)
Encode.encode 4 (encodeUser alice)
-- {
--     "name": "Alice",
--     "age": 30
-- }
```

---

## Common Patterns

### Encoding Maybe

```canopy
encodeMaybe : (a -> Value) -> Maybe a -> Value
encodeMaybe encoder maybe =
    case maybe of
        Just value ->
            encoder value

        Nothing ->
            Encode.null


encodeProfile : Profile -> Value
encodeProfile profile =
    Encode.object
        [ ( "name", Encode.string profile.name )
        , ( "bio", encodeMaybe Encode.string profile.bio )
        ]
```

### Encoding Custom Types

```canopy
type Status
    = Active
    | Inactive
    | Pending


encodeStatus : Status -> Value
encodeStatus status =
    case status of
        Active ->
            Encode.string "active"

        Inactive ->
            Encode.string "inactive"

        Pending ->
            Encode.string "pending"


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

                    _ ->
                        Decode.fail "Invalid status"
            )
```

### Tagged Union Types

```canopy
type Message
    = TextMessage String
    | ImageMessage String Int Int
    | LocationMessage Float Float


encodeMessage : Message -> Value
encodeMessage message =
    case message of
        TextMessage content ->
            Encode.object
                [ ( "type", Encode.string "text" )
                , ( "content", Encode.string content )
                ]

        ImageMessage url width height ->
            Encode.object
                [ ( "type", Encode.string "image" )
                , ( "url", Encode.string url )
                , ( "width", Encode.int width )
                , ( "height", Encode.int height )
                ]

        LocationMessage lat lng ->
            Encode.object
                [ ( "type", Encode.string "location" )
                , ( "lat", Encode.float lat )
                , ( "lng", Encode.float lng )
                ]


messageDecoder : Decoder Message
messageDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen messageDataDecoder


messageDataDecoder : String -> Decoder Message
messageDataDecoder messageType =
    case messageType of
        "text" ->
            Decode.map TextMessage
                (Decode.field "content" Decode.string)

        "image" ->
            Decode.map3 ImageMessage
                (Decode.field "url" Decode.string)
                (Decode.field "width" Decode.int)
                (Decode.field "height" Decode.int)

        "location" ->
            Decode.map2 LocationMessage
                (Decode.field "lat" Decode.float)
                (Decode.field "lng" Decode.float)

        _ ->
            Decode.fail ("Unknown message type: " ++ messageType)
```

### Roundtrip Testing

```canopy
-- Test that encode/decode are inverses
roundtripTest : User -> Bool
roundtripTest user =
    user
        |> encodeUser
        |> Decode.decodeValue userDecoder
        == Ok user
```
