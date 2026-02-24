# Functions

Functions are the building blocks of Canopy programs. They are pure, first-class values that can be passed around and composed together.

## Defining Functions

### Basic Function Definition

```canopy
-- Single parameter
square : Int -> Int
square n =
    n * n

-- Multiple parameters
add : Int -> Int -> Int
add x y =
    x + y

-- With type annotation
greet : String -> String -> String
greet greeting name =
    greeting ++ ", " ++ name ++ "!"
```

### Anonymous Functions (Lambdas)

```canopy
-- Anonymous function
\x -> x * x

-- With multiple parameters
\x y -> x + y

-- Used inline
List.map (\x -> x * 2) [1, 2, 3]  -- [2, 4, 6]

-- Named equivalent
double : Int -> Int
double x = x * 2

List.map double [1, 2, 3]  -- [2, 4, 6]
```

## Currying

Every function in Canopy takes exactly one argument. Multi-parameter functions are actually chains of single-parameter functions:

```canopy
-- These are equivalent
add : Int -> Int -> Int
add x y = x + y

add : Int -> (Int -> Int)
add x = \y -> x + y
```

This enables **partial application**:

```canopy
-- Partially apply to create new functions
add5 : Int -> Int
add5 = add 5

add5 10  -- 15

-- Common patterns
increment : Int -> Int
increment = add 1

isPositive : Int -> Bool
isPositive = (<) 0
```

## Function Application

### Normal Application

```canopy
-- Left to right
result = function argument

-- Multiple arguments
result = function arg1 arg2 arg3
```

### Pipe Operators

The pipe operator `|>` passes a value as the last argument:

```canopy
-- Without pipes (nested calls)
String.toUpper (String.trim (String.reverse "  hello  "))

-- With pipes (linear flow)
"  hello  "
    |> String.reverse
    |> String.trim
    |> String.toUpper
-- "OLLEH"
```

The backward pipe `<|` applies a function to what follows:

```canopy
-- Avoids parentheses at the end
String.toUpper <| String.trim "  hello  "

-- Useful for readability
viewUser <| getUser model.userId
```

## Function Composition

### The Composition Operator

The `>>` operator composes functions left to right:

```canopy
-- Compose functions
sanitize : String -> String
sanitize =
    String.trim >> String.toLower >> String.replace " " "-"

sanitize "  Hello World  "  -- "hello-world"
```

The `<<` operator composes right to left:

```canopy
-- Right to left composition
sanitize : String -> String
sanitize =
    String.replace " " "-" << String.toLower << String.trim
```

### When to Use Each

```canopy
-- Use >> when thinking "then"
-- "trim, then lowercase, then replace"
process = String.trim >> String.toLower >> String.replace " " "-"

-- Use << when thinking "of"
-- "replace of lowercase of trim"
process = String.replace " " "-" << String.toLower << String.trim

-- Use |> when you have a value to start with
"  Hello World  "
    |> String.trim
    |> String.toLower

-- Use >> when creating a new function
processAll : List String -> List String
processAll = List.map (String.trim >> String.toLower)
```

## Pattern Matching in Functions

### Direct Pattern Matching

```canopy
-- Pattern match on parameters directly
not : Bool -> Bool
not bool =
    case bool of
        True -> False
        False -> True

-- Multiple patterns
describe : Maybe Int -> String
describe maybe =
    case maybe of
        Just n -> "Got " ++ String.fromInt n
        Nothing -> "Nothing here"
```

### With Custom Types

```canopy
type Shape
    = Circle Float
    | Rectangle Float Float

area : Shape -> Float
area shape =
    case shape of
        Circle radius ->
            pi * radius * radius

        Rectangle width height ->
            width * height
```

## Higher-Order Functions

Functions that take or return functions:

### Taking Functions

```canopy
-- map applies a function to each element
map : (a -> b) -> List a -> List b

List.map String.toUpper ["a", "b", "c"]  -- ["A", "B", "C"]

-- filter keeps elements that satisfy a predicate
filter : (a -> Bool) -> List a -> List a

List.filter (\n -> n > 0) [-1, 0, 1, 2]  -- [1, 2]

-- foldl reduces a list to a single value
foldl : (a -> b -> b) -> b -> List a -> b

List.foldl (+) 0 [1, 2, 3, 4]  -- 10
```

### Returning Functions

```canopy
-- Create a multiplier function
multiplier : Int -> (Int -> Int)
multiplier factor =
    \n -> n * factor

double : Int -> Int
double = multiplier 2

triple : Int -> Int
triple = multiplier 3

double 5   -- 10
triple 5   -- 15
```

