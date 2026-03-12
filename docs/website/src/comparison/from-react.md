# Canopy for React Developers

If you know React, you already understand components, state, and side effects. Canopy
approaches these same problems differently — and once you see the mapping, everything
clicks. This guide translates React patterns directly into Canopy equivalents.

## The Mental Model Shift

React applications are a tree of components, each managing their own state. Canopy
applications have a single state tree with one update function. Think of it like
switching from many small `useReducer` hooks scattered across your component tree to
one big Redux store — except without the ceremony, and with a type system that
guarantees correctness.

| React | Canopy |
|-------|--------|
| Component state (`useState`) | `Model` type |
| Reducer (`useReducer`) | `update` function |
| JSX | `Html` module functions |
| Props | Function arguments |
| `useEffect` | `Cmd` (commands) |
| Event listeners | `Sub` (subscriptions) |
| `async`/`await` | `Task` with do-notation |
| `null` | `Maybe` |
| Union types | Custom types |
| `interface` / TypeScript types | Type aliases and custom types |

---

## 1. Core Architecture: Components vs. TEA

**React** distributes state across component hooks. **Canopy** uses The Elm Architecture
(TEA): one `Model`, one `update`, one `view`.

**React:**
```jsx
function Counter() {
    const [count, setCount] = useState(0);

    return (
        <div>
            <button onClick={() => setCount(count - 1)}>-</button>
            <span>{count}</span>
            <button onClick={() => setCount(count + 1)}>+</button>
        </div>
    );
}
```

**Canopy:**
```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, span, text)
import Html.Events exposing (onClick)


type alias Model =
    { count : Int
    }


type Msg
    = Increment
    | Decrement


init : Model
init =
    { count = 0 }


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
        , span [] [ text (String.fromInt model.count) ]
        , button [ onClick Increment ] [ text "+" ]
        ]


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
```

The `view` function receives the whole model and returns `Html Msg`. There are no
component instances — just functions producing HTML. The Canopy runtime calls `view`
whenever the model changes and efficiently patches the DOM.

---

## 2. State Management

### `useState` → Model fields

**React:**
```jsx
function UserProfile() {
    const [name, setName] = useState("");
    const [email, setEmail] = useState("");
    const [loading, setLoading] = useState(false);

    // ...
}
```

**Canopy:**
```canopy
type alias Model =
    { name : String
    , email : String
    , loading : Bool
    }


init : Model
init =
    { name = ""
    , email = ""
    , loading = False
    }
```

All state lives in `Model`. There is no per-field setter — the `update` function
produces a new model when a message arrives.

### `useReducer` → `update`

React's `useReducer` is structurally identical to Canopy's `update`. If you already
use reducers, the translation is almost mechanical.

**React:**
```jsx
const initialState = { count: 0, step: 1 };

function reducer(state, action) {
    switch (action.type) {
        case 'INCREMENT':
            return { ...state, count: state.count + action.step };
        case 'SET_STEP':
            return { ...state, step: action.value };
        default:
            return state;
    }
}

function Counter() {
    const [state, dispatch] = useReducer(reducer, initialState);

    return (
        <div>
            <button onClick={() => dispatch({ type: 'INCREMENT', step: state.step })}>
                +{state.step}
            </button>
            <input
                type="number"
                value={state.step}
                onChange={e => dispatch({ type: 'SET_STEP', value: Number(e.target.value) })}
            />
            <p>Count: {state.count}</p>
        </div>
    );
}
```

**Canopy:**
```canopy
type alias Model =
    { count : Int
    , step : Int
    }


type Msg
    = Increment
    | SetStep String


init : Model
init =
    { count = 0, step = 1 }


update : Msg -> Model -> Model
update msg model =
    case msg of
        Increment ->
            { model | count = model.count + model.step }

        SetStep value ->
            { model | step = Maybe.withDefault model.step (String.toInt value) }


view : Model -> Html Msg
view model =
    div []
        [ button [ onClick Increment ] [ text ("+" ++ String.fromInt model.step) ]
        , input
            [ type_ "number"
            , value (String.fromInt model.step)
            , onInput SetStep
            ]
            []
        , p [] [ text ("Count: " ++ String.fromInt model.count) ]
        ]
```

