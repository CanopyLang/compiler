# Platform Module

The Platform module provides core abstractions for programs, commands, and subscriptions.

## Cmd (Commands)

Commands describe side effects that the runtime should perform.

### Creating Commands

```canopy
Cmd.none : Cmd msg
-- No command (no side effect)

Cmd.batch : List (Cmd msg) -> Cmd msg
-- Combine multiple commands
```

**Example:**

```canopy
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        -- No side effects needed
        Increment ->
            ( { model | count = model.count + 1 }
            , Cmd.none
            )

        -- Multiple commands
        Init ->
            ( model
            , Cmd.batch
                [ fetchUser model.userId
                , fetchSettings
                , trackPageView "home"
                ]
            )
```

### Transforming Commands

```canopy
Cmd.map : (a -> msg) -> Cmd a -> Cmd msg
```

**Example:**

```canopy
-- Transform child module commands
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ProfileMsg subMsg ->
            let
                ( newProfile, profileCmd ) =
                    Profile.update subMsg model.profile
            in
            ( { model | profile = newProfile }
            , Cmd.map ProfileMsg profileCmd
            )
```

---

## Sub (Subscriptions)

Subscriptions describe events from outside your application.

### Creating Subscriptions

```canopy
Sub.none : Sub msg
-- No subscriptions

Sub.batch : List (Sub msg) -> Sub msg
-- Combine multiple subscriptions
```

**Example:**

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.isPlaying then
        Sub.batch
            [ Time.every 1000 Tick
            , Browser.Events.onKeyDown keyDecoder
            , Browser.Events.onAnimationFrame AnimationFrame
            ]
    else
        Sub.none
```

### Transforming Subscriptions

```canopy
Sub.map : (a -> msg) -> Sub a -> Sub msg
```

**Example:**

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Sub.map TimerMsg Timer.subscriptions
        , Sub.map GameMsg (Game.subscriptions model.game)
        ]
```

---

## Task

Tasks represent asynchronous operations that may fail.

### Basic Operations

```canopy
Task.succeed : a -> Task x a
-- Create a task that succeeds with a value

Task.fail : x -> Task x a
-- Create a task that fails with an error

Task.map : (a -> b) -> Task x a -> Task x b
-- Transform successful value

Task.mapError : (x -> y) -> Task x a -> Task y a
-- Transform error value

Task.andThen : (a -> Task x b) -> Task x a -> Task x b
-- Chain tasks sequentially
```

**Example:**

```canopy
-- Simple task
getTime : Task x Time.Posix
getTime =
    Time.now


-- Chaining tasks
fetchUserProfile : Int -> Task Error Profile
fetchUserProfile userId =
    fetchUser userId
        |> Task.andThen (\user -> fetchProfile user.profileId)


-- Transform values
getTimeAsString : Task x String
getTimeAsString =
    Time.now
        |> Task.map Time.posixToMillis
        |> Task.map String.fromInt
```

### Running Tasks

```canopy
Task.perform : (a -> msg) -> Task Never a -> Cmd msg
-- Run a task that cannot fail

Task.attempt : (Result x a -> msg) -> Task x a -> Cmd msg
-- Run a task that may fail
```

**Example:**

```canopy
-- Task that cannot fail
getCurrentTime : Cmd Msg
getCurrentTime =
    Task.perform GotTime Time.now


-- Task that may fail
focusElement : Cmd Msg
focusElement =
    Task.attempt FocusResult (Browser.Dom.focus "input-id")


type Msg
    = GotTime Time.Posix
    | FocusResult (Result Browser.Dom.Error ())
```

### Combining Tasks

```canopy
Task.map2 : (a -> b -> c) -> Task x a -> Task x b -> Task x c
Task.map3 : ...
Task.map4 : ...
Task.map5 : ...

Task.sequence : List (Task x a) -> Task x (List a)
-- Run tasks in sequence, collect results
```

**Example:**

```canopy
-- Run two tasks, combine results
fetchDashboard : Task Error Dashboard
fetchDashboard =
    Task.map2 Dashboard
        fetchUser
        fetchStats


-- Run list of tasks
fetchAllUsers : List Int -> Task Error (List User)
fetchAllUsers userIds =
    userIds
        |> List.map fetchUser
        |> Task.sequence
```

### Error Handling

```canopy
Task.onError : (x -> Task y a) -> Task x a -> Task y a
-- Handle errors, possibly recovering
```

**Example:**

```canopy
-- Try primary source, fall back to backup
fetchData : Task Error Data
fetchData =
    fetchFromPrimary
        |> Task.onError (\_ -> fetchFromBackup)
        |> Task.onError (\_ -> Task.succeed defaultData)
```

---

## Process

Process module for spawning independent processes.

```canopy
Process.sleep : Float -> Task x ()
-- Sleep for given milliseconds

Process.spawn : Task x a -> Task y Process.Id
-- Start a process that runs a task

Process.kill : Process.Id -> Task x ()
-- Kill a running process
```

**Example:**

