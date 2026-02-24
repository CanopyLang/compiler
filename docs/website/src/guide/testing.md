# Testing

Canopy provides a comprehensive testing framework for unit tests, fuzz tests, and integration tests.

## Getting Started

### Install Test Dependencies

```bash
canopy install canopy/test
```

### Create a Test File

```canopy
-- tests/Tests.can
module Tests exposing (suite)

import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "My Application"
        [ describe "Math operations"
            [ test "addition works" <|
                \_ ->
                    Expect.equal (2 + 2) 4

            , test "subtraction works" <|
                \_ ->
                    Expect.equal (5 - 3) 2
            ]
        ]
```

### Run Tests

```bash
canopy test
```

## Test Structure

### Basic Test

```canopy
import Expect
import Test exposing (Test, test)


myTest : Test
myTest =
    test "description of what is being tested" <|
        \_ ->
            Expect.equal actual expected
```

### Grouping Tests

```canopy
import Test exposing (Test, describe, test)


userTests : Test
userTests =
    describe "User module"
        [ describe "creation"
            [ test "creates user with valid data" <|
                \_ ->
                    User.create "Alice" "alice@example.com"
                        |> Expect.ok

            , test "fails with empty name" <|
                \_ ->
                    User.create "" "alice@example.com"
                        |> Expect.err
            ]
        , describe "validation"
            [ test "accepts valid email" <|
                \_ ->
                    User.validateEmail "user@example.com"
                        |> Expect.equal True
            ]
        ]
```

## Expectations

### Equality

```canopy
-- Exact equality
Expect.equal 4 (2 + 2)

-- Not equal
Expect.notEqual 5 (2 + 2)
```

### Comparisons

```canopy
-- Greater than
Expect.greaterThan 5 10

-- Less than
Expect.lessThan 10 5

-- At least (>=)
Expect.atLeast 5 5

-- At most (<=)
Expect.atMost 10 5
```

### Boolean Expectations

```canopy
-- True
Expect.true "should be positive" (x > 0)

-- False
Expect.false "should not be empty" (List.isEmpty list)
```

### Maybe and Result

```canopy
-- Maybe expectations
Expect.ok (Just 42)
Expect.err Nothing

-- Result expectations
Expect.ok (Ok 42)
Expect.err (Err "failed")
```

### Collections

```canopy
-- List equality (order matters)
Expect.equal [1, 2, 3] (List.sort [3, 1, 2])

-- List contains
Expect.equalLists [1, 2, 3] [1, 2, 3]

-- Custom element comparison
Expect.all
    [ \list -> Expect.equal 3 (List.length list)
    , \list -> Expect.true "contains 1" (List.member 1 list)
    ]
    [1, 2, 3]
```

### Floating Point

```canopy
-- Approximate equality for floats
Expect.within (Expect.Absolute 0.001) 3.14159 pi
Expect.within (Expect.Relative 0.01) 100.0 99.5
```

### All / Any

```canopy
-- All expectations must pass
Expect.all
    [ \n -> Expect.greaterThan 0 n
    , \n -> Expect.lessThan 100 n
    , \n -> Expect.notEqual 50 n
    ]
    42

-- Pass/fail explicitly
Expect.pass
Expect.fail "This should not happen"
```

## Fuzz Testing

Fuzz tests (property-based tests) generate random inputs to find edge cases:

### Basic Fuzz Test

```canopy
import Fuzz exposing (Fuzzer, int, string, list)
import Test exposing (Test, fuzz, fuzz2)


fuzzTests : Test
fuzzTests =
    describe "Fuzz tests"
        [ fuzz int "reversing twice returns original" <|
            \n ->
                negate (negate n)
                    |> Expect.equal n

        , fuzz string "String.reverse is its own inverse" <|
            \str ->
                String.reverse (String.reverse str)
                    |> Expect.equal str
        ]
```

### Multiple Fuzzers

```canopy
fuzz2Tests : Test
fuzz2Tests =
    fuzz2 int int "addition is commutative" <|
        \a b ->
            (a + b)
                |> Expect.equal (b + a)


fuzz3Tests : Test
fuzz3Tests =
    fuzz3 int int int "addition is associative" <|
        \a b c ->
            ((a + b) + c)
                |> Expect.equal (a + (b + c))
```

### Built-in Fuzzers

