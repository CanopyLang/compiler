# Do-Notation

Canopy extends Elm's syntax with do-notation, making it easier to work with Tasks, Results, and other monadic types.

## Why Do-Notation?

Consider fetching user data and their posts:

### Without Do-Notation

```canopy
fetchUserWithPosts : Int -> Task Error UserWithPosts
fetchUserWithPosts userId =
    fetchUser userId
        |> Task.andThen
            (\user ->
                fetchPosts user.id
                    |> Task.andThen
                        (\posts ->
                            Task.succeed
                                { user = user
                                , posts = posts
                                }
                        )
            )
```

### With Do-Notation

```canopy
fetchUserWithPosts : Int -> Task Error UserWithPosts
fetchUserWithPosts userId = do
    user <- fetchUser userId
    posts <- fetchPosts user.id
    pure { user = user, posts = posts }
```

The do-notation version is clearer and reads like imperative code, while maintaining all the benefits of pure functional programming.

## Basic Syntax

### The do Block

A do block sequences operations:

```canopy
operation : Task Error Result
operation = do
    x <- firstOperation
    y <- secondOperation x
    z <- thirdOperation y
    pure (combine x y z)
```

### <- (Bind)

The `<-` operator extracts a value from a Task (or other monad):

```canopy
-- This extracts the String from Task Error String
getName : Task Error String
getName = do
    user <- fetchUser 1
    pure user.name
```

### pure (Return)

`pure` wraps a value in the monad:

```canopy
constant : Task Never Int
constant = pure 42

-- Same as
constant : Task Never Int
constant = Task.succeed 42
```

### let in do Blocks

Use `let` for pure computations:

```canopy
process : Task Error String
process = do
    user <- fetchUser 1
    let fullName = user.firstName ++ " " ++ user.lastName
    posts <- fetchPosts user.id
    let postCount = List.length posts
    pure (fullName ++ " has " ++ String.fromInt postCount ++ " posts")
```

## Working with Tasks

### Sequential Operations

```canopy
createUserWorkflow : NewUser -> Task Error User
createUserWorkflow newUser = do
    -- Validate
    validatedUser <- validateUser newUser
    -- Create
    user <- createUser validatedUser
    -- Send welcome email
    _ <- sendWelcomeEmail user.email
    -- Return the created user
    pure user
```

### Early Return with Guards

```canopy
processOrder : Order -> Task Error Receipt
processOrder order = do
    inventory <- checkInventory order.items
    if not inventory.available then
        Task.fail OutOfStock
    else do
        payment <- processPayment order.payment
        shipment <- createShipment order.address order.items
        receipt <- generateReceipt order payment shipment
        pure receipt
```

### Combining Results

```canopy
getDashboardData : Int -> Task Error Dashboard
getDashboardData userId = do
    user <- fetchUser userId
    -- Fetch in parallel using Task.map2
    (stats, notifications) <- Task.map2 Tuple.pair
        (fetchStats userId)
        (fetchNotifications userId)
    recentActivity <- fetchRecentActivity userId
    pure
        { user = user
        , stats = stats
        , notifications = notifications
        , recentActivity = recentActivity
        }
```

## Working with Maybe

Do-notation also works with Maybe:

### Basic Maybe Operations

```canopy
findUserEmail : Int -> Dict Int User -> Maybe String
findUserEmail userId users = do
    user <- Dict.get userId users
    profile <- user.profile
    email <- profile.email
    pure email
```

### Without Do-Notation (Comparison)

```canopy
findUserEmail : Int -> Dict Int User -> Maybe String
findUserEmail userId users =
    Dict.get userId users
        |> Maybe.andThen .profile
        |> Maybe.andThen .email
```

## Working with Result

### Basic Result Operations

```canopy
parseAndValidate : String -> Result Error User
parseAndValidate input = do
    json <- parseJson input
    user <- decodeUser json
    validatedUser <- validateUser user
    pure validatedUser
```

### Error Handling

```canopy
type Error
    = ParseError String
    | ValidationError String
    | NetworkError String


processForm : FormData -> Result Error SubmitResult
processForm form = do
    email <- validateEmail form.email
        |> Result.mapError ValidationError
    password <- validatePassword form.password
        |> Result.mapError ValidationError
    pure { email = email, password = password }
```

## Combining Different Monads

### Task with Maybe

```canopy
findAndUpdateUser : Int -> (User -> User) -> Task Error (Maybe User)
findAndUpdateUser userId updateFn = do
    maybeUser <- fetchMaybeUser userId
    case maybeUser of
        Nothing ->
            pure Nothing

        Just user ->
            let updated = updateFn user
            in do
                savedUser <- saveUser updated
                pure (Just savedUser)
```

