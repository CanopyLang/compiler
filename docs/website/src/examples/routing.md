# Routing Example

Single-page application routing with URL parsing and navigation.

## Complete Routing Example

```canopy
module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html exposing (Html, a, div, h1, h2, li, nav, p, text, ul)
import Html.Attributes exposing (class, href)
import Url
import Url.Parser as Parser exposing ((</>), Parser)


-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = view
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }


-- MODEL


type alias Model =
    { key : Nav.Key
    , route : Route
    }


type Route
    = Home
    | About
    | Users
    | User String
    | Post Int
    | Settings
    | NotFound


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    ( { key = key
      , route = urlToRoute url
      }
    , Cmd.none
    )


-- URL PARSING


routeParser : Parser (Route -> a) a
routeParser =
    Parser.oneOf
        [ Parser.map Home Parser.top
        , Parser.map About (Parser.s "about")
        , Parser.map Users (Parser.s "users")
        , Parser.map User (Parser.s "users" </> Parser.string)
        , Parser.map Post (Parser.s "posts" </> Parser.int)
        , Parser.map Settings (Parser.s "settings")
        ]


urlToRoute : Url.Url -> Route
urlToRoute url =
    Maybe.withDefault NotFound (Parser.parse routeParser url)


-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                Browser.External href ->
                    ( model
                    , Nav.load href
                    )

        UrlChanged url ->
            ( { model | route = urlToRoute url }
            , Cmd.none
            )


-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = routeToTitle model.route
    , body =
        [ div [ class "app" ]
            [ viewNav model.route
            , viewPage model.route
            ]
        ]
    }


routeToTitle : Route -> String
routeToTitle route =
    case route of
        Home ->
            "Home - My App"

        About ->
            "About - My App"

        Users ->
            "Users - My App"

        User username ->
            username ++ " - My App"

        Post id ->
            "Post " ++ String.fromInt id ++ " - My App"

        Settings ->
            "Settings - My App"

        NotFound ->
            "Not Found - My App"


viewNav : Route -> Html Msg
viewNav currentRoute =
    nav [ class "main-nav" ]
        [ ul []
            [ viewNavLink Home "/" "Home" currentRoute
            , viewNavLink About "/about" "About" currentRoute
            , viewNavLink Users "/users" "Users" currentRoute
            , viewNavLink Settings "/settings" "Settings" currentRoute
            ]
        ]


viewNavLink : Route -> String -> String -> Route -> Html Msg
viewNavLink route path label currentRoute =
    li
        [ class
            (if route == currentRoute then
                "active"

             else
                ""
            )
        ]
        [ a [ href path ] [ text label ]
        ]


viewPage : Route -> Html Msg
viewPage route =
    div [ class "page" ]
        (case route of
            Home ->
                viewHome

            About ->
                viewAbout

            Users ->
                viewUsers

            User username ->
                viewUser username

            Post id ->
                viewPost id

            Settings ->
                viewSettings

            NotFound ->
                viewNotFound
        )


viewHome : List (Html Msg)
viewHome =
    [ h1 [] [ text "Welcome to My App" ]
    , p [] [ text "This is the home page." ]
    , p []
        [ text "Try visiting some pages: "
        , a [ href "/users/alice" ] [ text "Alice's profile" ]
        , text " or "
        , a [ href "/posts/42" ] [ text "Post #42" ]
        ]
    ]


viewAbout : List (Html Msg)
viewAbout =
    [ h1 [] [ text "About" ]
    , p [] [ text "This is a Canopy application demonstrating routing." ]
    ]


viewUsers : List (Html Msg)
viewUsers =
    [ h1 [] [ text "Users" ]
    , ul [ class "user-list" ]
        [ li [] [ a [ href "/users/alice" ] [ text "Alice" ] ]
        , li [] [ a [ href "/users/bob" ] [ text "Bob" ] ]
        , li [] [ a [ href "/users/charlie" ] [ text "Charlie" ] ]
        ]
    ]


viewUser : String -> List (Html Msg)
viewUser username =
    [ h1 [] [ text ("User: " ++ username) ]
    , p [] [ text ("Viewing profile for " ++ username) ]
    , a [ href "/users" ] [ text "Back to users" ]
    ]


viewPost : Int -> List (Html Msg)
viewPost id =
    [ h1 [] [ text ("Post #" ++ String.fromInt id) ]
    , p [] [ text ("This is post number " ++ String.fromInt id) ]
    , div [ class "post-nav" ]
        [ if id > 1 then
            a [ href ("/posts/" ++ String.fromInt (id - 1)) ] [ text "Previous" ]

          else
            text ""
        , a [ href ("/posts/" ++ String.fromInt (id + 1)) ] [ text "Next" ]
        ]
    ]


viewSettings : List (Html Msg)
viewSettings =
    [ h1 [] [ text "Settings" ]
    , p [] [ text "Configure your preferences here." ]
    ]


viewNotFound : List (Html Msg)
viewNotFound =
    [ h1 [] [ text "404 - Not Found" ]
    , p [] [ text "The page you're looking for doesn't exist." ]
    , a [ href "/" ] [ text "Go home" ]
    ]
```