The key differences:
- `action.type` strings become type-safe `Msg` constructors
- No `default` branch — the compiler ensures every message is handled
- No spread operator — Canopy's record update syntax is `{ model | field = newValue }`

---

## 3. Components and Views

### JSX → Html functions

Every JSX element maps to a function in Canopy's `Html` module. The structure is:

```
elementName [ attributes ] [ children ]
```

**React:**
```jsx
<div className="card">
    <h1>{title}</h1>
    <p className="subtitle">{subtitle}</p>
    <button onClick={handleClick} disabled={isLoading}>
        {isLoading ? "Loading..." : "Submit"}
    </button>
</div>
```

**Canopy:**
```canopy
div [ class "card" ]
    [ h1 [] [ text title ]
    , p [ class "subtitle" ] [ text subtitle ]
    , button
        [ onClick HandleClick
        , disabled isLoading
        ]
        [ text
            (if isLoading then
                "Loading..."
             else
                "Submit"
            )
        ]
    ]
```

Common attribute translations:

| React | Canopy |
|-------|--------|
| `className` | `class` |
| `onClick={fn}` | `onClick Msg` |
| `onChange={e => f(e.target.value)}` | `onInput MsgConstructor` |
| `onSubmit={fn}` | `onSubmit Msg` |
| `htmlFor` | `for` |
| `tabIndex` | `tabindex` |
| `style={{ color: 'red' }}` | `style "color: red"` |

### Props → Function arguments

React components accept props. Canopy view functions accept whatever arguments they
need — typically the full model or a slice of it.

**React:**
```jsx
function UserCard({ name, email, isAdmin, onDelete }) {
    return (
        <div className="user-card">
            <h2>{name}</h2>
            <p>{email}</p>
            {isAdmin && <span className="badge">Admin</span>}
            <button onClick={() => onDelete(email)}>Delete</button>
        </div>
    );
}
```

**Canopy:**
```canopy
type alias UserCardConfig msg =
    { name : String
    , email : String
    , isAdmin : Bool
    , onDelete : String -> msg
    }


viewUserCard : UserCardConfig msg -> Html msg
viewUserCard config =
    div [ class "user-card" ]
        [ h2 [] [ text config.name ]
        , p [] [ text config.email ]
        , if config.isAdmin then
            span [ class "badge" ] [ text "Admin" ]
          else
            text ""
        , button [ onClick (config.onDelete config.email) ] [ text "Delete" ]
        ]
```

The `msg` type variable in `Html msg` means the view function works with any message
type — the same composability as generic React components.

### Lists of elements

**React:**
```jsx
function UserList({ users }) {
    return (
        <ul>
            {users.map(user => (
                <li key={user.id}>{user.name}</li>
            ))}
        </ul>
    );
}
```

**Canopy:**
```canopy
viewUserList : List User -> Html Msg
viewUserList users =
    ul [] (List.map viewUserItem users)


viewUserItem : User -> Html Msg
viewUserItem user =
    li [] [ text user.name ]
```

There is no `key` prop in Canopy — the virtual DOM reconciliation handles this
automatically using structural position.

---

## 4. Effects and Side Effects

### `useEffect` → `Cmd`

React's `useEffect` runs after render for side effects. In Canopy, the `update`
function returns a tuple `( Model, Cmd Msg )` — the model update and a command
describing what side effect to perform.

