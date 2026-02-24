# HTTP Requests

Canopy provides a type-safe way to make HTTP requests. All network operations are handled through commands, ensuring predictable side effects.

## Making GET Requests

### Basic GET Request

```canopy
import Http
import Json.Decode as Decode


type Msg
    = GotQuote (Result Http.Error String)


getQuote : Cmd Msg
getQuote =
    Http.get
        { url = "https://api.example.com/quote"
        , expect = Http.expectString GotQuote
        }
```

### GET with JSON

```canopy
type alias User =
    { id : Int
    , name : String
    , email : String
    }


userDecoder : Decode.Decoder User
userDecoder =
    Decode.map3 User
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "email" Decode.string)


type Msg
    = GotUser (Result Http.Error User)


getUser : Int -> Cmd Msg
getUser userId =
    Http.get
        { url = "https://api.example.com/users/" ++ String.fromInt userId
        , expect = Http.expectJson GotUser userDecoder
        }
```

### GET with Query Parameters

```canopy
import Url.Builder as Url


searchUsers : String -> Int -> Cmd Msg
searchUsers query page =
    Http.get
        { url =
            Url.crossOrigin "https://api.example.com"
                [ "users", "search" ]
                [ Url.string "q" query
                , Url.int "page" page
                , Url.int "limit" 20
                ]
        , expect = Http.expectJson GotUsers usersDecoder
        }
```

## Making POST Requests

### POST with JSON Body

```canopy
import Json.Encode as Encode


type Msg
    = UserCreated (Result Http.Error User)


createUser : String -> String -> Cmd Msg
createUser name email =
    Http.post
        { url = "https://api.example.com/users"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "name", Encode.string name )
                    , ( "email", Encode.string email )
                    ]
                )
        , expect = Http.expectJson UserCreated userDecoder
        }
```

### POST with Form Data

```canopy
login : String -> String -> Cmd Msg
login username password =
    Http.post
        { url = "/login"
        , body =
            Http.stringBody "application/x-www-form-urlencoded"
                ("username=" ++ username ++ "&password=" ++ password)
        , expect = Http.expectJson LoggedIn sessionDecoder
        }
```

## Other HTTP Methods

### PUT Request

```canopy
updateUser : User -> Cmd Msg
updateUser user =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "https://api.example.com/users/" ++ String.fromInt user.id
        , body = Http.jsonBody (encodeUser user)
        , expect = Http.expectJson UserUpdated userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

### DELETE Request

```canopy
deleteUser : Int -> Cmd Msg
deleteUser userId =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "https://api.example.com/users/" ++ String.fromInt userId
        , body = Http.emptyBody
        , expect = Http.expectWhatever UserDeleted
        , timeout = Nothing
        , tracker = Nothing
        }
