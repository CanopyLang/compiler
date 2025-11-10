{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | CLI command definitions and configurations.
--
-- This module contains all the command definitions for the Canopy CLI,
-- including their metadata, argument parsers, flag configurations, and
-- help text. Each command is self-contained with complete documentation
-- and proper error handling.
--
-- == Available Commands
--
-- * 'createInitCommand' - Initialize new Canopy projects
-- * 'createReplCommand' - Interactive REPL session
-- * 'createReactorCommand' - Development server with hot reload
-- * 'createMakeCommand' - Compile Canopy code
-- * 'createInstallCommand' - Package installation
-- * 'createPublishCommand' - Package publishing
-- * 'createBumpCommand' - Version bumping
-- * 'createDiffCommand' - API change detection
--
-- == Architecture
--
-- Each command follows a consistent pattern:
--
-- * Comprehensive help text and examples
-- * Appropriate argument and flag parsers
-- * Integration with corresponding handler modules
-- * Consistent error messages and user guidance
--
-- @since 0.19.1
module CLI.Commands
  ( -- * Project Commands
    createInitCommand,
    createReplCommand,
    createReactorCommand,

    -- * Build Commands
    createMakeCommand,

    -- * Testing Commands
    createFFITestCommand,

    -- * Package Commands
    createInstallCommand,
    createPublishCommand,
    createBumpCommand,
    createDiffCommand,
  )
where

import qualified Bump
import CLI.Documentation (reflowText, stackDocuments)
import CLI.Parsers (createInterpreterParser, createPortParser)
import CLI.Types (Command, (|--))
import qualified Develop
import qualified Diff
import qualified Init
import qualified Install
import qualified Make
import qualified Publish
import qualified Repl
import qualified Terminal
import qualified Terminal.Helpers as Terminal
import qualified Test.FFI as FFI
import Text.PrettyPrint.ANSI.Leijen (Doc)
import qualified Text.PrettyPrint.ANSI.Leijen as P

-- | Create the init command for starting new Canopy projects.
--
-- The init command helps users bootstrap new Canopy projects by creating
-- the necessary configuration files and providing guidance on next steps.
--
-- @since 0.19.1
createInitCommand :: Command
createInitCommand =
  Terminal.Command "init" (Terminal.Common summary) details example Terminal.noArgs Terminal.noFlags Init.run
  where
    summary = createInitSummary
    details = createInitDetails
    example = createInitExample

-- | Create the REPL command for interactive programming sessions.
--
-- The REPL command opens an interactive programming environment where
-- users can experiment with Canopy expressions and see immediate results.
--
-- @since 0.19.1
createReplCommand :: Command
createReplCommand =
  Terminal.Command "repl" (Terminal.Common summary) details example Terminal.noArgs flags Repl.run
  where
    summary = createReplSummary
    details = createReplDetails
    example = createReplExample
    flags = createReplFlags

-- | Create the reactor command for development server.
--
-- The reactor command starts a local development server that provides
-- a web interface for compiling and previewing Canopy files.
--
-- @since 0.19.1
createReactorCommand :: Command
createReactorCommand =
  Terminal.Command "reactor" (Terminal.Common summary) details example Terminal.noArgs flags Develop.run
  where
    summary = createReactorSummary
    details = createReactorDetails
    example = createReactorExample
    flags = createReactorFlags

-- | Create the make command for compiling Canopy code.
--
-- The make command compiles Canopy source code into JavaScript or HTML,
-- with various optimization and output options available.
--
-- @since 0.19.1
createMakeCommand :: Command
createMakeCommand =
  Terminal.Command "make" Terminal.Uncommon details example args flags Make.run
  where
    details = createMakeDetails
    example = createMakeExample
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createMakeFlags

-- | Create the install command for package management.
--
-- The install command fetches and installs Canopy packages from
-- package repositories for use in projects.
--
-- @since 0.19.1
createInstallCommand :: Command
createInstallCommand =
  Terminal.Command "install" Terminal.Uncommon details example args Terminal.noFlags Install.run
  where
    details = createInstallDetails
    example = createInstallExample
    args = createInstallArgs

-- | Create the publish command for package distribution.
--
-- The publish command publishes Canopy packages to custom repositories
-- for sharing with other developers.
--
-- @since 0.19.1
createPublishCommand :: Command
createPublishCommand =
  Terminal.Command "publish" Terminal.Uncommon details example args Terminal.noFlags Publish.run
  where
    details = createPublishDetails
    example = createPublishExample
    args = createPublishArgs

-- | Create the bump command for version management.
--
-- The bump command analyzes API changes and automatically determines
-- the appropriate version number increment.
--
-- @since 0.19.1
createBumpCommand :: Command
createBumpCommand =
  Terminal.Command "bump" Terminal.Uncommon details example Terminal.noArgs Terminal.noFlags Bump.run
  where
    details = createBumpDetails
    example = createBumpExample

-- | Create the diff command for API change analysis.
--
-- The diff command detects and displays API changes between different
-- versions of packages, helping with upgrade planning.
--
-- @since 0.19.1
createDiffCommand :: Command
createDiffCommand =
  Terminal.Command "diff" Terminal.Uncommon details example args Terminal.noFlags Diff.run
  where
    details = createDiffDetails
    example = createDiffExample
    args = createDiffArgs

-- | Create the test-ffi command for FFI testing and validation.
--
-- The test-ffi command provides comprehensive testing of FFI functions
-- including property-based testing, integration testing, and runtime validation.
--
-- @since 0.19.1
createFFITestCommand :: Command
createFFITestCommand =
  Terminal.Command "test-ffi" Terminal.Uncommon details example Terminal.noArgs flags FFI.run
  where
    details = createFFITestDetails
    example = createFFITestExample
    flags = createFFITestFlags

-- Internal command content creators

createInitSummary :: String
createInitSummary =
  "Start an Canopy project. It creates a starter canopy.json file and\
  \ provides a link explaining what to do from there."

createInitDetails :: String
createInitDetails =
  "The `init` command helps start Canopy projects:"

createInitExample :: Doc
createInitExample =
  reflowText
    "It will ask permission to create an canopy.json file, the one thing common\
    \ to all Canopy projects. It also provides a link explaining what to do from there."

createReplSummary :: String
createReplSummary =
  "Open up an interactive programming session. Type in Canopy expressions\
  \ like (2 + 2) or (String.length \"test\") and see if they equal four!"

createReplDetails :: String
createReplDetails =
  "The `repl` command opens up an interactive programming session:"

createReplExample :: Doc
createReplExample =
  reflowText
    "Start working through <https://guide.canopy-lang.org> to learn how to use this!\
    \ It has a whole chapter that uses the REPL for everything, so that is probably\
    \ the quickest way to get started."

createReplFlags :: Terminal.Flags Repl.Flags
createReplFlags =
  Terminal.flags Repl.Flags
    |-- Terminal.flag "interpreter" createInterpreterParser "Path to a alternate JS interpreter, like node or nodejs."
    |-- Terminal.onOff "no-colors" "Turn off the colors in the REPL. This can help if you are having trouble reading the values. Some terminals use a custom color scheme that diverges significantly from the standard ANSI colors, so another path may be to pick a more standard color scheme."

createReactorSummary :: String
createReactorSummary =
  "Compile code with a click. It opens a file viewer in your browser, and\
  \ when you click on an Canopy file, it compiles and you see the result."

createReactorDetails :: String
createReactorDetails =
  "The `reactor` command starts a local server on your computer:"

createReactorExample :: Doc
createReactorExample =
  reflowText
    "After running that command, you would have a server at <http://localhost:8000>\
    \ that helps with development. It shows your files like a file viewer. If you\
    \ click on an Canopy file, it will compile it for you! And you can just press\
    \ the refresh button in the browser to recompile things."

createReactorFlags :: Terminal.Flags Develop.Flags
createReactorFlags =
  Terminal.flags Develop.Flags
    |-- Terminal.flag "port" createPortParser "The port of the server (default: 8000)"

createMakeDetails :: String
createMakeDetails =
  "The `make` command compiles Canopy code into JS or HTML:"

createMakeExample :: Doc
createMakeExample =
  stackDocuments
    [ reflowText "For example:",
      P.indent 4 $ P.green "canopy make src/Main.can",
      reflowText
        "This tries to compile a Canopy file named src/Main.can (also accepts .canopy), generating an index.html file if possible."
    ]

createMakeFlags :: Terminal.Flags Make.Flags
createMakeFlags =
  Terminal.flags Make.Flags
    |-- Terminal.onOff "debug" "Turn on the time-travelling debugger. It allows you to rewind and replay events. The events can be imported/exported into a file, which makes for very precise bug reports!"
    |-- Terminal.onOff "optimize" "Turn on optimizations to make code smaller and faster. For example, the compiler renames record fields to be as short as possible and unboxes values to reduce allocation."
    |-- Terminal.onOff "watch" "Turn on file watcher"
    |-- Terminal.flag "output" Make.output "Specify the name of the resulting JS file. For example --output=assets/canopy.js to generate the JS at assets/canopy.js or --output=/dev/null to generate no output at all!"
    |-- Terminal.flag "report" Make.reportType "You can say --report=json to get error messages as JSON. This is only really useful if you are an editor plugin. Humans should avoid it!"
    |-- Terminal.flag "docs" Make.docsFile "Generate a JSON file of documentation for a package. Eventually it will be possible to preview docs with `reactor` because it is quite hard to deal with these JSON files directly."
    |-- Terminal.onOff "verbose" "Turn on verbose logging when compiling. Useful for debugging errors in the Canopy compiler itself."

createInstallDetails :: String
createInstallDetails =
  "The `install` command fetches packages from <https://package.canopy-lang.org> for\
  \ use in your project:"

createInstallExample :: Doc
createInstallExample =
  stackDocuments
    [ reflowText
        "For example, if you want to get packages for HTTP and JSON, you would say:",
      P.indent 4 . P.green $
        P.vcat
          [ "canopy install canopy/http",
            "canopy install canopy/json"
          ],
      reflowText
        "Notice that you must say the AUTHOR name and PROJECT name! After running those\
        \ commands, you could say `import Http` or `import Json.Decode` in your code.",
      reflowText
        "What if two projects use different versions of the same package? No problem!\
        \ Each project is independent, so there cannot be conflicts like that!"
    ]

createInstallArgs :: Terminal.Args Install.Args
createInstallArgs =
  Terminal.oneOf
    [ Terminal.require0 Install.NoArgs,
      Terminal.require1 Install.Install Terminal.package
    ]

createPublishDetails :: String
createPublishDetails =
  "The `publish` command publishes your package to a custom repository\
  \ so that anyone with access to the repository can use it."

createPublishExample :: Doc
createPublishExample =
  stackDocuments
    [ reflowText
        "For example, if you have a custom repository located at https://www.example.com/my-custom-repo you can run the following command",
      P.indent 4 . P.green $
        P.vcat
          [ "Canopy publish https://www.example.com/my-custom-repo"
          ]
    ]

createPublishArgs :: Terminal.Args Publish.Args
createPublishArgs =
  Terminal.oneOf
    [ Terminal.require0 Publish.NoArgs,
      Terminal.require1 id (Publish.PublishToRepository <$> Terminal.repositoryLocalName)
    ]

createBumpDetails :: String
createBumpDetails =
  "The `bump` command figures out the next version number based on API changes:"

createBumpExample :: Doc
createBumpExample =
  reflowText
    "Say you just published version 1.0.0, but then decided to remove a function.\
    \ I will compare the published API to what you have locally, figure out that\
    \ it is a MAJOR change, and bump your version number to 2.0.0. I do this with\
    \ all packages, so there cannot be MAJOR changes hiding in PATCH releases in Canopy!"

createDiffDetails :: String
createDiffDetails =
  "The `diff` command detects API changes:"

createDiffExample :: Doc
createDiffExample =
  stackDocuments
    [ reflowText
        "For example, to see what changed in the HTML package between\
        \ versions 1.0.0 and 2.0.0, you can say:",
      P.indent 4 (P.green "canopy diff canopy/html 1.0.0 2.0.0"),
      reflowText
        "Sometimes a MAJOR change is not actually very big, so\
        \ this can help you plan your upgrade timelines."
    ]

createDiffArgs :: Terminal.Args Diff.Args
createDiffArgs =
  Terminal.oneOf
    [ Terminal.require0 Diff.CodeVsLatest,
      Terminal.require1 Diff.CodeVsExactly Terminal.version,
      Terminal.require2 Diff.LocalInquiry Terminal.version Terminal.version,
      Terminal.require3 Diff.GlobalInquiry Terminal.package Terminal.version Terminal.version
    ]

createFFITestDetails :: String
createFFITestDetails =
  "The `test-ffi` command provides comprehensive testing of FFI functions:"

createFFITestExample :: Doc
createFFITestExample =
  stackDocuments
    [ reflowText "For example:",
      P.indent 4 $ P.green "canopy test-ffi",
      reflowText
        "This runs all FFI tests in your project, validating contracts and testing function behavior.",
      P.indent 4 $ P.green "canopy test-ffi --generate --output test-generation/",
      reflowText
        "This generates test files without running them, useful for CI integration.",
      P.indent 4 $ P.green "canopy test-ffi --watch",
      reflowText
        "This watches for changes and re-runs tests automatically."
    ]

createFFITestFlags :: Terminal.Flags FFI.FFITestConfig
createFFITestFlags =
  Terminal.flags FFI.FFITestConfig
    |-- Terminal.onOff "generate" "Generate test files instead of running them"
    |-- Terminal.flag "output" FFI.outputParser "Output directory for generated tests (default: test-generation/)"
    |-- Terminal.onOff "watch" "Watch for file changes and re-run tests"
    |-- Terminal.onOff "validate-only" "Only validate contracts, don't run tests"
    |-- Terminal.onOff "verbose" "Verbose output showing detailed progress"
    |-- Terminal.flag "property-runs" FFI.propertyRunsParser "Number of property test runs (default: 100)"
    |-- Terminal.onOff "browser" "Run tests in browser instead of Node.js"