### Creating Your Own

```canopy
-- Apply a function twice
twice : (a -> a) -> a -> a
twice f x =
    f (f x)

twice ((+) 1) 5        -- 7
twice String.reverse "ab"  -- "ab"

-- Compose n functions
composeN : Int -> (a -> a) -> (a -> a)
composeN n f =
    if n <= 0 then
        identity
    else
        f >> composeN (n - 1) f

addTen : Int -> Int
addTen = composeN 10 ((+) 1)
```

## Point-Free Style

Point-free style omits explicit parameters:

```canopy
-- With explicit parameter (pointed)
doubleAll : List Int -> List Int
doubleAll list =
    List.map (\x -> x * 2) list

-- Point-free
doubleAll : List Int -> List Int
doubleAll =
    List.map ((*) 2)

-- Another example
-- Pointed
sumPositives : List Int -> Int
sumPositives list =
    List.filter (\x -> x > 0) list
        |> List.sum

-- Point-free
sumPositives : List Int -> Int
sumPositives =
    List.filter ((<) 0) >> List.sum
```

Use point-free style when it improves clarity, but prefer explicit parameters when it's clearer.

## Let Expressions

Define local bindings with `let`:

```canopy
circleArea : Float -> Float
circleArea radius =
    let
        diameter = radius * 2
        pi = 3.14159
    in
    pi * radius * radius


-- Multiple bindings
fullName : User -> String
fullName user =
    let
        first = user.firstName
        last = user.lastName
        middle = Maybe.withDefault "" user.middleName
    in
    first ++ " " ++ middle ++ " " ++ last
```

## Where Clauses (Preferred)

Define helper functions with `where`:

```canopy
-- Using where (preferred)
processData : List Int -> Int
processData numbers =
    numbers
        |> List.filter isValid
        |> List.map transform
        |> List.sum
  where
    isValid n = n > 0 && n < 100
    transform n = n * 2


-- Complex example
buildUrl : Config -> String -> String
buildUrl config path =
    protocol ++ "://" ++ host ++ "/" ++ path
  where
    protocol = if config.useHttps then "https" else "http"
    host = config.domain
```

**Note**: Prefer `where` over `let` in most cases for clarity.

## Recursive Functions

```canopy
-- Simple recursion
factorial : Int -> Int
factorial n =
    if n <= 1 then
        1
    else
        n * factorial (n - 1)

-- Tail recursion (optimized)
factorial : Int -> Int
factorial n =
    factorialHelp n 1
  where
    factorialHelp n acc =
        if n <= 1 then
            acc
        else
            factorialHelp (n - 1) (n * acc)

-- List recursion
length : List a -> Int
length list =
    case list of
        [] ->
            0

        _ :: rest ->
            1 + length rest
```

## Common Function Patterns

### Function Transformers

```canopy
-- Flip argument order
flip : (a -> b -> c) -> b -> a -> c
flip f b a =
    f a b

-- Usage
subtract : Int -> Int -> Int
subtract a b = a - b

subtractFrom10 : Int -> Int
subtractFrom10 = flip subtract 10

subtractFrom10 3  -- 7
```

### Conditional Application

```canopy
-- Apply function only if condition is true
applyIf : Bool -> (a -> a) -> a -> a
applyIf condition f x =
    if condition then
        f x
    else
        x

-- Usage
maybeUppercase : Bool -> String -> String
maybeUppercase shouldUpper =
    applyIf shouldUpper String.toUpper
```

### Combining Results

```canopy
-- Combine two Maybe values
map2 : (a -> b -> c) -> Maybe a -> Maybe b -> Maybe c
map2 f maybeA maybeB =
    case ( maybeA, maybeB ) of
        ( Just a, Just b ) ->
            Just (f a b)

        _ ->
            Nothing

-- Usage
fullName : Maybe String -> Maybe String -> Maybe String
fullName = map2 (\first last -> first ++ " " ++ last)
```

## Best Practices

1. **Keep functions small**: Each function should do one thing
2. **Use meaningful names**: `filterActiveUsers` not `filter1`
3. **Prefer composition over nesting**: Use `|>` and `>>`
4. **Add type annotations**: Documents intent and catches errors
5. **Use `where` for helpers**: Keeps main logic clear
6. **Consider partial application**: Create specialized functions

## Next Steps

- **[Modules](./modules.md)**: Organize functions into modules
- **[Pattern Matching](./pattern-matching.md)**: Advanced pattern matching
- **[Testing](./testing.md)**: Test your functions
