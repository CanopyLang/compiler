# Todo Application

A complete todo list application demonstrating form handling, list management, and local storage.

## The Complete Code

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, form, h1, input, label, li, text, ul)
import Html.Attributes exposing (autofocus, checked, class, placeholder, type_, value)
import Html.Events exposing (onCheck, onClick, onInput, onSubmit)


-- MAIN


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


-- MODEL


type alias Model =
    { todos : List Todo
    , newTodoText : String
    , filter : Filter
    , nextId : Int
    }


type alias Todo =
    { id : Int
    , text : String
    , completed : Bool
    }


type Filter
    = All
    | Active
    | Completed


init : Model
init =
    { todos = []
    , newTodoText = ""
    , filter = All
    , nextId = 1
    }


-- UPDATE


type Msg
    = UpdateNewTodo String
    | AddTodo
    | ToggleTodo Int
    | DeleteTodo Int
    | SetFilter Filter
    | ClearCompleted


update : Msg -> Model -> Model
update msg model =
    case msg of
        UpdateNewTodo text ->
            { model | newTodoText = text }

        AddTodo ->
            if String.isEmpty (String.trim model.newTodoText) then
                model

            else
                { model
                    | todos = model.todos ++ [ newTodo model.nextId model.newTodoText ]
                    , newTodoText = ""
                    , nextId = model.nextId + 1
                }

        ToggleTodo id ->
            { model | todos = List.map (toggleTodo id) model.todos }

        DeleteTodo id ->
            { model | todos = List.filter (\todo -> todo.id /= id) model.todos }

        SetFilter filter ->
            { model | filter = filter }

        ClearCompleted ->
            { model | todos = List.filter (not << .completed) model.todos }


newTodo : Int -> String -> Todo
newTodo id text =
    { id = id
    , text = String.trim text
    , completed = False
    }


toggleTodo : Int -> Todo -> Todo
toggleTodo id todo =
    if todo.id == id then
        { todo | completed = not todo.completed }

    else
        todo


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "todo-app" ]
        [ h1 [] [ text "Todos" ]
        , viewInput model.newTodoText
        , viewTodos model.filter model.todos
        , viewFooter model
        ]


viewInput : String -> Html Msg
viewInput newTodoText =
    form [ class "new-todo-form", onSubmit AddTodo ]
        [ input
            [ type_ "text"
            , class "new-todo"
            , placeholder "What needs to be done?"
            , value newTodoText
            , onInput UpdateNewTodo
            , autofocus True
            ]
            []
        , button [ type_ "submit", class "add-button" ] [ text "Add" ]
        ]


viewTodos : Filter -> List Todo -> Html Msg
viewTodos filter todos =
    let
        filteredTodos =
            filterTodos filter todos
    in
    if List.isEmpty todos then
        div [ class "empty-state" ] [ text "No todos yet!" ]

    else
        ul [ class "todo-list" ]
            (List.map viewTodo filteredTodos)


filterTodos : Filter -> List Todo -> List Todo
filterTodos filter todos =
    case filter of
        All ->
            todos

        Active ->
            List.filter (not << .completed) todos

        Completed ->
            List.filter .completed todos


viewTodo : Todo -> Html Msg
viewTodo todo =
    li
        [ class "todo-item"
        , class
            (if todo.completed then
                "completed"

             else
                ""
            )
        ]
        [ label [ class "toggle-container" ]
            [ input
                [ type_ "checkbox"
                , class "toggle"
                , checked todo.completed
                , onCheck (\_ -> ToggleTodo todo.id)
                ]
                []
            , text todo.text
            ]
        , button
            [ class "delete"
            , onClick (DeleteTodo todo.id)
            ]
            [ text "x" ]
        ]


viewFooter : Model -> Html Msg
viewFooter model =
    let
        activeCount =
            List.length (List.filter (not << .completed) model.todos)

        completedCount =
            List.length model.todos - activeCount
    in
    if List.isEmpty model.todos then
        text ""

    else
        div [ class "footer" ]
            [ span [ class "count" ]
                [ text (String.fromInt activeCount ++ " items left")
                ]
            , viewFilters model.filter
            , if completedCount > 0 then
                button
                    [ class "clear-completed"
                    , onClick ClearCompleted
                    ]
                    [ text "Clear completed" ]

              else
                text ""
            ]


viewFilters : Filter -> Html Msg
viewFilters currentFilter =
    div [ class "filters" ]
        [ viewFilterButton All currentFilter "All"
        , viewFilterButton Active currentFilter "Active"
        , viewFilterButton Completed currentFilter "Completed"
        ]


viewFilterButton : Filter -> Filter -> String -> Html Msg
viewFilterButton filter currentFilter label =
    button
        [ class "filter-button"
        , class
            (if filter == currentFilter then
                "selected"

             else
                ""
            )
        , onClick (SetFilter filter)
        ]
        [ text label ]
