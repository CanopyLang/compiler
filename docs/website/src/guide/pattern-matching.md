# Pattern Matching

Pattern matching is one of Canopy's most powerful features. It lets you destructure data and handle different cases in a clear, exhaustive way.

## Basic Pattern Matching

### Case Expressions

The `case` expression matches a value against patterns:

```canopy
describe : Int -> String
describe n =
    case n of
        0 ->
            "zero"

        1 ->
            "one"

        _ ->
            "many"
```

### Matching Custom Types

```canopy
type Color
    = Red
    | Green
    | Blue
    | Custom String


toHex : Color -> String
toHex color =
    case color of
        Red ->
            "#FF0000"

        Green ->
            "#00FF00"

        Blue ->
            "#0000FF"

        Custom hex ->
            hex
```

### Matching with Data

```canopy
type Result error value
    = Ok value
    | Err error


handleResult : Result String Int -> String
handleResult result =
    case result of
        Ok value ->
            "Success: " ++ String.fromInt value

        Err message ->
            "Error: " ++ message
```

## Exhaustiveness Checking

Canopy ensures you handle all cases:

```canopy
type Direction
    = North
    | South
    | East
    | West


-- This will NOT compile - missing West!
move : Direction -> String
move dir =
    case dir of
        North -> "up"
        South -> "down"
        East -> "right"
        -- Error: Missing pattern: West
```

This guarantee means if your code compiles, you've handled every possibility.

## Wildcard Patterns

The underscore `_` matches anything:

```canopy
-- Match specific values, catch-all for the rest
isWeekend : Day -> Bool
isWeekend day =
    case day of
        Saturday ->
            True

        Sunday ->
            True

        _ ->
            False
```

Use wildcards when you don't need the value:

```canopy
-- Ignore some tuple elements
getFirst : ( a, b, c ) -> a
getFirst tuple =
    case tuple of
        ( first, _, _ ) ->
            first
```

## Destructuring

### Tuples

```canopy
addPair : ( Int, Int ) -> Int
addPair pair =
    case pair of
        ( x, y ) ->
            x + y


-- Or directly in parameters
addPair : ( Int, Int ) -> Int
addPair ( x, y ) =
    x + y
```

### Records

```canopy
type alias User =
    { name : String
    , age : Int
    , email : String
    }


greet : User -> String
greet user =
    case user of
        { name, age } ->
            "Hello, " ++ name ++ "! You are " ++ String.fromInt age


-- Or directly in parameters
greet : User -> String
greet { name } =
    "Hello, " ++ name
```

### Lists

```canopy
describeList : List a -> String
describeList list =
    case list of
        [] ->
            "empty"

        [ x ] ->
            "single element"

        [ x, y ] ->
            "two elements"

        x :: y :: rest ->
            "more than two elements"


-- Get first element
head : List a -> Maybe a
head list =
    case list of
        [] ->
            Nothing

        first :: _ ->
            Just first


-- Get rest of list
tail : List a -> Maybe (List a)
tail list =
    case list of
        [] ->
            Nothing

        _ :: rest ->
            Just rest
```

## Nested Patterns

Match nested structures:

```canopy
type alias Point =
    { x : Int, y : Int }


type Shape
    = Circle Point Int
    | Rectangle Point Point


getOriginX : Shape -> Int
getOriginX shape =
    case shape of
        Circle { x } _ ->
            x

        Rectangle { x } _ ->
            x


-- Deeply nested
type Tree a
    = Leaf
    | Node a (Tree a) (Tree a)


hasLeftChild : Tree a -> Bool
hasLeftChild tree =
    case tree of
        Node _ (Node _ _ _) _ ->
            True

        _ ->
            False
```

## As Patterns

Bind the whole value while destructuring:

```canopy
-- Bind 'user' to the whole record while extracting 'name'
greetVerbose : User -> String
greetVerbose ({ name } as user) =
    "Hello, " ++ name ++ "! (User ID: " ++ String.fromInt user.id ++ ")"


-- With case expression
process : Maybe (List Int) -> String
process maybeList =
    case maybeList of
        Just ((_ :: _) as nonEmpty) ->
            "Got " ++ String.fromInt (List.length nonEmpty) ++ " items"

        Just [] ->
            "Empty list"

        Nothing ->
            "No list"
```

## Literal Patterns

Match on specific values:

```canopy
-- String literals
greetLanguage : String -> String
greetLanguage lang =
    case lang of
        "en" ->
            "Hello"

        "es" ->
            "Hola"

        "fr" ->
            "Bonjour"

        _ ->
            "Hi"


-- Number literals
fizzBuzz : Int -> String
fizzBuzz n =
    case ( modBy 3 n, modBy 5 n ) of
        ( 0, 0 ) ->
            "FizzBuzz"

        ( 0, _ ) ->
            "Fizz"

        ( _, 0 ) ->
            "Buzz"

        _ ->
            String.fromInt n
```

