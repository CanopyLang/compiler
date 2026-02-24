# Http Module

The Http module provides functions for making HTTP requests.

## Making Requests

### GET Request

```canopy
Http.get :
    { url : String
    , expect : Expect msg
    }
    -> Cmd msg
```

**Example:**

```canopy
fetchUser : Int -> Cmd Msg
fetchUser userId =
    Http.get
        { url = "/api/users/" ++ String.fromInt userId
        , expect = Http.expectJson GotUser userDecoder
        }
```

### POST Request

```canopy
Http.post :
    { url : String
    , body : Body
    , expect : Expect msg
    }
    -> Cmd msg
```

**Example:**

```canopy
createUser : NewUser -> Cmd Msg
createUser newUser =
    Http.post
        { url = "/api/users"
        , body = Http.jsonBody (encodeNewUser newUser)
        , expect = Http.expectJson UserCreated userDecoder
        }
```

### Custom Request

```canopy
Http.request :
    { method : String
    , headers : List Header
    , url : String
    , body : Body
    , expect : Expect msg
    , timeout : Maybe Float
    , tracker : Maybe String
    }
    -> Cmd msg
```

**Example:**

```canopy
updateUser : User -> Cmd Msg
updateUser user =
    Http.request
        { method = "PUT"
        , headers =
            [ Http.header "Authorization" ("Bearer " ++ token)
            ]
        , url = "/api/users/" ++ String.fromInt user.id
        , body = Http.jsonBody (encodeUser user)
        , expect = Http.expectJson UserUpdated userDecoder
        , timeout = Just 10000
        , tracker = Nothing
        }


deleteUser : Int -> Cmd Msg
deleteUser userId =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/users/" ++ String.fromInt userId
        , body = Http.emptyBody
        , expect = Http.expectWhatever UserDeleted
        , timeout = Nothing
        , tracker = Nothing
        }
```

---

## Request Body

```canopy
emptyBody : Body
-- No request body

stringBody : String -> String -> Body
-- stringBody mimeType content

jsonBody : Value -> Body
-- JSON body with application/json content type

fileBody : File -> Body
-- File upload body

bytesBody : String -> Bytes -> Body
-- bytesBody mimeType bytes

multipartBody : List Part -> Body
-- Multipart form data
```

**Examples:**

```canopy
-- JSON body
Http.jsonBody
    (Encode.object
        [ ( "name", Encode.string "Alice" )
        , ( "email", Encode.string "alice@example.com" )
        ]
    )


-- Form data
Http.stringBody "application/x-www-form-urlencoded"
    "username=alice&password=secret"


-- Multipart (file upload)
Http.multipartBody
    [ Http.stringPart "description" "My photo"
    , Http.filePart "file" file
    ]
```

---

## Response Handling

### Expect Types

```canopy
expectString : (Result Error String -> msg) -> Expect msg
-- Expect response body as String

expectJson : (Result Error a -> msg) -> Decoder a -> Expect msg
-- Expect and decode JSON response

expectBytes : (Result Error Bytes -> msg) -> Expect msg
-- Expect response body as Bytes

expectWhatever : (Result Error () -> msg) -> Expect msg
-- Ignore response body

expectStringResponse :
    (Result x a -> msg)
    -> (Response String -> Result x a)
    -> Expect msg
-- Custom response handling
```

**Examples:**

```canopy
-- String response
Http.get
    { url = "/api/version"
    , expect = Http.expectString GotVersion
    }


-- JSON response
Http.get
    { url = "/api/users"
    , expect = Http.expectJson GotUsers (Decode.list userDecoder)
    }


-- Ignore body (just check status)
Http.request
    { method = "DELETE"
    , ...
    , expect = Http.expectWhatever Deleted
    }
```

### Custom Response Handling