### Converting Between Monads

```canopy
-- Maybe to Task
maybeToTask : Error -> Maybe a -> Task Error a
maybeToTask error maybe =
    case maybe of
        Just value -> Task.succeed value
        Nothing -> Task.fail error


-- Result to Task
resultToTask : Result error value -> Task error value
resultToTask result =
    case result of
        Ok value -> Task.succeed value
        Err error -> Task.fail error


-- Using in do-notation
processUser : Int -> Task Error User
processUser userId = do
    maybeUser <- fetchMaybeUser userId
    user <- maybeToTask UserNotFound maybeUser
    validationResult <- validateUser user
    validUser <- resultToTask validationResult
    pure validUser
```

## Advanced Patterns

### Looping with Do-Notation

```canopy
processAllUsers : List Int -> Task Error (List User)
processAllUsers userIds =
    Task.sequence (List.map processUser userIds)


-- Or manually
processAllUsersManual : List Int -> Task Error (List User)
processAllUsersManual userIds = do
    results <- Task.sequence (List.map fetchUser userIds)
    validated <- Task.sequence (List.map validateUser results)
    pure validated
```

### Conditional Execution

```canopy
maybeRefresh : Model -> Task Error Model
maybeRefresh model = do
    if model.needsRefresh then do
        data <- fetchData
        pure { model | data = data, needsRefresh = False }
    else
        pure model
```

### Error Recovery

```canopy
fetchWithFallback : Task Error Data
fetchWithFallback =
    fetchPrimarySource
        |> Task.onError (\_ -> fetchBackupSource)
        |> Task.onError (\_ -> Task.succeed defaultData)


-- With do-notation for complex recovery
fetchWithRetry : Int -> Task Error Data
fetchWithRetry retries = do
    result <- Task.attempt fetchData
    case result of
        Ok data ->
            pure data

        Err error ->
            if retries > 0 then
                fetchWithRetry (retries - 1)
            else
                Task.fail error
```

## Best Practices

### 1. Keep Do Blocks Focused

```canopy
-- Good: Single responsibility
fetchUser : Int -> Task Error User
fetchUser id = do
    response <- Http.get userUrl
    user <- parseUser response
    pure user


-- Avoid: Too much in one block
processEverything : Task Error Result
processEverything = do
    user <- fetchUser 1
    posts <- fetchPosts user.id
    comments <- fetchAllComments posts
    analytics <- trackView user
    notification <- sendNotification user
    -- ... 20 more operations
    pure result
```

### 2. Extract Helper Functions

```canopy
-- Extract logical units
createOrder : OrderRequest -> Task Error Order
createOrder request = do
    validated <- validateOrder request
    order <- saveOrder validated
    _ <- notifyWarehouse order
    pure order


-- Main workflow uses helpers
processCheckout : Cart -> Task Error Receipt
processCheckout cart = do
    order <- createOrder (cartToOrderRequest cart)
    payment <- processPayment order
    receipt <- generateReceipt order payment
    pure receipt
```

### 3. Use Descriptive Names

```canopy
-- Good: Clear what each step does
enrollStudent : EnrollmentRequest -> Task Error Enrollment
enrollStudent request = do
    student <- validateStudent request.student
    course <- validateCourse request.courseId
    enrollment <- createEnrollment student course
    _ <- sendConfirmationEmail student enrollment
    pure enrollment
```

### 4. Handle Errors at the Right Level

```canopy
-- Handle errors where appropriate
processWithLogging : Request -> Task Error Response
processWithLogging request = do
    _ <- logRequest request
    response <- process request
        |> Task.onError (\err -> do
            _ <- logError err
            Task.fail err
        )
    _ <- logResponse response
    pure response
```

## Comparison with Other Approaches

### Do-Notation vs Pipelines

```canopy
-- Pipelines work well for transformations
process : String -> String
process =
    String.trim
        >> String.toLower
        >> String.replace " " "-"


-- Do-notation works well for effects
processWithEffects : String -> Task Error String
processWithEffects input = do
    validated <- validate input
    processed <- transform validated
    saved <- save processed
    pure saved
```

### Do-Notation vs Task.andThen

```canopy
-- Task.andThen for simple chains
simple : Task Error Int
simple =
    fetchNumber
        |> Task.andThen (\n -> Task.succeed (n * 2))


-- Do-notation for complex flows
complex : Task Error Result
complex = do
    a <- fetchA
    b <- fetchB a
    c <- fetchC a b
    pure (combine a b c)
```

## Next Steps

- **[Testing](./testing.md)**: Test async code
- **[Error Handling](./error-handling.md)**: Error patterns
- **[FFI](./ffi.md)**: Using do-notation with FFI
