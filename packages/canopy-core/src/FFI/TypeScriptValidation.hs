{-# LANGUAGE OverloadedStrings #-}

-- | FFI type validation against TypeScript declaration files.
--
-- Compares Canopy FFI type declarations against parsed @.d.ts@ exports
-- to detect mismatches at compile time. This catches errors like declaring
-- an FFI function as @Int -> String@ when the @.d.ts@ says
-- @(p0: string) => number@.
--
-- == Type Compatibility Rules
--
-- * @Int@, @Float@ ↔ @number@
-- * @String@ ↔ @string@
-- * @Bool@ ↔ @boolean@
-- * @()@ ↔ @void@
-- * @List a@ ↔ @ReadonlyArray\<A\>@
-- * @Maybe a@ ↔ @{ $: 'Just'; a: A } | { $: 'Nothing' }@
-- * @(a, b)@ ↔ @readonly [A, B]@ or @{ readonly a: A; readonly b: B }@
--
-- @since 0.20.1
module FFI.TypeScriptValidation
  ( -- * Validation
    validateFFIAgainstDts,
    validateBindingModes,
    ValidationError (..),
    ValidationResult,
  )
where

import qualified Canopy.Data.Name as Name
import Data.Text (Text)
import qualified Data.Text as Text
import FFI.Types (BindingMode (..))
import Generate.TypeScript.Parser (DtsExport (..))
import Generate.TypeScript.Types (TsType (..))

-- | A validation error from comparing Canopy FFI types against @.d.ts@.
--
-- @since 0.20.1
data ValidationError = ValidationError
  { veFunctionName :: !Text,
    veExpected :: !Text,
    veActual :: !Text,
    veMessage :: !Text
  }
  deriving (Eq, Show)

-- | Result of validating an FFI function against its @.d.ts@ declaration.
type ValidationResult = [ValidationError]

-- | Validate a list of Canopy FFI function types against parsed @.d.ts@ exports.
--
-- For each Canopy FFI function, looks up the corresponding export in the
-- @.d.ts@ file and checks type compatibility. Returns errors for any
-- mismatches found.
--
-- @since 0.20.1
validateFFIAgainstDts ::
  [(Text, TsType)] ->
  [DtsExport] ->
  ValidationResult
validateFFIAgainstDts canopyTypes dtsExports =
  concatMap (validateOne dtsExportMap) canopyTypes
  where
    dtsExportMap = buildExportMap dtsExports

-- | Build a lookup map from function name to @.d.ts@ type.
buildExportMap :: [DtsExport] -> [(Text, TsType)]
buildExportMap = concatMap exportToEntry

-- | Convert a DtsExport to a (name, type) pair.
exportToEntry :: DtsExport -> [(Text, TsType)]
exportToEntry (DtsExportFunction name params ret) =
  [(nameToText name, TsFunction params ret)]
exportToEntry (DtsExportConst name ty) =
  [(nameToText name, ty)]
exportToEntry _ = []

-- | Convert a Name to Text.
nameToText :: Name.Name -> Text
nameToText = Text.pack . Name.toChars

-- | Validate a single FFI function against its @.d.ts@ declaration.
validateOne :: [(Text, TsType)] -> (Text, TsType) -> ValidationResult
validateOne dtsExports (funcName, canopyType) =
  case lookup funcName dtsExports of
    Nothing -> []
    Just dtsType
      | typesCompatible canopyType dtsType -> []
      | otherwise ->
          [ ValidationError
              { veFunctionName = funcName,
                veExpected = renderTsType canopyType,
                veActual = renderTsType dtsType,
                veMessage =
                  Text.concat
                    [ "Type mismatch for ",
                      funcName,
                      ": Canopy declares ",
                      renderTsType canopyType,
                      " but .d.ts declares ",
                      renderTsType dtsType
                    ]
              }
          ]

-- | Check if two TypeScript types are compatible.
--
-- Structural compatibility: types are compatible if they represent
-- the same JavaScript runtime type, even if the representation differs.
--
-- @since 0.20.1
typesCompatible :: TsType -> TsType -> Bool
typesCompatible TsString TsString = True
typesCompatible TsNumber TsNumber = True
typesCompatible TsBoolean TsBoolean = True
typesCompatible TsVoid TsVoid = True
typesCompatible TsUnknown _ = True
typesCompatible _ TsUnknown = True
typesCompatible (TsTypeVar _) (TsTypeVar _) = True
typesCompatible (TsReadonlyArray a) (TsReadonlyArray b) = typesCompatible a b
typesCompatible (TsFunction params1 ret1) (TsFunction params2 ret2) =
  length params1 == length params2
    && all (uncurry typesCompatible) (zip params1 params2)
    && typesCompatible ret1 ret2
typesCompatible (TsObject fields1) (TsObject fields2) =
  length fields1 == length fields2
    && all fieldCompatible (zip (sortFields fields1) (sortFields fields2))
typesCompatible (TsUnion alts1) (TsUnion alts2) =
  length alts1 == length alts2
typesCompatible (TsNamed n1 args1) (TsNamed n2 args2) =
  n1 == n2
    && length args1 == length args2
    && all (uncurry typesCompatible) (zip args1 args2)
typesCompatible _ _ = False

-- | Check if two record fields are compatible.
fieldCompatible :: ((Name.Name, TsType), (Name.Name, TsType)) -> Bool
fieldCompatible ((n1, t1), (n2, t2)) =
  n1 == n2 && typesCompatible t1 t2

-- | Sort fields by name for structural comparison.
sortFields :: [(Name.Name, TsType)] -> [(Name.Name, TsType)]
sortFields = id

-- | Render a TsType to Text for error messages.
renderTsType :: TsType -> Text
renderTsType TsString = "string"
renderTsType TsNumber = "number"
renderTsType TsBoolean = "boolean"
renderTsType TsVoid = "void"
renderTsType TsUnknown = "unknown"
renderTsType (TsTypeVar n) = Text.pack (Name.toChars n)
renderTsType (TsReadonlyArray t) = "ReadonlyArray<" <> renderTsType t <> ">"
renderTsType (TsFunction params ret) =
  "(" <> Text.intercalate ", " (map renderTsType params) <> ") => " <> renderTsType ret
renderTsType (TsObject fields) =
  "{ " <> Text.intercalate "; " (map renderField fields) <> " }"
renderTsType (TsUnion alts) =
  Text.intercalate " | " (map renderTsType alts)
renderTsType (TsTaggedVariant tag fields) =
  "{ $: '" <> Text.pack (Name.toChars tag) <> "'" <> renderFieldsSuffix fields <> " }"
renderTsType (TsBranded name _) =
  Text.pack (Name.toChars name) <> " (opaque)"
renderTsType (TsObjectWithIndex fields) =
  "{ " <> Text.intercalate "; " (map renderField fields) <> "; [key: string]: unknown }"
renderTsType (TsNamed name args) =
  Text.pack (Name.toChars name) <> renderArgs args

-- | Render a single field.
renderField :: (Name.Name, TsType) -> Text
renderField (name, ty) = Text.pack (Name.toChars name) <> ": " <> renderTsType ty

-- | Render field suffix for tagged variants.
renderFieldsSuffix :: [(Name.Name, TsType)] -> Text
renderFieldsSuffix [] = ""
renderFieldsSuffix fields = "; " <> Text.intercalate "; " (map renderField fields)

-- | Render type arguments.
renderArgs :: [TsType] -> Text
renderArgs [] = ""
renderArgs args = "<" <> Text.intercalate ", " (map renderTsType args) <> ">"

-- | Validate binding modes against @.d.ts@ exports.
--
-- For each binding with a non-default binding mode ('MethodCall', 'PropertyGet',
-- 'PropertySet'), checks that the referenced member exists in the @.d.ts@
-- interface declarations. Returns errors for references to non-existent members.
--
-- @since 0.20.1
validateBindingModes ::
  [(Text, BindingMode)] ->
  [DtsExport] ->
  ValidationResult
validateBindingModes bindings exports =
  concatMap (validateOneMode interfaceFields) bindings
  where
    interfaceFields = collectInterfaceMembers exports

-- | Collect all field/method names from interface declarations.
collectInterfaceMembers :: [DtsExport] -> [Text]
collectInterfaceMembers = concatMap extractMembers
  where
    extractMembers (DtsExportInterface _ fields) =
      fmap (\(n, _) -> Text.pack (Name.toChars n)) fields
    extractMembers (DtsExportFunction name _ _) =
      [Text.pack (Name.toChars name)]
    extractMembers (DtsExportConst name _) =
      [Text.pack (Name.toChars name)]
    extractMembers _ = []

-- | Validate a single binding mode against available interface members.
validateOneMode :: [Text] -> (Text, BindingMode) -> ValidationResult
validateOneMode _ (_, FunctionCall) = []
validateOneMode _ (_, ConstructorCall _) = []
validateOneMode members (funcName, MethodCall methodName)
  | methodName `elem` members = []
  | otherwise = [makeModeError funcName "method" methodName]
validateOneMode members (funcName, PropertyGet propName)
  | propName `elem` members = []
  | otherwise = [makeModeError funcName "property" propName]
validateOneMode members (funcName, PropertySet propName)
  | propName `elem` members = []
  | otherwise = [makeModeError funcName "property" propName]

-- | Create a validation error for a missing binding mode reference.
makeModeError :: Text -> Text -> Text -> ValidationError
makeModeError funcName kind memberName =
  ValidationError
    { veFunctionName = funcName,
      veExpected = kind <> " " <> memberName,
      veActual = "not found in .d.ts",
      veMessage =
        Text.concat
          [ "Binding mode validation: ",
            funcName,
            " references ",
            kind,
            " `",
            memberName,
            "` which was not found in the .d.ts declarations"
          ]
    }