```canopy
import Fuzz


-- Primitives
Fuzz.int           -- Int
Fuzz.float         -- Float
Fuzz.string        -- String
Fuzz.bool          -- Bool
Fuzz.char          -- Char
Fuzz.unit          -- ()

-- Collections
Fuzz.list Fuzz.int           -- List Int
Fuzz.array Fuzz.string       -- Array String
Fuzz.maybe Fuzz.int          -- Maybe Int
Fuzz.result Fuzz.string Fuzz.int  -- Result String Int

-- Bounded
Fuzz.intRange 1 100          -- Int between 1 and 100
Fuzz.floatRange 0.0 1.0      -- Float between 0 and 1

-- Choice
Fuzz.oneOf [ Fuzz.constant "a", Fuzz.constant "b" ]
```

### Custom Fuzzers

```canopy
-- For records
type alias User =
    { name : String
    , age : Int
    , email : String
    }


userFuzzer : Fuzzer User
userFuzzer =
    Fuzz.map3 User
        Fuzz.string
        (Fuzz.intRange 0 120)
        emailFuzzer


emailFuzzer : Fuzzer String
emailFuzzer =
    Fuzz.map2
        (\name domain -> name ++ "@" ++ domain ++ ".com")
        (Fuzz.stringOfLengthBetween 1 20)
        (Fuzz.stringOfLengthBetween 3 10)


-- For custom types
type Status
    = Active
    | Inactive
    | Pending


statusFuzzer : Fuzzer Status
statusFuzzer =
    Fuzz.oneOf
        [ Fuzz.constant Active
        , Fuzz.constant Inactive
        , Fuzz.constant Pending
        ]
```

## Testing Update Functions

### Basic Update Test

```canopy
updateTests : Test
updateTests =
    describe "update"
        [ test "Increment increases count" <|
            \_ ->
                let
                    initialModel = { count = 0 }
                    ( newModel, _ ) = update Increment initialModel
                in
                Expect.equal 1 newModel.count

        , test "Decrement decreases count" <|
            \_ ->
                let
                    initialModel = { count = 5 }
                    ( newModel, _ ) = update Decrement initialModel
                in
                Expect.equal 4 newModel.count
        ]
```

### Testing with Commands

```canopy
test "FetchUser sends HTTP request" <|
    \_ ->
        let
            ( _, cmd ) = update FetchUser initialModel
        in
        -- Commands are opaque, but you can verify they exist
        Expect.notEqual Cmd.none cmd
```

## Testing Views

### Basic View Test

```canopy
import Html
import Test.Html.Query as Query
import Test.Html.Selector exposing (text, tag, class)


viewTests : Test
viewTests =
    describe "view"
        [ test "displays user name" <|
            \_ ->
                view { name = "Alice" }
                    |> Query.fromHtml
                    |> Query.find [ class "user-name" ]
                    |> Query.has [ text "Alice" ]

        , test "shows loading spinner when loading" <|
            \_ ->
                view { loading = True }
                    |> Query.fromHtml
                    |> Query.has [ class "spinner" ]
        ]
```

### Query API

```canopy
import Test.Html.Query as Query
import Test.Html.Selector as Selector


-- Find a single element
Query.find [ Selector.class "button" ]

-- Find all matching elements
Query.findAll [ Selector.tag "li" ]

-- Check element exists
Query.has [ Selector.text "Hello" ]

-- Check element count
Query.count (Expect.equal 3)

-- Check element structure
Query.children []
    |> Query.count (Expect.atLeast 1)
```

### Event Testing

```canopy
import Test.Html.Event as Event


eventTests : Test
eventTests =
    describe "events"
        [ test "clicking button sends Increment" <|
            \_ ->
                view { count = 0 }
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button" ]
                    |> Event.simulate Event.click
                    |> Event.expect Increment
        ]
```

## Testing JSON

### Decoder Tests

```canopy
decoderTests : Test
decoderTests =
    describe "JSON decoders"
        [ test "decodes valid user JSON" <|
            \_ ->
                """{"name": "Alice", "age": 30}"""
                    |> Decode.decodeString userDecoder
                    |> Expect.equal (Ok { name = "Alice", age = 30 })

        , test "fails on invalid JSON" <|
            \_ ->
                """{"name": "Alice"}"""  -- missing age
                    |> Decode.decodeString userDecoder
                    |> Expect.err

        , fuzz userFuzzer "roundtrip encoding/decoding" <|
            \user ->
                user
                    |> encodeUser
                    |> Encode.encode 0
                    |> Decode.decodeString userDecoder
                    |> Expect.equal (Ok user)
        ]
```