**React:**
```jsx
function UserProfile({ userId }) {
    const [user, setUser] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        setLoading(true);
        fetch(`/api/users/${userId}`)
            .then(r => r.json())
            .then(data => {
                setUser(data);
                setLoading(false);
            });
    }, [userId]);

    if (loading) return <p>Loading...</p>;
    if (!user) return <p>Not found</p>;
    return <h1>{user.name}</h1>;
}
```

**Canopy:**
```canopy
type alias Model =
    { userId : Int
    , user : Maybe User
    , loading : Bool
    }


type Msg
    = FetchUser Int
    | GotUser (Result Http.Error User)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FetchUser userId ->
            ( { model | userId = userId, loading = True }
            , Http.get
                { url = "/api/users/" ++ String.fromInt userId
                , expect = Http.expectJson GotUser userDecoder
                }
            )

        GotUser result ->
            case result of
                Ok user ->
                    ( { model | user = Just user, loading = False }
                    , Cmd.none
                    )

                Err _ ->
                    ( { model | loading = False }
                    , Cmd.none
                    )


view : Model -> Html Msg
view model =
    if model.loading then
        p [] [ text "Loading..." ]
    else
        case model.user of
            Just user ->
                h1 [] [ text user.name ]

            Nothing ->
                p [] [ text "Not found" ]
```

The critical difference: there is no implicit "run this when userId changes" — you
trigger `FetchUser` explicitly from `init` or from a navigation message.

### HTTP requests: `fetch`/axios → `Http.get`/`Http.post`

**React:**
```jsx
async function createPost(title, body) {
    const response = await fetch('/api/posts', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, body })
    });
    return response.json();
}
```

**Canopy:**
```canopy
import Http
import Json.Encode as Encode


type Msg
    = PostCreated (Result Http.Error Post)


createPost : String -> String -> Cmd Msg
createPost title body =
    Http.post
        { url = "/api/posts"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "title", Encode.string title )
                    , ( "body", Encode.string body )
                    ]
                )
        , expect = Http.expectJson PostCreated postDecoder
        }
```

### Event listeners → `Sub`

**React:**
```jsx
function KeyboardHandler() {
    const [lastKey, setLastKey] = useState("");

    useEffect(() => {
        function handleKeyDown(e) {
            setLastKey(e.key);
        }
        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, []);

    return <p>Last key: {lastKey}</p>;
}
```

**Canopy:**
```canopy
import Browser.Events
import Json.Decode as Decode


type Msg
    = KeyPressed String


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onKeyDown keyDecoder


keyDecoder : Decode.Decoder Msg
keyDecoder =
    Decode.map KeyPressed (Decode.field "key" Decode.string)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        KeyPressed key ->
            ( { model | lastKey = key }, Cmd.none )


view : Model -> Html Msg
view model =
    p [] [ text ("Last key: " ++ model.lastKey) ]
```

The `subscriptions` function returns a `Sub Msg` based on the current model. Canopy
manages adding and removing the event listener automatically when the subscription changes.

---

## 5. Routing

### React Router → URL parser + `Browser.application`

**React Router:**
```jsx
function App() {
    return (
        <Router>
            <Routes>
                <Route path="/" element={<Home />} />
                <Route path="/users" element={<Users />} />
                <Route path="/users/:id" element={<UserProfile />} />
                <Route path="*" element={<NotFound />} />
            </Routes>
        </Router>
    );
}

function UserProfile() {
    const { id } = useParams();
    // ...
}
```

