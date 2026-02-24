# Type System

Canopy has a powerful static type system that catches errors at compile time. If your code compiles, it will not crash at runtime due to type errors.

## Basic Types

### Primitives

```canopy
-- Integer
count : Int
count = 42

-- Floating point
price : Float
price = 19.99

-- String
name : String
name = "Canopy"

-- Character
letter : Char
letter = 'A'

-- Boolean
isActive : Bool
isActive = True
```

### Type Annotations

Type annotations are optional but recommended:

```canopy
-- With annotation (recommended)
greet : String -> String
greet name =
    "Hello, " ++ name

-- Without annotation (inferred)
greet name =
    "Hello, " ++ name
```

The compiler infers types, but explicit annotations:

- Serve as documentation
- Provide better error messages
- Prevent accidental type changes

## Composite Types

### Lists

Lists contain zero or more elements of the same type:

```canopy
numbers : List Int
numbers = [1, 2, 3, 4, 5]

names : List String
names = ["Alice", "Bob", "Charlie"]

empty : List a
empty = []
```

Common operations:

```canopy
-- Get length
List.length numbers  -- 5

-- Map over elements
List.map (\n -> n * 2) numbers  -- [2, 4, 6, 8, 10]

-- Filter elements
List.filter (\n -> n > 2) numbers  -- [3, 4, 5]

-- Fold/reduce
List.foldl (+) 0 numbers  -- 15
```

### Tuples

Tuples group a fixed number of values of potentially different types:

```canopy
-- Pair
point : ( Int, Int )
point = ( 10, 20 )

-- Triple
person : ( String, Int, Bool )
person = ( "Alice", 30, True )
```

Access tuple elements:

```canopy
-- For pairs, use Tuple functions
Tuple.first point   -- 10
Tuple.second point  -- 20

-- Or pattern matching
getName : ( String, Int, Bool ) -> String
getName ( name, _, _ ) =
    name
```

**Note**: Prefer records over tuples with more than two elements for clarity.

### Records

Records are collections of named fields:

```canopy
type alias User =
    { name : String
    , email : String
    , age : Int
    }

alice : User
alice =
    { name = "Alice"
    , email = "alice@example.com"
    , age = 30
    }
```

Access fields with dot notation:

```canopy
alice.name   -- "Alice"
alice.age    -- 30

-- Or as a function
.name alice  -- "Alice"
```

Update records (creates a new record):

```canopy
olderAlice : User
olderAlice =
    { alice | age = 31 }

-- Update multiple fields
updatedAlice : User
updatedAlice =
    { alice | name = "Alice Smith", age = 31 }
```

### Extensible Records

Functions can work with any record containing certain fields:

```canopy
-- Works with any record that has a "name" field
getName : { a | name : String } -> String
getName record =
    record.name

-- Usage
type alias User = { name : String, age : Int }
type alias Company = { name : String, employees : Int }

getName { name = "Alice", age = 30 }        -- "Alice"
getName { name = "Acme Inc", employees = 50 }  -- "Acme Inc"
```

## Custom Types

Custom types (also called union types or algebraic data types) let you define your own types:

### Simple Custom Types

```canopy
type Direction
    = North
    | South
    | East
    | West


move : Direction -> Position -> Position
move direction pos =
    case direction of
        North -> { pos | y = pos.y + 1 }
        South -> { pos | y = pos.y - 1 }
        East  -> { pos | x = pos.x + 1 }
        West  -> { pos | x = pos.x - 1 }
```

### Custom Types with Data

Constructors can carry associated data:

```canopy
type Shape
    = Circle Float
    | Rectangle Float Float
    | Triangle Float Float Float


area : Shape -> Float
area shape =
    case shape of
        Circle radius ->
            pi * radius * radius

        Rectangle width height ->
            width * height

        Triangle a b c ->
            let
                s = (a + b + c) / 2
            in
            sqrt (s * (s - a) * (s - b) * (s - c))
```

### Recursive Types

Types can reference themselves:

```canopy
type Tree a
    = Empty
    | Node a (Tree a) (Tree a)


exampleTree : Tree Int
exampleTree =
    Node 1
        (Node 2 Empty Empty)
        (Node 3 Empty Empty)


sum : Tree Int -> Int
sum tree =
    case tree of
        Empty ->
            0

        Node value left right ->
            value + sum left + sum right
```

## Maybe: Handling Missing Values

`Maybe` represents a value that might not exist:

```canopy
type Maybe a
    = Just a
    | Nothing
```

Usage:

```canopy
-- A function that might fail
findUser : Int -> Maybe User
findUser id =
    List.find (\u -> u.id == id) users


-- Handle both cases
viewUser : Maybe User -> Html msg
viewUser maybeUser =
    case maybeUser of
        Just user ->
            div [] [ text user.name ]

        Nothing ->
            div [] [ text "User not found" ]
```