## Testing Async Code

### Testing Tasks

```canopy
-- Tasks are tested by examining their results
taskTests : Test
taskTests =
    describe "async operations"
        [ test "successful task returns value" <|
            \_ ->
                Task.succeed 42
                    |> Task.map (\n -> n * 2)
                    -- You'd use a test runner that handles tasks
                    |> expectTaskSuccess (Expect.equal 84)
        ]
```

### Mocking HTTP

```canopy
-- Create mock responses for testing
mockUserResponse : String
mockUserResponse =
    """{"id": 1, "name": "Alice", "email": "alice@example.com"}"""


test "parses user response" <|
    \_ ->
        mockUserResponse
            |> Decode.decodeString userDecoder
            |> Expect.ok
```

## Test Organization

### Recommended Structure

```
tests/
├── Main.can              # Test runner
├── Unit/
│   ├── UserTest.can      # Unit tests for User module
│   ├── PostTest.can      # Unit tests for Post module
│   └── ValidationTest.can
├── Integration/
│   ├── ApiTest.can       # API integration tests
│   └── AuthTest.can
└── Fuzz/
    ├── UserFuzz.can      # Fuzz tests
    └── JsonFuzz.can
```

### Main Test File

```canopy
-- tests/Main.can
module Main exposing (main)

import Test exposing (Test, describe)
import Test.Runner.Html

import Unit.UserTest
import Unit.PostTest
import Integration.ApiTest
import Fuzz.UserFuzz


main : Program () Test
main =
    Test.Runner.Html.run suite


suite : Test
suite =
    describe "All Tests"
        [ Unit.UserTest.suite
        , Unit.PostTest.suite
        , Integration.ApiTest.suite
        , Fuzz.UserFuzz.suite
        ]
```

## Best Practices

### 1. Test Behavior, Not Implementation

```canopy
-- Good: Tests observable behavior
test "user can be created with valid data" <|
    \_ ->
        User.create "Alice" "alice@example.com"
            |> Result.map .name
            |> Expect.equal (Ok "Alice")


-- Avoid: Tests internal implementation
test "User record has correct fields" <|
    \_ ->
        -- Don't test internal structure
```

### 2. Use Descriptive Test Names

```canopy
-- Good: Describes the expected behavior
test "returns Nothing when user is not found" <|
    \_ -> ...

test "validates email contains @ symbol" <|
    \_ -> ...


-- Avoid: Vague descriptions
test "works correctly" <|
    \_ -> ...

test "handles edge case" <|
    \_ -> ...
```

### 3. One Assertion Per Test (Generally)

```canopy
-- Good: Focused tests
test "increment increases count by 1" <|
    \_ ->
        update Increment { count = 0 }
            |> Tuple.first
            |> .count
            |> Expect.equal 1


-- Okay for related assertions
test "user is created correctly" <|
    \_ ->
        let
            user = User.create "Alice" "alice@example.com"
        in
        Expect.all
            [ \u -> Expect.equal "Alice" u.name
            , \u -> Expect.equal "alice@example.com" u.email
            ]
            user
```

### 4. Use Fuzz Tests for Properties

```canopy
-- Good: Test invariants with fuzzing
fuzz (list int) "reversing twice yields original" <|
    \xs ->
        List.reverse (List.reverse xs)
            |> Expect.equal xs


fuzz2 int int "addition is commutative" <|
    \a b ->
        (a + b) |> Expect.equal (b + a)
```

### 5. Keep Tests Independent

```canopy
-- Each test should be self-contained
test "processes order correctly" <|
    \_ ->
        let
            order = createTestOrder ()  -- Create fresh data
        in
        processOrder order
            |> Expect.ok
```

## Running Tests

### Command Line

```bash
# Run all tests
canopy test

# Run specific test file
canopy test tests/Unit/UserTest.can

# Watch mode
canopy test --watch

# With coverage
canopy test --coverage
```

### CI/CD Integration

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: canopy-lang/setup-canopy@v1
      - run: canopy test
```

## Next Steps

- **[Error Handling](./error-handling.md)**: Test error cases
- **[JSON](./json.md)**: Test JSON codecs
- **[HTTP](./http.md)**: Test HTTP operations
