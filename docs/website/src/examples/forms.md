# Forms Example

Comprehensive form handling with validation, error display, and submission.

## Complete Form Example

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, button, div, form, input, label, p, select, option, text, textarea)
import Html.Attributes exposing (class, disabled, for, id, placeholder, required, selected, type_, value)
import Html.Events exposing (onCheck, onInput, onSubmit)


-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        , view = view
        }


-- MODEL


type alias Model =
    { form : FormData
    , errors : FormErrors
    , status : FormStatus
    }


type alias FormData =
    { name : String
    , email : String
    , password : String
    , confirmPassword : String
    , age : String
    , country : String
    , bio : String
    , agreeToTerms : Bool
    }


type alias FormErrors =
    { name : Maybe String
    , email : Maybe String
    , password : Maybe String
    , confirmPassword : Maybe String
    , age : Maybe String
    , country : Maybe String
    , agreeToTerms : Maybe String
    }


type FormStatus
    = Editing
    | Submitting
    | Submitted
    | Failed String


emptyForm : FormData
emptyForm =
    { name = ""
    , email = ""
    , password = ""
    , confirmPassword = ""
    , age = ""
    , country = ""
    , bio = ""
    , agreeToTerms = False
    }


emptyErrors : FormErrors
emptyErrors =
    { name = Nothing
    , email = Nothing
    , password = Nothing
    , confirmPassword = Nothing
    , age = Nothing
    , country = Nothing
    , agreeToTerms = Nothing
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { form = emptyForm
      , errors = emptyErrors
      , status = Editing
      }
    , Cmd.none
    )


-- UPDATE


type Msg
    = UpdateName String
    | UpdateEmail String
    | UpdatePassword String
    | UpdateConfirmPassword String
    | UpdateAge String
    | UpdateCountry String
    | UpdateBio String
    | UpdateAgreeToTerms Bool
    | Submit
    | SubmitComplete (Result String ())


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateName value ->
            updateField (\f -> { f | name = value }) model

        UpdateEmail value ->
            updateField (\f -> { f | email = value }) model

        UpdatePassword value ->
            updateField (\f -> { f | password = value }) model

        UpdateConfirmPassword value ->
            updateField (\f -> { f | confirmPassword = value }) model

        UpdateAge value ->
            updateField (\f -> { f | age = value }) model

        UpdateCountry value ->
            updateField (\f -> { f | country = value }) model

        UpdateBio value ->
            updateField (\f -> { f | bio = value }) model

        UpdateAgreeToTerms value ->
            updateField (\f -> { f | agreeToTerms = value }) model

        Submit ->
            let
                errors =
                    validateForm model.form
            in
            if hasErrors errors then
                ( { model | errors = errors }
                , Cmd.none
                )

            else
                ( { model | status = Submitting, errors = emptyErrors }
                , submitForm model.form
                )

        SubmitComplete result ->
            case result of
                Ok _ ->
                    ( { model
                        | status = Submitted
                        , form = emptyForm
                      }
                    , Cmd.none
                    )

                Err error ->
                    ( { model | status = Failed error }
                    , Cmd.none
                    )


updateField : (FormData -> FormData) -> Model -> ( Model, Cmd Msg )
updateField updater model =
    ( { model | form = updater model.form }
    , Cmd.none
    )


-- VALIDATION


validateForm : FormData -> FormErrors
validateForm form =
    { name = validateName form.name
    , email = validateEmail form.email
    , password = validatePassword form.password
    , confirmPassword = validateConfirmPassword form.password form.confirmPassword
    , age = validateAge form.age
    , country = validateCountry form.country
    , agreeToTerms = validateAgreeToTerms form.agreeToTerms
    }


validateName : String -> Maybe String
validateName name =
    if String.isEmpty (String.trim name) then
        Just "Name is required"

    else if String.length name < 2 then
        Just "Name must be at least 2 characters"

    else
        Nothing


validateEmail : String -> Maybe String
validateEmail email =
    if String.isEmpty email then
        Just "Email is required"

    else if not (String.contains "@" email && String.contains "." email) then
        Just "Please enter a valid email address"

    else
        Nothing


