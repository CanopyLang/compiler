# Canopy vs TypeScript

Both Canopy and TypeScript help you write safer JavaScript. Here's how they compare.

## Philosophy

| Aspect | Canopy | TypeScript |
|--------|--------|------------|
| **Type Safety** | Sound type system, no runtime type errors | Gradual typing, some runtime holes |
| **Paradigm** | Purely functional | Multi-paradigm |
| **Null Handling** | No null/undefined, uses Maybe | Optional with strictNullChecks |
| **Mutations** | Immutable by default | Mutable by default |
| **Side Effects** | Explicit via Cmd/Task | Implicit anywhere |

## Type System Comparison

### Null Safety

**TypeScript:**
```typescript
function getUser(id: number): User | null {
    return users.find(u => u.id === id) || null;
}

// Easy to forget null check
function greet(id: number): string {
    const user = getUser(id);
    return `Hello, ${user.name}`; // Possible runtime error!
}

// With strict null checks
function greetSafe(id: number): string {
    const user = getUser(id);
    if (user === null) {
        return "User not found";
    }
    return `Hello, ${user.name}`;
}
```

**Canopy:**
```canopy
getUser : Int -> Maybe User
getUser id =
    List.find (\u -> u.id == id) users


-- Must handle both cases - won't compile otherwise
greet : Int -> String
greet id =
    case getUser id of
        Just user ->
            "Hello, " ++ user.name

        Nothing ->
            "User not found"


-- Or use helper functions
greet : Int -> String
greet id =
    getUser id
        |> Maybe.map (\user -> "Hello, " ++ user.name)
        |> Maybe.withDefault "User not found"
```

### Error Handling

**TypeScript:**
```typescript
async function fetchUser(id: number): Promise<User> {
    const response = await fetch(`/api/users/${id}`);
    if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
    }
    return response.json();
}

// Caller might forget try/catch
async function displayUser(id: number) {
    const user = await fetchUser(id); // Can throw!
    console.log(user.name);
}
```

**Canopy:**
```canopy
fetchUser : Int -> Task Http.Error User
fetchUser id =
    Http.get
        { url = "/api/users/" ++ String.fromInt id
        , expect = Http.expectJson GotUser userDecoder
        }


-- Error handling is enforced
update msg model =
    case msg of
        GotUser result ->
            case result of
                Ok user ->
                    ( { model | user = Just user }, Cmd.none )

                Err error ->
                    ( { model | error = Just error }, Cmd.none )
```

### Exhaustive Pattern Matching

**TypeScript:**
```typescript
type Status = 'active' | 'inactive' | 'pending';

function getStatusColor(status: Status): string {
    switch (status) {
        case 'active': return 'green';
        case 'inactive': return 'gray';
        // Forgot 'pending' - no compile error by default!
    }
}

// Need explicit exhaustiveness check
function getStatusColorExhaustive(status: Status): string {
    switch (status) {
        case 'active': return 'green';
        case 'inactive': return 'gray';
        case 'pending': return 'yellow';
        default:
            const _exhaustive: never = status;
            return _exhaustive;
    }
}
```

**Canopy:**
```canopy
type Status
    = Active
    | Inactive
    | Pending


getStatusColor : Status -> String
getStatusColor status =
    case status of
        Active -> "green"
        Inactive -> "gray"
        -- Compile error: Missing patterns: Pending


-- Must handle all cases
getStatusColor : Status -> String
getStatusColor status =
    case status of
        Active -> "green"
        Inactive -> "gray"
        Pending -> "yellow"
```

## State Management

**TypeScript (with Redux):**
```typescript
// Action types
const INCREMENT = 'INCREMENT';
const DECREMENT = 'DECREMENT';

interface IncrementAction {
    type: typeof INCREMENT;
}

interface DecrementAction {
    type: typeof DECREMENT;
}

type Action = IncrementAction | DecrementAction;

// Reducer
function counterReducer(state = 0, action: Action): number {
    switch (action.type) {
        case INCREMENT:
            return state + 1;
        case DECREMENT:
            return state - 1;
        default:
            return state;
    }
}

// Usage in component
function Counter() {
    const count = useSelector(state => state.counter);
    const dispatch = useDispatch();

    return (
        <div>
            <button onClick={() => dispatch({ type: DECREMENT })}>-</button>
            <span>{count}</span>
            <button onClick={() => dispatch({ type: INCREMENT })}>+</button>
        </div>
    );
}
```

