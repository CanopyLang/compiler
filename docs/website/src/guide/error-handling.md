# Error Handling

Canopy's type system makes error handling explicit and safe. You cannot ignore errors - they must be handled at compile time.

## Core Types for Errors

### Maybe

`Maybe` represents a value that might not exist:

```canopy
type Maybe a
    = Just a
    | Nothing
```

Use `Maybe` when:

- A value might be absent (no error information needed)
- Looking up items that may not exist
- Optional fields in records

```canopy
-- Looking up in a list
List.head : List a -> Maybe a
List.head [1, 2, 3]  -- Just 1
List.head []         -- Nothing

-- Looking up in a dictionary
Dict.get : comparable -> Dict comparable v -> Maybe v
Dict.get "key" myDict  -- Just value or Nothing

-- Parsing that might fail
String.toInt : String -> Maybe Int
String.toInt "42"   -- Just 42
String.toInt "abc"  -- Nothing
```

### Result

`Result` represents success or failure with error details:

```canopy
type Result error value
    = Ok value
    | Err error
```

Use `Result` when:

- An operation can fail
- You need to know why it failed
- The caller should handle different error cases

```canopy
-- Decoding JSON
Decode.decodeString : Decoder a -> String -> Result Decode.Error a

-- HTTP responses
type alias HttpResult a = Result Http.Error a

-- Validation
validateEmail : String -> Result ValidationError Email
```

## Working with Maybe

### Creating Maybe Values

```canopy
-- From a value
Just 42 : Maybe Int
Nothing : Maybe a

-- From nullable operations
List.head [1, 2, 3]  -- Just 1
Dict.get "key" dict  -- Maybe value
```

### Pattern Matching

```canopy
viewUser : Maybe User -> Html msg
viewUser maybeUser =
    case maybeUser of
        Just user ->
            div [] [ text user.name ]

        Nothing ->
            div [] [ text "No user found" ]
```

### Helper Functions

```canopy
-- Default value
Maybe.withDefault : a -> Maybe a -> a
Maybe.withDefault 0 (Just 5)   -- 5
Maybe.withDefault 0 Nothing    -- 0

-- Transform if present
Maybe.map : (a -> b) -> Maybe a -> Maybe b
Maybe.map String.toUpper (Just "hello")  -- Just "HELLO"
Maybe.map String.toUpper Nothing          -- Nothing

-- Chain operations
Maybe.andThen : (a -> Maybe b) -> Maybe a -> Maybe b
Just 5
    |> Maybe.andThen (\n -> if n > 0 then Just n else Nothing)
    -- Just 5

-- Convert to list
Maybe.toList : Maybe a -> List a
Maybe.toList (Just 1)  -- [1]
Maybe.toList Nothing   -- []
```

### Combining Multiple Maybes

```canopy
-- Both must be Just
Maybe.map2 : (a -> b -> c) -> Maybe a -> Maybe b -> Maybe c
Maybe.map2 (+) (Just 1) (Just 2)  -- Just 3
Maybe.map2 (+) (Just 1) Nothing   -- Nothing

-- With do-notation
combineUsers : Maybe User -> Maybe User -> Maybe ( User, User )
combineUsers m1 m2 = do
    user1 <- m1
    user2 <- m2
    pure ( user1, user2 )
```

## Working with Result

### Creating Results

```canopy
-- Success
Ok 42 : Result error Int

-- Failure
Err "Something went wrong" : Result String a

-- From operations
validateAge : Int -> Result String Int
validateAge age =
    if age < 0 then
        Err "Age cannot be negative"
    else if age > 150 then
        Err "Age seems unrealistic"
    else
        Ok age
```

### Pattern Matching

```canopy
viewResult : Result String User -> Html msg
viewResult result =
    case result of
        Ok user ->
            div [] [ text user.name ]

        Err message ->
            div [ class "error" ] [ text message ]
```

### Helper Functions

