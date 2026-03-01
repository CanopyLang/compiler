{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for building and compiling.
--
-- Contains make, check, and reactor commands for compiling Canopy code
-- and running the development server.
--
-- @since 0.19.1
module CLI.Commands.Build
  ( createMakeCommand,
    createCheckCommand,
    createReactorCommand,
  )
where

import CLI.Documentation (reflowText, stackDocuments)
import CLI.Parsers (createPortParser)
import CLI.Types (Command, (|--))
import qualified Check
import qualified Develop
import qualified Make
import qualified Terminal
import qualified Terminal.Helpers as Terminal
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the make command for compiling Canopy code.
--
-- @since 0.19.1
createMakeCommand :: Command
createMakeCommand =
  Terminal.Command "make" (Terminal.Common "Compile Canopy code into JS or HTML") details example args flags Make.run
  where
    details = "The `make` command compiles Canopy code into JS or HTML:"
    example =
      stackDocuments
        [ reflowText "For example:",
          PP.indent 4 (PP.green "canopy make src/Main.can"),
          reflowText
            "This tries to compile a Canopy file named src/Main.can (also accepts .canopy), generating an index.html file if possible."
        ]
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createMakeFlags

-- | Create the check command for type-checking without code generation.
--
-- @since 0.19.1
createCheckCommand :: Command
createCheckCommand =
  Terminal.Command "check" (Terminal.Common "Type-check files without generating output") details example args flags Check.run
  where
    details = "The `check` command type-checks Canopy files without generating output:"
    example = PP.indent 4 (PP.green "canopy check src/Main.can")
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createCheckFlags

-- | Create the reactor command for development server.
--
-- @since 0.19.1
createReactorCommand :: Command
createReactorCommand =
  Terminal.Command "reactor" (Terminal.Common summary) details example Terminal.noArgs flags Develop.run
  where
    summary =
      "Compile code with a click. It opens a file viewer in your browser, and\
      \ when you click on a Canopy file, it compiles and you see the result."
    details = "The `reactor` command starts a local server on your computer:"
    example =
      reflowText
        "After running that command, you would have a server at <http://localhost:8000>\
        \ that helps with development. It shows your files like a file viewer. If you\
        \ click on a Canopy file, it will compile it for you! And you can just press\
        \ the refresh button in the browser to recompile things."
    flags = createReactorFlags

-- FLAGS

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
    |-- Terminal.onOff "no-split" "Force single-file output even when lazy imports are present. Useful for debugging code splitting issues."
    |-- Terminal.onOff "ffi-unsafe" "Disable runtime type validation at FFI boundaries. Use only when you are confident FFI types are correct and need maximum performance."
    |-- Terminal.onOff "ffi-debug" "Enable verbose FFI validation logging. When enabled, generated validators include detailed type mismatch information in error messages."
    |-- Terminal.flag "jobs" Make.jobsParser "Maximum parallel compilation workers. 0 = auto (uses all CPU cores), 1 = sequential (useful for debugging). Default: auto."
    |-- Terminal.onOff "verify-reproducible" "Build twice and compare output to verify reproducibility. Fails if the two builds produce different byte-for-byte output."

createCheckFlags :: Terminal.Flags Check.Flags
createCheckFlags =
  Terminal.flags Check.Flags
    |-- Terminal.flag "report" Check.reportType "You can say --report=json to get error messages as JSON."
    |-- Terminal.onOff "verbose" "Enable verbose compiler logging."

createReactorFlags :: Terminal.Flags Develop.Flags
createReactorFlags =
  Terminal.flags Develop.Flags
    |-- Terminal.flag "port" createPortParser "The port of the server (default: 8000)"
