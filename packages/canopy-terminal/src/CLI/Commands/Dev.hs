{-# LANGUAGE OverloadedStrings #-}

-- | CLI command definitions for developer tools.
--
-- Contains repl, fmt, lint, test, docs, bench, audit, and upgrade
-- commands for development workflow support.
--
-- @since 0.19.1
module CLI.Commands.Dev
  ( createReplCommand,
    createFmtCommand,
    createLintCommand,
    createTestCommand,
    createDocsCommand,
    createAuditCommand,
    createUpgradeCommand,
    createBenchCommand,
  )
where

import qualified Audit
import qualified Bench
import CLI.Documentation (reflowText)
import CLI.Parsers (createIntParser, createInterpreterParser)
import CLI.Types (Command, (|--))
import qualified Docs
import qualified Fmt
import qualified Lint
import qualified Repl
import qualified Terminal
import qualified Terminal.Helpers as Terminal
import qualified Test
import qualified Upgrade
import qualified Text.PrettyPrint.ANSI.Leijen as PP

-- | Create the REPL command for interactive programming sessions.
--
-- @since 0.19.1
createReplCommand :: Command
createReplCommand =
  Terminal.Command "repl" (Terminal.Common summary) details example Terminal.noArgs flags Repl.run
  where
    summary =
      "Open up an interactive programming session. Type in Canopy expressions\
      \ like (2 + 2) or (String.length \"test\") and see if they equal four!"
    details = "The `repl` command opens up an interactive programming session:"
    example =
      reflowText
        "Start working through <https://guide.canopy-lang.org> to learn how to use this!\
        \ It has a whole chapter that uses the REPL for everything, so that is probably\
        \ the quickest way to get started."
    flags = createReplFlags

-- | Create the fmt command for formatting source files.
--
-- @since 0.19.1
createFmtCommand :: Command
createFmtCommand =
  Terminal.Command "fmt" (Terminal.Common "Format Canopy source files") details example args flags Fmt.run
  where
    details = "The `fmt` command formats Canopy source files:"
    example = PP.indent 4 (PP.green "canopy fmt src/Main.can")
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createFmtFlags

-- | Create the lint command for static analysis.
--
-- @since 0.19.1
createLintCommand :: Command
createLintCommand =
  Terminal.Command "lint" (Terminal.Common "Run static analysis on source files") details example args flags Lint.run
  where
    details = "The `lint` command runs static analysis on Canopy source files:"
    example = PP.indent 4 (PP.green "canopy lint src/Main.can")
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createLintFlags

-- | Create the test command for running the test suite.
--
-- @since 0.19.1
createTestCommand :: Command
createTestCommand =
  Terminal.Command "test" (Terminal.Common "Run Canopy tests") details example args flags Test.run
  where
    details = "The `test` command runs Canopy test files. Browser tests are auto-detected and run with Playwright:"
    example =
      PP.vcat
        [ PP.indent 4 (PP.green "canopy test tests/MyTest.can"),
          PP.indent 4 (PP.green "canopy test --headed test/BrowserTests.can"),
          PP.indent 4 (PP.green "canopy test --app src/Main.can test/BrowserTests.can")
        ]
    args = Terminal.zeroOrMore Terminal.canopyFileOrDir
    flags = createTestFlags

-- | Create the docs command for generating documentation.
--
-- @since 0.19.2
createDocsCommand :: Command
createDocsCommand =
  Terminal.Command "docs" Terminal.Uncommon details example args flags Docs.run
  where
    details = "The `docs` command generates documentation for your Canopy project:"
    example =
      PP.vcat
        [ PP.indent 4 (PP.green "canopy docs"),
          PP.indent 4 (PP.green "canopy docs --format markdown --output docs.md"),
          PP.indent 4 (PP.green "canopy docs src/Main.can --output docs.json")
        ]
    args = Terminal.zeroOrMore Terminal.canopyFile
    flags = createDocsFlags

-- | Create the audit command for dependency analysis.
--
-- @since 0.19.1
createAuditCommand :: Command
createAuditCommand =
  Terminal.Command "audit" Terminal.Uncommon details example Terminal.noArgs flags Audit.run
  where
    details = "The `audit` command analyzes project dependencies:"
    example = PP.indent 4 (PP.green "canopy audit")
    flags = createAuditFlags

-- | Create the upgrade command for Elm-to-Canopy migration.
--
-- @since 0.19.1
createUpgradeCommand :: Command
createUpgradeCommand =
  Terminal.Command "upgrade" Terminal.Uncommon details example Terminal.noArgs flags Upgrade.run
  where
    details = "The `upgrade` command migrates Elm projects to Canopy:"
    example = PP.indent 4 (PP.green "canopy upgrade")
    flags = createUpgradeFlags

-- | Create the bench command for compilation benchmarking.
--
-- @since 0.19.1
createBenchCommand :: Command
createBenchCommand =
  Terminal.Command "bench" Terminal.Uncommon details example Terminal.noArgs flags Bench.run
  where
    details = "The `bench` command measures compilation performance:"
    example = PP.indent 4 (PP.green "canopy bench")
    flags = createBenchFlags

-- FLAGS

createReplFlags :: Terminal.Flags Repl.Flags
createReplFlags =
  Terminal.flags Repl.Flags
    |-- Terminal.flag "interpreter" createInterpreterParser "Path to a alternate JS interpreter, like node or nodejs."
    |-- Terminal.onOff "no-colors" "Turn off the colors in the REPL. This can help if you are having trouble reading the values. Some terminals use a custom color scheme that diverges significantly from the standard ANSI colors, so another path may be to pick a more standard color scheme."

createFmtFlags :: Terminal.Flags Fmt.Flags
createFmtFlags =
  Terminal.flags Fmt.Flags
    |-- Terminal.onOff "check" "Report which files need formatting and exit non-zero; do not write files."
    |-- Terminal.onOff "stdin" "Read from stdin and write formatted output to stdout."
    |-- Terminal.flag "indent" createIntParser "Number of spaces per indentation level (default: 4)."
    |-- Terminal.flag "line-width" createIntParser "Target maximum line width (default: 80)."

createLintFlags :: Terminal.Flags Lint.Flags
createLintFlags =
  Terminal.flags Lint.Flags
    |-- Terminal.onOff "fix" "Apply auto-fixes for fixable warnings."
    |-- Terminal.flag "report" Lint.reportFormatParser "Output format: use --report=json for machine-readable output."

createTestFlags :: Terminal.Flags Test.Flags
createTestFlags =
  Terminal.flags Test.Flags
    |-- Terminal.flag "filter" Test.filterParser "Only run tests whose names contain this pattern."
    |-- Terminal.onOff "watch" "Watch for file changes and re-run tests automatically."
    |-- Terminal.onOff "verbose" "Enable verbose output during test execution."
    |-- Terminal.onOff "headed" "Show the browser window when running browser tests (non-headless mode)."
    |-- Terminal.flag "app" Test.appParser "Application entry point for browser tests (e.g. src/Main.can). Can also be set via @browser-app annotation in test files."
    |-- Terminal.flag "slowmo" Test.slowMoParser "Slow down Playwright browser actions by N milliseconds. Useful for debugging browser tests."
    |-- Terminal.onOff "coverage" "Instrument code and show coverage report after tests."
    |-- Terminal.flag "coverage-format" Test.coverageFormatParser "Coverage output format: istanbul or lcov."
    |-- Terminal.flag "coverage-output" Test.coverageOutputParser "Write coverage report to file."

createDocsFlags :: Terminal.Flags Docs.Flags
createDocsFlags =
  Terminal.flags Docs.Flags
    |-- Terminal.flag "format" Docs.formatParser "Output format: json (default) or markdown."
    |-- Terminal.flag "output" Docs.outputParser "Write documentation to a file instead of stdout."

createAuditFlags :: Terminal.Flags Audit.Flags
createAuditFlags =
  Terminal.flags Audit.Flags
    |-- Terminal.onOff "json" "Output findings as JSON."
    |-- Terminal.flag "level" Audit.levelParser "Minimum severity to report: info, warning, or critical."
    |-- Terminal.onOff "verbose" "Show verbose details."

createUpgradeFlags :: Terminal.Flags Upgrade.Flags
createUpgradeFlags =
  Terminal.flags Upgrade.Flags
    |-- Terminal.onOff "dry-run" "Preview changes without applying them."
    |-- Terminal.onOff "verbose" "Show verbose output."

createBenchFlags :: Terminal.Flags Bench.Flags
createBenchFlags =
  Terminal.flags Bench.Flags
    |-- Terminal.flag "iterations" createIntParser "Number of iterations to run (default: 3)."
    |-- Terminal.onOff "json" "Output results as JSON."
    |-- Terminal.onOff "verbose" "Show verbose output."
