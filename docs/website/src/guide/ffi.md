# JavaScript FFI

Canopy provides a capability-based Foreign Function Interface (FFI) for safe JavaScript interoperability. This system ensures type safety while allowing access to the full JavaScript ecosystem.

## Overview

The FFI system consists of:

1. **Capabilities**: Objects that grant access to specific JavaScript APIs
2. **Foreign imports**: Declarations that bring capabilities into Canopy
3. **JSDoc annotations**: Type information for JavaScript functions
4. **Runtime wrappers**: Automatic marshalling between Canopy and JavaScript

## Basic FFI Usage

### Defining a Foreign Import

```canopy
-- Import a capability
foreign import console : Console

-- Use the capability
main : Program () Model Msg
main =
    Platform.worker
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( {}
    , Console.log console "Hello from Canopy!"
    )
```

### JavaScript Side

```javascript
// Initialize with capabilities
var app = Canopy.Main.init({
    node: document.getElementById('app'),
    flags: {},
    capabilities: {
        console: window.console
    }
});
```

## Capability Types

Capabilities are typed interfaces to JavaScript functionality:

### Console Capability

```canopy
type alias Console =
    { log : String -> Task Never ()
    , warn : String -> Task Never ()
    , error : String -> Task Never ()
    , time : String -> Task Never ()
    , timeEnd : String -> Task Never ()
    }


foreign import console : Console


logMessage : String -> Cmd Msg
logMessage msg =
    Task.perform (\_ -> NoOp) (Console.log console msg)
```

### Storage Capability

```canopy
type alias Storage =
    { getItem : String -> Task Never (Maybe String)
    , setItem : String -> String -> Task Never ()
    , removeItem : String -> Task Never ()
    , clear : Task Never ()
    }


foreign import localStorage : Storage


saveData : String -> String -> Cmd Msg
saveData key value =
    Task.attempt DataSaved (Storage.setItem localStorage key value)


loadData : String -> Cmd Msg
loadData key =
    Task.perform DataLoaded (Storage.getItem localStorage key)
```

### Custom Capabilities

Define your own capability types:

```canopy
-- Canopy side
type alias Analytics =
    { track : String -> Json.Value -> Task Never ()
    , identify : String -> Task Never ()
    , page : String -> Task Never ()
    }


foreign import analytics : Analytics


trackEvent : String -> List ( String, String ) -> Cmd Msg
trackEvent event properties =
    let
        props =
            Encode.object
                (List.map (\( k, v ) -> ( k, Encode.string v )) properties)
    in
    Task.perform (\_ -> NoOp) (Analytics.track analytics event props)
```

```javascript
// JavaScript side
var app = Canopy.Main.init({
    node: document.getElementById('app'),
    capabilities: {
        analytics: {
            track: function(event, props) {
                mixpanel.track(event, props);
            },
            identify: function(userId) {
                mixpanel.identify(userId);
            },
            page: function(pageName) {
                mixpanel.track('Page View', { page: pageName });
            }
        }
    }
});
```

## JSDoc Annotations

Canopy uses JSDoc comments to understand JavaScript types:

### Basic Annotations

```javascript
/**
 * Add two numbers together
 * @param {number} a - First number
 * @param {number} b - Second number
 * @returns {number} The sum
 */
function add(a, b) {
    return a + b;
}
```

### Type Mappings

| JavaScript | JSDoc | Canopy |
|------------|-------|--------|
| `number` (int) | `{number}` | `Int` |
| `number` (float) | `{number}` | `Float` |
| `string` | `{string}` | `String` |
| `boolean` | `{boolean}` | `Bool` |
| `null` | `{null}` | `()` |
| `undefined` | `{undefined}` | `()` |
| `Array<T>` | `{Array<T>}` | `List T` |
| `Object` | `{Object}` | `Json.Value` |
| `Promise<T>` | `{Promise<T>}` | `Task Never T` |
| `T \| null` | `{?T}` | `Maybe T` |

### Nullable Types

```javascript
/**
 * Find a user by ID
 * @param {number} id - User ID
 * @returns {?User} The user or null
 */
function findUser(id) {
    return users.find(u => u.id === id) || null;
}
```

Canopy sees this as:

```canopy
findUser : Int -> Task Never (Maybe User)
```

### Array Types

```javascript
/**
 * Get all active users
 * @returns {Array<User>} List of users
 */
function getActiveUsers() {
    return users.filter(u => u.active);
}
```

### Promise Types

```javascript
/**
 * Fetch user data
 * @param {number} id - User ID
 * @returns {Promise<User>} User data
 * @throws {Error} If user not found
 */
async function fetchUser(id) {
    const response = await fetch(`/api/users/${id}`);
    if (!response.ok) throw new Error('User not found');
    return response.json();
}
```

Canopy sees this as:

```canopy
fetchUser : Int -> Task Error User
```

### Throws Annotation

```javascript
/**
 * Parse JSON safely
 * @param {string} json - JSON string
 * @returns {Object} Parsed object
 * @throws {SyntaxError} If JSON is invalid
 */
function parseJson(json) {
    return JSON.parse(json);
}
```

