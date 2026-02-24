# HTTP Example

Fetch data from an API and display it with proper loading and error states.

## Basic API Fetch

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, h1, img, p, text)
import Html.Attributes exposing (class, src)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode exposing (Decoder)


-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = view
        }


-- MODEL


type alias Model =
    { quote : RemoteData String Quote
    }


type RemoteData e a
    = NotAsked
    | Loading
    | Failure e
    | Success a


type alias Quote =
    { content : String
    , author : String
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { quote = NotAsked }
    , Cmd.none
    )


-- UPDATE


type Msg
    = FetchQuote
    | GotQuote (Result Http.Error Quote)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FetchQuote ->
            ( { model | quote = Loading }
            , fetchQuote
            )

        GotQuote result ->
            case result of
                Ok quote ->
                    ( { model | quote = Success quote }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | quote = Failure (httpErrorToString error) }
                    , Cmd.none
                    )


fetchQuote : Cmd Msg
fetchQuote =
    Http.get
        { url = "https://api.quotable.io/random"
        , expect = Http.expectJson GotQuote quoteDecoder
        }


quoteDecoder : Decoder Quote
quoteDecoder =
    Decode.map2 Quote
        (Decode.field "content" Decode.string)
        (Decode.field "author" Decode.string)


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error - check your connection"

        Http.BadStatus status ->
            "Server error: " ++ String.fromInt status

        Http.BadBody message ->
            "Invalid response: " ++ message


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "quote-app" ]
        [ h1 [] [ text "Random Quote" ]
        , viewQuote model.quote
        , button [ onClick FetchQuote ] [ text "Get Quote" ]
        ]


viewQuote : RemoteData String Quote -> Html Msg
viewQuote remoteQuote =
    case remoteQuote of
        NotAsked ->
            p [ class "hint" ] [ text "Click the button to get a quote!" ]

        Loading ->
            div [ class "loading" ] [ text "Loading..." ]

        Failure error ->
            div [ class "error" ]
                [ p [] [ text "Something went wrong:" ]
                , p [] [ text error ]
                ]

        Success quote ->
            div [ class "quote" ]
                [ p [ class "content" ] [ text ("\"" ++ quote.content ++ "\"") ]
                , p [ class "author" ] [ text ("— " ++ quote.author) ]
                ]
```

## Fetching a List

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, div, h1, li, text, ul)
import Html.Attributes exposing (class)
import Http
import Json.Decode as Decode exposing (Decoder)


-- MODEL


type alias Model =
    { users : RemoteData (List User)
    }


type RemoteData a
    = Loading
    | Failure String
    | Success a


type alias User =
    { id : Int
    , name : String
    , email : String
    , company : String
    }


-- INIT


init : () -> ( Model, Cmd Msg )
init _ =
    ( { users = Loading }
    , fetchUsers
    )


-- UPDATE


type Msg
    = GotUsers (Result Http.Error (List User))


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotUsers result ->
            case result of
                Ok users ->
                    ( { model | users = Success users }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | users = Failure (httpErrorToString error) }
                    , Cmd.none
                    )


-- HTTP


fetchUsers : Cmd Msg
fetchUsers =
    Http.get
        { url = "https://jsonplaceholder.typicode.com/users"
        , expect = Http.expectJson GotUsers (Decode.list userDecoder)
        }


userDecoder : Decoder User
userDecoder =
    Decode.map4 User
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.at [ "company", "name" ] Decode.string)


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "users-app" ]
        [ h1 [] [ text "Users" ]
        , viewUsers model.users
        ]


viewUsers : RemoteData (List User) -> Html Msg
viewUsers remoteUsers =
    case remoteUsers of
        Loading ->
            div [ class "loading" ] [ text "Loading users..." ]

        Failure error ->
            div [ class "error" ] [ text error ]

        Success users ->
            ul [ class "user-list" ]
                (List.map viewUser users)


viewUser : User -> Html Msg
viewUser user =
    li [ class "user" ]
        [ div [ class "name" ] [ text user.name ]
        , div [ class "email" ] [ text user.email ]
        , div [ class "company" ] [ text user.company ]
        ]
```