## Combining Patterns

### Multiple Values

```canopy
-- Match on multiple values
compare : Int -> Int -> String
compare a b =
    case ( a, b ) of
        ( 0, 0 ) ->
            "both zero"

        ( 0, _ ) ->
            "first is zero"

        ( _, 0 ) ->
            "second is zero"

        ( x, y ) ->
            if x == y then "equal" else "different"
```

### With Maybe and Result

```canopy
-- Two Maybes
combine : Maybe Int -> Maybe Int -> Maybe Int
combine ma mb =
    case ( ma, mb ) of
        ( Just a, Just b ) ->
            Just (a + b)

        _ ->
            Nothing


-- Maybe and Result
handleBoth : Maybe String -> Result String Int -> String
handleBoth maybeStr result =
    case ( maybeStr, result ) of
        ( Just str, Ok n ) ->
            str ++ ": " ++ String.fromInt n

        ( Just str, Err _ ) ->
            str ++ ": error"

        ( Nothing, Ok n ) ->
            String.fromInt n

        ( Nothing, Err err ) ->
            "Error: " ++ err
```

## Guards (Using If)

Add conditions to patterns:

```canopy
absolute : Int -> Int
absolute n =
    if n < 0 then
        -n
    else
        n


classify : Int -> String
classify n =
    if n < 0 then
        "negative"
    else if n == 0 then
        "zero"
    else if n < 10 then
        "small positive"
    else
        "large positive"
```

## Pattern Matching Best Practices

### 1. Handle All Cases

Don't use catch-all wildcards when you can be explicit:

```canopy
-- Less safe: Adding a new Color won't warn you
toRgb : Color -> ( Int, Int, Int )
toRgb color =
    case color of
        Red -> ( 255, 0, 0 )
        _ -> ( 0, 0, 0 )  -- Catches everything else


-- Better: Explicit patterns warn when new cases are added
toRgb : Color -> ( Int, Int, Int )
toRgb color =
    case color of
        Red -> ( 255, 0, 0 )
        Green -> ( 0, 255, 0 )
        Blue -> ( 0, 0, 255 )
        Custom hex -> parseHex hex
```

### 2. Put Specific Cases First

```canopy
-- Good: Specific cases before general
handleNumber : Int -> String
handleNumber n =
    case n of
        0 ->
            "zero"

        1 ->
            "one"

        _ ->
            "other"
```

### 3. Use Helper Functions for Complex Matching

```canopy
-- Instead of deeply nested patterns
process : Result String (Maybe (List Int)) -> Int
process result =
    case result of
        Ok (Just (x :: _)) -> x
        _ -> 0


-- Consider breaking it down
process : Result String (Maybe (List Int)) -> Int
process result =
    result
        |> Result.toMaybe
        |> Maybe.andThen identity
        |> Maybe.andThen List.head
        |> Maybe.withDefault 0
```

### 4. Destructure in Function Parameters When Clear

```canopy
-- Clear and concise
distance : ( Float, Float ) -> ( Float, Float ) -> Float
distance ( x1, y1 ) ( x2, y2 ) =
    sqrt ((x2 - x1) ^ 2 + (y2 - y1) ^ 2)


-- Also clear
getName : { a | name : String } -> String
getName { name } =
    name
```

## Common Patterns

### Safe List Operations

```canopy
safeHead : List a -> Maybe a
safeHead list =
    case list of
        [] ->
            Nothing

        x :: _ ->
            Just x


safeLast : List a -> Maybe a
safeLast list =
    case list of
        [] ->
            Nothing

        [ x ] ->
            Just x

        _ :: rest ->
            safeLast rest
```

### Unpacking Nested Maybe

```canopy
-- Join Maybe (Maybe a) into Maybe a
join : Maybe (Maybe a) -> Maybe a
join mm =
    case mm of
        Just (Just x) ->
            Just x

        _ ->
            Nothing
```

### Recursive Processing

```canopy
sum : List Int -> Int
sum list =
    case list of
        [] ->
            0

        x :: xs ->
            x + sum xs


-- With accumulator (tail recursive)
sum : List Int -> Int
sum list =
    sumHelper 0 list
  where
    sumHelper acc list =
        case list of
            [] ->
                acc

            x :: xs ->
                sumHelper (acc + x) xs
```

## Next Steps

- **[JSON](./json.md)**: Pattern matching with JSON decoders
- **[Error Handling](./error-handling.md)**: Using pattern matching for errors
- **[Functions](./functions.md)**: Combine with higher-order functions
