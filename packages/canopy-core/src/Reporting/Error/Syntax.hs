{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Syntax error reporting for the Canopy parser.
--
-- This module re-exports all syntax error types from
-- @Reporting.Error.Syntax.Types@ and provides the rendering functions
-- that convert errors into human-readable diagnostics and reports.
--
-- Sub-modules handle specific error categories:
--
--   * "Reporting.Error.Syntax.Helpers"     - shared region helpers and notes
--   * "Reporting.Error.Syntax.Literal"     - character, string, number, operator errors
--   * "Reporting.Error.Syntax.Type"        - type annotation errors
--   * "Reporting.Error.Syntax.Pattern"     - pattern errors
--   * "Reporting.Error.Syntax.Expression"  - expression errors
--   * "Reporting.Error.Syntax.Declaration" - declaration errors
--   * "Reporting.Error.Syntax.Module"      - module and import errors
--
-- @since 0.19.1
module Reporting.Error.Syntax
  ( -- * Re-exported types
    module Reporting.Error.Syntax.Types,
    -- * Rendering
    toDiagnostic,
    toSpaceReport,
  )
where

import qualified Canopy.ModuleName as ModuleName
import qualified Reporting.Annotation as A
import qualified Reporting.Doc as D
import Reporting.Diagnostic (Diagnostic)
import qualified Reporting.Diagnostic as Diag
import qualified Reporting.ErrorCode as EC
import Reporting.Error.Syntax.Helpers
  ( noteForPortsInPackage,
    toRegion,
    toSpaceReport,
    wrapReport,
  )
import Reporting.Error.Syntax.Module
  ( toParseErrorReport,
  )
import Reporting.Error.Syntax.Types
import qualified Reporting.Render.Code as Code
import qualified Reporting.Report as Report
import Prelude hiding (Char, String)

-- | Convert a top-level syntax 'Error' to a 'Report.Report'.
toReport :: Code.Source -> Error -> Report.Report
toReport source err =
  case err of
    ModuleNameUnspecified name ->
      toModuleNameUnspecifiedReport name
    ModuleNameMismatch expectedName (A.At region actualName) ->
      toModuleNameMismatchReport source expectedName region actualName
    UnexpectedPort region ->
      toUnexpectedPortReport source region
    NoPorts region ->
      toNoPortsReport source region
    NoPortsInPackage (A.At region _) ->
      toNoPortsInPackageReport source region
    NoPortModulesInPackage region ->
      toNoPortModulesInPackageReport source region
    NoFFIModulesInPackage region ->
      toNoFFIModulesInPackageReport source region
    NoEffectsOutsideKernel region ->
      toNoEffectsOutsideKernelReport source region
    ParseError modul ->
      toParseErrorReport source modul

toModuleNameUnspecifiedReport :: ModuleName.Raw -> Report.Report
toModuleNameUnspecifiedReport name =
  let region = toRegion 1 1
   in Report.Report "MODULE NAME MISSING" region [] $
        D.stack
          [ D.reflow $
              "I need the module name to be declared at the top of this file, like this:",
            D.indent 4 $
              D.fillSep
                [D.cyan "module", D.fromName name, D.cyan "exposing", "(..)"],
            D.reflow "Try adding that as the first line of your file!",
            D.toSimpleNote $
              "It is best to replace (..) with an explicit list of types and\
              \ functions you want to expose. When you know a value is only used\
              \ within this module, you can refactor without worrying about uses\
              \ elsewhere. Limiting exposed values can also speed up compilation\
              \ because I can skip a bunch of work if I see that the exposed API\
              \ has not changed."
          ]

toModuleNameMismatchReport :: Code.Source -> ModuleName.Raw -> A.Region -> ModuleName.Raw -> Report.Report
toModuleNameMismatchReport source expectedName region actualName =
  Report.Report "MODULE NAME MISMATCH" region [ModuleName.toChars expectedName] $
    Code.toSnippet
      source
      region
      Nothing
      ( "It looks like this module name is out of sync:",
        D.stack
          [ D.reflow $
              "I need it to match the file path, so I was expecting to see `"
                ++ ModuleName.toChars expectedName
                ++ "` here. Make the following change, and you should be all set!",
            D.indent 4 $
              D.dullyellow (D.fromName actualName) <> " -> " <> D.green (D.fromName expectedName),
            D.toSimpleNote $
              "I require that module names correspond to file paths. This makes it much\
              \ easier to explore unfamiliar codebases! So if you want to keep the current\
              \ module name, try renaming the file instead."
          ]
      )

toUnexpectedPortReport :: Code.Source -> A.Region -> Report.Report
toUnexpectedPortReport source region =
  Report.Report "UNEXPECTED PORTS" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( D.reflow "You are declaring ports in a normal module.",
        D.stack
          [ D.fillSep
              [ "Switch", "this", "to", "say",
                D.cyan "port module",
                "instead,", "marking", "that", "this", "module", "contains", "port", "declarations."
              ],
            D.link
              "Note"
              "Ports are not a traditional FFI for calling JS functions directly. They need a different mindset! Read"
              "ports"
              "to learn the syntax and how to use it effectively."
          ]
      )

toNoPortsReport :: Code.Source -> A.Region -> Report.Report
toNoPortsReport source region =
  Report.Report "NO PORTS" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( D.reflow "This module does not declare any ports, but it says it will:",
        D.fillSep
          [ "Switch", "this", "to", D.cyan "module", "and", "you", "should", "be", "all", "set!"
          ]
      )

toNoPortsInPackageReport :: Code.Source -> A.Region -> Report.Report
toNoPortsInPackageReport source region =
  Report.Report "PACKAGES CANNOT HAVE PORTS" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( D.reflow "Packages cannot declare any ports, so I am getting stuck here:",
        D.stack
          [ D.reflow "Remove this port declaration.",
            noteForPortsInPackage
          ]
      )

toNoPortModulesInPackageReport :: Code.Source -> A.Region -> Report.Report
toNoPortModulesInPackageReport source region =
  Report.Report "PACKAGES CANNOT HAVE PORTS" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( D.reflow "Packages cannot have `port module` declarations.",
        D.reflow "Try using a regular `module` declaration instead. Ports are only allowed in applications."
      )

toNoFFIModulesInPackageReport :: Code.Source -> A.Region -> Report.Report
toNoFFIModulesInPackageReport source region =
  Report.Report "PACKAGES CANNOT HAVE FFI MODULES" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( D.reflow "Packages cannot have `ffi module` declarations, so I am getting stuck here:",
        D.stack
          [ D.fillSep
              [ "Remove", "the", D.cyan "ffi", "keyword", "and", "I",
                "should", "be", "able", "to", "continue."
              ],
            D.reflow "FFI modules are only allowed in applications, not in packages that other people can install."
          ]
      )

toNoEffectsOutsideKernelReport :: Code.Source -> A.Region -> Report.Report
toNoEffectsOutsideKernelReport source region =
  Report.Report "INVALID EFFECT MODULE" region [] $
    Code.toSnippet
      source
      region
      Nothing
      ( D.reflow $
          "It is not possible to declare an `effect module` outside the @canopy organization,\
          \ so I am getting stuck here:",
        D.stack
          [ D.reflow "Switch to a normal module declaration.",
            D.toSimpleNote $
              "Effect modules are designed to allow certain core functionality to be\
              \ defined separately from the compiler. So the @canopy organization has access to\
              \ this so that certain changes, extensions, and fixes can be introduced without\
              \ needing to release new Canopy binaries. For example, we want to make it possible\
              \ to test effects, but this may require changes to the design of effect modules.\
              \ By only having them defined in the @canopy organization, that kind of design work\
              \ can proceed much more smoothly."
          ]
      )

-- | Convert a syntax error to a structured 'Diagnostic'.
--
-- @
-- ModuleNameUnspecified   -> E0100
-- ModuleNameMismatch      -> E0101
-- UnexpectedPort          -> E0102
-- NoPorts                 -> E0103
-- NoPortsInPackage        -> E0104
-- NoPortModulesInPackage  -> E0105
-- NoFFIModulesInPackage   -> E0106
-- NoEffectsOutsideKernel  -> E0107
-- ParseError              -> E0110
-- @
toDiagnostic :: Code.Source -> Error -> Diagnostic
toDiagnostic source err =
  wrapReport (errorCode err) (errorRegion err) (toReport source err)

-- | Extract the error code for a syntax error.
errorCode :: Error -> Diag.ErrorCode
errorCode = \case
  ModuleNameUnspecified _ -> EC.parseError 0
  ModuleNameMismatch _ _ -> EC.parseError 1
  UnexpectedPort _ -> EC.parseError 2
  NoPorts _ -> EC.parseError 3
  NoPortsInPackage _ -> EC.parseError 4
  NoPortModulesInPackage _ -> EC.parseError 5
  NoFFIModulesInPackage _ -> EC.parseError 6
  NoEffectsOutsideKernel _ -> EC.parseError 7
  ParseError _ -> EC.parseError 10

-- | Extract the source region for a syntax error.
errorRegion :: Error -> A.Region
errorRegion = \case
  ModuleNameUnspecified _ -> toRegion 1 1
  ModuleNameMismatch _ (A.At region _) -> region
  UnexpectedPort region -> region
  NoPorts region -> region
  NoPortsInPackage (A.At region _) -> region
  NoPortModulesInPackage region -> region
  NoFFIModulesInPackage region -> region
  NoEffectsOutsideKernel region -> region
  ParseError _ -> toRegion 1 1
