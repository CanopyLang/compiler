# Counter Example

A simple counter application demonstrating the basic Canopy Architecture.

## The Complete Code

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
        , button [ onClick Reset, class "reset" ] [ text "Reset" ]
        ]
```

## Understanding Each Part

### The Model

```canopy
type alias Model =
    { count : Int
    }


init : Model
init =
    { count = 0
    }
```

The **Model** represents the entire state of the application. For a counter, we just need one integer. The `init` function provides the starting state.

### Messages

```canopy
type Msg
    = Increment
    | Decrement
    | Reset
```

**Messages** describe all possible events in your application. This is a custom type with three variants - one for each action the user can take.

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

The **update** function handles each message by returning a new model. Note that we never mutate the existing model - we create a new one with the updated value.

### The View

```canopy
view : Model -> Html Msg
view model =
    div [ class "counter" ]
        [ button [ onClick Decrement ] [ text "-" ]
        , div [ class "count" ] [ text (String.fromInt model.count) ]
        , button [ onClick Increment ] [ text "+" ]
        , button [ onClick Reset, class "reset" ] [ text "Reset" ]
        ]
```

The **view** function renders the model as HTML. Each button has an `onClick` handler that sends the corresponding message.

## Adding Styles

Create a `style.css` file:

```css
.counter {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 2rem;
    font-family: system-ui, sans-serif;
}

.counter button {
    width: 3rem;
    height: 3rem;
    font-size: 1.5rem;
    border: none;
    border-radius: 8px;
    background: #4a90d9;
    color: white;
    cursor: pointer;
    transition: background 0.2s;
}

.counter button:hover {
    background: #357abd;
}

.counter button.reset {
    width: auto;
    padding: 0 1rem;
    font-size: 1rem;
    background: #888;
}

.counter button.reset:hover {
    background: #666;
}

.counter .count {
    min-width: 4rem;
    text-align: center;
    font-size: 2.5rem;
    font-weight: bold;
}
```

## Variations

### Counter with Step Size

```canopy
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
    | SetStep Int
    | Reset


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + model.step }

        Decrement ->
            { model | count = model.count - model.step }

        SetStep newStep ->
            { model | step = newStep }

        Reset ->
            { model | count = 0 }
```

### Counter with Bounds

```canopy
type alias Model =
    { count : Int
    , min : Int
    , max : Int
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = min model.max (model.count + 1) }

        Decrement ->
            { model | count = max model.min (model.count - 1) }
```

### Counter with History

```canopy
type alias Model =
    { count : Int
    , history : List Int
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model
                | count = model.count + 1
                , history = model.count :: model.history
            }

        Undo ->
            case model.history of
                previous :: rest ->
                    { model
                        | count = previous
                        , history = rest
                    }

                [] ->
                    model
```

## Running the Example

1. Create a new project:
   ```bash
   canopy init counter
   cd counter
   ```

2. Replace `src/Main.can` with the code above

3. Add the CSS to `public/style.css`

4. Run the development server:
   ```bash
   canopy reactor
   ```

5. Open `http://localhost:8000/src/Main.can`

## Key Takeaways

- **Separation of concerns**: Model, Messages, Update, and View are clearly separated
- **Immutability**: We never mutate state, always create new state
- **Exhaustive handling**: The compiler ensures we handle every message
- **Type safety**: Invalid states are impossible to represent