**Canopy:**
```canopy
import Browser
import Browser.Navigation as Nav
import Url
import Url.Parser as Parser exposing ((</>))


type Route
    = Home
    | Users
    | UserProfile String
    | NotFound


routeParser : Parser.Parser (Route -> a) a
routeParser =
    Parser.oneOf
        [ Parser.map Home Parser.top
        , Parser.map Users (Parser.s "users")
        , Parser.map UserProfile (Parser.s "users" </> Parser.string)
        ]


urlToRoute : Url.Url -> Route
urlToRoute url =
    Maybe.withDefault NotFound (Parser.parse routeParser url)


type alias Model =
    { key : Nav.Key
    , route : Route
    }


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked (Browser.Internal url) ->
            ( model, Nav.pushUrl model.key (Url.toString url) )

        LinkClicked (Browser.External href) ->
            ( model, Nav.load href )

        UrlChanged url ->
            ( { model | route = urlToRoute url }, Cmd.none )


view : Model -> Browser.Document Msg
view model =
    { title = routeTitle model.route
    , body =
        [ div []
            [ viewNav
            , viewPage model.route
            ]
        ]
    }


viewPage : Route -> Html Msg
viewPage route =
    case route of
        Home ->
            viewHome

        Users ->
            viewUsers

        UserProfile userId ->
            viewUserProfile userId

        NotFound ->
            viewNotFound
```

Route parameters live in the `Route` type — no `useParams()` hook needed. When you
match `UserProfile userId` in `viewPage`, the compiler guarantees `userId` is a `String`.

### Programmatic navigation

**React Router:**
```jsx
const navigate = useNavigate();
navigate('/users/alice');
```

**Canopy:**
```canopy
-- In update, return a navigation command
update msg model =
    case msg of
        GoToUser username ->
            ( model
            , Nav.pushUrl model.key ("/users/" ++ username)
            )
```

The `Nav.Key` is passed through your model, so navigation commands are always available
in `update`.

---

## 6. Forms

### Controlled components → Model fields + `onInput`

**React:**
```jsx
function SignupForm() {
    const [name, setName] = useState("");
    const [email, setEmail] = useState("");

    function handleSubmit(e) {
        e.preventDefault();
        submitSignup({ name, email });
    }

    return (
        <form onSubmit={handleSubmit}>
            <input
                value={name}
                onChange={e => setName(e.target.value)}
                placeholder="Name"
            />
            <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                placeholder="Email"
            />
            <button type="submit">Sign Up</button>
        </form>
    );
}
```

**Canopy:**
```canopy
type alias Model =
    { name : String
    , email : String
    , status : FormStatus
    }


type FormStatus
    = Editing
    | Submitting
    | Done


type Msg
    = NameChanged String
    | EmailChanged String
    | Submit
    | SubmitCompleted (Result Http.Error ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NameChanged value ->
            ( { model | name = value }, Cmd.none )

        EmailChanged value ->
            ( { model | email = value }, Cmd.none )

        Submit ->
            ( { model | status = Submitting }
            , submitSignup model.name model.email
            )

        SubmitCompleted (Ok _) ->
            ( { model | status = Done }, Cmd.none )

        SubmitCompleted (Err _) ->
            ( { model | status = Editing }, Cmd.none )


view : Model -> Html Msg
view model =
    form [ onSubmit Submit ]
        [ input
            [ value model.name
            , onInput NameChanged
            , placeholder "Name"
            ]
            []
        , input
            [ type_ "email"
            , value model.email
            , onInput EmailChanged
            , placeholder "Email"
            ]
            []
        , button
            [ type_ "submit"
            , disabled (model.status == Submitting)
            ]
            [ text "Sign Up" ]
        ]
```

`onInput` delivers the current input value as a `String` directly to your message
constructor. No `e.target.value` unwrapping required.

---

## 7. Context and Global State

### React Context / Redux → Model + flags

React Context solves prop drilling. In Canopy, there is no prop drilling to begin with
— the full `Model` is always available in `view` and `update`. Pass what each
sub-view needs as function arguments.

**React (with Context):**
```jsx
const ThemeContext = createContext('light');
const UserContext = createContext(null);

function App() {
    const [theme, setTheme] = useState('light');
    const [user, setUser] = useState(null);

    return (
        <ThemeContext.Provider value={theme}>
            <UserContext.Provider value={user}>
                <MainLayout />
            </UserContext.Provider>
        </ThemeContext.Provider>
    );
}

// Deep in the tree:
function UserAvatar() {
    const user = useContext(UserContext);
    const theme = useContext(ThemeContext);
    return <img className={theme} src={user.avatar} />;
}
```

