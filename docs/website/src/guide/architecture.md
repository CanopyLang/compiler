# The Canopy Architecture

The Canopy Architecture (based on The Elm Architecture, or TEA) is a pattern for building web applications. It provides a simple, predictable way to structure your code that scales from small widgets to large applications.

## Core Concepts

Every Canopy application consists of three parts:

1. **Model**: The state of your application
2. **Update**: A way to update your state
3. **View**: A way to view your state as HTML

```
┌─────────────────────────────────────────────────────────┐
│                     Canopy Runtime                       │
│                                                          │
│    ┌──────────┐        ┌──────────┐       ┌──────────┐  │
│    │          │  Msg   │          │ Model │          │  │
│    │   View   │◀───────│  Update  │◀──────│  Model   │  │
│    │          │        │          │       │          │  │
│    └────┬─────┘        └──────────┘       └──────────┘  │
│         │                   ▲                           │
│         │ Html Msg          │ Msg                       │
│         ▼                   │                           │
│    ┌─────────────────────────────────────────────────┐  │
│    │               Virtual DOM / Browser              │  │
│    └─────────────────────────────────────────────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## The Basic Pattern

### Model

The Model is a data structure representing the entire state of your application:

```canopy
type alias Model =
    { user : Maybe User
    , posts : List Post
    , currentPage : Page
    , isLoading : Bool
    }

type Page
    = Home
    | Profile String
    | Settings
```

Key principles:

- **Single Source of Truth**: All application state lives in the Model
- **Immutable**: The Model is never mutated, only replaced
- **Serializable**: You can encode/decode the Model for debugging or persistence

### Messages

Messages describe all the events that can happen in your application:

```canopy
type Msg
    = UserLoggedIn User
    | UserLoggedOut
    | PostsLoaded (Result Http.Error (List Post))
    | NavigateTo Page
    | ToggleMenu
    | FormFieldChanged String String
```

Key principles:

- **Exhaustive**: Every possible event has a corresponding message
- **Descriptive**: Names should describe what happened, not what to do
- **Data Carriers**: Messages can carry associated data

### Update

The update function handles messages and produces a new Model:

```canopy
update : Msg -> Model -> Model
update msg model =
    case msg of
        UserLoggedIn user ->
            { model | user = Just user }

        UserLoggedOut ->
            { model | user = Nothing }

        PostsLoaded result ->
            case result of
                Ok posts ->
                    { model | posts = posts, isLoading = False }

                Err _ ->
                    { model | isLoading = False }

        NavigateTo page ->
            { model | currentPage = page }

        ToggleMenu ->
            { model | menuOpen = not model.menuOpen }

        FormFieldChanged field value ->
            updateFormField field value model
```

Key principles:

- **Pure Function**: Same inputs always produce same outputs
- **Centralized Logic**: All state changes happen here
- **Pattern Matching**: Handle every message explicitly

### View

The view function renders your Model as HTML:

```canopy
view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ viewHeader model
        , viewContent model
        , viewFooter
        ]


viewHeader : Model -> Html Msg
viewHeader model =
    header []
        [ h1 [] [ text "My App" ]
        , case model.user of
            Just user ->
                button [ onClick UserLoggedOut ] [ text "Log Out" ]

            Nothing ->
                button [ onClick NavigateTo Login ] [ text "Log In" ]
        ]


viewContent : Model -> Html Msg
viewContent model =
    case model.currentPage of
        Home ->
            viewHome model.posts

        Profile userId ->
            viewProfile userId

        Settings ->
            viewSettings model