```

### PATCH Request

```canopy
updateUserName : Int -> String -> Cmd Msg
updateUserName userId newName =
    Http.request
        { method = "PATCH"
        , headers = []
        , url = "https://api.example.com/users/" ++ String.fromInt userId
        , body =
            Http.jsonBody
                (Encode.object [ ( "name", Encode.string newName ) ])
        , expect = Http.expectJson UserUpdated userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

## Headers and Authentication

### Adding Headers

```canopy
authenticatedGet : String -> String -> Cmd Msg
authenticatedGet token url =
    Http.request
        { method = "GET"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ token)
            , Http.header "Accept" "application/json"
            ]
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson GotData dataDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

### Custom Headers Helper

```canopy
type alias AuthConfig =
    { token : String
    , apiKey : String
    }


authHeaders : AuthConfig -> List Http.Header
authHeaders config =
    [ Http.header "Authorization" ("Bearer " ++ config.token)
    , Http.header "X-API-Key" config.apiKey
    , Http.header "Accept" "application/json"
    ]


fetchWithAuth : AuthConfig -> String -> Cmd Msg
fetchWithAuth config url =
    Http.request
        { method = "GET"
        , headers = authHeaders config
        , url = url
        , body = Http.emptyBody
        , expect = Http.expectJson GotData dataDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
```

## Error Handling

### Http.Error Type

```canopy
type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Int
    | BadBody String
```

### Handling Errors

```canopy
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotUser result ->
            case result of
                Ok user ->
                    ( { model | user = Just user, loading = False }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | error = Just (httpErrorToString error), loading = False }
                    , Cmd.none
                    )


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "Invalid URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error - check your connection"

        Http.BadStatus status ->
            "Server error: " ++ String.fromInt status

        Http.BadBody message ->
            "Invalid response: " ++ message
```

### Detailed Error Handling

```canopy
type ApiError
    = NotFound
    | Unauthorized
    | Forbidden
    | ServerError Int
    | ParseError String
    | OtherError String


handleHttpError : Http.Error -> ApiError
handleHttpError error =
    case error of
        Http.BadStatus 404 ->
            NotFound

        Http.BadStatus 401 ->
            Unauthorized

        Http.BadStatus 403 ->
            Forbidden

        Http.BadStatus status ->
            if status >= 500 then
                ServerError status
            else
                OtherError ("HTTP " ++ String.fromInt status)

        Http.BadBody message ->
            ParseError message

        Http.Timeout ->
            OtherError "Request timed out"

        Http.NetworkError ->
            OtherError "Network error"

        Http.BadUrl url ->
            OtherError ("Invalid URL: " ++ url)
```

## Timeouts and Tracking

### Setting Timeouts

```canopy
getWithTimeout : Cmd Msg
getWithTimeout =
    Http.request
        { method = "GET"
        , headers = []
        , url = "https://api.example.com/data"
        , body = Http.emptyBody
        , expect = Http.expectJson GotData dataDecoder
        , timeout = Just 5000  -- 5 seconds
        , tracker = Nothing
        }
```

### Tracking Progress

For large uploads or downloads:

```canopy
type Msg
    = GotProgress Http.Progress
    | UploadComplete (Result Http.Error ())


uploadFile : File -> Cmd Msg
uploadFile file =
    Http.request
        { method = "POST"
        , headers = []
        , url = "/upload"
        , body = Http.fileBody file
        , expect = Http.expectWhatever UploadComplete
        , timeout = Nothing
        , tracker = Just "upload"
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    Http.track "upload" GotProgress


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotProgress progress ->
            case progress of
                Http.Sending { sent, size } ->
                    ( { model | uploadProgress = toFloat sent / toFloat size }
                    , Cmd.none
                    )

                Http.Receiving { received, size } ->
                    case size of
                        Just total ->
                            ( { model | downloadProgress = toFloat received / toFloat total }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )
```

## Canceling Requests

```canopy
cancelUpload : Cmd Msg
cancelUpload =
    Http.cancel "upload"
```

## Expect Options

Different ways to handle responses:

```canopy
-- Expect a string
Http.expectString : (Result Http.Error String -> msg) -> Http.Expect msg

-- Expect JSON
Http.expectJson : (Result Http.Error a -> msg) -> Decoder a -> Http.Expect msg

-- Expect bytes
Http.expectBytes : (Result Http.Error Bytes -> msg) -> Http.Expect msg

-- Ignore the response body
Http.expectWhatever : (Result Http.Error () -> msg) -> Http.Expect msg

-- Custom response handling
Http.expectStringResponse : (Result x a -> msg) -> (Http.Response String -> Result x a) -> Http.Expect msg
```

### Custom Response Handling

```canopy
type alias ApiResponse a =
    { data : a
    , meta : Meta
    }


expectApiResponse : Decoder a -> (Result ApiError a -> msg) -> Http.Expect msg
expectApiResponse decoder toMsg =
    Http.expectStringResponse toMsg (handleApiResponse decoder)


handleApiResponse : Decoder a -> Http.Response String -> Result ApiError a
handleApiResponse decoder response =
    case response of
        Http.BadUrl_ url ->
            Err (OtherError ("Bad URL: " ++ url))

        Http.Timeout_ ->
            Err (OtherError "Timeout")

        Http.NetworkError_ ->
            Err (OtherError "Network error")

        Http.BadStatus_ metadata _ ->
            Err (handleBadStatus metadata.statusCode)

        Http.GoodStatus_ _ body ->
            case Decode.decodeString (Decode.field "data" decoder) body of
                Ok data ->
                    Ok data

                Err err ->
                    Err (ParseError (Decode.errorToString err))


handleBadStatus : Int -> ApiError
handleBadStatus status =
    case status of
        404 -> NotFound
        401 -> Unauthorized
        403 -> Forbidden
        _ -> ServerError status
```

## Building an API Module

Organize HTTP calls in a dedicated module:

```canopy
-- src/Api/User.can
module Api.User exposing
    ( getUser
    , getUsers
    , createUser
    , updateUser
    , deleteUser
    )

import Http
import Json.Decode as Decode
import Json.Encode as Encode


baseUrl : String
baseUrl =
    "https://api.example.com"


getUser : Int -> (Result Http.Error User -> msg) -> Cmd msg
getUser userId toMsg =
    Http.get
        { url = baseUrl ++ "/users/" ++ String.fromInt userId
        , expect = Http.expectJson toMsg userDecoder
        }


getUsers : (Result Http.Error (List User) -> msg) -> Cmd msg
getUsers toMsg =
    Http.get
        { url = baseUrl ++ "/users"
        , expect = Http.expectJson toMsg (Decode.list userDecoder)
        }


createUser : NewUser -> (Result Http.Error User -> msg) -> Cmd msg
createUser newUser toMsg =
    Http.post
        { url = baseUrl ++ "/users"
        , body = Http.jsonBody (encodeNewUser newUser)
        , expect = Http.expectJson toMsg userDecoder
        }


updateUser : User -> (Result Http.Error User -> msg) -> Cmd msg
updateUser user toMsg =
    Http.request
        { method = "PUT"
        , headers = []
        , url = baseUrl ++ "/users/" ++ String.fromInt user.id
        , body = Http.jsonBody (encodeUser user)
        , expect = Http.expectJson toMsg userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


deleteUser : Int -> (Result Http.Error () -> msg) -> Cmd msg
deleteUser userId toMsg =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = baseUrl ++ "/users/" ++ String.fromInt userId
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
```

## Best Practices

### 1. Always Handle Errors

```canopy
-- Don't ignore errors
case result of
    Ok data -> ...
    Err _ -> model  -- Bad! Handle the error

-- Handle errors properly
case result of
    Ok data -> { model | data = data }
    Err error -> { model | error = Just (httpErrorToString error) }
```

### 2. Show Loading States

```canopy
type alias Model =
    { users : List User
    , loading : Bool
    , error : Maybe String
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FetchUsers ->
            ( { model | loading = True, error = Nothing }
            , getUsers
            )

        GotUsers result ->
            case result of
                Ok users ->
                    ( { model | users = users, loading = False }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | loading = False, error = Just (httpErrorToString error) }
                    , Cmd.none
                    )
```

### 3. Use RemoteData Pattern

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
            button [ onClick FetchUsers ] [ text "Load Users" ]

        Loading ->
            div [] [ text "Loading..." ]

        Failure error ->
            div [ class "error" ] [ text (httpErrorToString error) ]

        Success users ->
            viewUsers users
```

## Next Steps

- **[Commands and Subscriptions](./commands.md)**: More about side effects
- **[JSON](./json.md)**: Complex JSON decoding
- **[Error Handling](./error-handling.md)**: Advanced error patterns