validatePassword : String -> Maybe String
validatePassword password =
    if String.isEmpty password then
        Just "Password is required"

    else if String.length password < 8 then
        Just "Password must be at least 8 characters"

    else if not (String.any Char.isUpper password) then
        Just "Password must contain at least one uppercase letter"

    else if not (String.any Char.isDigit password) then
        Just "Password must contain at least one number"

    else
        Nothing


validateConfirmPassword : String -> String -> Maybe String
validateConfirmPassword password confirmPassword =
    if String.isEmpty confirmPassword then
        Just "Please confirm your password"

    else if password /= confirmPassword then
        Just "Passwords do not match"

    else
        Nothing


validateAge : String -> Maybe String
validateAge ageStr =
    if String.isEmpty ageStr then
        Just "Age is required"

    else
        case String.toInt ageStr of
            Just age ->
                if age < 13 then
                    Just "You must be at least 13 years old"

                else if age > 120 then
                    Just "Please enter a valid age"

                else
                    Nothing

            Nothing ->
                Just "Please enter a valid number"


validateCountry : String -> Maybe String
validateCountry country =
    if String.isEmpty country then
        Just "Please select a country"

    else
        Nothing


validateAgreeToTerms : Bool -> Maybe String
validateAgreeToTerms agreed =
    if not agreed then
        Just "You must agree to the terms"

    else
        Nothing


hasErrors : FormErrors -> Bool
hasErrors errors =
    List.any ((/=) Nothing)
        [ errors.name
        , errors.email
        , errors.password
        , errors.confirmPassword
        , errors.age
        , errors.country
        , errors.agreeToTerms
        ]


-- SUBMIT


submitForm : FormData -> Cmd Msg
submitForm form =
    -- In a real app, this would be an HTTP request
    Process.sleep 1000
        |> Task.perform (\_ -> SubmitComplete (Ok ()))


-- VIEW


view : Model -> Html Msg
view model =
    div [ class "form-container" ]
        [ viewStatus model.status
        , viewForm model
        ]


viewStatus : FormStatus -> Html Msg
viewStatus status =
    case status of
        Editing ->
            text ""

        Submitting ->
            div [ class "status submitting" ] [ text "Submitting..." ]

        Submitted ->
            div [ class "status success" ] [ text "Registration successful!" ]

        Failed error ->
            div [ class "status error" ] [ text ("Error: " ++ error) ]


viewForm : Model -> Html Msg
viewForm model =
    let
        isSubmitting =
            model.status == Submitting
    in
    form [ onSubmit Submit, class "registration-form" ]
        [ viewTextField
            { label = "Name"
            , id = "name"
            , value = model.form.name
            , onInput = UpdateName
            , error = model.errors.name
            , disabled = isSubmitting
            , type_ = "text"
            , placeholder = "John Doe"
            }
        , viewTextField
            { label = "Email"
            , id = "email"
            , value = model.form.email
            , onInput = UpdateEmail
            , error = model.errors.email
            , disabled = isSubmitting
            , type_ = "email"
            , placeholder = "john@example.com"
            }
        , viewTextField
            { label = "Password"
            , id = "password"
            , value = model.form.password
            , onInput = UpdatePassword
            , error = model.errors.password
            , disabled = isSubmitting
            , type_ = "password"
            , placeholder = "At least 8 characters"
            }
        , viewTextField
            { label = "Confirm Password"
            , id = "confirmPassword"
            , value = model.form.confirmPassword
            , onInput = UpdateConfirmPassword
            , error = model.errors.confirmPassword
            , disabled = isSubmitting
            , type_ = "password"
            , placeholder = "Repeat your password"
            }
        , viewTextField
            { label = "Age"
            , id = "age"
            , value = model.form.age
            , onInput = UpdateAge
            , error = model.errors.age
            , disabled = isSubmitting
            , type_ = "number"
            , placeholder = "25"
            }
        , viewSelect
            { label = "Country"
            , id = "country"
            , value = model.form.country
            , onInput = UpdateCountry
            , error = model.errors.country
            , disabled = isSubmitting
            , options = countries
            }
        , viewTextarea
            { label = "Bio (optional)"
            , id = "bio"
            , value = model.form.bio
            , onInput = UpdateBio
            , disabled = isSubmitting
            , placeholder = "Tell us about yourself..."
            }
        , viewCheckbox
            { label = "I agree to the terms and conditions"
            , id = "agreeToTerms"
            , checked = model.form.agreeToTerms
            , onCheck = UpdateAgreeToTerms
            , error = model.errors.agreeToTerms
            , disabled = isSubmitting
            }
        , button
            [ type_ "submit"
            , class "submit-button"
            , disabled isSubmitting
            ]
            [ text
                (if isSubmitting then
                    "Registering..."

                 else
                    "Register"
                )
            ]
        ]


