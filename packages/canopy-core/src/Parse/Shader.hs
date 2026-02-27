{-# LANGUAGE BangPatterns, UnboxedTuples #-}
module Parse.Shader
  ( shader
  )
  where


import qualified Data.ByteString.Internal as BSI
import qualified Data.ByteString.UTF8 as BS_UTF8
import qualified Data.Map as Map
import qualified Data.Name as Name
import Data.Word (Word8)
import Foreign.Ptr (Ptr, plusPtr, minusPtr)
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)
import qualified Language.GLSL.Parser as GLP
import qualified Language.GLSL.Syntax as GLS
import qualified Text.Parsec as Parsec
import qualified Text.Parsec.Error as Parsec

import qualified AST.Source as Src
import qualified AST.Utils.Shader as Shader
import qualified Reporting.InternalError as InternalError
import Parse.Primitives (Parser, Row, Col)
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError



-- SHADER


shader :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
shader start@(Ann.Position row col) =
  do  block <- parseBlock
      shdr <- parseGlsl row col block
      end <- Parse.getPosition
      return (Ann.at start end (Src.Shader (Shader.fromChars block) shdr))



-- BLOCK


parseBlock :: Parser SyntaxError.Expr String
parseBlock =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ cerr eerr ->
    let
      !pos6 = plusPtr pos 6
    in
    if pos6 <= end
      && Parse.unsafeIndex (        pos  ) == 0x5B {- [ -}
      && Parse.unsafeIndex (plusPtr pos 1) == 0x67 {- g -}
      && Parse.unsafeIndex (plusPtr pos 2) == 0x6C {- l -}
      && Parse.unsafeIndex (plusPtr pos 3) == 0x73 {- s -}
      && Parse.unsafeIndex (plusPtr pos 4) == 0x6C {- l -}
      && Parse.unsafeIndex (plusPtr pos 5) == 0x7C {- | -}
    then
      let
        (# status, newPos, newRow, newCol #) =
          eatShader pos6 end row (col + 6)
      in
      case status of
        Good ->
          let
            !off = minusPtr pos6 (unsafeForeignPtrToPtr src)
            !len = minusPtr newPos pos6
            !block = BS_UTF8.toString (BSI.PS src off len)
            !newState = Parse.State src (plusPtr newPos 2) end indent newRow (newCol + 2)
          in
          cok block newState

        Unending ->
          cerr row col SyntaxError.EndlessShader

    else
      eerr row col SyntaxError.Start


data Status
  = Good
  | Unending


eatShader :: Ptr Word8 -> Ptr Word8 -> Row -> Col -> (# Status, Ptr Word8, Row, Col #)
eatShader pos end row col =
  if pos >= end then
    (# Unending, pos, row, col #)

  else
    let !word = Parse.unsafeIndex pos in
    if word == 0x007C {- | -} && Parse.isWord (plusPtr pos 1) end 0x5D {- ] -} then
      (# Good, pos, row, col #)

    else if word == 0x0A {- \n -} then
      eatShader (plusPtr pos 1) end (row + 1) 1

    else
      let !newPos = plusPtr pos (Parse.getCharWidth word) in
      eatShader newPos end row (col + 1)



-- GLSL


parseGlsl :: Row -> Col -> String -> Parser SyntaxError.Expr Shader.Types
parseGlsl startRow startCol src =
  case GLP.parse src of
    Right (GLS.TranslationUnit decls) ->
      return (foldr addInput emptyTypes (concatMap extractInputs decls))

    Left err ->
      let
        pos = Parsec.errorPos err
        row = fromIntegral (Parsec.sourceLine pos)
        col = fromIntegral (Parsec.sourceColumn pos)
        msg =
          Parsec.showErrorMessages
            "or"
            "unknown parse error"
            "expecting"
            "unexpected"
            "end of input"
            (Parsec.errorMessages err)
      in
      if row == 1
        then failure startRow (startCol + 6 + col) msg
        else failure (startRow + row - 1) col msg


failure :: Row -> Col -> String -> Parser SyntaxError.Expr a
failure row col msg =
  Parse.Parser $ \(Parse.State {}) _ _ cerr _ ->
    cerr row col (SyntaxError.ShaderProblem msg)



-- INPUTS


emptyTypes :: Shader.Types
emptyTypes =
  Shader.Types Map.empty Map.empty Map.empty


addInput :: (GLS.StorageQualifier, Shader.Type, String) -> Shader.Types -> Shader.Types
addInput (qual, tipe, name) glDecls =
  case qual of
    GLS.Attribute -> glDecls { Shader._attribute = Map.insert (Name.fromChars name) tipe (Shader._attribute glDecls) }
    GLS.Uniform   -> glDecls { Shader._uniform = Map.insert (Name.fromChars name) tipe (Shader._uniform glDecls) }
    GLS.Varying   -> glDecls { Shader._varying = Map.insert (Name.fromChars name) tipe (Shader._varying glDecls) }
    _             -> InternalError.report
      "Parse.Shader.addInput"
      "unexpected storage qualifier in addInput"
      "addInput only handles Attribute, Uniform, and Varying qualifiers. The extractInputs function should filter out all other qualifier types before reaching this point."


extractInputs :: GLS.ExternalDeclaration -> [(GLS.StorageQualifier, Shader.Type, String)]
extractInputs decl =
  case decl of
    GLS.Declaration
      (GLS.InitDeclaration
         (GLS.TypeDeclarator
            (GLS.FullType
               (Just (GLS.TypeQualSto qual))
               (GLS.TypeSpec _prec (GLS.TypeSpecNoPrecision tipe _mexpr1))))
         [GLS.InitDecl name _mexpr2 _mexpr3]
      ) ->
        (if qual `elem` [GLS.Attribute, GLS.Varying, GLS.Uniform] then (case tipe of
          GLS.Vec2 -> [(qual, Shader.V2, name)]
          GLS.Vec3 -> [(qual, Shader.V3, name)]
          GLS.Vec4 -> [(qual, Shader.V4, name)]
          GLS.Mat4 -> [(qual, Shader.M4, name)]
          GLS.Int -> [(qual, Shader.Int, name)]
          GLS.Float -> [(qual, Shader.Float, name)]
          GLS.Sampler2D -> [(qual, Shader.Texture, name)]
          _ -> []) else [])
    _ -> []