**Canopy:**
```canopy
type alias Model =
    { count : Int
    }


type Msg
    = Increment
    | Decrement


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + 1 }

        Decrement ->
            { model | count = model.count - 1 }


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Decrement ] [ text "-" ]
        , text (String.fromInt model.count)
        , button [ onClick Increment ] [ text "+" ]
        ]
```

## Immutability

**TypeScript:**
```typescript
interface User {
    name: string;
    settings: {
        theme: string;
        notifications: boolean;
    };
}

// Mutation is easy (and common)
function updateTheme(user: User, theme: string) {
    user.settings.theme = theme; // Mutates!
}

// Immutable update is verbose
function updateThemeImmutable(user: User, theme: string): User {
    return {
        ...user,
        settings: {
            ...user.settings,
            theme
        }
    };
}
```

**Canopy:**
```canopy
type alias User =
    { name : String
    , settings : Settings
    }


type alias Settings =
    { theme : String
    , notifications : Bool
    }


-- Only option - always immutable
updateTheme : String -> User -> User
updateTheme theme user =
    { user | settings = { (user.settings) | theme = theme } }


-- Or with nested update helper
updateSettings : (Settings -> Settings) -> User -> User
updateSettings f user =
    { user | settings = f user.settings }


updateTheme : String -> User -> User
updateTheme theme =
    updateSettings (\s -> { s | theme = theme })
```

## Side Effects

**TypeScript:**
```typescript
// Side effects can happen anywhere
async function loadUserData(userId: number) {
    console.log('Loading user...'); // Side effect
    localStorage.setItem('lastUser', userId.toString()); // Side effect
    const user = await fetch(`/api/users/${userId}`); // Side effect
    analytics.track('user_loaded'); // Side effect
    return user.json();
}
```

**Canopy:**
```canopy
-- Side effects are explicit and controlled
loadUserData : Int -> Cmd Msg
loadUserData userId =
    Cmd.batch
        [ -- Each side effect is explicit
          logMessage "Loading user..."
        , saveToStorage "lastUser" (String.fromInt userId)
        , fetchUser userId
        , trackEvent "user_loaded"
        ]


-- They can only run through the update function
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoadUser userId ->
            ( { model | loading = True }
            , loadUserData userId
            )
```

## When to Choose Canopy

**Choose Canopy when:**

- Reliability is critical (no runtime errors)
- You want enforced best practices
- You prefer functional programming
- You're building complex UIs with lots of state
- You want excellent refactoring support

**Choose TypeScript when:**

- You need to work with existing JavaScript libraries
- Your team is more familiar with OOP
- You need maximum flexibility
- You're integrating with non-JS backends
- You need the full npm ecosystem

## Migration Path

You can use both together:

1. **Canopy for UI**: Build reliable interfaces in Canopy
2. **TypeScript for complex JS interop**: Use ports to communicate
3. **Gradual adoption**: Start with one component, expand from there

```javascript
// TypeScript code
const app = Canopy.Main.init({
    node: document.getElementById('app'),
    flags: getInitialData()
});

// Send data to Canopy
app.ports.receiveData.send(processData(rawData));

// Receive data from Canopy
app.ports.sendData.subscribe((data: CanopyData) => {
    saveToServer(data);
});
```

## Summary

| Feature | Canopy | TypeScript |
|---------|--------|------------|
| Null safety | Built-in (Maybe) | Optional (strictNullChecks) |
| Runtime errors | Impossible | Possible |
| Learning curve | Steeper | Gentler |
| Ecosystem | Smaller, curated | Massive (npm) |
| Refactoring | Excellent | Good |
| Performance | Very good | Excellent |
| Team adoption | Requires buy-in | Easy |
