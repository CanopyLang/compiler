# Core Modules

The core modules provide fundamental types and functions for every Canopy application.

## Basics

Core functions and types available without import.

### Operators

```canopy
-- Arithmetic
(+) : number -> number -> number
(-) : number -> number -> number
(*) : number -> number -> number
(/) : Float -> Float -> Float
(//) : Int -> Int -> Int      -- Integer division
(^) : number -> number -> number

-- Comparison
(==) : a -> a -> Bool
(/=) : a -> a -> Bool
(<) : comparable -> comparable -> Bool
(>) : comparable -> comparable -> Bool
(<=) : comparable -> comparable -> Bool
(>=) : comparable -> comparable -> Bool

-- Boolean
(&&) : Bool -> Bool -> Bool
(||) : Bool -> Bool -> Bool
not : Bool -> Bool

-- Function
(|>) : a -> (a -> b) -> b    -- Pipe
(<|) : (a -> b) -> a -> b    -- Backward pipe
(>>) : (a -> b) -> (b -> c) -> (a -> c)  -- Compose
(<<) : (b -> c) -> (a -> b) -> (a -> c)  -- Backward compose
```

### Core Functions

```canopy
identity : a -> a
-- Returns its argument unchanged

always : a -> b -> a
-- Returns first argument, ignoring second

flip : (a -> b -> c) -> (b -> a -> c)
-- Swaps argument order
```

### Math

```canopy
-- Constants
pi : Float
e : Float

-- Operations
modBy : Int -> Int -> Int
remainderBy : Int -> Int -> Int
abs : number -> number
negate : number -> number
sqrt : Float -> Float
logBase : Float -> Float -> Float
clamp : number -> number -> number -> number

-- Rounding
round : Float -> Int
floor : Float -> Int
ceiling : Float -> Int
truncate : Float -> Int

-- Trigonometry
sin : Float -> Float
cos : Float -> Float
tan : Float -> Float
asin : Float -> Float
acos : Float -> Float
atan : Float -> Float
atan2 : Float -> Float -> Float

-- Conversion
toFloat : Int -> Float
```

### Infinity and NaN

```canopy
isNaN : Float -> Bool
isInfinite : Float -> Bool
```

---

## Maybe

Represents values that may or may not exist.

```canopy
type Maybe a
    = Just a
    | Nothing
```

### Functions

```canopy
-- Transform
map : (a -> b) -> Maybe a -> Maybe b
map2 : (a -> b -> c) -> Maybe a -> Maybe b -> Maybe c
map3 : (a -> b -> c -> d) -> Maybe a -> Maybe b -> Maybe c -> Maybe d
map4 : ...
map5 : ...

-- Default value
withDefault : a -> Maybe a -> a

-- Chaining
andThen : (a -> Maybe b) -> Maybe a -> Maybe b

-- Conversion
toList : Maybe a -> List a
```

### Examples

```canopy
Maybe.map ((+) 1) (Just 5)     -- Just 6
Maybe.map ((+) 1) Nothing       -- Nothing

Maybe.withDefault 0 (Just 5)   -- 5
Maybe.withDefault 0 Nothing    -- 0

Maybe.andThen String.toInt (Just "42")  -- Just 42
```

---

## Result

Represents success or failure with error information.

```canopy
type Result error value
    = Ok value
    | Err error
```

### Functions

```canopy
-- Transform
map : (a -> b) -> Result x a -> Result x b
mapError : (x -> y) -> Result x a -> Result y a
map2 : (a -> b -> c) -> Result x a -> Result x b -> Result x c

-- Default value
withDefault : a -> Result x a -> a

-- Chaining
andThen : (a -> Result x b) -> Result x a -> Result x b

-- Conversion
toMaybe : Result x a -> Maybe a
fromMaybe : x -> Maybe a -> Result x a
```

---

## String

Operations on strings.

```canopy
-- Create
fromInt : Int -> String
fromFloat : Float -> String
fromChar : Char -> String

-- Combine
append : String -> String -> String
concat : List String -> String
join : String -> List String -> String

-- Query
isEmpty : String -> Bool
length : String -> Int
contains : String -> String -> Bool
startsWith : String -> String -> Bool
endsWith : String -> String -> Bool

-- Transform
reverse : String -> String
repeat : Int -> String -> String
replace : String -> String -> String -> String
toUpper : String -> String
toLower : String -> String
trim : String -> String
trimLeft : String -> String
trimRight : String -> String

-- Split
split : String -> String -> List String
words : String -> List String
lines : String -> List String

-- Substrings
slice : Int -> Int -> String -> String
left : Int -> String -> String
right : Int -> String -> String
dropLeft : Int -> String -> String
dropRight : Int -> String -> String

-- Characters
cons : Char -> String -> String
uncons : String -> Maybe ( Char, String )
toList : String -> List Char
fromList : List Char -> String

-- Conversion
toInt : String -> Maybe Int
toFloat : String -> Maybe Float

-- Padding
pad : Int -> Char -> String -> String
padLeft : Int -> Char -> String -> String
padRight : Int -> Char -> String -> String
```

---

## Char

Operations on characters.