```canopy
type alias ApiResponse a =
    { data : a
    , meta : Meta
    }


expectApiResponse : Decoder a -> (Result ApiError a -> msg) -> Expect msg
expectApiResponse decoder toMsg =
    Http.expectStringResponse toMsg (handleApiResponse decoder)


handleApiResponse : Decoder a -> Response String -> Result ApiError a
handleApiResponse decoder response =
    case response of
        Http.BadUrl_ url ->
            Err (BadUrl url)

        Http.Timeout_ ->
            Err Timeout

        Http.NetworkError_ ->
            Err NetworkError

        Http.BadStatus_ metadata body ->
            Err (BadStatus metadata.statusCode body)

        Http.GoodStatus_ metadata body ->
            case Decode.decodeString (Decode.field "data" decoder) body of
                Ok data ->
                    Ok data

                Err err ->
                    Err (ParseError (Decode.errorToString err))
```

---

## Error Handling

### Error Type

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
                    ( { model | user = Just user }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | error = Just (httpErrorToString error) }
                    , Cmd.none
                    )


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "Bad URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error"

        Http.BadStatus status ->
            "Server error: " ++ String.fromInt status

        Http.BadBody message ->
            "Invalid response: " ++ message
```

---

## Headers

```canopy
header : String -> String -> Header
```

**Example:**

```canopy
Http.request
    { method = "GET"
    , headers =
        [ Http.header "Authorization" "Bearer token123"
        , Http.header "Accept" "application/json"
        , Http.header "X-Custom-Header" "value"
        ]
    , ...
    }
```

---

## Progress Tracking

Track upload/download progress for large requests.

```canopy
-- Start a tracked request
Http.request
    { ...
    , tracker = Just "my-request"
    }


-- Subscribe to progress updates
subscriptions : Model -> Sub Msg
subscriptions model =
    Http.track "my-request" GotProgress


-- Handle progress
type Msg
    = GotProgress Http.Progress


update msg model =
    case msg of
        GotProgress progress ->
            case progress of
                Http.Sending { sent, size } ->
                    let
                        percent = toFloat sent / toFloat size
                    in
                    ( { model | uploadProgress = percent }
                    , Cmd.none
                    )

                Http.Receiving { received, size } ->
                    case size of
                        Just total ->
                            let
                                percent = toFloat received / toFloat total
                            in
                            ( { model | downloadProgress = percent }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )
```

---

## Cancellation

```canopy
Http.cancel : String -> Cmd msg
```

**Example:**

```canopy
-- Cancel a tracked request
cancelUpload : Cmd Msg
cancelUpload =
    Http.cancel "upload-tracker"
```

---

## Response Type

For custom response handling:

```canopy
type Response body
    = BadUrl_ String
    | Timeout_
    | NetworkError_
    | BadStatus_ Metadata body
    | GoodStatus_ Metadata body


type alias Metadata =
    { url : String
    , statusCode : Int
    , statusText : String
    , headers : Dict String String
    }
```

---

## Best Practices

### API Module Pattern

```canopy
module Api exposing (fetchUser, createUser, updateUser)

import Http
import Json.Decode as Decode
import Json.Encode as Encode


baseUrl : String
baseUrl =
    "https://api.example.com"


fetchUser : Int -> (Result Http.Error User -> msg) -> Cmd msg
fetchUser id toMsg =
    Http.get
        { url = baseUrl ++ "/users/" ++ String.fromInt id
        , expect = Http.expectJson toMsg userDecoder
        }


createUser : NewUser -> (Result Http.Error User -> msg) -> Cmd msg
createUser user toMsg =
    Http.post
        { url = baseUrl ++ "/users"
        , body = Http.jsonBody (encodeNewUser user)
        , expect = Http.expectJson toMsg userDecoder
        }
```

### Retry Logic

```canopy
fetchWithRetry : Int -> Cmd Msg
fetchWithRetry retries =
    Http.get
        { url = "/api/data"
        , expect = Http.expectJson (GotDataWithRetry retries) dataDecoder
        }


update msg model =
    case msg of
        GotDataWithRetry retries result ->
            case result of
                Ok data ->
                    ( { model | data = Just data }, Cmd.none )

                Err error ->
                    if retries > 0 && isRetryable error then
                        ( model, fetchWithRetry (retries - 1) )
                    else
                        ( { model | error = Just error }, Cmd.none )


isRetryable : Http.Error -> Bool
isRetryable error =
    case error of
        Http.Timeout ->
            True

        Http.NetworkError ->
            True

        Http.BadStatus status ->
            status >= 500

        _ ->
            False
```