```

Key principles:

- **Pure Function**: Rendering is deterministic
- **Declarative**: Describe what to show, not how to update the DOM
- **Composable**: Break complex views into smaller functions

## Adding Commands (Side Effects)

For applications with side effects (HTTP requests, random numbers, current time), use `Browser.element` or `Browser.application`:

```canopy
main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( initialModel
    , Http.get
        { url = "/api/posts"
        , expect = Http.expectJson PostsLoaded postsDecoder
        }
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FetchPosts ->
            ( { model | isLoading = True }
            , Http.get
                { url = "/api/posts"
                , expect = Http.expectJson PostsLoaded postsDecoder
                }
            )

        PostsLoaded result ->
            ( { model
                | posts = Result.withDefault [] result
                , isLoading = False
              }
            , Cmd.none
            )
```

### Commands (Cmd)

Commands represent side effects to perform:

```canopy
-- HTTP requests
fetchUsers : Cmd Msg
fetchUsers =
    Http.get
        { url = "/api/users"
        , expect = Http.expectJson UsersLoaded usersDecoder
        }

-- Generate random values
rollDice : Cmd Msg
rollDice =
    Random.generate DiceRolled (Random.int 1 6)

-- Get current time
getCurrentTime : Cmd Msg
getCurrentTime =
    Task.perform GotTime Time.now

-- Multiple commands
initCommands : Cmd Msg
initCommands =
    Cmd.batch
        [ fetchUsers
        , getCurrentTime
        ]
```

### Subscriptions

Subscriptions let you listen for external events:

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 1000 Tick
        , Browser.Events.onResize WindowResized
        , if model.isPlaying then
            Time.every 16 AnimationFrame
          else
            Sub.none
        ]
```

## Program Types

Canopy provides several program types for different needs:

### Browser.sandbox

Simplest option, no side effects:

```canopy
Browser.sandbox
    { init : Model
    , update : Msg -> Model -> Model
    , view : Model -> Html Msg
    }
```

### Browser.element

Embeddable component with commands and subscriptions:

```canopy
Browser.element
    { init : flags -> ( Model, Cmd Msg )
    , update : Msg -> Model -> ( Model, Cmd Msg )
    , subscriptions : Model -> Sub Msg
    , view : Model -> Html Msg
    }
```

### Browser.document

Controls the entire document including `<title>`:

```canopy
Browser.document
    { init : flags -> ( Model, Cmd Msg )
    , update : Msg -> Model -> ( Model, Cmd Msg )
    , subscriptions : Model -> Sub Msg
    , view : Model -> Document Msg
    }

type alias Document msg =
    { title : String
    , body : List (Html msg)
    }
```

### Browser.application

Full single-page application with routing:

```canopy
Browser.application
    { init : flags -> Url -> Key -> ( Model, Cmd Msg )
    , update : Msg -> Model -> ( Model, Cmd Msg )
    , subscriptions : Model -> Sub Msg
    , view : Model -> Document Msg
    , onUrlRequest : UrlRequest -> Msg
    , onUrlChange : Url -> Msg
    }
```

## Scaling the Architecture

As your application grows, organize your code into focused modules:

```
src/
├── Main.can           # Entry point, wires everything together
├── Model.can          # Shared model types
├── Msg.can            # All message types
├── Update.can         # Main update logic
├── View.can           # Main view
├── Route.can          # URL routing
├── Api.can            # HTTP API calls
├── Page/
│   ├── Home.can       # Home page (Model, Msg, update, view)
│   ├── Profile.can    # Profile page
│   └── Settings.can   # Settings page
└── Component/
    ├── Header.can     # Reusable header
    └── Modal.can      # Modal component
```

### Page Modules Pattern

Each page can have its own Model, Msg, update, and view:

```canopy
-- Page/Profile.can
module Page.Profile exposing (Model, Msg, init, update, view)

type alias Model =
    { userId : String
    , user : Maybe User
    , posts : List Post
    }

type Msg
    = UserLoaded (Result Http.Error User)
    | PostsLoaded (Result Http.Error (List Post))

init : String -> ( Model, Cmd Msg )
init userId =
    ( { userId = userId, user = Nothing, posts = [] }
    , fetchUser userId
    )

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model = ...

view : Model -> Html Msg
view model = ...
```

Then compose in Main:

```canopy
-- Main.can
type Model
    = Home Home.Model
    | Profile Profile.Model
    | Settings Settings.Model

type Msg
    = HomeMsg Home.Msg
    | ProfileMsg Profile.Msg
    | SettingsMsg Settings.Msg

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model ) of
        ( HomeMsg subMsg, Home subModel ) ->
            Home.update subMsg subModel
                |> Tuple.mapBoth Home (Cmd.map HomeMsg)

        ( ProfileMsg subMsg, Profile subModel ) ->
            Profile.update subMsg subModel
                |> Tuple.mapBoth Profile (Cmd.map ProfileMsg)

        _ ->
            ( model, Cmd.none )
```

## Benefits of this Architecture

### Predictability

- State changes are explicit and traceable
- No hidden mutations or side effects
- Easy to understand what the application will do

### Testability

- Pure functions are trivial to test
- No mocking required for most tests
- Time-travel debugging is possible

### Maintainability

- Clear separation of concerns
- Adding features follows the same pattern
- Refactoring is safe with the type system

### Performance

- Virtual DOM efficiently updates only what changed
- Immutable data enables optimization
- Lazy rendering for large lists

## Common Patterns

### Nested Update with Effects

```canopy
updateWith : (subModel -> Model) -> (subMsg -> Msg) -> ( subModel, Cmd subMsg ) -> ( Model, Cmd Msg )
updateWith toModel toMsg ( subModel, subCmd ) =
    ( toModel subModel
    , Cmd.map toMsg subCmd
    )
```

### Shared State

```canopy
type alias SharedState =
    { user : Maybe User
    , theme : Theme
    }

-- Pass to page views
viewPage : SharedState -> Page.Model -> Html Msg
```

### Command Helpers

```canopy
withNoCmd : Model -> ( Model, Cmd Msg )
withNoCmd model =
    ( model, Cmd.none )

withCmd : Cmd Msg -> Model -> ( Model, Cmd Msg )
withCmd cmd model =
    ( model, cmd )
```

## Next Steps

- **[Commands and Subscriptions](./commands.md)**: Deep dive into side effects
- **[HTTP Requests](./http.md)**: Making API calls
- **[Testing](./testing.md)**: Testing your architecture