```canopy
-- Classification
isUpper : Char -> Bool
isLower : Char -> Bool
isAlpha : Char -> Bool
isAlphaNum : Char -> Bool
isDigit : Char -> Bool
isOctDigit : Char -> Bool
isHexDigit : Char -> Bool

-- Conversion
toUpper : Char -> Char
toLower : Char -> Char
toCode : Char -> Int
fromCode : Int -> Char
```

---

## List

Operations on lists.

```canopy
-- Create
singleton : a -> List a
repeat : Int -> a -> List a
range : Int -> Int -> List Int
cons : a -> List a -> List a  -- (::)

-- Query
isEmpty : List a -> Bool
length : List a -> Int
member : a -> List a -> Bool
head : List a -> Maybe a
tail : List a -> Maybe (List a)
last : List a -> Maybe a

-- Transform
map : (a -> b) -> List a -> List b
indexedMap : (Int -> a -> b) -> List a -> List b
reverse : List a -> List a
sort : List comparable -> List comparable
sortBy : (a -> comparable) -> List a -> List a
sortWith : (a -> a -> Order) -> List a -> List a

-- Filter
filter : (a -> Bool) -> List a -> List a
filterMap : (a -> Maybe b) -> List a -> List b
partition : (a -> Bool) -> List a -> ( List a, List a )

-- Combine
append : List a -> List a -> List a
concat : List (List a) -> List a
concatMap : (a -> List b) -> List a -> List b
intersperse : a -> List a -> List a

-- Reduce
foldl : (a -> b -> b) -> b -> List a -> b
foldr : (a -> b -> b) -> b -> List a -> b
sum : List number -> number
product : List number -> number
maximum : List comparable -> Maybe comparable
minimum : List comparable -> Maybe comparable
all : (a -> Bool) -> List a -> Bool
any : (a -> Bool) -> List a -> Bool

-- Sublists
take : Int -> List a -> List a
drop : Int -> List a -> List a
splitAt : Int -> List a -> ( List a, List a )

-- Zip
map2 : (a -> b -> c) -> List a -> List b -> List c
map3 : ...
map4 : ...
map5 : ...

-- Unique
uniq : List comparable -> List comparable
```

---

## Dict

Key-value dictionaries.

```canopy
-- Create
empty : Dict k v
singleton : comparable -> v -> Dict comparable v
fromList : List ( comparable, v ) -> Dict comparable v

-- Query
isEmpty : Dict k v -> Bool
size : Dict k v -> Int
member : comparable -> Dict comparable v -> Bool
get : comparable -> Dict comparable v -> Maybe v

-- Modify
insert : comparable -> v -> Dict comparable v -> Dict comparable v
update : comparable -> (Maybe v -> Maybe v) -> Dict comparable v -> Dict comparable v
remove : comparable -> Dict comparable v -> Dict comparable v

-- Transform
map : (k -> a -> b) -> Dict k a -> Dict k b
filter : (comparable -> v -> Bool) -> Dict comparable v -> Dict comparable v
partition : (comparable -> v -> Bool) -> Dict comparable v -> ( Dict comparable v, Dict comparable v )

-- Combine
union : Dict comparable v -> Dict comparable v -> Dict comparable v
intersect : Dict comparable v -> Dict comparable v -> Dict comparable v
diff : Dict comparable a -> Dict comparable b -> Dict comparable a

-- Lists
keys : Dict k v -> List k
values : Dict k v -> List v
toList : Dict k v -> List ( k, v )

-- Fold
foldl : (k -> v -> b -> b) -> b -> Dict k v -> b
foldr : (k -> v -> b -> b) -> b -> Dict k v -> b
```

---

## Set

Sets of unique values.

```canopy
-- Create
empty : Set comparable
singleton : comparable -> Set comparable
fromList : List comparable -> Set comparable

-- Query
isEmpty : Set a -> Bool
size : Set a -> Int
member : comparable -> Set comparable -> Bool

-- Modify
insert : comparable -> Set comparable -> Set comparable
remove : comparable -> Set comparable -> Set comparable

-- Combine
union : Set comparable -> Set comparable -> Set comparable
intersect : Set comparable -> Set comparable -> Set comparable
diff : Set comparable -> Set comparable -> Set comparable

-- Transform
map : (comparable -> comparable2) -> Set comparable -> Set comparable2
filter : (comparable -> Bool) -> Set comparable -> Set comparable
partition : (comparable -> Bool) -> Set comparable -> ( Set comparable, Set comparable )

-- Fold
foldl : (a -> b -> b) -> b -> Set a -> b
foldr : (a -> b -> b) -> b -> Set a -> b

-- Convert
toList : Set a -> List a
```

---

## Tuple

Operations on tuples.

```canopy
-- Pairs
first : ( a, b ) -> a
second : ( a, b ) -> b
mapFirst : (a -> x) -> ( a, b ) -> ( x, b )
mapSecond : (b -> y) -> ( a, b ) -> ( a, y )
mapBoth : (a -> x) -> (b -> y) -> ( a, b ) -> ( x, y )
pair : a -> b -> ( a, b )
```

---

## Debug

Debugging utilities (remove before production).

```canopy
log : String -> a -> a
-- Logs a value and returns it

toString : a -> String
-- Convert any value to a string

todo : String -> a
-- Crash with a message (for incomplete implementations)
```

**Note**: Remove all `Debug` calls before production builds.
