# Scaling TEA (The Elm Architecture)

As your Canopy application grows, you need patterns for composing multiple
independent modules that each manage their own model, update, and
subscriptions. This guide covers the two key tools: **message delegation**
and **code splitting**.

## The Problem

In a naive multi-page app, the parent `update` function accumulates
boilerplate for every child module:

```canopy
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        HeaderMsg headerMsg ->
            let
                ( headerModel, headerCmd ) =
                    Header.update headerMsg model.header
            in
            ( { model | header = headerModel }
            , Cmd.map HeaderMsg headerCmd
            )

        SidebarMsg sidebarMsg ->
            -- same pattern repeated...
```

Every child module means another 5-line block that does the same thing:
unwrap the child result, update the parent model, and re-wrap the command.

## Message Delegation with `Platform.Delegate`

Import `Platform.Delegate` and the boilerplate collapses to one line per child:

```canopy
import Platform.Delegate exposing (delegate, delegateSub)

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        HeaderMsg headerMsg ->
            delegate HeaderMsg
                (\m -> { model | header = m })
                (Header.update headerMsg model.header)

        SidebarMsg sidebarMsg ->
            delegate SidebarMsg
                (\m -> { model | sidebar = m })
                (Sidebar.update sidebarMsg model.sidebar)
```

### API Reference

#### `delegate`

```canopy
delegate :
    (childMsg -> parentMsg)
    -> (childModel -> parentModel)
    -> ( childModel, Cmd childMsg )
    -> ( parentModel, Cmd parentMsg )
```

Maps a child's `(model, Cmd msg)` tuple into the parent's domain.

- **First argument**: message wrapper (e.g. `HeaderMsg`)
- **Second argument**: function to place the child model into the parent
- **Third argument**: the child's update result

#### `delegateWithBatch`

```canopy
delegateWithBatch :
    (childMsg -> parentMsg)
    -> (childModel -> parentModel)
    -> List (Cmd parentMsg)
    -> ( childModel, Cmd childMsg )
    -> ( parentModel, Cmd parentMsg )
```

Like `delegate`, but also batches additional parent-level commands:

```canopy
HeaderMsg headerMsg ->
    delegateWithBatch HeaderMsg
        (\m -> { model | header = m })
        [ Ports.logNavigation "header" ]
        (Header.update headerMsg model.header)
```

#### `delegateSub`

```canopy
delegateSub :
    (childMsg -> parentMsg)
    -> Sub childMsg
    -> Sub parentMsg
```

Maps a child subscription into the parent's message type:

```canopy
subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ delegateSub HeaderMsg (Header.subscriptions model.header)
        , delegateSub SidebarMsg (Sidebar.subscriptions model.sidebar)
        ]
```

## Code Splitting with `lazy import`

For large applications, loading all JavaScript upfront hurts initial page
load. Canopy's compiler automatically splits code at `lazy import` boundaries.

### Declaring Lazy Imports

```canopy
module Main exposing (main)

import Dashboard  -- eager: included in entry chunk
lazy import Settings  -- lazy: loaded on demand
lazy import Analytics  -- lazy: separate chunk
```

When the compiler encounters `lazy import`, it:

1. Places that module (and its unique dependencies) in a separate chunk
2. Generates a content-hashed filename for cache busting
3. Emits a manifest mapping chunk IDs to filenames

### Route-Level Splitting

The most common pattern is splitting per route:

```canopy
module Main exposing (main)

lazy import Pages.Home
lazy import Pages.Dashboard
lazy import Pages.Settings

main =
    Browser.application
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }
```

Each page becomes its own chunk. When the user navigates to `/settings`,
only then is the Settings chunk fetched.

### Output Structure

A code-split build produces:

```
build/
  entry.js                          -- always loaded
  chunk-Dashboard-a1b2c3d4.js       -- loaded on demand
  chunk-Settings-e5f6a7b8.js        -- loaded on demand
  shared-0-deadbeef.js              -- shared dependencies
  manifest.json                     -- maps chunk IDs to files
```

Shared code that two or more lazy chunks depend on is automatically
extracted into a `shared-*` chunk to avoid duplication.

### Prefetching

The runtime supports prefetching chunks before they're needed:

```javascript
// In your JavaScript, after initial load:
__canopy_prefetch("Settings");
```

This adds a `<link rel="prefetch">` hint so the browser downloads the
chunk during idle time, making subsequent navigation instant.

## Putting It Together

A well-structured large application combines both patterns:

```canopy
module Main exposing (main)

import Platform.Delegate exposing (delegate, delegateSub)
import Header
lazy import Pages.Home
lazy import Pages.Settings

type Msg
    = HeaderMsg Header.Msg
    | PageMsg Page.Msg
    | UrlChanged Url

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        HeaderMsg headerMsg ->
            delegate HeaderMsg
                (\m -> { model | header = m })
                (Header.update headerMsg model.header)

        PageMsg pageMsg ->
            delegate PageMsg
                (\m -> { model | page = m })
                (Page.update pageMsg model.page)

        UrlChanged url ->
            navigateTo url model

subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ delegateSub HeaderMsg (Header.subscriptions model.header)
        , delegateSub PageMsg (Page.subscriptions model.page)
        ]
```

The compiler handles code splitting automatically — you focus on the
application structure, not the bundling strategy.