## POST Request with Form

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, form, h1, input, label, p, text)
import Html.Attributes exposing (class, disabled, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Http
import Json.Decode as Decode
import Json.Encode as Encode


-- MODEL


type alias Model =
    { name : String
    , email : String
    , status : FormStatus
    }


type FormStatus
    = Idle
    | Submitting
    | Success String
    | Error String


init : () -> ( Model, Cmd Msg )
init _ =
    ( { name = ""
      , email = ""
      , status = Idle
      }
    , Cmd.none
    )


-- UPDATE


type Msg
    = UpdateName String
    | UpdateEmail String
    | Submit
    | GotResponse (Result Http.Error String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateName name ->
            ( { model | name = name }, Cmd.none )

        UpdateEmail email ->
            ( { model | email = email }, Cmd.none )

        Submit ->
            ( { model | status = Submitting }
            , submitForm model
            )

        GotResponse result ->
            case result of
                Ok message ->
                    ( { model
                        | status = Success message
                        , name = ""
                        , email = ""
                      }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | status = Error (httpErrorToString error) }
                    , Cmd.none
                    )


submitForm : Model -> Cmd Msg
submitForm model =
    Http.post
        { url = "https://jsonplaceholder.typicode.com/users"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "name", Encode.string model.name )
                    , ( "email", Encode.string model.email )
                    ]
                )
        , expect = Http.expectJson GotResponse responseDecoder
        }


responseDecoder : Decode.Decoder String
responseDecoder =
    Decode.field "id" Decode.int
        |> Decode.map (\id -> "User created with ID: " ++ String.fromInt id)


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "form-app" ]
        [ h1 [] [ text "Create User" ]
        , viewForm model
        , viewStatus model.status
        ]


viewForm : Model -> Html Msg
viewForm model =
    let
        isSubmitting =
            model.status == Submitting
    in
    form [ onSubmit Submit, class "user-form" ]
        [ div [ class "field" ]
            [ label [] [ text "Name" ]
            , input
                [ type_ "text"
                , value model.name
                , onInput UpdateName
                , disabled isSubmitting
                ]
                []
            ]
        , div [ class "field" ]
            [ label [] [ text "Email" ]
            , input
                [ type_ "email"
                , value model.email
                , onInput UpdateEmail
                , disabled isSubmitting
                ]
                []
            ]
        , button
            [ type_ "submit"
            , disabled (isSubmitting || String.isEmpty model.name || String.isEmpty model.email)
            ]
            [ text
                (if isSubmitting then
                    "Submitting..."

                 else
                    "Create User"
                )
            ]
        ]


viewStatus : FormStatus -> Html Msg
viewStatus status =
    case status of
        Idle ->
            text ""

        Submitting ->
            text ""

        Success message ->
            p [ class "success" ] [ text message ]

        Error message ->
            p [ class "error" ] [ text message ]
```

## Using Do-Notation for Complex Requests

```canopy
-- Fetch user and their posts
fetchUserWithPosts : Int -> Task Http.Error UserWithPosts
fetchUserWithPosts userId = do
    user <- fetchUser userId
    posts <- fetchPostsByUser userId
    pure { user = user, posts = posts }


-- In update
update msg model =
    case msg of
        LoadUserData userId ->
            ( { model | userData = Loading }
            , Task.attempt GotUserData (fetchUserWithPosts userId)
            )

        GotUserData result ->
            case result of
                Ok data ->
                    ( { model | userData = Success data }, Cmd.none )

                Err error ->
                    ( { model | userData = Failure error }, Cmd.none )
```

## Key Patterns

### RemoteData Pattern

Always model async data with all states:

```canopy
type RemoteData e a
    = NotAsked     -- Haven't started
    | Loading      -- In progress
    | Failure e    -- Failed with error
    | Success a    -- Succeeded with value
```

### Error Display

```canopy
httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "Invalid URL: " ++ url

        Http.Timeout ->
            "The request timed out. Please try again."

        Http.NetworkError ->
            "Unable to connect. Check your internet connection."

        Http.BadStatus 404 ->
            "Not found."

        Http.BadStatus 401 ->
            "Please log in to continue."

        Http.BadStatus 403 ->
            "You don't have permission to access this."

        Http.BadStatus status ->
            "Server error (" ++ String.fromInt status ++ ")"

        Http.BadBody message ->
            "Unexpected response format."
```

### Retry on Error

```canopy
update msg model =
    case msg of
        GotData (Err error) ->
            if model.retryCount < 3 && isRetryable error then
                ( { model | retryCount = model.retryCount + 1 }
                , Process.sleep 1000
                    |> Task.andThen (\_ -> Task.succeed ())
                    |> Task.perform (\_ -> RetryFetch)
                )

            else
                ( { model | data = Failure error }, Cmd.none )
```