**Canopy:**
```canopy
type alias Model =
    { user : Maybe User
    , theme : Theme
    , page : Page
    }


type Theme
    = Light
    | Dark


-- Pass shared state as arguments to sub-views
view : Model -> Html Msg
view model =
    div [ themeClass model.theme ]
        [ viewHeader model.user model.theme
        , viewContent model
        , viewFooter
        ]


viewHeader : Maybe User -> Theme -> Html Msg
viewHeader maybeUser theme =
    header [ themeClass theme ]
        [ case maybeUser of
            Just user ->
                viewUserAvatar user theme

            Nothing ->
                viewLoginButton
        ]


viewUserAvatar : User -> Theme -> Html Msg
viewUserAvatar user theme =
    img [ class (themeToClass theme), src user.avatar ] []
```

No providers, no context hooks, no prop drilling. The type system ensures every
sub-view gets exactly the data it declares it needs.

### Flags: initializing from JavaScript

Flags replace `localStorage` reads and external initial data that you might configure
via `window.__INITIAL_STATE__` in Redux:

```javascript
// JavaScript
const app = Canopy.Main.init({
    node: document.getElementById('app'),
    flags: {
        userId: localStorage.getItem('userId'),
        theme: localStorage.getItem('theme') || 'light'
    }
});
```

```canopy
-- Canopy
type alias Flags =
    { userId : Maybe String
    , theme : String
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { user = Nothing
      , theme = parseTheme flags.theme
      , userId = flags.userId
      }
    , case flags.userId of
        Just id ->
            fetchUser id

        Nothing ->
            Cmd.none
    )
```

---

## 8. Component Communication

### Parent-child: callbacks → `Msg` variants

**React:**
```jsx
function Parent() {
    const [selected, setSelected] = useState(null);

    return (
        <div>
            <ItemList onSelect={setSelected} />
            {selected && <ItemDetail item={selected} />}
        </div>
    );
}

function ItemList({ onSelect }) {
    return (
        <ul>
            {items.map(item => (
                <li key={item.id} onClick={() => onSelect(item)}>
                    {item.name}
                </li>
            ))}
        </ul>
    );
}
```

**Canopy:**
```canopy
type alias Model =
    { items : List Item
    , selected : Maybe Item
    }


type Msg
    = SelectItem Item
    | ClearSelection


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectItem item ->
            ( { model | selected = Just item }, Cmd.none )

        ClearSelection ->
            ( { model | selected = Nothing }, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ viewItemList model.items
        , case model.selected of
            Just item ->
                viewItemDetail item

            Nothing ->
                text ""
        ]


viewItemList : List Item -> Html Msg
viewItemList items =
    ul [] (List.map viewItem items)


viewItem : Item -> Html Msg
viewItem item =
    li [ onClick (SelectItem item) ] [ text item.name ]
```

Instead of passing a callback prop down, the child view produces `Html Msg` where
`Msg` is the parent's message type. `SelectItem` flows up through the runtime — no
manual callback threading.

### Child modules: `Cmd.map` and `delegate`

For genuinely independent sub-components (like a date picker or a rich text editor),
use sub-modules with their own `Model` and `Msg`, then wire them with `delegate`:

```canopy
import Platform.Delegate exposing (delegate, delegateSub)


-- Parent wraps child messages
type Msg
    = DatePickerMsg DatePicker.Msg
    | FormMsg Form.Msg


-- Parent update delegates to children
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        DatePickerMsg subMsg ->
            delegate DatePickerMsg
                (\m -> { model | datePicker = m })
                (DatePicker.update subMsg model.datePicker)

        FormMsg subMsg ->
            delegate FormMsg
                (\m -> { model | form = m })
                (Form.update subMsg model.form)
```

