{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Generate TypeScript @.d.ts@ declarations from FFI bindings.
--
-- When a Canopy module uses FFI with @\@canopy-type@ annotations, this module
-- can generate a companion @.d.ts@ file so downstream TypeScript consumers
-- get type safety without manually maintaining declarations.
--
-- == Example
--
-- Given an FFI binding:
--
-- @
-- \@name addNumbers
-- \@canopy-type Int -> Int -> Int
-- @
--
-- Generates:
--
-- @
-- export function addNumbers(p0: number, p1: number): number;
-- @
--
-- @since 0.20.1
module Generate.TypeScript.FromFFI
  ( generateDtsFromBindings,
    bindingToDtsDecl,
  )
where

import Data.ByteString.Builder (Builder)
import qualified Data.Maybe as Maybe
import Data.Text (Text)
import qualified Data.Text as Text
import FFI.Types
  ( FFIBinding (..),
    FFIFuncName (..),
    FFIType (..),
    FFITypeAnnotation (..),
  )
import qualified FFI.TypeParser as TypeParser
import qualified Generate.TypeScript.Render as Render
import Generate.TypeScript.Types (DtsDecl (..), TsType (..))
import qualified Canopy.Data.Name as Name

-- | Generate a complete @.d.ts@ file from a list of FFI bindings.
--
-- Parses each binding's @\@canopy-type@ annotation, converts to a TypeScript
-- declaration, and renders the result. Bindings with unparseable types are
-- silently skipped.
--
-- @since 0.20.1
generateDtsFromBindings :: [FFIBinding] -> Builder
generateDtsFromBindings bindings =
  Render.renderDecls (Maybe.mapMaybe bindingToDtsDecl bindings)

-- | Convert a single FFI binding to a @.d.ts@ declaration.
--
-- Returns 'Nothing' if the type annotation cannot be parsed.
--
-- @since 0.20.1
bindingToDtsDecl :: FFIBinding -> Maybe DtsDecl
bindingToDtsDecl binding = do
  ffiType <- TypeParser.parseType typeStr
  let tsType = ffiTypeToTsType ffiType
      name = Name.fromChars (Text.unpack funcName)
  Just (DtsValue name tsType)
  where
    funcName = unFFIFuncName (_bindingFuncName binding)
    typeStr = unFFITypeAnnotation (_bindingTypeAnnotation binding)

-- | Convert an FFI type to a TypeScript type for @.d.ts@ output.
--
-- Maps Canopy FFI types to their TypeScript equivalents:
--
-- * @Int@, @Float@ → @number@
-- * @String@ → @string@
-- * @Bool@ → @boolean@
-- * @Unit@ → @void@
-- * @List a@ → @ReadonlyArray\<A\>@
-- * @Maybe a@ → @A | null@
-- * @Result e a@ → @{ readonly $: 'Ok'; readonly a: A } | { readonly $: 'Err'; readonly a: E }@
-- * @Task e a@ → @Promise\<A\>@
-- * @a -> b -> c@ → @(p0: A, p1: B) => C@
-- * @Record@ → @{ readonly field: Type; ... }@
-- * @Opaque@ → @unknown@
--
-- @since 0.20.1
ffiTypeToTsType :: FFIType -> TsType
ffiTypeToTsType = \case
  FFIInt -> TsNumber
  FFIFloat -> TsNumber
  FFIString -> TsString
  FFIBool -> TsBoolean
  FFIUnit -> TsVoid
  FFIList inner -> TsReadonlyArray (ffiTypeToTsType inner)
  FFIMaybe inner ->
    TsUnion [ffiTypeToTsType inner, TsVoid]
  FFIResult errTy valTy ->
    TsUnion
      [ TsObject
          [ (Name.fromChars "$", TsNamed (Name.fromChars "'Ok'") []),
            (Name.fromChars "a", ffiTypeToTsType valTy)
          ],
        TsObject
          [ (Name.fromChars "$", TsNamed (Name.fromChars "'Err'") []),
            (Name.fromChars "a", ffiTypeToTsType errTy)
          ]
      ]
  FFITask _errTy valTy ->
    TsNamed (Name.fromChars "Promise") [ffiTypeToTsType valTy]
  FFIFunctionType params ret ->
    TsFunction (fmap ffiTypeToTsType params) (ffiTypeToTsType ret)
  FFITuple types ->
    TsObject (zipWith tupleField [0 ..] types)
  FFIRecord fields ->
    TsObject (fmap (\(n, t) -> (Name.fromChars (Text.unpack n), ffiTypeToTsType t)) fields)
  FFITypeVar name ->
    TsTypeVar (Name.fromChars (Text.unpack (uppercaseFirst name)))
  FFIOpaque _ _ -> TsUnknown
  where
    tupleField :: Int -> FFIType -> (Name.Name, TsType)
    tupleField idx ty =
      (Name.fromChars (Text.unpack (Text.pack (show idx))), ffiTypeToTsType ty)

-- | Uppercase the first character of a type variable for TypeScript convention.
uppercaseFirst :: Text -> Text
uppercaseFirst t =
  case Text.uncons t of
    Just (c, rest) -> Text.cons (toUpper c) rest
    Nothing -> t
  where
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise = c