## Error Handling

### Tasks and Errors

FFI functions that can fail return `Task error value`:

```canopy
type alias FileSystem =
    { readFile : String -> Task FileError String
    , writeFile : String -> String -> Task FileError ()
    }


foreign import fs : FileSystem


type FileError
    = NotFound
    | PermissionDenied
    | Unknown String


readConfig : Cmd Msg
readConfig =
    fs.readFile "config.json"
        |> Task.attempt ConfigLoaded


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ConfigLoaded result ->
            case result of
                Ok content ->
                    ( { model | config = parseConfig content }
                    , Cmd.none
                    )

                Err NotFound ->
                    ( { model | error = "Config file not found" }
                    , Cmd.none
                    )

                Err PermissionDenied ->
                    ( { model | error = "Cannot read config file" }
                    , Cmd.none
                    )

                Err (Unknown msg) ->
                    ( { model | error = msg }
                    , Cmd.none
                    )
```

### JavaScript Error Mapping

```javascript
// Provide error mapping
var app = Canopy.Main.init({
    capabilities: {
        fs: {
            readFile: function(path) {
                return new Promise((resolve, reject) => {
                    try {
                        const content = readFileSync(path, 'utf8');
                        resolve(content);
                    } catch (e) {
                        if (e.code === 'ENOENT') {
                            reject({ type: 'NotFound' });
                        } else if (e.code === 'EACCES') {
                            reject({ type: 'PermissionDenied' });
                        } else {
                            reject({ type: 'Unknown', message: e.message });
                        }
                    }
                });
            }
        }
    }
});
```

## Working with Complex Types

### Records

```canopy
type alias User =
    { id : Int
    , name : String
    , email : String
    }


type alias UserService =
    { getUser : Int -> Task Never User
    , createUser : User -> Task Never User
    }


foreign import userService : UserService
```

JavaScript returns/accepts plain objects that match the record structure.

### Custom Types

```canopy
type Status
    = Active
    | Inactive
    | Pending


type alias StatusService =
    { getStatus : Int -> Task Never Status
    }
```

JavaScript representation:

```javascript
// Custom types are represented as tagged unions
{ tag: 'Active' }
{ tag: 'Inactive' }
{ tag: 'Pending' }

// With data
{ tag: 'Error', data: 'Something went wrong' }
```

### JSON Values

For dynamic data, use `Json.Value`:

```canopy
type alias Api =
    { fetch : String -> Task Never Json.Value
    }


foreign import api : Api


fetchData : String -> Cmd Msg
fetchData url =
    api.fetch url
        |> Task.map decodeResponse
        |> Task.attempt DataReceived
```

## Security Considerations

### Capability Principle

Only provide capabilities that are actually needed:

```javascript
// Good: Minimal capabilities
var app = Canopy.Main.init({
    capabilities: {
        storage: {
            getItem: key => localStorage.getItem(key),
            setItem: (key, value) => localStorage.setItem(key, value)
        }
    }
});

// Avoid: Exposing too much
var app = Canopy.Main.init({
    capabilities: {
        window: window  // Don't do this!
    }
});
```

### Validation

Validate data from JavaScript:

```canopy
type alias ExternalApi =
    { getData : Task Never Json.Value
    }


foreign import externalApi : ExternalApi


loadData : Cmd Msg
loadData =
    externalApi.getData
        |> Task.map validateAndDecode
        |> Task.attempt DataLoaded


validateAndDecode : Json.Value -> Result String Data
validateAndDecode json =
    Decode.decodeValue dataDecoder json
        |> Result.mapError Decode.errorToString
```

## Best Practices

### 1. Type All Capabilities

```canopy
-- Good: Fully typed capability
type alias Storage =
    { getItem : String -> Task Never (Maybe String)
    , setItem : String -> String -> Task Never ()
    }


foreign import storage : Storage


-- Avoid: Generic untyped interface
foreign import storage : Json.Value
```

### 2. Handle All Errors

```canopy
-- Good: Handle errors explicitly
loadUser : Int -> Cmd Msg
loadUser id =
    userService.getUser id
        |> Task.attempt UserLoaded


update msg model =
    case msg of
        UserLoaded (Ok user) -> ...
        UserLoaded (Err error) -> ...  -- Handle error!
```

### 3. Wrap Complex JavaScript

Create abstraction layers:

```canopy
-- Don't expose raw capability
-- Instead, provide a clean API

module Storage exposing (get, set, remove)


foreign import storage : StorageCapability


get : String -> Task Never (Maybe String)
get key =
    storage.getItem key


set : String -> String -> Task Never ()
set key value =
    storage.setItem key value


remove : String -> Task Never ()
remove key =
    storage.removeItem key
```

### 4. Document Capabilities

```canopy
{-| Console capability for logging.

Provides access to browser console methods.

**Required JavaScript:**

```javascript
capabilities: {
    console: window.console
}
```

-}
foreign import console : Console
```

## Next Steps

- **[Do-Notation](./do-notation.md)**: Chain FFI tasks elegantly
- **[Testing](./testing.md)**: Test FFI code
- **[Commands](./commands.md)**: Using FFI with commands