See the [Scaling TEA guide](../guide/scaling-tea.md) for the full `Platform.Delegate` API.

---

## 9. Common Patterns

### Fetching data on mount → `init` returning `Cmd`

**React:**
```jsx
useEffect(() => {
    fetchPosts().then(setPosts);
}, []); // Empty array = run once on mount
```

**Canopy:**
```canopy
init : () -> ( Model, Cmd Msg )
init _ =
    ( { posts = [], loading = True }
    , Http.get
        { url = "/api/posts"
        , expect = Http.expectJson GotPosts postsDecoder
        }
    )
```

`init` returns the initial model and an initial command. There is no "on mount" — the
app starts with `init` and the runtime executes the command immediately.

### Loading states → Custom type

**React:**
```jsx
const [status, setStatus] = useState('idle'); // 'idle' | 'loading' | 'success' | 'error'
const [data, setData] = useState(null);
const [error, setError] = useState(null);
```

**Canopy:**
```canopy
type RemoteData
    = NotAsked
    | Loading
    | Loaded (List Post)
    | Failed Http.Error


type alias Model =
    { posts : RemoteData
    }


view : Model -> Html Msg
view model =
    case model.posts of
        NotAsked ->
            button [ onClick FetchPosts ] [ text "Load Posts" ]

        Loading ->
            div [ class "spinner" ] []

        Loaded posts ->
            viewPostList posts

        Failed error ->
            div [ class "error" ] [ text (httpErrorToString error) ]
```

The custom type makes impossible states impossible. You cannot have both `data` and
`error` set simultaneously — the type system prevents it.

### Conditional rendering → `if` / `case`

**React:**
```jsx
{isLoggedIn && <UserMenu />}
{status === 'loading' ? <Spinner /> : <Content />}
```

**Canopy:**
```canopy
-- Boolean condition
if model.isLoggedIn then
    viewUserMenu model.user
else
    text ""

-- Pattern match on state
case model.status of
    Loading ->
        viewSpinner

    Ready data ->
        viewContent data

    Error message ->
        viewError message
```

### Lists → `List.map`

**React:**
```jsx
{posts.map(post => <PostCard key={post.id} post={post} />)}
```

**Canopy:**
```canopy
div [] (List.map viewPostCard model.posts)
```

---

## 10. TypeScript vs Canopy Types

### Interfaces → Type aliases

**TypeScript:**
```typescript
interface User {
    id: number;
    name: string;
    email: string;
    role: 'admin' | 'viewer';
}
```

**Canopy:**
```canopy
type UserRole
    = Admin
    | Viewer


type alias User =
    { id : Int
    , name : String
    , email : String
    , role : UserRole
    }
```

### Union types → Custom types

**TypeScript:**
```typescript
type ApiState<T> =
    | { status: 'idle' }
    | { status: 'loading' }
    | { status: 'success'; data: T }
    | { status: 'error'; message: string };
```

**Canopy:**
```canopy
type ApiState data
    = Idle
    | Loading
    | Success data
    | Failure String
```

Canopy's custom types are the same concept as TypeScript discriminated unions, but
exhaustiveness is checked at compile time with no extra configuration required.

### `null`/`undefined` → `Maybe`

**TypeScript:**
```typescript
function findUser(id: number): User | null {
    return users.find(u => u.id === id) ?? null;
}

// Caller must null-check:
const user = findUser(42);
if (user !== null) {
    console.log(user.name); // Safe
}
```

**Canopy:**
```canopy
findUser : Int -> Maybe User
findUser id =
    List.head (List.filter (\u -> u.id == id) users)


-- Caller pattern-matches — no way to skip the check:
case findUser 42 of
    Just user ->
        text user.name

    Nothing ->
        text "Not found"
```

There is no `null` or `undefined` in Canopy. `Maybe` is the only way to represent an
absent value, and the compiler enforces handling both cases.

