# Commands and Subscriptions

Commands (Cmd) and Subscriptions (Sub) are how Canopy handles side effects while maintaining pure functions.

## Understanding Side Effects

In Canopy, functions are pure - they always return the same output for the same input. But real applications need side effects:

- HTTP requests
- Random number generation
- Getting the current time
- Reading from ports

**Commands** describe side effects you want to perform.
**Subscriptions** listen for events from the outside world.

## Commands (Cmd)

A `Cmd msg` is a description of something you want Canopy to do. When the runtime executes the command, it will send a message back to your update function.

### The Update Function with Commands

```canopy
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FetchUser userId ->
            ( { model | loading = True }
            , Http.get
                { url = "/api/users/" ++ String.fromInt userId
                , expect = Http.expectJson GotUser userDecoder
                }
            )

        GotUser result ->
            ( { model | loading = False, user = Result.toMaybe result }
            , Cmd.none
            )
```

### Cmd.none

When you don't need any side effects:

```canopy
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }
            , Cmd.none  -- No side effects
            )
```

### Cmd.batch

Run multiple commands together:

```canopy
init : () -> ( Model, Cmd Msg )
init _ =
    ( initialModel
    , Cmd.batch
        [ fetchUser 1
        , fetchPosts
        , getCurrentTime
        ]
    )
```

### Cmd.map

Transform the message type of a command:

```canopy
-- In a child module
module Profile exposing (Model, Msg, update, fetchProfile)

type Msg
    = GotProfile (Result Http.Error Profile)


fetchProfile : Int -> Cmd Msg
fetchProfile userId = ...


-- In the parent module
type Msg
    = ProfileMsg Profile.Msg
    | ...


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoadProfile userId ->
            ( model
            , Cmd.map ProfileMsg (Profile.fetchProfile userId)
            )
```

## Common Commands

### HTTP Requests

```canopy
import Http


fetchUser : Int -> Cmd Msg
fetchUser userId =
    Http.get
        { url = "/api/users/" ++ String.fromInt userId
        , expect = Http.expectJson GotUser userDecoder
        }
```

### Random Values

```canopy
import Random


rollDice : Cmd Msg
rollDice =
    Random.generate DiceRolled (Random.int 1 6)


-- For multiple dice
rollMultipleDice : Int -> Cmd Msg
rollMultipleDice count =
    Random.generate DiceRolled (Random.list count (Random.int 1 6))
```

### Current Time

```canopy
import Task
import Time


getCurrentTime : Cmd Msg
getCurrentTime =
    Task.perform GotTime Time.now


getTimeZone : Cmd Msg
getTimeZone =
    Task.perform GotTimeZone Time.here
```

### Focus an Element

```canopy
import Browser.Dom as Dom
import Task


focusInput : Cmd Msg
focusInput =
    Task.attempt (\_ -> NoOp) (Dom.focus "my-input")
```

### Navigation

```canopy
import Browser.Navigation as Nav


navigateTo : Nav.Key -> String -> Cmd Msg
navigateTo key url =
    Nav.pushUrl key url


goBack : Nav.Key -> Cmd Msg
goBack key =
    Nav.back key 1
```

### Local Storage (via Ports)

```canopy
port saveToStorage : String -> Cmd msg
port loadFromStorage : () -> Cmd msg


save : Model -> Cmd Msg
save model =
    saveToStorage (Encode.encode 0 (encodeModel model))
```

## Subscriptions (Sub)

Subscriptions let you listen for external events over time.

### Basic Structure

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 Tick
        , Browser.Events.onKeyDown keyDecoder
        ]
```

### Sub.none

When you don't need any subscriptions:

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
```

### Conditional Subscriptions

Only subscribe when needed:

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.isPlaying then
        Time.every 16 AnimationFrame
    else
        Sub.none
```

### Sub.batch

Combine multiple subscriptions:

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 Tick
        , Browser.Events.onResize WindowResized
        , Browser.Events.onVisibilityChange VisibilityChanged
        ]
```

### Sub.map

Transform the message type:

```canopy
-- Child module
module Timer exposing (subscriptions)

subscriptions : Sub Msg
subscriptions =
    Time.every 1000 Tick


-- Parent module
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Sub.map TimerMsg Timer.subscriptions
        , otherSubscriptions
        ]
```

## Common Subscriptions

### Time

```canopy
import Time


-- Every second
subscriptions model =
    Time.every 1000 Tick


-- Every frame (60 FPS)
subscriptions model =
    if model.animating then
        Browser.Events.onAnimationFrame AnimationFrame
    else
        Sub.none
```

### Keyboard Events

