# Html Module

The Html module provides functions for creating virtual DOM nodes.

## Basic Structure

```canopy
import Html exposing (Html, div, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)


view : Model -> Html Msg
view model =
    div [ class "container" ]
        [ text "Hello, World!"
        ]
```

## Html

### Creating Elements

All HTML elements follow the same pattern:

```canopy
element : List (Attribute msg) -> List (Html msg) -> Html msg
```

**Common Elements:**

```canopy
-- Structure
div : List (Attribute msg) -> List (Html msg) -> Html msg
span : List (Attribute msg) -> List (Html msg) -> Html msg
header : List (Attribute msg) -> List (Html msg) -> Html msg
footer : List (Attribute msg) -> List (Html msg) -> Html msg
main_ : List (Attribute msg) -> List (Html msg) -> Html msg
section : List (Attribute msg) -> List (Html msg) -> Html msg
article : List (Attribute msg) -> List (Html msg) -> Html msg
aside : List (Attribute msg) -> List (Html msg) -> Html msg
nav : List (Attribute msg) -> List (Html msg) -> Html msg

-- Headings
h1 : List (Attribute msg) -> List (Html msg) -> Html msg
h2 : List (Attribute msg) -> List (Html msg) -> Html msg
h3 : List (Attribute msg) -> List (Html msg) -> Html msg
h4 : List (Attribute msg) -> List (Html msg) -> Html msg
h5 : List (Attribute msg) -> List (Html msg) -> Html msg
h6 : List (Attribute msg) -> List (Html msg) -> Html msg

-- Text
p : List (Attribute msg) -> List (Html msg) -> Html msg
text : String -> Html msg
pre : List (Attribute msg) -> List (Html msg) -> Html msg
code : List (Attribute msg) -> List (Html msg) -> Html msg
blockquote : List (Attribute msg) -> List (Html msg) -> Html msg

-- Lists
ul : List (Attribute msg) -> List (Html msg) -> Html msg
ol : List (Attribute msg) -> List (Html msg) -> Html msg
li : List (Attribute msg) -> List (Html msg) -> Html msg

-- Links and Media
a : List (Attribute msg) -> List (Html msg) -> Html msg
img : List (Attribute msg) -> List (Html msg) -> Html msg
video : List (Attribute msg) -> List (Html msg) -> Html msg
audio : List (Attribute msg) -> List (Html msg) -> Html msg

-- Forms
form : List (Attribute msg) -> List (Html msg) -> Html msg
input : List (Attribute msg) -> List (Html msg) -> Html msg
textarea : List (Attribute msg) -> List (Html msg) -> Html msg
button : List (Attribute msg) -> List (Html msg) -> Html msg
select : List (Attribute msg) -> List (Html msg) -> Html msg
option : List (Attribute msg) -> List (Html msg) -> Html msg
label : List (Attribute msg) -> List (Html msg) -> Html msg

-- Tables
table : List (Attribute msg) -> List (Html msg) -> Html msg
thead : List (Attribute msg) -> List (Html msg) -> Html msg
tbody : List (Attribute msg) -> List (Html msg) -> Html msg
tr : List (Attribute msg) -> List (Html msg) -> Html msg
th : List (Attribute msg) -> List (Html msg) -> Html msg
td : List (Attribute msg) -> List (Html msg) -> Html msg
```

### Text

```canopy
text : String -> Html msg
```

**Example:**

```canopy
div []
    [ text "Hello, "
    , strong [] [ text "World" ]
    , text "!"
    ]
```

### Empty Node

```canopy
-- When you need to conditionally render nothing
viewMaybe : Maybe User -> Html msg
viewMaybe maybeUser =
    case maybeUser of
        Just user ->
            viewUser user

        Nothing ->
            text ""  -- Empty text node
```

---

## Html.Attributes

### Common Attributes

```canopy
-- Identification
id : String -> Attribute msg
class : String -> Attribute msg
classList : List ( String, Bool ) -> Attribute msg
title : String -> Attribute msg

-- Styling
style : String -> String -> Attribute msg

-- Links
href : String -> Attribute msg
target : String -> Attribute msg
rel : String -> Attribute msg

-- Forms
name : String -> Attribute msg
value : String -> Attribute msg
type_ : String -> Attribute msg
placeholder : String -> Attribute msg
disabled : Bool -> Attribute msg
checked : Bool -> Attribute msg
selected : Bool -> Attribute msg
readonly : Bool -> Attribute msg
required : Bool -> Attribute msg
autofocus : Bool -> Attribute msg
maxlength : Int -> Attribute msg
minlength : Int -> Attribute msg
min : String -> Attribute msg
max : String -> Attribute msg
step : String -> Attribute msg
pattern : String -> Attribute msg
for : String -> Attribute msg
multiple : Bool -> Attribute msg
accept : String -> Attribute msg

-- Media
src : String -> Attribute msg
alt : String -> Attribute msg
width : Int -> Attribute msg
height : Int -> Attribute msg
autoplay : Bool -> Attribute msg
controls : Bool -> Attribute msg
loop : Bool -> Attribute msg

-- Tables
colspan : Int -> Attribute msg
rowspan : Int -> Attribute msg

-- Accessibility
role : String -> Attribute msg
attribute : String -> String -> Attribute msg
```

### Class and Style

```canopy
-- Single class
div [ class "container" ] []

-- Multiple classes
div [ class "container large primary" ] []

-- Conditional classes
div
    [ classList
        [ ( "active", model.isActive )
        , ( "disabled", model.isDisabled )
        , ( "hidden", not model.isVisible )
        ]
    ]
    []

-- Inline styles
div
    [ style "color" "red"
    , style "font-size" "16px"
    , style "display" "flex"
    ]
    []
```