```canopy
-- Default value on error
Result.withDefault : a -> Result x a -> a
Result.withDefault 0 (Ok 5)   -- 5
Result.withDefault 0 (Err _)  -- 0

-- Transform success value
Result.map : (a -> b) -> Result x a -> Result x b
Result.map String.toUpper (Ok "hello")  -- Ok "HELLO"
Result.map String.toUpper (Err e)       -- Err e

-- Transform error value
Result.mapError : (x -> y) -> Result x a -> Result y a
Result.mapError String.toUpper (Err "fail")  -- Err "FAIL"

-- Chain operations
Result.andThen : (a -> Result x b) -> Result x a -> Result x b
Ok 5
    |> Result.andThen validateAge
    |> Result.andThen (\age -> Ok (age + 1))
```

### Converting Between Types

```canopy
-- Maybe to Result
Result.fromMaybe : x -> Maybe a -> Result x a
Result.fromMaybe "Not found" (Just 5)  -- Ok 5
Result.fromMaybe "Not found" Nothing   -- Err "Not found"

-- Result to Maybe
Result.toMaybe : Result x a -> Maybe a
Result.toMaybe (Ok 5)    -- Just 5
Result.toMaybe (Err _)   -- Nothing
```

## Defining Error Types

### Simple Errors

```canopy
type ValidationError
    = EmptyName
    | InvalidEmail
    | PasswordTooShort


validate : Form -> Result ValidationError ValidatedForm
validate form =
    if String.isEmpty form.name then
        Err EmptyName
    else if not (String.contains "@" form.email) then
        Err InvalidEmail
    else if String.length form.password < 8 then
        Err PasswordTooShort
    else
        Ok (toValidatedForm form)
```

### Errors with Data

```canopy
type ApiError
    = NetworkError String
    | NotFound String
    | Unauthorized
    | ServerError Int String
    | ParseError String


errorToString : ApiError -> String
errorToString error =
    case error of
        NetworkError message ->
            "Network error: " ++ message

        NotFound resource ->
            "Not found: " ++ resource

        Unauthorized ->
            "Please log in to continue"

        ServerError code message ->
            "Server error " ++ String.fromInt code ++ ": " ++ message

        ParseError details ->
            "Failed to parse response: " ++ details
```

### Hierarchical Errors

```canopy
type AppError
    = ApiError ApiError
    | ValidationError ValidationError
    | StorageError StorageError


handleError : AppError -> Model -> Model
handleError error model =
    case error of
        ApiError apiErr ->
            { model | apiError = Just (apiErrorToString apiErr) }

        ValidationError valErr ->
            { model | formErrors = validationErrorToFields valErr }

        StorageError storageErr ->
            { model | storageError = Just (storageErrorToString storageErr) }
```

## Error Handling Patterns

### The RemoteData Pattern

Model data that comes from an async source:

```canopy
type RemoteData e a
    = NotAsked
    | Loading
    | Failure e
    | Success a


type alias Model =
    { users : RemoteData Http.Error (List User)
    }


view : Model -> Html Msg
view model =
    case model.users of
        NotAsked ->
            button [ onClick LoadUsers ] [ text "Load Users" ]

        Loading ->
            div [ class "spinner" ] []

        Failure error ->
            viewError error

        Success users ->
            viewUsers users
```

### Collecting All Errors

```canopy
type alias Validated a =
    Result (List String) a


validateForm : Form -> Validated ValidatedForm
validateForm form =
    let
        nameResult =
            if String.isEmpty form.name then
                Err [ "Name is required" ]
            else
                Ok form.name

        emailResult =
            if not (String.contains "@" form.email) then
                Err [ "Invalid email address" ]
            else
                Ok form.email

        passwordResult =
            if String.length form.password < 8 then
                Err [ "Password must be at least 8 characters" ]
            else
                Ok form.password
    in
    case ( nameResult, emailResult, passwordResult ) of
        ( Ok name, Ok email, Ok password ) ->
            Ok { name = name, email = email, password = password }

        ( n, e, p ) ->
            Err (collectErrors [ n, e, p ])


collectErrors : List (Result (List String) a) -> List String
collectErrors results =
    results
        |> List.filterMap
            (\r ->
                case r of
                    Err errs -> Just errs
                    Ok _ -> Nothing
            )
        |> List.concat
```

