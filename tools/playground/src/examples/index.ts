import type { Example } from '../types';

export const EXAMPLES: Example[] = [
  {
    id: 'hello-world',
    name: 'Hello World',
    description: 'A simple greeting application',
    files: [
      {
        name: 'Main.can',
        language: 'canopy',
        content: `module Main exposing (..)

import Html exposing (Html, div, text, h1, p)
import Html.Attributes exposing (style)


-- | The main entry point for the application
main : Html msg
main =
    div
        [ style "padding" "2rem"
        , style "font-family" "system-ui, sans-serif"
        , style "max-width" "600px"
        , style "margin" "0 auto"
        ]
        [ h1 [] [ text "Hello, Canopy!" ]
        , p [] [ text "Welcome to the Canopy programming language." ]
        , p [] [ text "This is a type-safe, functional language for building web applications." ]
        ]
`,
      },
    ],
  },
  {
    id: 'counter',
    name: 'Counter',
    description: 'Interactive counter with state management',
    files: [
      {
        name: 'Main.can',
        language: 'canopy',
        content: `module Main exposing (..)

import Browser
import Html exposing (Html, div, button, text, h1)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)


-- MODEL

type alias Model =
    { count : Int
    }


init : Model
init =
    { count = 0 }


-- UPDATE

type Msg
    = Increment
    | Decrement
    | Reset


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        Decrement ->
            { model | count = model.count - 1 }

        Reset ->
            { model | count = 0 }


-- VIEW

view : Model -> Html Msg
view model =
    div
        [ style "padding" "2rem"
        , style "font-family" "system-ui, sans-serif"
        , style "text-align" "center"
        ]
        [ h1 [] [ text "Counter" ]
        , div
            [ style "font-size" "4rem"
            , style "margin" "2rem 0"
            ]
            [ text (String.fromInt model.count) ]
        , div [ style "display" "flex", style "gap" "1rem", style "justify-content" "center" ]
            [ button
                [ onClick Decrement
                , style "padding" "0.5rem 1.5rem"
                , style "font-size" "1.5rem"
                , style "cursor" "pointer"
                ]
                [ text "-" ]
            , button
                [ onClick Reset
                , style "padding" "0.5rem 1.5rem"
                , style "font-size" "1rem"
                , style "cursor" "pointer"
                ]
                [ text "Reset" ]
            , button
                [ onClick Increment
                , style "padding" "0.5rem 1.5rem"
                , style "font-size" "1.5rem"
                , style "cursor" "pointer"
                ]
                [ text "+" ]
            ]
        ]


-- MAIN

main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
`,
      },
    ],
  },
  {
    id: 'todo-app',
    name: 'Todo App',
    description: 'A simple todo list application',
    files: [
      {
        name: 'Main.can',
        language: 'canopy',
        content: `module Main exposing (..)

import Browser
import Html exposing (Html, div, input, button, text, h1, ul, li, span)
import Html.Attributes exposing (style, value, placeholder, type_, checked)
import Html.Events exposing (onClick, onInput, onSubmit)


-- MODEL

type alias Todo =
    { id : Int
    , text : String
    , completed : Bool
    }


type alias Model =
    { todos : List Todo
    , inputText : String
    , nextId : Int
    }


init : Model
init =
    { todos = []
    , inputText = ""
    , nextId = 1
    }


-- UPDATE

type Msg
    = UpdateInput String
    | AddTodo
    | ToggleTodo Int
    | DeleteTodo Int


update : Msg -> Model -> Model
update msg model =
    case msg of
        UpdateInput text ->
            { model | inputText = text }

        AddTodo ->
            if String.isEmpty (String.trim model.inputText) then
                model
            else
                { model
                    | todos = model.todos ++ [ newTodo model.nextId model.inputText ]
                    , inputText = ""
                    , nextId = model.nextId + 1
                }

        ToggleTodo id ->
            { model | todos = List.map (toggleIfMatch id) model.todos }

        DeleteTodo id ->
            { model | todos = List.filter (\\t -> t.id /= id) model.todos }


newTodo : Int -> String -> Todo
newTodo id text =
    { id = id
    , text = text
    , completed = False
    }


toggleIfMatch : Int -> Todo -> Todo
toggleIfMatch id todo =
    if todo.id == id then
        { todo | completed = not todo.completed }
    else
        todo


-- VIEW

view : Model -> Html Msg
view model =
    div
        [ style "padding" "2rem"
        , style "font-family" "system-ui, sans-serif"
        , style "max-width" "500px"
        , style "margin" "0 auto"
        ]
        [ h1 [] [ text "Todo List" ]
        , viewInput model.inputText
        , viewTodos model.todos
        , viewStats model.todos
        ]


viewInput : String -> Html Msg
viewInput inputText =
    div [ style "display" "flex", style "gap" "0.5rem", style "margin-bottom" "1rem" ]
        [ input
            [ type_ "text"
            , placeholder "What needs to be done?"
            , value inputText
            , onInput UpdateInput
            , style "flex" "1"
            , style "padding" "0.5rem"
            , style "font-size" "1rem"
            ]
            []
        , button
            [ onClick AddTodo
            , style "padding" "0.5rem 1rem"
            , style "cursor" "pointer"
            ]
            [ text "Add" ]
        ]


viewTodos : List Todo -> Html Msg
viewTodos todos =
    ul [ style "list-style" "none", style "padding" "0" ]
        (List.map viewTodo todos)


viewTodo : Todo -> Html Msg
viewTodo todo =
    li
        [ style "display" "flex"
        , style "align-items" "center"
        , style "padding" "0.5rem"
        , style "border-bottom" "1px solid #eee"
        ]
        [ input
            [ type_ "checkbox"
            , checked todo.completed
            , onClick (ToggleTodo todo.id)
            , style "margin-right" "0.5rem"
            ]
            []
        , span
            [ style "flex" "1"
            , style "text-decoration" (if todo.completed then "line-through" else "none")
            , style "color" (if todo.completed then "#999" else "inherit")
            ]
            [ text todo.text ]
        , button
            [ onClick (DeleteTodo todo.id)
            , style "background" "none"
            , style "border" "none"
            , style "color" "#e74c3c"
            , style "cursor" "pointer"
            ]
            [ text "x" ]
        ]


viewStats : List Todo -> Html msg
viewStats todos =
    let
        total = List.length todos
        completed = List.length (List.filter .completed todos)
        remaining = total - completed
    in
    div [ style "margin-top" "1rem", style "color" "#666" ]
        [ text (String.fromInt remaining ++ " items remaining") ]


-- MAIN

main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
`,
      },
    ],
  },
  {
    id: 'http-requests',
    name: 'HTTP Requests',
    description: 'Fetching data from an API',
    files: [
      {
        name: 'Main.can',
        language: 'canopy',
        content: `module Main exposing (..)

import Browser
import Html exposing (Html, div, button, text, h1, p, ul, li)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode exposing (Decoder)


-- MODEL

type alias User =
    { id : Int
    , name : String
    , email : String
    }


type Model
    = Loading
    | Failure String
    | Success (List User)


init : ( Model, Cmd Msg )
init =
    ( Loading, fetchUsers )


-- UPDATE

type Msg
    = GotUsers (Result Http.Error (List User))
    | Refresh


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotUsers result ->
            case result of
                Ok users ->
                    ( Success users, Cmd.none )

                Err error ->
                    ( Failure (httpErrorToString error), Cmd.none )

        Refresh ->
            ( Loading, fetchUsers )


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


-- HTTP

fetchUsers : Cmd Msg
fetchUsers =
    Http.get
        { url = "https://jsonplaceholder.typicode.com/users"
        , expect = Http.expectJson GotUsers usersDecoder
        }


usersDecoder : Decoder (List User)
usersDecoder =
    Decode.list userDecoder


userDecoder : Decoder User
userDecoder =
    Decode.map3 User
        (Decode.field "id" Decode.int)
        (Decode.field "name" Decode.string)
        (Decode.field "email" Decode.string)


-- VIEW

view : Model -> Html Msg
view model =
    div
        [ style "padding" "2rem"
        , style "font-family" "system-ui, sans-serif"
        , style "max-width" "600px"
        , style "margin" "0 auto"
        ]
        [ h1 [] [ text "Users from API" ]
        , viewContent model
        ]


viewContent : Model -> Html Msg
viewContent model =
    case model of
        Loading ->
            div [ style "text-align" "center", style "padding" "2rem" ]
                [ text "Loading..." ]

        Failure errorMsg ->
            div []
                [ p [ style "color" "#e74c3c" ] [ text errorMsg ]
                , button [ onClick Refresh ] [ text "Try Again" ]
                ]

        Success users ->
            div []
                [ button
                    [ onClick Refresh
                    , style "margin-bottom" "1rem"
                    ]
                    [ text "Refresh" ]
                , ul [ style "list-style" "none", style "padding" "0" ]
                    (List.map viewUser users)
                ]


viewUser : User -> Html msg
viewUser user =
    li
        [ style "padding" "1rem"
        , style "border" "1px solid #eee"
        , style "margin-bottom" "0.5rem"
        , style "border-radius" "4px"
        ]
        [ div [ style "font-weight" "bold" ] [ text user.name ]
        , div [ style "color" "#666" ] [ text user.email ]
        ]


-- MAIN

main : Program () Model Msg
main =
    Browser.element
        { init = \\_ -> init
        , update = update
        , view = view
        , subscriptions = \\_ -> Sub.none
        }
`,
      },
    ],
  },
  {
    id: 'json-decoding',
    name: 'JSON Decoding',
    description: 'Parsing and working with JSON data',
    files: [
      {
        name: 'Main.can',
        language: 'canopy',
        content: `module Main exposing (..)

import Html exposing (Html, div, text, h1, h2, pre, code)
import Html.Attributes exposing (style)
import Json.Decode as Decode exposing (Decoder)


-- TYPES

type alias Person =
    { name : String
    , age : Int
    , email : Maybe String
    , hobbies : List String
    }


type alias Address =
    { street : String
    , city : String
    , zipCode : String
    }


type alias Profile =
    { person : Person
    , address : Address
    }


-- DECODERS

personDecoder : Decoder Person
personDecoder =
    Decode.map4 Person
        (Decode.field "name" Decode.string)
        (Decode.field "age" Decode.int)
        (Decode.maybe (Decode.field "email" Decode.string))
        (Decode.field "hobbies" (Decode.list Decode.string))


addressDecoder : Decoder Address
addressDecoder =
    Decode.map3 Address
        (Decode.field "street" Decode.string)
        (Decode.field "city" Decode.string)
        (Decode.field "zipCode" Decode.string)


profileDecoder : Decoder Profile
profileDecoder =
    Decode.map2 Profile
        (Decode.field "person" personDecoder)
        (Decode.field "address" addressDecoder)


-- SAMPLE DATA

sampleJson : String
sampleJson =
    """
{
  "person": {
    "name": "Alice Smith",
    "age": 28,
    "email": "alice@example.com",
    "hobbies": ["reading", "hiking", "photography"]
  },
  "address": {
    "street": "123 Main Street",
    "city": "Portland",
    "zipCode": "97201"
  }
}
"""


sampleJsonWithoutEmail : String
sampleJsonWithoutEmail =
    """
{
  "person": {
    "name": "Bob Jones",
    "age": 35,
    "hobbies": ["gaming", "cooking"]
  },
  "address": {
    "street": "456 Oak Avenue",
    "city": "Seattle",
    "zipCode": "98101"
  }
}
"""


-- VIEW

main : Html msg
main =
    div
        [ style "padding" "2rem"
        , style "font-family" "system-ui, sans-serif"
        , style "max-width" "800px"
        , style "margin" "0 auto"
        ]
        [ h1 [] [ text "JSON Decoding Examples" ]
        , viewExample "Profile with Email" sampleJson
        , viewExample "Profile without Email" sampleJsonWithoutEmail
        ]


viewExample : String -> String -> Html msg
viewExample title json =
    div [ style "margin-bottom" "2rem" ]
        [ h2 [] [ text title ]
        , div [ style "display" "grid", style "grid-template-columns" "1fr 1fr", style "gap" "1rem" ]
            [ div []
                [ div [ style "font-weight" "bold", style "margin-bottom" "0.5rem" ] [ text "Input JSON:" ]
                , pre
                    [ style "background" "#f5f5f5"
                    , style "padding" "1rem"
                    , style "border-radius" "4px"
                    , style "overflow-x" "auto"
                    ]
                    [ code [] [ text json ] ]
                ]
            , div []
                [ div [ style "font-weight" "bold", style "margin-bottom" "0.5rem" ] [ text "Decoded Result:" ]
                , viewDecodeResult (Decode.decodeString profileDecoder json)
                ]
            ]
        ]


viewDecodeResult : Result Decode.Error Profile -> Html msg
viewDecodeResult result =
    case result of
        Ok profile ->
            div
                [ style "background" "#e8f5e9"
                , style "padding" "1rem"
                , style "border-radius" "4px"
                ]
                [ viewPerson profile.person
                , viewAddress profile.address
                ]

        Err error ->
            div
                [ style "background" "#ffebee"
                , style "padding" "1rem"
                , style "border-radius" "4px"
                , style "color" "#c62828"
                ]
                [ text (Decode.errorToString error) ]


viewPerson : Person -> Html msg
viewPerson person =
    div [ style "margin-bottom" "1rem" ]
        [ div [ style "font-weight" "bold" ] [ text person.name ]
        , div [] [ text ("Age: " ++ String.fromInt person.age) ]
        , div [] [ text ("Email: " ++ Maybe.withDefault "(not provided)" person.email) ]
        , div [] [ text ("Hobbies: " ++ String.join ", " person.hobbies) ]
        ]


viewAddress : Address -> Html msg
viewAddress address =
    div []
        [ div [ style "font-weight" "bold" ] [ text "Address" ]
        , div [] [ text address.street ]
        , div [] [ text (address.city ++ ", " ++ address.zipCode) ]
        ]
`,
      },
    ],
  },
  {
    id: 'custom-types',
    name: 'Custom Types',
    description: 'Working with sum types and pattern matching',
    files: [
      {
        name: 'Main.can',
        language: 'canopy',
        content: `module Main exposing (..)

import Html exposing (Html, div, text, h1, h2, ul, li)
import Html.Attributes exposing (style)


-- CUSTOM TYPES

type Shape
    = Circle Float
    | Rectangle Float Float
    | Triangle Float Float Float
    | Square Float


type RemoteData e a
    = NotAsked
    | Loading
    | Failure e
    | Success a


type alias Order =
    { id : Int
    , items : List OrderItem
    , status : OrderStatus
    }


type OrderItem
    = Product String Int Float
    | Subscription String Float


type OrderStatus
    = Pending
    | Processing
    | Shipped String
    | Delivered
    | Cancelled String


-- FUNCTIONS

calculateArea : Shape -> Float
calculateArea shape =
    case shape of
        Circle radius ->
            3.14159 * radius * radius

        Rectangle width height ->
            width * height

        Triangle a b c ->
            let
                s = (a + b + c) / 2
            in
            sqrt (s * (s - a) * (s - b) * (s - c))

        Square side ->
            side * side


describeshape : Shape -> String
describeshape shape =
    case shape of
        Circle r ->
            "Circle with radius " ++ String.fromFloat r

        Rectangle w h ->
            "Rectangle " ++ String.fromFloat w ++ " x " ++ String.fromFloat h

        Triangle a b c ->
            "Triangle with sides " ++ String.fromFloat a ++ ", " ++ String.fromFloat b ++ ", " ++ String.fromFloat c

        Square s ->
            "Square with side " ++ String.fromFloat s


mapRemoteData : (a -> b) -> RemoteData e a -> RemoteData e b
mapRemoteData f remoteData =
    case remoteData of
        NotAsked ->
            NotAsked

        Loading ->
            Loading

        Failure e ->
            Failure e

        Success a ->
            Success (f a)


orderTotal : Order -> Float
orderTotal order =
    List.foldl addItemPrice 0 order.items


addItemPrice : OrderItem -> Float -> Float
addItemPrice item total =
    case item of
        Product _ quantity price ->
            total + (toFloat quantity * price)

        Subscription _ monthlyPrice ->
            total + monthlyPrice


orderStatusMessage : OrderStatus -> String
orderStatusMessage status =
    case status of
        Pending ->
            "Your order is being prepared"

        Processing ->
            "Your order is being processed"

        Shipped trackingNumber ->
            "Shipped! Tracking: " ++ trackingNumber

        Delivered ->
            "Your order has been delivered"

        Cancelled reason ->
            "Cancelled: " ++ reason


-- SAMPLE DATA

shapes : List Shape
shapes =
    [ Circle 5
    , Rectangle 4 6
    , Triangle 3 4 5
    , Square 7
    ]


sampleOrder : Order
sampleOrder =
    { id = 1001
    , items =
        [ Product "Laptop" 1 999.99
        , Product "Mouse" 2 29.99
        , Subscription "Cloud Storage" 9.99
        ]
    , status = Shipped "TRACK123456"
    }


-- VIEW

main : Html msg
main =
    div
        [ style "padding" "2rem"
        , style "font-family" "system-ui, sans-serif"
        , style "max-width" "800px"
        , style "margin" "0 auto"
        ]
        [ h1 [] [ text "Custom Types in Canopy" ]
        , viewShapes
        , viewOrder sampleOrder
        ]


viewShapes : Html msg
viewShapes =
    div [ style "margin-bottom" "2rem" ]
        [ h2 [] [ text "Shapes" ]
        , ul []
            (List.map viewShape shapes)
        ]


viewShape : Shape -> Html msg
viewShape shape =
    li [ style "margin-bottom" "0.5rem" ]
        [ text (describeshape shape ++ " - Area: " ++ String.fromFloat (calculateArea shape))
        ]


viewOrder : Order -> Html msg
viewOrder order =
    div
        [ style "background" "#f5f5f5"
        , style "padding" "1rem"
        , style "border-radius" "4px"
        ]
        [ h2 [] [ text ("Order #" ++ String.fromInt order.id) ]
        , div [ style "margin-bottom" "0.5rem" ]
            [ text ("Status: " ++ orderStatusMessage order.status) ]
        , ul []
            (List.map viewOrderItem order.items)
        , div [ style "font-weight" "bold", style "margin-top" "1rem" ]
            [ text ("Total: $" ++ String.fromFloat (orderTotal order)) ]
        ]


viewOrderItem : OrderItem -> Html msg
viewOrderItem item =
    case item of
        Product name quantity price ->
            li []
                [ text (name ++ " x" ++ String.fromInt quantity ++ " @ $" ++ String.fromFloat price) ]

        Subscription name price ->
            li []
                [ text (name ++ " (monthly): $" ++ String.fromFloat price) ]
`,
      },
    ],
  },
];

export const DEFAULT_EXAMPLE = EXAMPLES[0];

export function getExampleById(id: string): Example | undefined {
  return EXAMPLES.find(e => e.id === id);
}
