# Browser Module

The Browser module provides functions for creating web applications with different levels of control over the document.

## Program Types

### Browser.sandbox

The simplest program type. No commands, no subscriptions, no JavaScript interop.

```canopy
Browser.sandbox :
    { init : model
    , update : msg -> model -> model
    , view : model -> Html msg
    }
    -> Program () model msg
```

**Example:**

```canopy
main : Program () Model Msg
main =
    Browser.sandbox
        { init = initialModel
        , update = update
        , view = view
        }
```

**Use when:**

- Learning Canopy
- Simple widgets without side effects
- Prototyping UI

---

### Browser.element

Embeddable component with commands and subscriptions.

```canopy
Browser.element :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> Html msg
    }
    -> Program flags model msg
```

**Example:**

```canopy
main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


type alias Flags =
    { apiUrl : String
    , userId : Int
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { apiUrl = flags.apiUrl, user = Nothing }
    , fetchUser flags.userId
    )
```

**Use when:**

- Embedding Canopy in an existing page
- Need HTTP requests, random numbers, or other effects
- Building reusable components

---

### Browser.document

Full control over the `<title>` and `<body>`.

```canopy
Browser.document :
    { init : flags -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> Document msg
    }
    -> Program flags model msg


type alias Document msg =
    { title : String
    , body : List (Html msg)
    }
```

**Example:**

```canopy
main : Program () Model Msg
main =
    Browser.document
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


view : Model -> Document Msg
view model =
    { title = "My App - " ++ model.pageTitle
    , body =
        [ viewHeader model
        , viewContent model
        , viewFooter
        ]
    }
```

**Use when:**

- Need to control the page title dynamically
- Building a full-page application

---

### Browser.application

Full single-page application with URL routing.

```canopy
Browser.application :
    { init : flags -> Url -> Key -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , view : model -> Document msg
    , onUrlRequest : UrlRequest -> msg
    , onUrlChange : Url -> msg
    }
    -> Program flags model msg


type UrlRequest
    = Internal Url
    | External String
```

**Example:**

```canopy
main : Program () Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


type Msg
    = LinkClicked UrlRequest
    | UrlChanged Url
    | ...


init : () -> Url -> Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , page = urlToPage url
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            ( { model | page = urlToPage url }
            , Cmd.none
            )
```

**Use when:**

- Building single-page applications
- Need URL routing
- Managing browser history

---

## Browser.Navigation

Navigation functions for controlling the browser URL and history.

### Key

```canopy
type Key
-- Opaque type representing navigation capability
```

The `Key` is provided when your app initializes and is required for navigation functions.

### Navigation Functions

```canopy
-- Push a URL onto the history stack
pushUrl : Key -> String -> Cmd msg

-- Replace the current URL
replaceUrl : Key -> String -> Cmd msg

-- Go back in history
back : Key -> Int -> Cmd msg

-- Go forward in history
forward : Key -> Int -> Cmd msg

-- Load a new page (full page load)
load : String -> Cmd msg

-- Reload the current page
reload : Cmd msg
```

**Example:**

```canopy
navigateToProfile : Key -> Int -> Cmd Msg
navigateToProfile key userId =
    Nav.pushUrl key ("/users/" ++ String.fromInt userId)


goBack : Key -> Cmd Msg
goBack key =
    Nav.back key 1
```

---

## Browser.Events

Subscribe to global browser events.

### Keyboard Events

```canopy
onKeyDown : Decoder msg -> Sub msg
onKeyUp : Decoder msg -> Sub msg
onKeyPress : Decoder msg -> Sub msg
```

**Example:**

```canopy
import Browser.Events
import Json.Decode as Decode


subscriptions : Model -> Sub Msg
subscriptions model =
    Browser.Events.onKeyDown keyDecoder


keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.field "key" Decode.string
        |> Decode.map KeyPressed


type Msg
    = KeyPressed String
```

### Mouse Events

```canopy
onClick : Decoder msg -> Sub msg
onMouseDown : Decoder msg -> Sub msg
onMouseUp : Decoder msg -> Sub msg
onMouseMove : Decoder msg -> Sub msg
```

### Window Events

```canopy
onResize : (Int -> Int -> msg) -> Sub msg
onVisibilityChange : (Visibility -> msg) -> Sub msg


type Visibility
    = Visible
    | Hidden
```

**Example:**

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onResize WindowResized
        , Browser.Events.onVisibilityChange VisibilityChanged
        ]


type Msg
    = WindowResized Int Int
    | VisibilityChanged Browser.Events.Visibility
```

### Animation

```canopy
onAnimationFrame : (Time.Posix -> msg) -> Sub msg
onAnimationFrameDelta : (Float -> msg) -> Sub msg
```

**Example:**

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.isAnimating then
        Browser.Events.onAnimationFrameDelta AnimationFrame
    else
        Sub.none


type Msg
    = AnimationFrame Float  -- Delta time in milliseconds
```

---

## Browser.Dom

Interact with the DOM.

### Focus

```canopy
focus : String -> Task Error ()
blur : String -> Task Error ()
```

**Example:**

```canopy
focusInput : Cmd Msg
focusInput =
    Task.attempt FocusResult (Browser.Dom.focus "search-input")
```

### Scroll

```canopy
getViewport : Task x Viewport
getViewportOf : String -> Task Error Viewport

setViewport : Float -> Float -> Task x ()
setViewportOf : String -> Float -> Float -> Task Error ()

getElement : String -> Task Error Element
```

**Types:**

```canopy
type alias Viewport =
    { scene : { width : Float, height : Float }
    , viewport : { x : Float, y : Float, width : Float, height : Float }
    }


type alias Element =
    { scene : { width : Float, height : Float }
    , viewport : { x : Float, y : Float, width : Float, height : Float }
    , element : { x : Float, y : Float, width : Float, height : Float }
    }
```

**Example:**

```canopy
scrollToTop : Cmd Msg
scrollToTop =
    Task.perform (\_ -> NoOp) (Browser.Dom.setViewport 0 0)


getElementPosition : String -> Cmd Msg
getElementPosition id =
    Task.attempt GotElement (Browser.Dom.getElement id)
```

---

## URL Parsing

Parse URLs into structured data.

### Url

```canopy
type alias Url =
    { protocol : Protocol
    , host : String
    , port_ : Maybe Int
    , path : String
    , query : Maybe String
    , fragment : Maybe String
    }


type Protocol
    = Http
    | Https
```

### Url.Parser

Build URL parsers for routing.

```canopy
import Url.Parser exposing (Parser, (</>), int, map, oneOf, s, string, top)


type Route
    = Home
    | Profile String
    | Post Int
    | NotFound


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ map Home top
        , map Profile (s "users" </> string)
        , map Post (s "posts" </> int)
        ]


urlToRoute : Url -> Route
urlToRoute url =
    Maybe.withDefault NotFound (Url.Parser.parse routeParser url)
```

### Url.Builder

Build URLs safely.

```canopy
import Url.Builder as Url


-- Absolute path
Url.absolute [ "users", "123" ] []
-- "/users/123"

-- With query parameters
Url.absolute [ "search" ]
    [ Url.string "q" "canopy"
    , Url.int "page" 1
    ]
-- "/search?q=canopy&page=1"

-- Cross-origin URL
Url.crossOrigin "https://api.example.com"
    [ "users" ]
    [ Url.string "token" "abc123" ]
-- "https://api.example.com/users?token=abc123"
```