### Recovery Patterns

```canopy
-- Try alternatives
loadConfig : Task Error Config
loadConfig =
    loadFromFile "config.json"
        |> Task.onError (\_ -> loadFromFile "config.default.json")
        |> Task.onError (\_ -> Task.succeed defaultConfig)


-- With do-notation
loadWithFallback : Task Never Config
loadWithFallback = do
    result <- Task.attempt loadConfig
    case result of
        Ok config ->
            pure config

        Err _ ->
            pure defaultConfig
```

### Error Boundaries in Views

```canopy
viewWithErrorBoundary : Model -> Html Msg
viewWithErrorBoundary model =
    case model.criticalError of
        Just error ->
            viewCriticalError error

        Nothing ->
            case model.pageError of
                Just pageErr ->
                    div []
                        [ viewErrorBanner pageErr
                        , viewPageContent model
                        ]

                Nothing ->
                    viewPageContent model
```

## Best Practices

### 1. Use Specific Error Types

```canopy
-- Good: Specific, actionable errors
type CreateUserError
    = EmailAlreadyExists
    | InvalidEmailFormat
    | PasswordTooWeak WeakPasswordReason
    | NameTooLong Int  -- includes max length


-- Avoid: Generic errors
type Error
    = Error String
```

### 2. Handle Errors at the Right Level

```canopy
-- Low level: Return Result
parseConfig : String -> Result ParseError Config
parseConfig = ...

-- Higher level: Handle and transform
loadConfig : Task AppError Config
loadConfig =
    readFile "config.json"
        |> Task.mapError FileError
        |> Task.andThen (parseConfig >> resultToTask >> Task.mapError ConfigError)


-- Highest level: Show to user
update msg model =
    case msg of
        ConfigLoaded (Err error) ->
            ( { model | error = Just (errorToUserMessage error) }
            , Cmd.none
            )
```

### 3. Provide User-Friendly Messages

```canopy
errorToUserMessage : AppError -> String
errorToUserMessage error =
    case error of
        NetworkError _ ->
            "Unable to connect. Please check your internet connection."

        NotFound _ ->
            "The requested item could not be found."

        Unauthorized ->
            "Your session has expired. Please log in again."

        ServerError code _ ->
            if code >= 500 then
                "Our servers are having trouble. Please try again later."
            else
                "Something went wrong. Please try again."

        ParseError _ ->
            "We received an unexpected response. Please try again."
```

### 4. Log Technical Details

```canopy
handleError : AppError -> ( Model, Cmd Msg )
handleError error model =
    ( { model | error = Just (errorToUserMessage error) }
    , logError (errorToLogMessage error)  -- Log technical details
    )


errorToLogMessage : AppError -> String
errorToLogMessage error =
    case error of
        ServerError code message ->
            "Server error " ++ String.fromInt code ++ ": " ++ message

        ParseError details ->
            "Parse error: " ++ details

        _ ->
            toString error
```

### 5. Don't Swallow Errors

```canopy
-- Bad: Silently ignoring errors
processData : Data -> Data
processData data =
    case validate data of
        Ok valid -> valid
        Err _ -> data  -- Silent failure!


-- Good: Make error handling explicit
processData : Data -> Result ValidationError Data
processData data =
    validate data
```

## Next Steps

- **[Maybe and Result](./type-system.md#maybe-handling-missing-values)**: Type system details
- **[HTTP](./http.md)**: Handling HTTP errors
- **[Testing](./testing.md)**: Testing error cases
