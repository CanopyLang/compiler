# Plan 24: Type-Safe Forms

## Priority: CRITICAL — Tier 1
## Effort: 4-5 weeks
## Depends on: Plan 03 (packages)

## Problem

Forms are the #1 pain point in web development. React developers juggle React Hook Form + Zod + Formik. Angular has reactive forms. Elm has... nothing built in. Developers write hundreds of lines of boilerplate for every form.

A typed functional language should make forms trivial.

## Solution: Schema-Driven Forms

Define the schema once. The compiler derives validation, UI, serialization, and server-side validation from it.

### Schema Definition

```canopy
module Forms.SignUp exposing (SignUpForm, signUpForm)

import Form exposing (Form, field, required, optional, email, minLength, matches)

type alias SignUpData =
    { name : String
    , email : String
    , password : String
    , confirmPassword : String
    , acceptTerms : Bool
    }

signUpForm : Form SignUpData Msg
signUpForm =
    Form.form SignUpData
        |> field "name"
            [ required "Name is required"
            , minLength 2 "Name must be at least 2 characters"
            ]
        |> field "email"
            [ required "Email is required"
            , email "Must be a valid email address"
            ]
        |> field "password"
            [ required "Password is required"
            , minLength 8 "Password must be at least 8 characters"
            , matches "[A-Z]" "Must contain an uppercase letter"
            , matches "[0-9]" "Must contain a number"
            ]
        |> field "confirmPassword"
            [ required "Please confirm your password"
            , Form.matchesField "password" "Passwords must match"
            ]
        |> field "acceptTerms"
            [ Form.mustBeTrue "You must accept the terms"
            ]
```

### Auto-Generated UI

```canopy
view model =
    Form.view signUpForm model.formState
        { onSubmit = FormSubmitted
        , onChange = FormChanged
        , submitLabel = "Create Account"
        }
```

This generates:
- Labeled inputs for each field (accessible, with `for`/`id` association)
- Validation error messages shown on blur/submit
- Disabled submit button until valid
- Loading state during submission
- Correct input types (email → `type="email"`, password → `type="password"`)

### Form State Management

```canopy
type alias Model =
    { formState : Form.State SignUpData
    }

init =
    ( { formState = Form.init signUpForm }
    , Cmd.none
    )

update msg model =
    case msg of
        FormChanged state ->
            ( { model | formState = state }, Cmd.none )

        FormSubmitted data ->
            -- `data` is already validated and typed as SignUpData
            ( model, submitToServer data )
```

### Validation Runs Everywhere

The same schema generates:
- **Client-side**: Real-time validation as user types
- **Server-side**: Request body validation in API routes (CanopyKit)
- **Compile-time**: Type checking ensures all fields are handled

```canopy
-- In an API route:
handleSignUp : Request -> Task ApiError Response
handleSignUp request =
    Form.decodeBody signUpForm request
        |> Task.andThen (\data ->
            -- `data` is validated SignUpData, guaranteed to pass all rules
            createUser data
        )
```

### Advanced Patterns

```canopy
-- Multi-step wizard:
wizard =
    Form.wizard
        [ ( "Personal Info", personalForm )
        , ( "Address", addressForm )
        , ( "Payment", paymentForm )
        ]

-- Dynamic fields (add/remove items):
itemsForm =
    Form.list "items"
        (Form.form Item
            |> field "name" [ required "Required" ]
            |> field "quantity" [ Form.int, Form.min 1 "Min 1" ]
        )

-- Dependent validation:
dateRangeForm =
    Form.form DateRange
        |> field "startDate" [ required "Required" ]
        |> field "endDate"
            [ required "Required"
            , Form.afterField "startDate" "End date must be after start date"
            ]
```

### Dirty/Touched/Pristine Tracking

Built into `Form.State`:

```canopy
Form.isDirty model.formState          -- any field changed?
Form.isTouched "email" model.formState -- was email field focused/blurred?
Form.errors "password" model.formState -- current validation errors for field
Form.isValid model.formState           -- all validations pass?
Form.isSubmitting model.formState      -- submission in progress?
```

## Implementation

### Phase 1: Core form types and validation (Weeks 1-2)
- `Form`, `Form.State`, field combinators
- Built-in validators (required, minLength, email, matches, etc.)
- Client-side validation engine
- State management (dirty/touched/pristine)

### Phase 2: Auto-generated UI (Week 3)
- Default renderers for each field type
- Accessible markup generation (labels, error messages, ARIA)
- Custom renderer API for full control

### Phase 3: Server-side validation (Week 4)
- `Form.decodeBody` for API routes
- Same validation rules run on server
- JSON schema generation from form schema

### Phase 4: Advanced patterns (Week 5)
- Multi-step wizard
- Dynamic field lists
- Dependent validation
- File upload with progress