```canopy
-- Delayed action
delayedAction : Cmd Msg
delayedAction =
    Process.sleep 2000
        |> Task.andThen (\_ -> Task.succeed ())
        |> Task.perform (\_ -> DelayedActionComplete)
```

---

## Random

Generate random values.

### Generators

```canopy
Random.int : Int -> Int -> Generator Int
Random.float : Float -> Float -> Generator Float
Random.uniform : a -> List a -> Generator a
Random.weighted : ( Float, a ) -> List ( Float, a ) -> Generator a
Random.constant : a -> Generator a
Random.map : (a -> b) -> Generator a -> Generator b
Random.andThen : (a -> Generator b) -> Generator a -> Generator b
Random.list : Int -> Generator a -> Generator (List a)
Random.pair : Generator a -> Generator b -> Generator ( a, b )
```

### Running Generators

```canopy
Random.generate : (a -> msg) -> Generator a -> Cmd msg
Random.step : Generator a -> Seed -> ( a, Seed )
Random.initialSeed : Int -> Seed
```

**Example:**

```canopy
-- Roll a die
rollDie : Cmd Msg
rollDie =
    Random.generate DieRolled (Random.int 1 6)


-- Generate random user
type alias RandomUser =
    { name : String
    , age : Int
    }


randomUserGenerator : Generator RandomUser
randomUserGenerator =
    Random.map2 RandomUser
        (Random.uniform "Alice" [ "Bob", "Charlie", "Diana" ])
        (Random.int 18 65)


generateRandomUser : Cmd Msg
generateRandomUser =
    Random.generate GotRandomUser randomUserGenerator


-- Weighted random selection
randomPriority : Generator Priority
randomPriority =
    Random.weighted
        ( 50, Low )
        [ ( 30, Medium )
        , ( 20, High )
        ]
```

---

## Time

Work with time.

### Types

```canopy
type Posix
-- A point in time (milliseconds since epoch)

type Zone
-- A time zone
```

### Current Time

```canopy
Time.now : Task x Posix
Time.here : Task x Zone
Time.utc : Zone
```

### Subscriptions

```canopy
Time.every : Float -> (Posix -> msg) -> Sub msg
-- Trigger message every N milliseconds
```

### Conversions

```canopy
Time.posixToMillis : Posix -> Int
Time.millisToPosix : Int -> Posix

Time.toYear : Zone -> Posix -> Int
Time.toMonth : Zone -> Posix -> Month
Time.toDay : Zone -> Posix -> Int
Time.toWeekday : Zone -> Posix -> Weekday
Time.toHour : Zone -> Posix -> Int
Time.toMinute : Zone -> Posix -> Int
Time.toSecond : Zone -> Posix -> Int
Time.toMillis : Zone -> Posix -> Int
```

**Example:**

```canopy
-- Get current time
init : () -> ( Model, Cmd Msg )
init _ =
    ( initialModel
    , Task.perform GotTime Time.now
    )


-- Timer subscription
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.timerActive then
        Time.every 1000 Tick
    else
        Sub.none


-- Format time
formatTime : Time.Zone -> Time.Posix -> String
formatTime zone time =
    String.fromInt (Time.toHour zone time)
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt (Time.toMinute zone time))
```

---

## File

Work with files from user input.

### Types

```canopy
type File
-- A selected file

File.name : File -> String
File.mime : File -> String
File.size : File -> Int
File.lastModified : File -> Time.Posix
```

### Reading Files

```canopy
File.toString : File -> Task x String
File.toBytes : File -> Task x Bytes
File.toUrl : File -> Task x String  -- Data URL
```

### File Selection

```canopy
-- Single file
File.Select.file : List String -> (File -> msg) -> Cmd msg

-- Multiple files
File.Select.files : List String -> (File -> List File -> msg) -> Cmd msg
```

**Example:**

```canopy
selectImage : Cmd Msg
selectImage =
    File.Select.file [ "image/png", "image/jpeg" ] ImageSelected


type Msg
    = ImageSelected File
    | GotImageUrl String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ImageSelected file ->
            ( model
            , Task.perform GotImageUrl (File.toUrl file)
            )

        GotImageUrl url ->
            ( { model | imageUrl = Just url }
            , Cmd.none
            )
```

---

## Ports

Communication with JavaScript.

### Defining Ports

```canopy
-- Outgoing (Canopy to JS)
port sendMessage : String -> Cmd msg

-- Incoming (JS to Canopy)
port receiveMessage : (String -> msg) -> Sub msg
```

### Using Ports

```canopy
-- Sending to JS
saveToStorage : String -> Cmd Msg
saveToStorage data =
    sendMessage data


-- Receiving from JS
subscriptions : Model -> Sub Msg
subscriptions model =
    receiveMessage ReceivedMessage
```

### JavaScript Side

```javascript
// Initialize app
var app = Canopy.Main.init({
    node: document.getElementById('app')
});

// Subscribe to outgoing port
app.ports.sendMessage.subscribe(function(message) {
    console.log('Got from Canopy:', message);
    localStorage.setItem('data', message);
});

// Send to incoming port
app.ports.receiveMessage.send('Hello from JavaScript');
```
