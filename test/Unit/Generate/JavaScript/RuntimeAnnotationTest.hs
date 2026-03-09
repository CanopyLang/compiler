{-# LANGUAGE OverloadedStrings #-}

-- | Validates that every function\/variable in the embedded runtime
-- has a @\@canopy-type@ annotation.
--
-- Uses @language-javascript@ to parse the embedded JS into a proper AST,
-- then checks that every declaration's annotation carries a @\@canopy-type@
-- comment. This is the same parser the FFI pipeline uses, so it cannot
-- be fooled by string contents, comments, or indentation.
--
-- @since 0.20.0
module Unit.Generate.JavaScript.RuntimeAnnotationTest (tests) where

import Data.ByteString.Builder (Builder)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import Language.JavaScript.Parser.AST
  ( JSAnnot (..),
    JSCommaList (..),
    JSCommaTrailingList (..),
    JSExpression (..),
    JSIdent (..),
    JSModuleItem (..),
    JSObjectProperty (..),
    JSPropertyName (..),
    JSStatement (..),
    JSVarInitializer (..),
    JSAST (..),
  )
import qualified Language.JavaScript.Parser as JS
import qualified Language.JavaScript.Parser.Token as JSToken
import Test.Tasty
import Test.Tasty.HUnit

import qualified Generate.JavaScript.FFIRuntime as FFIRuntime
import qualified Generate.JavaScript.Runtime as Runtime

tests :: TestTree
tests =
  testGroup
    "Runtime Annotation Coverage"
    [ runtimeAnnotationTests,
      ffiRuntimeAnnotationTests
    ]

-- ── Helpers ─────────────────────────────────────────────────────────

-- | Convert a Builder to a strict ByteString.
builderToBS :: Builder -> BS.ByteString
builderToBS = LBS.toStrict . BB.toLazyByteString

-- | Parse a Builder's content as a JS module, failing the test on parse error.
parseJS :: String -> Builder -> IO JSAST
parseJS label builder =
  case JS.parseModule (Text.unpack (TextEnc.decodeUtf8Lenient (builderToBS builder))) label of
    Left err -> assertFailure ("Failed to parse " ++ label ++ ": " ++ show err) >> error "unreachable"
    Right ast -> pure ast

-- | Check whether a list of 'JSToken.CommentAnnotation' contains @\@canopy-type@.
hasCanopyType :: [JSToken.CommentAnnotation] -> Bool
hasCanopyType = any isCanopyTypeComment
  where
    isCanopyTypeComment (JSToken.CommentA _ bs) =
      "@canopy-type" `BS.isInfixOf` bs
    isCanopyTypeComment _ = False

-- | Extract the annotation's comment list from a 'JSAnnot'.
annotComments :: JSAnnot -> [JSToken.CommentAnnotation]
annotComments (JSAnnot _ comments) = comments
annotComments JSNoAnnot = []

-- ── Runtime.hs: top-level function\/var declarations ────────────────

-- | Extract all top-level declarations from a parsed JS module.
--
-- Returns @(name, hasAnnotation)@ pairs for every @function _Name@,
-- @async function _Name@, and @var _Name@ at module scope.
extractTopLevelDecls :: JSAST -> [(String, Bool)]
extractTopLevelDecls ast =
  case ast of
    JSAstModule items _ -> concatMap extractFromModuleItem items
    JSAstProgram stmts _ -> concatMap extractFromStmt stmts
    _ -> []

extractFromModuleItem :: JSModuleItem -> [(String, Bool)]
extractFromModuleItem (JSModuleStatementListItem stmt) = extractFromStmt stmt
extractFromModuleItem _ = []

extractFromStmt :: JSStatement -> [(String, Bool)]
extractFromStmt stmt =
  case stmt of
    JSFunction annot ident _ _ _ _ _ ->
      identEntry annot ident
    JSAsyncFunction _ annot ident _ _ _ _ _ ->
      identEntry annot ident
    JSVariable annot exprs _ ->
      varEntries annot exprs
    JSStatementBlock _ stmts _ _ ->
      concatMap extractFromStmt stmts
    _ -> []

identEntry :: JSAnnot -> JSIdent -> [(String, Bool)]
identEntry annot ident =
  case ident of
    JSIdentName _ nameBS ->
      let name = Text.unpack (TextEnc.decodeUtf8Lenient nameBS)
       in [(name, hasCanopyType (annotComments annot))]
    JSIdentNone -> []

varEntries :: JSAnnot -> JSCommaList JSExpression -> [(String, Bool)]
varEntries annot exprs =
  map (\name -> (name, hasCanopyType (annotComments annot))) (varNames exprs)

varNames :: JSCommaList JSExpression -> [String]
varNames = \case
  JSLCons rest _ expr -> varNames rest ++ exprVarName expr
  JSLOne expr -> exprVarName expr
  JSLNil -> []

exprVarName :: JSExpression -> [String]
exprVarName (JSVarInitExpression (JSIdentifier _ nameBS) _) =
  [Text.unpack (TextEnc.decodeUtf8Lenient nameBS)]
exprVarName _ = []

-- ── FFIRuntime.hs: object property declarations ────────────────────

-- | Extract all object properties from a @var $xxx = { ... }@ declaration.
--
-- Returns @(propertyName, hasAnnotation)@ for each property in the object
-- literal. The @\@canopy-type@ comment attaches to the 'JSPropertyName'
-- annotation.
extractObjectProperties :: JSAST -> [(String, Bool)]
extractObjectProperties ast =
  case ast of
    JSAstModule items _ -> concatMap propFromModuleItem items
    JSAstProgram stmts _ -> concatMap propFromStmt stmts
    _ -> []

propFromModuleItem :: JSModuleItem -> [(String, Bool)]
propFromModuleItem (JSModuleStatementListItem stmt) = propFromStmt stmt
propFromModuleItem _ = []

propFromStmt :: JSStatement -> [(String, Bool)]
propFromStmt (JSVariable _ exprs _) = concatMap propFromExpr (commaToList exprs)
propFromStmt _ = []

propFromExpr :: JSExpression -> [(String, Bool)]
propFromExpr (JSVarInitExpression _ (JSVarInit _ (JSObjectLiteral _ props _))) =
  concatMap propFromTrailing [props]
propFromExpr _ = []

propFromTrailing :: JSCommaTrailingList JSObjectProperty -> [(String, Bool)]
propFromTrailing (JSCTLComma list _) = concatMap propFromObjectProp (commaToList list)
propFromTrailing (JSCTLNone list) = concatMap propFromObjectProp (commaToList list)

propFromObjectProp :: JSObjectProperty -> [(String, Bool)]
propFromObjectProp (JSPropertyNameandValue pname _ _) =
  case pname of
    JSPropertyIdent annot nameBS ->
      [(Text.unpack (TextEnc.decodeUtf8Lenient nameBS), hasCanopyType (annotComments annot))]
    JSPropertyString annot _ ->
      [("<string-key>", hasCanopyType (annotComments annot))]
    _ -> []
propFromObjectProp _ = []

commaToList :: JSCommaList a -> [a]
commaToList = \case
  JSLCons rest _ item -> commaToList rest ++ [item]
  JSLOne item -> [item]
  JSLNil -> []

-- ── Tests ───────────────────────────────────────────────────────────

runtimeAnnotationTests :: TestTree
runtimeAnnotationTests =
  testGroup
    "Runtime.hs annotations"
    [ testCase "all runtime declarations have @canopy-type" $ do
        ast <- parseJS "Runtime.hs" Runtime.embeddedRuntime
        let decls = extractTopLevelDecls ast
            unannotated = [name | (name, annotated) <- decls, not annotated]
        unannotated @?= [],
      testCase "runtime has declarations to check" $ do
        ast <- parseJS "Runtime.hs" Runtime.embeddedRuntime
        let decls = extractTopLevelDecls ast
        assertBool
          ("Expected at least 50 runtime declarations, found " ++ show (length decls))
          (length decls >= 50)
    ]

ffiRuntimeAnnotationTests :: TestTree
ffiRuntimeAnnotationTests =
  testGroup
    "FFIRuntime.hs annotations"
    [ testCase "all $canopy properties have @canopy-type" $ do
        ast <- parseJS "$canopy" FFIRuntime.embeddedMarshal
        let props = extractObjectProperties ast
            unannotated = [name | (name, annotated) <- props, not annotated]
        unannotated @?= [],
      testCase "all $validate properties have @canopy-type" $ do
        ast <- parseJS "$validate" FFIRuntime.embeddedValidate
        let props = extractObjectProperties ast
            unannotated = [name | (name, annotated) <- props, not annotated]
        unannotated @?= [],
      testCase "all $smart properties have @canopy-type" $ do
        ast <- parseJS "$smart" FFIRuntime.embeddedSmart
        let props = extractObjectProperties ast
            unannotated = [name | (name, annotated) <- props, not annotated]
        unannotated @?= [],
      testCase "all $env properties have @canopy-type" $ do
        ast <- parseJS "$env" FFIRuntime.embeddedEnvironment
        let props = extractObjectProperties ast
            unannotated = [name | (name, annotated) <- props, not annotated]
        unannotated @?= []
    ]
