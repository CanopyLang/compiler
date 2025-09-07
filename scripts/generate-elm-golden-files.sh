#!/bin/bash

# Generate Elm Golden Files for Compatibility Testing
# This script pre-compiles all test cases using Elm to create golden output files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GOLDEN_DIR="$PROJECT_ROOT/test/Golden/expected/elm-canopy"
TEMP_DIR="$(mktemp -d)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if elm is available
if ! command -v elm &> /dev/null; then
    log_error "elm command not found. Please install Elm first."
    exit 1
fi

# Create golden files directory
mkdir -p "$GOLDEN_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

log_info "Starting Elm golden file generation..."
log_info "Temporary directory: $TEMP_DIR"
log_info "Golden files directory: $GOLDEN_DIR"

# Test case definitions with their Elm source code
declare -A test_cases=(
    ["basic-arithmetic"]='
module Main exposing (main, add, mul, compose)

import Html exposing (text)

add : Int -> Int -> Int
add x y = x + y

mul : Int -> Int -> Int
mul x y = x * y

compose : (b -> c) -> (a -> b) -> a -> c
compose f g x = f (g x)

main = text (String.fromInt (compose (add 1) (mul 2) 3))
'

    ["function-composition"]='
module Main exposing (main, compose, pipe)

import Html exposing (text)

compose : (b -> c) -> (a -> b) -> (a -> c)
compose f g x = f (g x)

pipe : a -> (a -> b) -> (b -> c) -> c  
pipe x f g = g (f x)

addOne : Int -> Int
addOne x = x + 1

timeTwo : Int -> Int
timeTwo x = x * 2

main = text (String.fromInt (compose addOne timeTwo 5))
'

    ["lambda-expressions"]='
module Main exposing (main)

import Html exposing (text)

main = text (String.fromInt ((\x -> x + 10) 5))
'

    ["let-binding"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let 
        x = 10
        y = 20
        result = x + y
    in 
    text (String.fromInt result)
'

    ["if-expression"]='
module Main exposing (main, absolute)

import Html exposing (text)

absolute : Int -> Int
absolute n = if n < 0 then -n else n

main = text (String.fromInt (absolute -42))
'

    ["pipeline"]='
module Main exposing (main)

import Html exposing (text)

main = 
    5
        |> (\x -> x * 2)
        |> (\x -> x + 1)
        |> String.fromInt
        |> text
'

    ["partial-application"]='
module Main exposing (main, add, add5)

import Html exposing (text)

add : Int -> Int -> Int
add x y = x + y

add5 : Int -> Int
add5 = add 5

main = text (String.fromInt (add5 10))
'

    ["operator-precedence"]='
module Main exposing (main)

import Html exposing (text)

main = text (String.fromInt (2 + 3 * 4 - 1))
'

    ["string-operations"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        greeting = "Hello"
        name = "World" 
        message = greeting ++ ", " ++ name ++ "!"
    in
    text message
'

    ["boolean-operations"]='
module Main exposing (main, checkConditions)

import Html exposing (text)

checkConditions : Bool -> Bool -> String
checkConditions a b = 
    if a && b then "Both true"
    else if a || b then "One true"
    else "Both false"

main = text (checkConditions True False)
'

    ["numeric-operations"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        a = 10
        b = 3
        result = String.fromFloat (toFloat a / toFloat b)
    in
    text result
'

    ["nested-function-calls"]='
module Main exposing (main, f, g, h)

import Html exposing (text)

f : Int -> Int
f x = x + 1

g : Int -> Int  
g x = x * 2

h : Int -> Int
h x = x - 3

main = text (String.fromInt (f (g (h 10))))
'

    ["simple-record"]='
module Main exposing (main, Person)

import Html exposing (text)

type alias Person = 
    { name : String
    , age : Int
    }

main = 
    let
        person = { name = "Alice", age = 30 }
    in
    text (person.name ++ " is " ++ String.fromInt person.age)
'

    ["record-update"]='
module Main exposing (main, Person)

import Html exposing (text)

type alias Person = 
    { name : String
    , age : Int
    }

main = 
    let
        person = { name = "Alice", age = 30 }
        older = { person | age = person.age + 1 }
    in
    text (older.name ++ " is " ++ String.fromInt older.age)
'

    ["nested-record"]='
module Main exposing (main, Person, Address)

import Html exposing (text)

type alias Address = 
    { street : String
    , city : String
    }

type alias Person = 
    { name : String
    , address : Address
    }

main = 
    let
        person = 
            { name = "Alice"
            , address = { street = "123 Main St", city = "Anytown" }
            }
    in
    text (person.name ++ " lives in " ++ person.address.city)
'

    ["record-accessor"]='
module Main exposing (main, getName, getAge)

import Html exposing (text)

type alias Person = 
    { name : String
    , age : Int
    }

getName : Person -> String
getName person = person.name

getAge : Person -> Int  
getAge person = person.age

main = 
    let
        person = { name = "Bob", age = 25 }
    in
    text (getName person ++ " " ++ String.fromInt (getAge person))
'

    ["list-operations"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        numbers = [ 1, 2, 3, 4, 5 ]
        filtered = List.filter (\x -> x > 2) numbers
        sum = List.foldl (+) 0
        result = sum filtered
    in
    text (String.fromInt result)
'

    ["nested-tuple"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        nested = ( ( 1, 2 ), "hello" )
        innerTuple = Tuple.first nested
        firstNum = Tuple.first innerTuple
        secondNum = Tuple.second innerTuple
        result = firstNum + secondNum
    in
    text (String.fromInt result)
'

    ["custom-type"]='
module Main exposing (main, Status(..))

import Html exposing (text)

type Status
    = Loading
    | Success String
    | Error String

main = 
    let
        status = Success "Data loaded"
        message = 
            case status of
                Loading -> "Loading..."
                Success data -> data
                Error msg -> "Error: " ++ msg
    in
    text message
'

    ["type-alias"]='
module Main exposing (main, User, UserID)

import Html exposing (text)

type alias UserID = Int

type alias User = 
    { id : UserID
    , name : String
    , email : String
    }

main = 
    let
        user = { id = 42, name = "Alice", email = "alice@example.com" }
        greeting = "Hello, " ++ user.name
    in
    text greeting
'

    ["nested-case"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        numbers = [ 1, 2 ]
        result = 
            case numbers of
                [] -> "empty"
                head :: tail -> 
                    case tail of
                        [] -> "one item"
                        _ -> "multiple items"
    in
    text result
'

    ["wildcard-pattern"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        numbers = [ 1, 2, 3 ]
        result = 
            case numbers of
                [] -> "empty"
                first :: _ -> String.fromInt first
    in
    text result
'

    ["tuple-pattern"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        pair = ( 42, "hello" )
        result = 
            case pair of
                ( num, str ) -> str ++ " " ++ String.fromInt num
    in
    text result
'

    ["string-module"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        text1 = "Hello, World!"
        upper = String.toUpper text1
        length = String.length text1
        slice = String.slice 0 5 text1
        result = slice ++ " (length: " ++ String.fromInt length ++ ")"
    in
    text result
'

    ["maybe-module"]='
module Main exposing (main)

import Html exposing (text)

main = 
    let
        maybeValue = Just 42
        result = 
            case maybeValue of
                Nothing -> "No value"
                Just value -> "Value: " ++ String.fromInt value
        withDefault = Maybe.withDefault 0 maybeValue
    in
    text result
'
)

# Function to compile a single test case
compile_test_case() {
    local test_name="$1"
    local elm_source="$2"
    local project_dir="$TEMP_DIR/$test_name"
    
    log_info "Compiling $test_name..."
    
    # Create project structure
    mkdir -p "$project_dir/src"
    
    # Create elm.json
    cat > "$project_dir/elm.json" << 'EOF'
{
    "type": "application",
    "source-directories": [
        "src"
    ],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": {
            "elm/browser": "1.0.2",
            "elm/core": "1.0.5",
            "elm/html": "1.0.0"
        },
        "indirect": {
            "elm/json": "1.1.3",
            "elm/time": "1.0.0",
            "elm/url": "1.0.0",
            "elm/virtual-dom": "1.0.3"
        }
    },
    "test-dependencies": {
        "direct": {},
        "indirect": {}
    }
}
EOF

    # Write the Elm source  
    echo "$elm_source" > "$project_dir/src/Main.elm"
    
    # Compile with Elm
    local output_file="$GOLDEN_DIR/${test_name}.js"
    
    if (cd "$project_dir" && elm make src/Main.elm --output="$output_file" --optimize); then
        log_success "Compiled $test_name -> ${test_name}.js"
    else
        log_error "Failed to compile $test_name"
        return 1
    fi
}

# Compile all test cases
failed_tests=()
successful_tests=()

for test_name in "${!test_cases[@]}"; do
    if compile_test_case "$test_name" "${test_cases[$test_name]}"; then
        successful_tests+=("$test_name")
    else
        failed_tests+=("$test_name")
    fi
done

# Summary
log_info "Golden file generation complete!"
log_success "Successfully compiled ${#successful_tests[@]} test cases"

if [ ${#failed_tests[@]} -gt 0 ]; then
    log_error "Failed to compile ${#failed_tests[@]} test cases:"
    for test in "${failed_tests[@]}"; do
        echo "  - $test"
    done
    exit 1
fi

log_success "All Elm golden files generated successfully in $GOLDEN_DIR"