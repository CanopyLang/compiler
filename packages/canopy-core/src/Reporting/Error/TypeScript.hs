{-# LANGUAGE OverloadedStrings #-}

-- | TypeScript interop error types and rendering.
--
-- Provides structured error messages for TypeScript-related validation
-- failures, including FFI type mismatches against @.d.ts@ declarations
-- and web component generation errors.
--
-- @since 0.20.1
module Reporting.Error.TypeScript
  ( -- * Error Types
    TypeScriptError (..),

    -- * Rendering
    toDoc,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Reporting.Doc as Doc

-- | TypeScript interop errors.
--
-- @since 0.20.1
data TypeScriptError
  = -- | FFI function type doesn't match @.d.ts@ declaration.
    DtsMismatch !Text !Text !Text !Text
  | -- | @.d.ts@ file not found for an FFI import.
    DtsFileNotFound !FilePath !FilePath
  | -- | @.d.ts@ file failed to parse.
    DtsParseError !FilePath !Text
  deriving (Eq, Show)

-- | Render a TypeScript error to a 'Doc' for display.
--
-- @since 0.20.1
toDoc :: TypeScriptError -> Doc.Doc
toDoc (DtsMismatch funcName expected actual _msg) =
  Doc.vcat
    [ Doc.dullcyan (Doc.fromChars "-- TYPE MISMATCH IN FFI --"),
      "",
      Doc.reflow (Text.unpack ("The FFI function " <> funcName <> " has a type mismatch:")),
      "",
      Doc.indent 4 (Doc.fromChars ("Canopy type:    " <> Text.unpack expected)),
      Doc.indent 4 (Doc.fromChars (".d.ts declares: " <> Text.unpack actual)),
      "",
      Doc.reflow "Make sure your Canopy FFI declaration matches the TypeScript types."
    ]
toDoc (DtsFileNotFound ffiPath dtsPath) =
  Doc.vcat
    [ Doc.dullcyan (Doc.fromChars "-- MISSING .d.ts FILE --"),
      "",
      Doc.reflow ("FFI import " <> ffiPath <> " expects a .d.ts file at:"),
      "",
      Doc.indent 4 (Doc.fromChars dtsPath),
      "",
      Doc.reflow "Create the .d.ts file or remove the FFI import."
    ]
toDoc (DtsParseError path msg) =
  Doc.vcat
    [ Doc.dullcyan (Doc.fromChars "-- .d.ts PARSE ERROR --"),
      "",
      Doc.reflow ("Failed to parse " <> path <> ":"),
      "",
      Doc.indent 4 (Doc.fromChars (Text.unpack msg))
    ]