### Generic components → Polymorphic functions

**TypeScript:**
```typescript
interface SelectProps<T> {
    options: T[];
    selected: T | null;
    getLabel: (item: T) => string;
    onSelect: (item: T) => void;
}

function Select<T>({ options, selected, getLabel, onSelect }: SelectProps<T>) {
    return (
        <select onChange={e => onSelect(options[Number(e.target.value)])}>
            {options.map((opt, i) => (
                <option key={i} value={i} selected={opt === selected}>
                    {getLabel(opt)}
                </option>
            ))}
        </select>
    );
}
```

**Canopy:**
```canopy
type alias SelectConfig a msg =
    { options : List a
    , selected : Maybe a
    , getLabel : a -> String
    , onSelect : a -> msg
    }


viewSelect : SelectConfig a msg -> Html msg
viewSelect config =
    select []
        (List.indexedMap
            (\i opt ->
                option
                    [ value (String.fromInt i)
                    , selected (config.selected == Just opt)
                    ]
                    [ text (config.getLabel opt) ]
            )
            config.options
        )
```

The type variable `a` works exactly like TypeScript's `T` — the function works for
any type of option, and the compiler infers it at each call site.

---

## 11. Migration Tips

### Start with leaf components

Pick a component that receives data as props and calls callbacks — no internal state,
no effects. These translate most directly into Canopy view functions.

### Convert one route at a time

Use Canopy's `Browser.element` to embed a Canopy app inside an existing React page.
The two can coexist and communicate through JavaScript:

```javascript
// Mount Canopy inside a React-managed div
const app = Canopy.UserProfile.init({
    node: document.getElementById('canopy-user-profile'),
    flags: { userId: currentUserId }
});

// React can send updates to Canopy via ports
app.ports.updateUserId.send(newUserId);

// React can receive events from Canopy
app.ports.userDeleted.subscribe(userId => {
    reactStore.dispatch(userDeletedAction(userId));
});
```

### The learning curve

The hardest adjustment from React:

1. **No local component state** — everything goes in `Model`. This feels restrictive
   at first and liberating once you realise the debugger can replay your entire app.

2. **Explicit effects** — there is no `useEffect`. Every side effect you want must be
   returned from `update` as a `Cmd`. Once you internalize this, async code becomes
   dramatically easier to reason about.

3. **Pattern matching everywhere** — instead of `if (user !== null)`, you write
   `case model.user of Just u -> ... ; Nothing -> ...`. The compiler verifies you
   handled every case.

### Tooling

```bash
# Install Canopy
npm install -g canopy

# Create a new project
canopy init my-app

# Build for development
canopy make src/Main.can

# Build for production (optimized, minified)
canopy make --optimize src/Main.can --output=main.js
```

The VS Code extension provides inline type errors, go-to-definition, and auto-formatting.

---

## Summary

| React concept | Canopy equivalent |
|---|---|
| `useState` | Field in `Model` |
| `useReducer` | `update` function |
| `useEffect` (on mount) | `init` returning `Cmd` |
| `useEffect` (on change) | `update` returning `Cmd` |
| `useContext` | Function argument from `view` |
| Event listener cleanup | `subscriptions` returning `Sub.none` |
| JSX element | `Html.div [ attrs ] [ children ]` |
| Callback prop | `Msg` type variant |
| `null`/`undefined` | `Maybe` |
| Discriminated union | Custom type |
| TypeScript interface | `type alias` record |
| Generic component | Polymorphic function |
| React Router `useParams` | Pattern match on `Route` variant |
| Redux store | `Model` |
| Redux action | `Msg` constructor |
| Redux reducer | `update` function |
| Redux `dispatch` | Return `Cmd` from `update` |

Canopy is not a different way to build React apps — it is a different model entirely.
The patterns above are starting points; once you feel the shape of TEA, you will find
solutions that have no React equivalent at all.