```canopy
import Browser.Events
import Json.Decode as Decode


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onKeyDown (keyDecoder KeyDown)
        , Browser.Events.onKeyUp (keyDecoder KeyUp)
        ]


keyDecoder : (String -> msg) -> Decode.Decoder msg
keyDecoder toMsg =
    Decode.map toMsg (Decode.field "key" Decode.string)
```

### Mouse Events

```canopy
import Browser.Events


subscriptions : Model -> Sub Msg
subscriptions model =
    if model.isDragging then
        Sub.batch
            [ Browser.Events.onMouseMove (Decode.map MouseMove positionDecoder)
            , Browser.Events.onMouseUp (Decode.succeed MouseUp)
            ]
    else
        Sub.none


positionDecoder : Decode.Decoder Position
positionDecoder =
    Decode.map2 Position
        (Decode.field "clientX" Decode.float)
        (Decode.field "clientY" Decode.float)
```

### Window Events

```canopy
import Browser.Events


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize WindowResized
        , Browser.Events.onVisibilityChange VisibilityChanged
        ]
```

### Ports (External Events)

```canopy
port onStorageChange : (String -> msg) -> Sub msg


subscriptions : Model -> Sub Msg
subscriptions model =
    onStorageChange StorageChanged
```

## Tasks

Tasks are more flexible commands that can be chained and combined.

### Basic Task Usage

```canopy
import Task


-- Simple task
getCurrentTime : Cmd Msg
getCurrentTime =
    Task.perform GotTime Time.now


-- Task that can fail
type Msg
    = GotFocus
    | FocusFailed


focusElement : String -> Cmd Msg
focusElement id =
    Dom.focus id
        |> Task.attempt
            (\result ->
                case result of
                    Ok () -> GotFocus
                    Err _ -> FocusFailed
            )
```

### Chaining Tasks

```canopy
-- Perform tasks in sequence
getTimeAndZone : Cmd Msg
getTimeAndZone =
    Task.map2 Tuple.pair Time.now Time.here
        |> Task.perform GotTimeAndZone


-- Chain dependent tasks
createAndFetch : NewUser -> Cmd Msg
createAndFetch newUser =
    createUserTask newUser
        |> Task.andThen (\user -> fetchUserDetailsTask user.id)
        |> Task.attempt GotUserDetails
```

### Task with Do-Notation

Canopy supports do-notation for tasks:

```canopy
complexOperation : Task Error Result
complexOperation = do
    user <- fetchUser userId
    profile <- fetchProfile user.id
    posts <- fetchPosts user.id
    pure { user = user, profile = profile, posts = posts }
```

## Ports

Ports allow communication with JavaScript.

### Defining Ports

```canopy
-- Send data to JavaScript
port sendMessage : String -> Cmd msg

-- Receive data from JavaScript
port receiveMessage : (String -> msg) -> Sub msg
```

### Using Ports

```canopy
-- Sending
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SaveToLocalStorage data ->
            ( model
            , sendMessage (Encode.encode 0 (encodeData data))
            )


-- Receiving
subscriptions : Model -> Sub Msg
subscriptions model =
    receiveMessage ReceivedMessage
```

### JavaScript Side

```javascript
// Initialize the app
var app = Canopy.Main.init({
    node: document.getElementById('app')
});

// Send to Canopy
app.ports.receiveMessage.send("Hello from JS!");

// Receive from Canopy
app.ports.sendMessage.subscribe(function(message) {
    console.log("Got from Canopy:", message);
    localStorage.setItem('data', message);
});
```

## Best Practices

### 1. Keep Commands in Update

```canopy
-- Good: Commands returned from update
update msg model =
    case msg of
        Save -> ( model, saveCmd )


-- Avoid: Creating commands elsewhere
view model =
    button [ onClick (performSave model) ] [ text "Save" ]  -- Don't do this
```

### 2. Use Cmd.batch for Multiple Commands

```canopy
init _ =
    ( initialModel
    , Cmd.batch
        [ fetchConfig
        , fetchUser
        , recordPageView
        ]
    )
```

### 3. Handle All Subscription States

```canopy
subscriptions model =
    case model.state of
        Loading ->
            Sub.none

        Playing game ->
            Sub.batch
                [ Time.every 16 Tick
                , Browser.Events.onKeyDown keyDecoder
                ]

        Paused ->
            Browser.Events.onKeyDown resumeKeyDecoder

        GameOver ->
            Sub.none
```

### 4. Unsubscribe When Not Needed

```canopy
subscriptions model =
    if model.shouldPoll then
        Time.every 5000 Poll
    else
        Sub.none  -- Stop polling when not needed
```

## Next Steps

- **[HTTP Requests](./http.md)**: Deep dive into HTTP commands
- **[JavaScript FFI](./ffi.md)**: Working with ports
- **[Testing](./testing.md)**: Testing commands and subscriptions