## URL Parser Patterns

### Basic Routes

```canopy
Parser.oneOf
    [ Parser.map Home Parser.top           -- "/"
    , Parser.map About (Parser.s "about")  -- "/about"
    ]
```

### Route Parameters

```canopy
-- String parameter: /users/:username
Parser.map User (Parser.s "users" </> Parser.string)

-- Int parameter: /posts/:id
Parser.map Post (Parser.s "posts" </> Parser.int)

-- Multiple parameters: /users/:username/posts/:id
Parser.map UserPost (Parser.s "users" </> Parser.string </> Parser.s "posts" </> Parser.int)
```

### Query Parameters

```canopy
import Url.Parser.Query as Query


type Route
    = Search (Maybe String) (Maybe Int)


searchParser : Parser (Route -> a) a
searchParser =
    Parser.map Search
        (Parser.s "search"
            <?> Query.string "q"
            <?> Query.int "page"
        )


-- Parses: /search?q=canopy&page=2
```

### Custom Parsers

```canopy
-- Parse a UUID
uuid : Parser (String -> a) a
uuid =
    Parser.custom "UUID" <|
        \segment ->
            if isValidUuid segment then
                Just segment

            else
                Nothing


-- Usage
Parser.map Document (Parser.s "docs" </> uuid)
```

## Route with Loading Data

```canopy
type Route
    = Home
    | UserProfile String UserProfileData
    | NotFound


type UserProfileData
    = Loading
    | Loaded User
    | Failed String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChanged url ->
            let
                route =
                    urlToRoute url
            in
            case route of
                UserProfile username Loading ->
                    ( { model | route = route }
                    , fetchUser username
                    )

                _ ->
                    ( { model | route = route }
                    , Cmd.none
                    )

        GotUser username result ->
            case result of
                Ok user ->
                    ( { model | route = UserProfile username (Loaded user) }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | route = UserProfile username (Failed (httpErrorToString error)) }
                    , Cmd.none
                    )
```

## Protected Routes

```canopy
type alias Model =
    { route : Route
    , user : Maybe User
    , key : Nav.Key
    }


update msg model =
    case msg of
        UrlChanged url ->
            let
                route = urlToRoute url
            in
            if requiresAuth route && model.user == Nothing then
                -- Redirect to login
                ( model
                , Nav.replaceUrl model.key ("/login?redirect=" ++ Url.toString url)
                )

            else
                ( { model | route = route }, Cmd.none )


requiresAuth : Route -> Bool
requiresAuth route =
    case route of
        Settings ->
            True

        Profile _ ->
            True

        _ ->
            False
```

## Building URLs

```canopy
import Url.Builder as Builder


-- Build path URLs
userUrl : String -> String
userUrl username =
    Builder.absolute [ "users", username ] []
-- "/users/alice"


-- Build with query parameters
searchUrl : String -> Int -> String
searchUrl query page =
    Builder.absolute [ "search" ]
        [ Builder.string "q" query
        , Builder.int "page" page
        ]
-- "/search?q=canopy&page=2"


-- Build external URLs
apiUrl : String -> List Builder.QueryParameter -> String
apiUrl path params =
    Builder.crossOrigin "https://api.example.com"
        (String.split "/" path)
        params
```

## Styling

```css
.app {
    max-width: 800px;
    margin: 0 auto;
    padding: 1rem;
}

.main-nav {
    border-bottom: 1px solid #ddd;
    margin-bottom: 2rem;
}

.main-nav ul {
    display: flex;
    gap: 1rem;
    list-style: none;
    padding: 0;
    margin: 0;
}

.main-nav a {
    display: block;
    padding: 0.75rem 1rem;
    color: #333;
    text-decoration: none;
    border-radius: 4px;
}

.main-nav a:hover {
    background: #f5f5f5;
}

.main-nav li.active a {
    background: #4a90d9;
    color: white;
}

.page {
    padding: 1rem 0;
}

.user-list {
    list-style: none;
    padding: 0;
}

.user-list li {
    padding: 0.5rem 0;
}

.post-nav {
    display: flex;
    gap: 1rem;
    margin-top: 2rem;
}
```

## Key Concepts

1. **Browser.application**: Full control over URL and navigation
2. **Nav.Key**: Required for programmatic navigation
3. **Url.Parser**: Type-safe URL parsing
4. **Document title**: Dynamic page titles based on route
5. **Internal vs External links**: Handle both navigation types
