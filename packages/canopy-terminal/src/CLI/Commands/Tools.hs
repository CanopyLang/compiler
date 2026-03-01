{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for external tools.
--
-- Contains test-ffi, webidl, and self-update commands.
--
-- @since 0.19.1
module CLI.Commands.Tools
  ( createFFITestCommand,
    createWebIDLCommand,
    createSelfUpdateCommand,
  )
where

import CLI.Documentation (stackDocuments)
import CLI.Types (Command, (|--))
import qualified SelfUpdate
import qualified Terminal
import qualified Test.FFI as FFI
import qualified WebIDL.Command as WebIDLCmd
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the test-ffi command for FFI testing and validation.
--
-- @since 0.19.1
createFFITestCommand :: Command
createFFITestCommand =
  Terminal.Command "test-ffi" Terminal.Uncommon details example Terminal.noArgs flags FFI.run
  where
    details = "The `test-ffi` command provides comprehensive testing of FFI functions:"
    example =
      stackDocuments
        [ PP.text "For example:",
          PP.indent 4 (PP.green "canopy test-ffi"),
          PP.text
            "This runs all FFI tests in your project, validating contracts and testing function behavior.",
          PP.indent 4 (PP.green "canopy test-ffi --generate --output test-generation/"),
          PP.text
            "This generates test files without running them, useful for CI integration.",
          PP.indent 4 (PP.green "canopy test-ffi --watch"),
          PP.text
            "This watches for changes and re-runs tests automatically."
        ]
    flags = createFFITestFlags

-- | Create the webidl command for generating FFI bindings from WebIDL.
--
-- @since 0.19.2
createWebIDLCommand :: Command
createWebIDLCommand =
  Terminal.Command "webidl" Terminal.Uncommon details example args flags WebIDLCmd.run
  where
    details = "The `webidl` command generates Canopy FFI bindings from WebIDL specifications:"
    example =
      stackDocuments
        [ PP.indent 4 (PP.green "canopy webidl specs/dom.webidl"),
          PP.indent 4 (PP.green "canopy webidl --output=src/Web/ specs/dom.webidl specs/fetch.webidl")
        ]
    args = Terminal.zeroOrMore (Terminal.stringParser "FILE" "WebIDL specification file (.webidl)")
    flags = createWebIDLFlags

-- | Create the self-update command for checking and installing compiler updates.
--
-- @since 0.19.2
createSelfUpdateCommand :: Command
createSelfUpdateCommand =
  Terminal.Command "self-update" Terminal.Uncommon details example Terminal.noArgs flags SelfUpdate.run
  where
    details = "The `self-update` command checks for and installs Canopy compiler updates:"
    example =
      stackDocuments
        [ PP.indent 4 (PP.green "canopy self-update"),
          PP.indent 4 (PP.green "canopy self-update --check")
        ]
    flags = createSelfUpdateFlags

-- FLAGS

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

createWebIDLFlags :: Terminal.Flags WebIDLCmd.Flags
createWebIDLFlags =
  Terminal.flags WebIDLCmd.Flags
    |-- Terminal.flag "output" (Terminal.stringParser "DIR" "output directory") "Directory for generated modules (default: current directory)."
    |-- Terminal.onOff "verbose" "Show verbose output."

createSelfUpdateFlags :: Terminal.Flags SelfUpdate.Flags
createSelfUpdateFlags =
  Terminal.flags SelfUpdate.Flags
    |-- Terminal.onOff "check" "Only check for updates, do not download or install."
    |-- Terminal.onOff "force" "Force update even if already at the latest version."