Helper functions:

```canopy
-- Provide a default value
Maybe.withDefault "Anonymous" maybeName

-- Transform if present
Maybe.map String.toUpper maybeName

-- Chain operations that might fail
Maybe.andThen findUser maybeId
```

## Result: Handling Errors

`Result` represents success or failure with an error value:

```canopy
type Result error value
    = Ok value
    | Err error
```

Usage:

```canopy
type ParseError
    = InvalidFormat
    | OutOfRange


parseAge : String -> Result ParseError Int
parseAge input =
    case String.toInt input of
        Nothing ->
            Err InvalidFormat

        Just age ->
            if age < 0 || age > 150 then
                Err OutOfRange
            else
                Ok age


-- Handle both cases
viewAge : Result ParseError Int -> Html msg
viewAge result =
    case result of
        Ok age ->
            text ("Age: " ++ String.fromInt age)

        Err InvalidFormat ->
            text "Please enter a valid number"

        Err OutOfRange ->
            text "Age must be between 0 and 150"
```

## Type Variables (Generics)

Type variables make functions work with any type:

```canopy
-- Works with any type
identity : a -> a
identity x = x

-- Works with any two types
swap : ( a, b ) -> ( b, a )
swap ( x, y ) = ( y, x )

-- Works with lists of any type
length : List a -> Int
length list =
    case list of
        [] -> 0
        _ :: rest -> 1 + length rest
```

Constrained type variables:

```canopy
-- The `number` constraint means Int or Float
double : number -> number
double n = n + n

-- Works with both
doubleInt : Int
doubleInt = double 5

doubleFloat : Float
doubleFloat = double 5.5

-- The `comparable` constraint
maximum : comparable -> comparable -> comparable
maximum a b =
    if a > b then a else b
```

## Type Aliases

Type aliases give names to types:

```canopy
-- Simple alias
type alias Name = String

-- Record alias
type alias Point =
    { x : Float
    , y : Float
    }

-- Parameterized alias
type alias Response a =
    { data : a
    , status : Int
    }
```

**Important distinction:**

- `type alias` creates an interchangeable name (Point = { x, y })
- `type` creates a completely new type (Direction is not String)

## Opaque Types

Hide implementation details using opaque types:

```canopy
-- EmailAddress.can
module EmailAddress exposing (EmailAddress, fromString, toString)

-- Opaque type - constructor not exported
type EmailAddress
    = EmailAddress String


fromString : String -> Maybe EmailAddress
fromString str =
    if isValidEmail str then
        Just (EmailAddress str)
    else
        Nothing


toString : EmailAddress -> String
toString (EmailAddress str) =
    str
```

Users can only create valid `EmailAddress` values through `fromString`.

## Pattern Matching

Pattern matching deconstructs values:

```canopy
-- Match on custom types
describe : Shape -> String
describe shape =
    case shape of
        Circle r ->
            "Circle with radius " ++ String.fromFloat r

        Rectangle w h ->
            "Rectangle " ++ String.fromFloat w ++ "x" ++ String.fromFloat h

        Triangle _ _ _ ->
            "Triangle"


-- Match on lists
describeList : List a -> String
describeList list =
    case list of
        [] ->
            "Empty list"

        [ x ] ->
            "Single element"

        [ x, y ] ->
            "Two elements"

        x :: rest ->
            "At least one element"


-- Match with guards (using if)
absolute : Int -> Int
absolute n =
    if n < 0 then
        -n
    else
        n
```

## Common Patterns

### Modeling State

```canopy
type RemoteData e a
    = NotAsked
    | Loading
    | Failure e
    | Success a

type alias Model =
    { users : RemoteData Http.Error (List User)
    }
```

### Phantom Types

```canopy
type Validated
type Unvalidated

type Form a =
    Form
        { name : String
        , email : String
        }


validate : Form Unvalidated -> Maybe (Form Validated)
validate (Form data) =
    if isValid data then
        Just (Form data)
    else
        Nothing


-- Only accepts validated forms
submit : Form Validated -> Cmd Msg
submit form = ...
```

## Best Practices

1. **Use custom types over primitives**: `UserId` instead of `Int`
2. **Make invalid states unrepresentable**: Design types so invalid combinations are impossible
3. **Use Maybe/Result for operations that can fail**: Never assume success
4. **Prefer records over tuples**: Named fields are clearer
5. **Use opaque types for validation**: Ensure invariants at the type level

## Next Steps

- **[Functions](./functions.md)**: Learn about function composition
- **[Pattern Matching](./pattern-matching.md)**: Advanced pattern matching
- **[JSON](./json.md)**: Encoding and decoding JSON