countries : List ( String, String )
countries =
    [ ( "", "Select a country" )
    , ( "us", "United States" )
    , ( "uk", "United Kingdom" )
    , ( "ca", "Canada" )
    , ( "au", "Australia" )
    , ( "de", "Germany" )
    , ( "fr", "France" )
    ]


-- FORM FIELD COMPONENTS


type alias TextFieldConfig msg =
    { label : String
    , id : String
    , value : String
    , onInput : String -> msg
    , error : Maybe String
    , disabled : Bool
    , type_ : String
    , placeholder : String
    }


viewTextField : TextFieldConfig msg -> Html msg
viewTextField config =
    div [ class "field" ]
        [ label [ for config.id ] [ text config.label ]
        , input
            [ id config.id
            , type_ config.type_
            , value config.value
            , onInput config.onInput
            , disabled config.disabled
            , placeholder config.placeholder
            , class
                (if config.error /= Nothing then
                    "error"

                 else
                    ""
                )
            ]
            []
        , viewError config.error
        ]


type alias SelectConfig msg =
    { label : String
    , id : String
    , value : String
    , onInput : String -> msg
    , error : Maybe String
    , disabled : Bool
    , options : List ( String, String )
    }


viewSelect : SelectConfig msg -> Html msg
viewSelect config =
    div [ class "field" ]
        [ label [ for config.id ] [ text config.label ]
        , select
            [ id config.id
            , onInput config.onInput
            , disabled config.disabled
            ]
            (List.map
                (\( val, lbl ) ->
                    option
                        [ value val
                        , selected (val == config.value)
                        ]
                        [ text lbl ]
                )
                config.options
            )
        , viewError config.error
        ]


type alias TextareaConfig msg =
    { label : String
    , id : String
    , value : String
    , onInput : String -> msg
    , disabled : Bool
    , placeholder : String
    }


viewTextarea : TextareaConfig msg -> Html msg
viewTextarea config =
    div [ class "field" ]
        [ label [ for config.id ] [ text config.label ]
        , textarea
            [ id config.id
            , value config.value
            , onInput config.onInput
            , disabled config.disabled
            , placeholder config.placeholder
            ]
            []
        ]


type alias CheckboxConfig msg =
    { label : String
    , id : String
    , checked : Bool
    , onCheck : Bool -> msg
    , error : Maybe String
    , disabled : Bool
    }


viewCheckbox : CheckboxConfig msg -> Html msg
viewCheckbox config =
    div [ class "field checkbox-field" ]
        [ label [ class "checkbox-label" ]
            [ input
                [ type_ "checkbox"
                , Html.Attributes.checked config.checked
                , onCheck config.onCheck
                , disabled config.disabled
                ]
                []
            , text config.label
            ]
        , viewError config.error
        ]


viewError : Maybe String -> Html msg
viewError maybeError =
    case maybeError of
        Just error ->
            p [ class "field-error" ] [ text error ]

        Nothing ->
            text ""
```

## Key Concepts

### Controlled Inputs

Every input is controlled - its value comes from the model:

```canopy
input
    [ value model.form.email
    , onInput UpdateEmail
    ]
    []
```

### Validation on Submit

Validate all fields when submitting:

```canopy
Submit ->
    let
        errors = validateForm model.form
    in
    if hasErrors errors then
        ( { model | errors = errors }, Cmd.none )
    else
        ( { model | status = Submitting }, submitForm )
```

### Real-time Validation

For real-time validation, validate on each input:

```canopy
UpdateEmail value ->
    let
        form = { model.form | email = value }
        errors = { model.errors | email = validateEmail value }
    in
    ( { model | form = form, errors = errors }, Cmd.none )
```

### Debounced Validation

For expensive validation:

```canopy
UpdateEmail value ->
    ( { model | form = updateEmail value model.form }
    , debounce 300 (ValidateEmail value)
    )
```