### Custom Attributes

```canopy
-- Any attribute
attribute : String -> String -> Attribute msg

-- Data attributes
div [ attribute "data-id" "123" ] []

-- ARIA attributes
button
    [ attribute "aria-label" "Close"
    , attribute "aria-expanded" "false"
    ]
    []
```

---

## Html.Events

### Mouse Events

```canopy
onClick : msg -> Attribute msg
onDoubleClick : msg -> Attribute msg
onMouseDown : msg -> Attribute msg
onMouseUp : msg -> Attribute msg
onMouseEnter : msg -> Attribute msg
onMouseLeave : msg -> Attribute msg
onMouseOver : msg -> Attribute msg
onMouseOut : msg -> Attribute msg
```

**Example:**

```canopy
button [ onClick Increment ] [ text "+" ]

div
    [ onMouseEnter ShowTooltip
    , onMouseLeave HideTooltip
    ]
    [ text "Hover me" ]
```

### Form Events

```canopy
onInput : (String -> msg) -> Attribute msg
onChange : (String -> msg) -> Attribute msg
onCheck : (Bool -> msg) -> Attribute msg
onSubmit : msg -> Attribute msg
onFocus : msg -> Attribute msg
onBlur : msg -> Attribute msg
```

**Example:**

```canopy
input
    [ type_ "text"
    , value model.name
    , onInput UpdateName
    ]
    []


type Msg
    = UpdateName String


-- Checkbox
input
    [ type_ "checkbox"
    , checked model.agree
    , onCheck ToggleAgree
    ]
    []


-- Form submission
form
    [ onSubmit Submit ]
    [ input [ type_ "text" ] []
    , button [ type_ "submit" ] [ text "Submit" ]
    ]
```

### Keyboard Events

```canopy
onKeyDown : (Int -> msg) -> Attribute msg
onKeyUp : (Int -> msg) -> Attribute msg
onKeyPress : (Int -> msg) -> Attribute msg
```

### Custom Events

```canopy
on : String -> Decoder msg -> Attribute msg
```

**Example:**

```canopy
-- Custom scroll event
onScroll : (Float -> msg) -> Attribute msg
onScroll toMsg =
    on "scroll"
        (Decode.at [ "target", "scrollTop" ] Decode.float
            |> Decode.map toMsg
        )


-- Prevent default
onClickPreventDefault : msg -> Attribute msg
onClickPreventDefault msg =
    preventDefaultOn "click"
        (Decode.succeed ( msg, True ))


-- Stop propagation
onClickStopPropagation : msg -> Attribute msg
onClickStopPropagation msg =
    stopPropagationOn "click"
        (Decode.succeed ( msg, True ))
```

---

## Html.Keyed

Efficient rendering of lists with stable identity.

```canopy
import Html.Keyed as Keyed


viewList : List Item -> Html msg
viewList items =
    Keyed.ul []
        (List.map viewKeyedItem items)


viewKeyedItem : Item -> ( String, Html msg )
viewKeyedItem item =
    ( String.fromInt item.id
    , li [] [ text item.name ]
    )
```

**Use when:**

- Rendering lists that change (items added, removed, reordered)
- Each item has a stable, unique identifier
- Performance optimization for large lists

---

## Html.Lazy

Lazy rendering for performance optimization.

```canopy
import Html.Lazy as Lazy


view : Model -> Html Msg
view model =
    div []
        [ Lazy.lazy viewHeader model.user
        , Lazy.lazy2 viewContent model.posts model.filter
        , Lazy.lazy viewFooter model.config
        ]
```

**Functions:**

```canopy
lazy : (a -> Html msg) -> a -> Html msg
lazy2 : (a -> b -> Html msg) -> a -> b -> Html msg
lazy3 : (a -> b -> c -> Html msg) -> a -> b -> c -> Html msg
lazy4 : ...
lazy5 : ...
lazy6 : ...
lazy7 : ...
lazy8 : ...
```

**Use when:**

- Rendering is expensive
- Data doesn't change frequently
- View depends only on its arguments (referential equality check)

---

## Common Patterns

### Conditional Rendering

```canopy
view : Model -> Html Msg
view model =
    div []
        [ viewHeader
        , if model.showSidebar then
            viewSidebar model
          else
            text ""
        , viewContent model
        ]


-- Or using helper
viewIf : Bool -> Html msg -> Html msg
viewIf condition html =
    if condition then
        html
    else
        text ""


view : Model -> Html Msg
view model =
    div []
        [ viewIf model.isAdmin (viewAdminPanel model)
        ]
```

### Rendering Lists

```canopy
viewUsers : List User -> Html Msg
viewUsers users =
    ul [ class "user-list" ]
        (List.map viewUser users)


viewUser : User -> Html Msg
viewUser user =
    li [ class "user" ]
        [ text user.name
        ]
```

### View Composition

```canopy
viewPage : Model -> Html Msg
viewPage model =
    div [ class "page" ]
        [ viewHeader model.user
        , viewNav model.currentRoute
        , viewMainContent model
        , viewFooter
        ]


viewHeader : Maybe User -> Html Msg
viewHeader maybeUser =
    header [ class "header" ]
        [ h1 [] [ text "My App" ]
        , case maybeUser of
            Just user ->
                viewUserMenu user

            Nothing ->
                viewLoginButton
        ]
```

### Event Handlers with Data

```canopy
viewItem : Item -> Html Msg
viewItem item =
    li []
        [ text item.name
        , button
            [ onClick (DeleteItem item.id) ]
            [ text "Delete" ]
        , button
            [ onClick (EditItem item) ]
            [ text "Edit" ]
        ]
```
