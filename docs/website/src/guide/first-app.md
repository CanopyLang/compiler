# Your First Application

Let's build a complete counter application from scratch. This will teach you the fundamentals of Canopy development.

## Creating the Project

```bash
canopy init counter-app
cd counter-app
```

## The Counter Application

Replace the contents of `src/Main.can` with:

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)


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
    { count : Int
    }


init : Model
init =
    { count = 0
    }


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
    div [ class "counter" ]
        [ button [ onClick Decrement ] [ text "-" ]
        , div [ class "count" ] [ text (String.fromInt model.count) ]
        , button [ onClick Increment ] [ text "+" ]
        , button [ onClick Reset ] [ text "Reset" ]
        ]
```

## Understanding Each Part

### The Model

```canopy
type alias Model =
    { count : Int
    }
```

The **Model** represents your application's state. Here, we have a single integer tracking the count.

Key concepts:

- `type alias` creates a named alias for a type
- Records use `{ field : Type }` syntax
- Types are always capitalized (Int, String, Bool)

### The Init Function

```canopy
init : Model
init =
    { count = 0
    }
```

The **init** function provides the initial state of your application. Every application needs a starting point.

### Messages

```canopy
type Msg
    = Increment
    | Decrement
    | Reset
```

**Messages** describe everything that can happen in your application. This is a custom type (also called a union type or sum type) with three possible values.

Key concepts:

- Custom types are defined with `type Name = Constructor1 | Constructor2`
- Each constructor creates a value of that type
- Messages are typically named as past-tense verbs or nouns describing events

### The Update Function

```canopy
update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        Decrement ->
            { model | count = model.count - 1 }

        Reset ->
            { model | count = 0 }
```

The **update** function handles each message and returns a new model. It never modifies the existing model; instead, it creates a new one.

Key concepts:

- `case ... of` is pattern matching
- `{ model | field = value }` is record update syntax
- The function is pure: same inputs always produce same outputs

### The View

```canopy
view : Model -> Html Msg
view model =
    div [ class "counter" ]
        [ button [ onClick Decrement ] [ text "-" ]
        , div [ class "count" ] [ text (String.fromInt model.count) ]
        , button [ onClick Increment ] [ text "+" ]
        , button [ onClick Reset ] [ text "Reset" ]
        ]
```

The **view** function renders your model as HTML. It returns `Html Msg`, meaning the HTML can produce messages of type `Msg`.

Key concepts:

- HTML elements are functions: `div`, `button`, `text`
- First argument is a list of attributes
- Second argument is a list of children
- `onClick Increment` creates an attribute that sends `Increment` when clicked

## Running the Application

```bash
canopy reactor
```

Visit `http://localhost:8000/src/Main.can` to see your counter in action.

## Adding Styling

Create `public/style.css`:

```css
.counter {
    display: flex;
    align-items: center;
    gap: 1rem;
    font-family: sans-serif;
    padding: 2rem;
}

.counter button {
    padding: 0.5rem 1rem;
    font-size: 1.5rem;
    cursor: pointer;
    border: 1px solid #ccc;
    border-radius: 4px;
    background: #f5f5f5;
}

.counter button:hover {
    background: #e5e5e5;
}

.counter .count {
    font-size: 2rem;
    min-width: 3rem;
    text-align: center;
}
```

Update `public/index.html` to include the stylesheet:

```html
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Counter</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div id="app"></div>
    <script src="main.js"></script>
    <script>
        var app = Canopy.Main.init({
            node: document.getElementById('app')
        });
    </script>
</body>
</html>
```

## Adding Features

Let's add a step size feature:

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, input, text)
import Html.Attributes exposing (class, type_, value)
import Html.Events exposing (onClick, onInput)


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


type alias Model =
    { count : Int
    , step : Int
    }


init : Model
init =
    { count = 0
    , step = 1
    }


type Msg
    = Increment
    | Decrement
    | Reset
    | SetStep String


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + model.step }

        Decrement ->
            { model | count = model.count - model.step }

        Reset ->
            { model | count = 0 }

        SetStep stepStr ->
            case String.toInt stepStr of
                Just newStep ->
                    { model | step = newStep }

                Nothing ->
                    model


view : Model -> Html Msg
view model =
    div [ class "counter" ]
        [ div [ class "controls" ]
            [ button [ onClick Decrement ] [ text "-" ]
            , div [ class "count" ] [ text (String.fromInt model.count) ]
            , button [ onClick Increment ] [ text "+" ]
            ]
        , div [ class "step-control" ]
            [ text "Step: "
            , input
                [ type_ "number"
                , value (String.fromInt model.step)
                , onInput SetStep
                ]
                []
            ]
        , button [ onClick Reset ] [ text "Reset" ]
        ]
```

### Key Changes

1. **Extended Model**: Added `step` field to control increment/decrement amount
2. **New Message**: `SetStep String` handles input changes
3. **String Parsing**: Used `String.toInt` which returns `Maybe Int`
4. **Handling Maybe**: Pattern matched on `Just` and `Nothing`

## Building for Production

When you're ready to deploy:

```bash
canopy make src/Main.can --output=public/main.js --optimize
```

The `--optimize` flag:

- Removes dead code
- Minifies output
- Optimizes for performance

Your `public/` directory is now ready to deploy to any static hosting service.

## Key Takeaways

1. **Model**: Represents your entire application state
2. **Messages**: Describe all possible events
3. **Update**: Pure function that handles messages
4. **View**: Pure function that renders the model

This pattern scales from simple counters to complex applications. The key insight is that your entire application is just data flowing through pure functions.

## Exercises

Try these modifications to practice:

1. Add minimum and maximum bounds to the counter
2. Add a "Double" button that doubles the current count
3. Display whether the count is even or odd
4. Add keyboard shortcuts (requires `Browser.element` and subscriptions)

## Next Steps

- **[The Canopy Architecture](./architecture.md)**: Deep dive into the architecture
- **[Type System](./type-system.md)**: Learn about types in depth
- **[Commands](./commands.md)**: Add side effects like HTTP requests