```

## Styling

```css
.todo-app {
    max-width: 500px;
    margin: 2rem auto;
    padding: 1rem;
    font-family: system-ui, sans-serif;
}

.todo-app h1 {
    text-align: center;
    color: #333;
    margin-bottom: 1.5rem;
}

.new-todo-form {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 1rem;
}

.new-todo {
    flex: 1;
    padding: 0.75rem;
    font-size: 1rem;
    border: 2px solid #ddd;
    border-radius: 4px;
}

.new-todo:focus {
    outline: none;
    border-color: #4a90d9;
}

.add-button {
    padding: 0.75rem 1.5rem;
    background: #4a90d9;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
}

.todo-list {
    list-style: none;
    padding: 0;
    margin: 0;
}

.todo-item {
    display: flex;
    align-items: center;
    padding: 0.75rem;
    border-bottom: 1px solid #eee;
}

.todo-item.completed .toggle-container {
    text-decoration: line-through;
    color: #888;
}

.toggle-container {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
}

.toggle {
    width: 1.25rem;
    height: 1.25rem;
}

.delete {
    background: none;
    border: none;
    color: #cc0000;
    font-size: 1.25rem;
    cursor: pointer;
    opacity: 0;
    transition: opacity 0.2s;
}

.todo-item:hover .delete {
    opacity: 1;
}

.footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 0;
    font-size: 0.875rem;
    color: #666;
}

.filters {
    display: flex;
    gap: 0.5rem;
}

.filter-button {
    background: none;
    border: 1px solid transparent;
    padding: 0.25rem 0.5rem;
    border-radius: 4px;
    cursor: pointer;
}

.filter-button.selected {
    border-color: #4a90d9;
}

.clear-completed {
    background: none;
    border: none;
    color: #666;
    cursor: pointer;
}

.clear-completed:hover {
    text-decoration: underline;
}

.empty-state {
    text-align: center;
    padding: 2rem;
    color: #888;
}
```

## Adding Local Storage

To persist todos, we need to use ports:

```canopy
port module Main exposing (main)

import Browser
import Json.Decode as Decode
import Json.Encode as Encode
import Html exposing (..)


-- PORTS


port saveTodos : Encode.Value -> Cmd msg
port loadTodos : (Encode.Value -> msg) -> Sub msg


-- MAIN


main : Program Encode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }


-- Initialize from flags (localStorage)
init : Encode.Value -> ( Model, Cmd Msg )
init flags =
    case Decode.decodeValue todosDecoder flags of
        Ok todos ->
            ( { todos = todos
              , newTodoText = ""
              , filter = All
              , nextId = List.length todos + 1
              }
            , Cmd.none
            )

        Err _ ->
            ( { todos = []
              , newTodoText = ""
              , filter = All
              , nextId = 1
              }
            , Cmd.none
            )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


-- Save after each update
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        newModel =
            updateModel msg model
    in
    ( newModel
    , saveTodos (encodeTodos newModel.todos)
    )


-- JSON Encoding/Decoding


encodeTodo : Todo -> Encode.Value
encodeTodo todo =
    Encode.object
        [ ( "id", Encode.int todo.id )
        , ( "text", Encode.string todo.text )
        , ( "completed", Encode.bool todo.completed )
        ]


encodeTodos : List Todo -> Encode.Value
encodeTodos =
    Encode.list encodeTodo


todoDecoder : Decode.Decoder Todo
todoDecoder =
    Decode.map3 Todo
        (Decode.field "id" Decode.int)
        (Decode.field "text" Decode.string)
        (Decode.field "completed" Decode.bool)


todosDecoder : Decode.Decoder (List Todo)
todosDecoder =
    Decode.list todoDecoder
```

JavaScript setup:

```javascript
// Load from localStorage
var storedTodos = localStorage.getItem('canopy-todos');
var flags = storedTodos ? JSON.parse(storedTodos) : [];

var app = Canopy.Main.init({
    node: document.getElementById('app'),
    flags: flags
});

// Save to localStorage
app.ports.saveTodos.subscribe(function(todos) {
    localStorage.setItem('canopy-todos', JSON.stringify(todos));
});
```

## Key Concepts Demonstrated

1. **Form handling**: Using `onInput`, `onSubmit`, and controlled inputs
2. **List operations**: Adding, removing, and updating items in a list
3. **Filtering**: Dynamically filtering displayed items
4. **Conditional rendering**: Showing/hiding elements based on state
5. **Ports**: Communicating with JavaScript for localStorage
6. **JSON encoding/decoding**: Serializing data for persistence

## Exercises

1. Add the ability to edit existing todos
2. Add drag-and-drop reordering
3. Add due dates to todos
4. Add categories/tags to todos
5. Add keyboard shortcuts (Enter to add, Escape to cancel)
