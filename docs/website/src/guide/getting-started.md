# Getting Started

This guide will walk you through installing Canopy and creating your first application.

## Prerequisites

Before installing Canopy, ensure you have:

- **Node.js** version 16 or later
- **npm** or **yarn** package manager

## Installation

### Using npm (Recommended)

```bash
npm install -g canopy
```

### Using yarn

```bash
yarn global add canopy
```

### Verify Installation

After installation, verify that Canopy is correctly installed:

```bash
canopy --version
```

You should see output like:

```
Canopy 0.19.2
```

## Create Your First Project

### Initialize a New Project

Create a new Canopy project using the `init` command:

```bash
canopy init hello-canopy
cd hello-canopy
```

This creates a project with the following structure:

```
hello-canopy/
├── canopy.json        # Project configuration
├── src/
│   └── Main.can       # Main application file
└── public/
    └── index.html     # HTML entry point
```

### Project Configuration

The `canopy.json` file configures your project:

```json
{
    "type": "application",
    "source-directories": ["src"],
    "canopy-version": "0.19.2",
    "dependencies": {
        "direct": {
            "canopy/browser": "1.0.0",
            "canopy/core": "1.0.0",
            "canopy/html": "1.0.0",
            "canopy/json": "1.0.0"
        },
        "indirect": {
            "canopy/virtual-dom": "1.0.0"
        }
    }
}
```

## Hello World

Let's look at the generated `src/Main.can` file:

```canopy
module Main exposing (main)

import Browser
import Html exposing (Html, div, text)


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }


type alias Model =
    {}


init : Model
init =
    {}


type Msg
    = NoOp


update : Msg -> Model -> Model
update msg model =
    model


view : Model -> Html Msg
view model =
    div []
        [ text "Hello, Canopy!"
        ]
```

### Understanding the Code

Let's break down each part:

**Module Declaration**

```canopy
module Main exposing (main)
```

Every Canopy file is a module. The `exposing` clause lists what the module makes available to other modules.

**Imports**

```canopy
import Browser
import Html exposing (Html, div, text)
```

We import the `Browser` module for creating applications and `Html` for building the view.

**Main Program**

```canopy
main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , update = update
        , view = view
        }
```

The `main` value is the entry point. `Browser.sandbox` creates a simple application with no side effects.

**Model**

```canopy
type alias Model =
    {}

init : Model
init =
    {}
```

The model holds your application state. We start with an empty record.

**Messages**

```canopy
type Msg
    = NoOp
```

Messages describe events that can happen in your application.

**Update**

```canopy
update : Msg -> Model -> Model
update msg model =
    model
```

The update function handles messages and returns a new model.

**View**

```canopy
view : Model -> Html Msg
view model =
    div []
        [ text "Hello, Canopy!"
        ]
```

The view function renders your model as HTML.

## Running Your Application

### Development Server

Start the development server:

```bash
canopy reactor
```

Open your browser to `http://localhost:8000` and click on `src/Main.can` to see your application.

### Building for Production

Compile your application for production:

```bash
canopy make src/Main.can --output=main.js --optimize
```

This creates an optimized JavaScript file ready for deployment.

## Editor Setup

### Visual Studio Code

Install the Canopy extension for VS Code:

1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X / Cmd+Shift+X)
3. Search for "Canopy"
4. Install the Canopy Language Support extension

Features include:

- Syntax highlighting
- Inline type information
- Error highlighting
- Format on save
- Jump to definition

### Other Editors

- **Vim/Neovim**: Use the `canopy.vim` plugin
- **Emacs**: Use `canopy-mode`
- **Sublime Text**: Install the Canopy package

## Project Structure Best Practices

For larger projects, organize your code like this:

```
my-app/
├── canopy.json
├── src/
│   ├── Main.can           # Entry point
│   ├── Model.can          # Shared model types
│   ├── Msg.can            # Message types
│   ├── View/
│   │   ├── Header.can
│   │   ├── Footer.can
│   │   └── Page/
│   │       ├── Home.can
│   │       └── About.can
│   └── Api/
│       ├── User.can
│       └── Post.can
├── tests/
│   └── Tests.can
└── public/
    ├── index.html
    └── assets/
```

## Next Steps

Now that you have Canopy installed and running:

1. **[Your First Application](./first-app.md)**: Build a complete counter application
2. **[The Canopy Architecture](./architecture.md)**: Understand the core pattern
3. **[Type System](./type-system.md)**: Learn about Canopy's types

## Troubleshooting

### Common Issues

**"canopy: command not found"**

Make sure the npm global bin directory is in your PATH:

```bash
export PATH="$PATH:$(npm bin -g)"
```

**"Cannot find module 'canopy/core'"**

Run `canopy install` to fetch dependencies:

```bash
canopy install
```

**Port 8000 is already in use**

Specify a different port:

```bash
canopy reactor --port=8001
```

### Getting Help

- Check the [FAQ](../faq.md) for common questions
- Visit the [GitHub issues](https://github.com/canopy-lang/canopy/issues)
- Join the [Discord community](https://discord.gg/canopy)
