{-# LANGUAGE OverloadedStrings #-}

module Unit.FFI.ValidatorTest (tests) where

import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEnc
import qualified FFI.Validator as Validator
import qualified Generate.JavaScript.Builder as JS
import Test.Tasty
import Test.Tasty.HUnit

-- | Convert a ByteString 'BB.Builder' to 'Text' for inspection in tests.
builderToText :: BB.Builder -> Text.Text
builderToText = TextEnc.decodeUtf8 . LBS.toStrict . BB.toLazyByteString

-- | Convert a 'JS.Stmt' to 'Text' for inspection in tests.
stmtToText :: JS.Stmt -> Text.Text
stmtToText = builderToText . JS.stmtToBuilder

tests :: TestTree
tests =
  testGroup
    "FFI.Validator Tests"
    [ parseFFITypeTests,
      parseReturnTypeTests,
      generateValidatorNameTests,
      generateValidatorTests,
      generateAllValidatorsTests,
      generateAllValidatorsDedupedTests,
      generateOpaqueValidatorTests,
      collectAllTypesTests,
      validatorNameSanitizationTests,
      additionalValidatorTests
    ]

parseFFITypeTests :: TestTree
parseFFITypeTests =
  testGroup
    "parseFFIType"
    [ testCase "parses Int" $
        Validator.parseFFIType "Int" @?= Just Validator.FFIInt,
      testCase "parses Float" $
        Validator.parseFFIType "Float" @?= Just Validator.FFIFloat,
      testCase "parses String" $
        Validator.parseFFIType "String" @?= Just Validator.FFIString,
      testCase "parses Bool" $
        Validator.parseFFIType "Bool" @?= Just Validator.FFIBool,
      testCase "parses Unit" $
        Validator.parseFFIType "()" @?= Just Validator.FFIUnit,
      testCase "parses opaque type" $
        Validator.parseFFIType "AudioContext" @?= Just (Validator.FFIOpaque "AudioContext" []),
      testCase "parses List Int" $
        Validator.parseFFIType "List Int" @?= Just (Validator.FFIList Validator.FFIInt),
      testCase "parses List Float" $
        Validator.parseFFIType "List Float" @?= Just (Validator.FFIList Validator.FFIFloat),
      testCase "parses Maybe Int" $
        Validator.parseFFIType "Maybe Int" @?= Just (Validator.FFIMaybe Validator.FFIInt),
      testCase "parses Maybe String" $
        Validator.parseFFIType "Maybe String" @?= Just (Validator.FFIMaybe Validator.FFIString),
      testCase "parses Result String Int" $
        Validator.parseFFIType "Result String Int" @?= Just (Validator.FFIResult Validator.FFIString Validator.FFIInt),
      testCase "parses Result Error Value" $
        Validator.parseFFIType "Result Error Value" @?= Just (Validator.FFIResult (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "parses Task String Int" $
        Validator.parseFFIType "Task String Int" @?= Just (Validator.FFITask Validator.FFIString Validator.FFIInt),
      testCase "parses Task Error Value" $
        Validator.parseFFIType "Task Error Value" @?= Just (Validator.FFITask (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "parses nested List Maybe Int" $
        Validator.parseFFIType "List (Maybe Int)" @?= Just (Validator.FFIList (Validator.FFIMaybe Validator.FFIInt)),
      testCase "parses nested Maybe (List String)" $
        Validator.parseFFIType "Maybe (List String)" @?= Just (Validator.FFIMaybe (Validator.FFIList Validator.FFIString)),
      testCase "parses tuple (Int, String)" $
        Validator.parseFFIType "(Int, String)" @?= Just (Validator.FFITuple [Validator.FFIInt, Validator.FFIString]),
      testCase "parses tuple (Int, String, Bool)" $
        Validator.parseFFIType "(Int, String, Bool)" @?= Just (Validator.FFITuple [Validator.FFIInt, Validator.FFIString, Validator.FFIBool]),
      testCase "parses function Int -> String" $
        Validator.parseFFIType "Int -> String" @?= Just (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString),
      testCase "parses function Int -> String -> Bool" $
        Validator.parseFFIType "Int -> String -> Bool" @?= Just (Validator.FFIFunctionType [Validator.FFIInt, Validator.FFIString] Validator.FFIBool),
      testCase "parses function with complex return" $
        Validator.parseFFIType "Int -> Result String Bool" @?= Just (Validator.FFIFunctionType [Validator.FFIInt] (Validator.FFIResult Validator.FFIString Validator.FFIBool)),
      testCase "handles whitespace" $
        Validator.parseFFIType "  Int  " @?= Just Validator.FFIInt,
      testCase "handles whitespace in List" $
        Validator.parseFFIType "List   Int" @?= Just (Validator.FFIList Validator.FFIInt),
      testCase "returns Nothing for empty string" $
        Validator.parseFFIType "" @?= Nothing
    ]

parseReturnTypeTests :: TestTree
parseReturnTypeTests =
  testGroup
    "parseReturnType"
    [ testCase "extracts return type from simple function" $
        Validator.parseReturnType "Int -> String" @?= Just Validator.FFIString,
      testCase "extracts return type from multi-arg function" $
        Validator.parseReturnType "Int -> String -> Bool" @?= Just Validator.FFIBool,
      testCase "extracts Result return type" $
        Validator.parseReturnType "Int -> Result Error Value" @?= Just (Validator.FFIResult (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "extracts Task return type" $
        Validator.parseReturnType "String -> Task Error Value" @?= Just (Validator.FFITask (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])),
      testCase "returns Nothing for empty string" $
        Validator.parseReturnType "" @?= Nothing,
      testCase "returns type for non-function" $
        Validator.parseReturnType "Int" @?= Just Validator.FFIInt
    ]

generateValidatorNameTests :: TestTree
generateValidatorNameTests =
  testGroup
    "generateValidatorName"
    [ testCase "generates name for Int" $
        Validator.generateValidatorName Validator.FFIInt @?= "_validate_Int",
      testCase "generates name for Float" $
        Validator.generateValidatorName Validator.FFIFloat @?= "_validate_Float",
      testCase "generates name for String" $
        Validator.generateValidatorName Validator.FFIString @?= "_validate_String",
      testCase "generates name for Bool" $
        Validator.generateValidatorName Validator.FFIBool @?= "_validate_Bool",
      testCase "generates name for Unit" $
        Validator.generateValidatorName Validator.FFIUnit @?= "_validate_Unit",
      testCase "generates name for List Int" $
        Validator.generateValidatorName (Validator.FFIList Validator.FFIInt) @?= "_validate_List_Int",
      testCase "generates name for Maybe String" $
        Validator.generateValidatorName (Validator.FFIMaybe Validator.FFIString) @?= "_validate_Maybe_String",
      testCase "generates name for Result String Int" $
        Validator.generateValidatorName (Validator.FFIResult Validator.FFIString Validator.FFIInt) @?= "_validate_Result_String_Int",
      testCase "generates name for Task Error Value" $
        Validator.generateValidatorName (Validator.FFITask (Validator.FFIOpaque "Error" []) (Validator.FFIOpaque "Value" [])) @?= "_validate_Task_Opaque_Error_Opaque_Value",
      testCase "generates name for Tuple" $
        Validator.generateValidatorName (Validator.FFITuple [Validator.FFIInt, Validator.FFIString]) @?= "_validate_Tuple_Int_String",
      testCase "generates name for Opaque type" $
        Validator.generateValidatorName (Validator.FFIOpaque "AudioContext" []) @?= "_validate_Opaque_AudioContext",
      testCase "generates name for Function" $
        Validator.generateValidatorName (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString) @?= "_validate_Fn_String"
    ]

generateValidatorTests :: TestTree
generateValidatorTests =
  testGroup
    "generateValidator"
    [ testCase "generates exact Int validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig Validator.FFIInt)
          @?= "function _validate_Int(v,ctx){ if (! Number.isInteger( v) ) throw new Error('FFI type error at ' + ctx +': expected Int, got ' +typeof v); return ( v);}\n",
      testCase "generates exact Float validator with Infinity rejection" $
        stmtToText (Validator.generateValidator Validator.defaultConfig Validator.FFIFloat)
          @?= "function _validate_Float(v,ctx){ if (typeof v !=='number' ) throw new Error('FFI type error at ' + ctx +': expected Float, got ' +typeof v); if (! Number.isFinite( v) ) throw new Error('FFI type error at ' + ctx +': expected finite Float, got ' +typeof v); return ( v);}\n",
      testCase "generates exact String validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig Validator.FFIString)
          @?= "function _validate_String(v,ctx){ if (typeof v !=='string' ) throw new Error('FFI type error at ' + ctx +': expected String, got ' +typeof v); return ( v);}\n",
      testCase "generates exact Bool validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig Validator.FFIBool)
          @?= "function _validate_Bool(v,ctx){ if (typeof v !=='boolean' ) throw new Error('FFI type error at ' + ctx +': expected Bool, got ' +typeof v); return ( v);}\n",
      testCase "generates exact Unit validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig Validator.FFIUnit)
          @?= "function _validate_Unit(v,ctx){ return ( v);}\n",
      testCase "generates exact List Int validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFIList Validator.FFIInt))
          @?= "function _validate_List_Int(v,ctx){ if (! Array.isArray( v) ) throw new Error('FFI type error at ' + ctx +': expected List, got ' +typeof v); return ( v.map( function(el,i){ return ( _validate_Int( el, ctx +'[' + i +']'));}));}\n",
      testCase "generates exact Maybe Int validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFIMaybe Validator.FFIInt))
          @?= "function _validate_Maybe_Int(v,ctx){ if ( v ==null ) return ({$ :'Nothing'}); return ({$ :'Just',a : _validate_Int( v, ctx)});}\n",
      testCase "generates exact Result String Int validator with hasOwnProperty" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFIResult Validator.FFIString Validator.FFIInt))
          @?= "function _validate_Result_String_Int(v,ctx){ if (typeof v !=='object' || v ===null ||! Object.prototype.hasOwnProperty.call( v,'$') ) throw new Error('FFI type error at ' + ctx +': expected Result, got ' +typeof v); if ( v.$ ==='Ok' ) return ({$ :'Ok',a : _validate_Int( v.a, ctx +'.Ok')}); else{ if ( v.$ ==='Err' ) return ({$ :'Err',a : _validate_String( v.a, ctx +'.Err')});} throw new Error('FFI type error at ' + ctx +': expected Result (invalid $), got ' +typeof v);}\n",
      testCase "generates exact Task String Int validator with try/catch" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFITask Validator.FFIString Validator.FFIInt))
          @?= "function _validate_Task_String_Int(v,ctx){ if (typeof v !=='object' || v ==null ||typeof v.then !=='function' ) throw new Error('FFI type error at ' + ctx +': expected Task (expected Promise), got ' +typeof v); return ( v.then( function(ok){ try{ return ({$ :'Ok',a : _validate_Int( ok, ctx +'.then')});}catch(e){ return ({$ :'Err',a : _validate_String( String( e), ctx +'.validation')});}}, function(err){ try{ return ({$ :'Err',a : _validate_String( err, ctx +'.catch')});}catch(e){ return ({$ :'Err',a : String( e)});}}));}\n",
      testCase "generates exact Tuple Int String validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFITuple [Validator.FFIInt, Validator.FFIString]))
          @?= "function _validate_Tuple_Int_String(v,ctx){ if (! Array.isArray( v) || v.length !==2 ) throw new Error('FFI type error at ' + ctx +': expected Tuple2, got ' +typeof v); return ([ _validate_Int( v[0], ctx +'[' +0 +']') , _validate_String( v[1], ctx +'[' +1 +']')]);}\n",
      testCase "generates exact Function Int->String validator" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString))
          @?= "function _validate_Fn_String(v,ctx){ if (typeof v !=='function' ) throw new Error('FFI type error at ' + ctx +': expected Function, got ' +typeof v); return ( v);}\n",
      testCase "strict mode generates throw new Error" $
        let config = Validator.defaultConfig {Validator._configStrictMode = True}
         in stmtToText (Validator.generateValidator config Validator.FFIInt)
              @?= "function _validate_Int(v,ctx){ if (! Number.isInteger( v) ) throw new Error('FFI type error at ' + ctx +': expected Int, got ' +typeof v); return ( v);}\n",
      testCase "non-strict mode generates console.warn" $
        let config = Validator.defaultConfig {Validator._configStrictMode = False}
         in stmtToText (Validator.generateValidator config Validator.FFIInt)
              @?= "function _validate_Int(v,ctx){ if (! Number.isInteger( v) ) console.warn('FFI type warning at ' + ctx +': expected Int, got ' +typeof v) return ( v);}\n",
      testCase "debug mode generates JSON.stringify in error message" $
        let config = Validator.defaultConfig {Validator._configDebugMode = True}
         in stmtToText (Validator.generateValidator config Validator.FFIInt)
              @?= "function _validate_Int(v,ctx){ if (! Number.isInteger( v) ) throw new Error('FFI type error at ' + ctx +': expected Int, got ' +typeof v +': ' + JSON.stringify( v)); return ( v);}\n",
      testCase "validates opaque types with null check and instanceof when configured" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = True}
         in stmtToText (Validator.generateValidator config (Validator.FFIOpaque "AudioContext" []))
              @?= "function _validate_Opaque_AudioContext(v,ctx){ if ( v ==null ) throw new Error('FFI type error at ' + ctx +': expected AudioContext, got ' +typeof v); if (!( v instanceof AudioContext) ) throw new Error('FFI type error at ' + ctx +': expected AudioContext, got ' +typeof v); return ( v);}\n",
      testCase "validates opaque types with null check even when instanceof not configured" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = False}
         in stmtToText (Validator.generateValidator config (Validator.FFIOpaque "AudioContext" []))
              @?= "function _validate_Opaque_AudioContext(v,ctx){ if ( v ==null ) throw new Error('FFI type error at ' + ctx +': expected AudioContext, got ' +typeof v); return ( v);}\n",
      testCase "type variable validator rejects undefined" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFITypeVar "a"))
          @?= "function _validate_Var_a(v,ctx){ if (typeof v ==='undefined' ) throw new Error('FFI type error at ' + ctx +': expected non-undefined value, got ' +typeof v); return ( v);}\n",
      testCase "record validator generates hasOwnProperty field checks" $
        stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFIRecord [("name", Validator.FFIString), ("age", Validator.FFIInt)]))
          @?= "function _validate_Rec_name_age(v,ctx){ if (typeof v !=='object' || v ===null || Array.isArray( v) ) throw new Error('FFI type error at ' + ctx +': expected Record, got ' +typeof v); if (! Object.prototype.hasOwnProperty.call( v,'name') ) throw new Error('FFI type error at ' + ctx +': expected Record (missing field name), got ' +typeof v); _validate_String( v.name, ctx +'.name') if (! Object.prototype.hasOwnProperty.call( v,'age') ) throw new Error('FFI type error at ' + ctx +': expected Record (missing field age), got ' +typeof v); _validate_Int( v.age, ctx +'.age') return ( v);}\n"
    ]

generateAllValidatorsTests :: TestTree
generateAllValidatorsTests =
  testGroup
    "generateAllValidators"
    [ testCase "generates validator for List Int and nested Int" $
        builderToText (Validator.generateAllValidators Validator.defaultConfig (Validator.FFIList Validator.FFIInt))
          @?= "function _validate_List_Int(v,ctx){ if (! Array.isArray( v) ) throw new Error('FFI type error at ' + ctx +': expected List, got ' +typeof v); return ( v.map( function(el,i){ return ( _validate_Int( el, ctx +'[' + i +']'));}));}\nfunction _validate_Int(v,ctx){ if (! Number.isInteger( v) ) throw new Error('FFI type error at ' + ctx +': expected Int, got ' +typeof v); return ( v);}\n",
      testCase "generates validators for Result String Int with hasOwnProperty" $
        builderToText (Validator.generateAllValidators Validator.defaultConfig (Validator.FFIResult Validator.FFIString Validator.FFIInt))
          @?= "function _validate_Result_String_Int(v,ctx){ if (typeof v !=='object' || v ===null ||! Object.prototype.hasOwnProperty.call( v,'$') ) throw new Error('FFI type error at ' + ctx +': expected Result, got ' +typeof v); if ( v.$ ==='Ok' ) return ({$ :'Ok',a : _validate_Int( v.a, ctx +'.Ok')}); else{ if ( v.$ ==='Err' ) return ({$ :'Err',a : _validate_String( v.a, ctx +'.Err')});} throw new Error('FFI type error at ' + ctx +': expected Result (invalid $), got ' +typeof v);}\nfunction _validate_String(v,ctx){ if (typeof v !=='string' ) throw new Error('FFI type error at ' + ctx +': expected String, got ' +typeof v); return ( v);}\nfunction _validate_Int(v,ctx){ if (! Number.isInteger( v) ) throw new Error('FFI type error at ' + ctx +': expected Int, got ' +typeof v); return ( v);}\n",
      testCase "generates validators for Maybe (List Int)" $
        builderToText (Validator.generateAllValidators Validator.defaultConfig (Validator.FFIMaybe (Validator.FFIList Validator.FFIInt)))
          @?= "function _validate_Maybe_List_Int(v,ctx){ if ( v ==null ) return ({$ :'Nothing'}); return ({$ :'Just',a : _validate_List_Int( v, ctx)});}\nfunction _validate_List_Int(v,ctx){ if (! Array.isArray( v) ) throw new Error('FFI type error at ' + ctx +': expected List, got ' +typeof v); return ( v.map( function(el,i){ return ( _validate_Int( el, ctx +'[' + i +']'));}));}\nfunction _validate_Int(v,ctx){ if (! Number.isInteger( v) ) throw new Error('FFI type error at ' + ctx +': expected Int, got ' +typeof v); return ( v);}\n"
    ]

generateAllValidatorsDedupedTests :: TestTree
generateAllValidatorsDedupedTests =
  testGroup
    "generateAllValidatorsDeduped"
    [ testCase "deduplicates identical types across multiple return types" $
        -- FFIOpaque "Decoder" with different type args generates the SAME function name.
        -- nubBy on validator name must emit _validate_Opaque_Decoder only once.
        let types =
              [ Validator.FFIOpaque "Decoder" [Validator.FFITypeVar "flags"]
              , Validator.FFIOpaque "Decoder" [Validator.FFITypeVar "msg"]
              ]
            result = builderToText (Validator.generateAllValidatorsDeduped Validator.defaultConfig types)
            occurrences = length (filter (Text.isPrefixOf "function _validate_Opaque_Decoder") (Text.lines result))
         in occurrences @?= 1,
      testCase "emits each validator exactly once when types share subtypes" $
        -- Two functions returning List Int must not emit _validate_Int twice.
        let types = [Validator.FFIList Validator.FFIInt, Validator.FFIList Validator.FFIInt]
            result = builderToText (Validator.generateAllValidatorsDeduped Validator.defaultConfig types)
            intCount = length (filter (Text.isPrefixOf "function _validate_Int(v,ctx)") (Text.lines result))
         in intCount @?= 1,
      testCase "emits all distinct validators when types differ" $
        let types = [Validator.FFIList Validator.FFIInt, Validator.FFIList Validator.FFIString]
            result = builderToText (Validator.generateAllValidatorsDeduped Validator.defaultConfig types)
         in do
              length (filter (Text.isPrefixOf "function _validate_List_Int(v,ctx)") (Text.lines result)) @?= 1
              length (filter (Text.isPrefixOf "function _validate_List_String(v,ctx)") (Text.lines result)) @?= 1
              length (filter (Text.isPrefixOf "function _validate_Int(v,ctx)") (Text.lines result)) @?= 1
              length (filter (Text.isPrefixOf "function _validate_String(v,ctx)") (Text.lines result)) @?= 1
    ]

generateOpaqueValidatorTests :: TestTree
generateOpaqueValidatorTests =
  testGroup
    "generateOpaqueValidator"
    [ testCase "Unverified opaque null check with validateOpaque=False" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = False}
            result = stmtToText (Validator.generateOpaqueValidator config "AudioContext" Validator.Unverified)
         in do
              assertBool "contains null check" (Text.isInfixOf "==null" result)
              assertBool "no instanceof" (not (Text.isInfixOf "instanceof" result)),
      testCase "Unverified opaque instanceof check with validateOpaque=True" $
        let config = Validator.defaultConfig {Validator._configValidateOpaque = True}
            result = stmtToText (Validator.generateOpaqueValidator config "AudioContext" Validator.Unverified)
         in assertBool "contains instanceof" (Text.isInfixOf "instanceof" result),
      testCase "ClassBacked opaque uses instanceof check" $
        let result = stmtToText (Validator.generateOpaqueValidator Validator.defaultConfig "Foo" (Validator.ClassBacked "FooImpl"))
         in assertBool "contains instanceof FooImpl" (Text.isInfixOf "instanceof FooImpl" result),
      testCase "SymbolBranded opaque checks brand property" $
        let result = stmtToText (Validator.generateOpaqueValidator Validator.defaultConfig "Token" (Validator.SymbolBranded "token"))
         in assertBool "contains brand check" (Text.isInfixOf "__canopy_brand_token" result),
      testCase "ClassBacked opaque contains null check" $
        let result = stmtToText (Validator.generateOpaqueValidator Validator.defaultConfig "MyClass" (Validator.ClassBacked "MyClass"))
         in assertBool "contains null check" (Text.isInfixOf "==null" result),
      testCase "SymbolBranded opaque contains null check" $
        let result = stmtToText (Validator.generateOpaqueValidator Validator.defaultConfig "Brand" (Validator.SymbolBranded "brand"))
         in assertBool "contains null check" (Text.isInfixOf "==null" result),
      testCase "generated opaque function contains return v" $
        let result = stmtToText (Validator.generateOpaqueValidator Validator.defaultConfig "T" Validator.Unverified)
         in assertBool "contains return v" (Text.isInfixOf "return" result)
    ]

collectAllTypesTests :: TestTree
collectAllTypesTests =
  testGroup
    "collectAllTypes"
    [ testCase "primitive type returns singleton list" $
        Validator.collectAllTypes Validator.FFIInt @?= [Validator.FFIInt],
      testCase "List Int returns List Int and Int" $
        Validator.collectAllTypes (Validator.FFIList Validator.FFIInt)
          @?= [Validator.FFIList Validator.FFIInt, Validator.FFIInt],
      testCase "Maybe String returns Maybe String and String" $
        Validator.collectAllTypes (Validator.FFIMaybe Validator.FFIString)
          @?= [Validator.FFIMaybe Validator.FFIString, Validator.FFIString],
      testCase "Result String Int returns all three types" $
        Validator.collectAllTypes (Validator.FFIResult Validator.FFIString Validator.FFIInt)
          @?= [Validator.FFIResult Validator.FFIString Validator.FFIInt, Validator.FFIString, Validator.FFIInt],
      testCase "Task String Int returns all three types" $
        Validator.collectAllTypes (Validator.FFITask Validator.FFIString Validator.FFIInt)
          @?= [Validator.FFITask Validator.FFIString Validator.FFIInt, Validator.FFIString, Validator.FFIInt],
      testCase "Tuple includes all element types" $
        Validator.collectAllTypes (Validator.FFITuple [Validator.FFIInt, Validator.FFIString, Validator.FFIBool])
          @?= [Validator.FFITuple [Validator.FFIInt, Validator.FFIString, Validator.FFIBool], Validator.FFIInt, Validator.FFIString, Validator.FFIBool],
      testCase "FunctionType includes arg and return types" $
        Validator.collectAllTypes (Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString)
          @?= [Validator.FFIFunctionType [Validator.FFIInt] Validator.FFIString, Validator.FFIInt, Validator.FFIString],
      testCase "Record includes all field types" $
        Validator.collectAllTypes (Validator.FFIRecord [("x", Validator.FFIInt), ("y", Validator.FFIString)])
          @?= [Validator.FFIRecord [("x", Validator.FFIInt), ("y", Validator.FFIString)], Validator.FFIInt, Validator.FFIString],
      testCase "TypeVar returns singleton" $
        Validator.collectAllTypes (Validator.FFITypeVar "a") @?= [Validator.FFITypeVar "a"],
      testCase "Opaque returns singleton" $
        Validator.collectAllTypes (Validator.FFIOpaque "AudioContext" [])
          @?= [Validator.FFIOpaque "AudioContext" []],
      testCase "nested List (Maybe Int) returns all three" $
        length (Validator.collectAllTypes (Validator.FFIList (Validator.FFIMaybe Validator.FFIInt))) @?= 3
    ]

validatorNameSanitizationTests :: TestTree
validatorNameSanitizationTests =
  testGroup
    "validator name sanitization"
    [ testCase "Record with underscore field strips underscore" $
        let name = Validator.generateValidatorName (Validator.FFIRecord [("my_field", Validator.FFIInt)])
         in assertBool "name contains myfield" (Text.isInfixOf "myfield" name),
      testCase "Opaque with special chars produces valid name" $
        let name = Validator.generateValidatorName (Validator.FFIOpaque "My.Type" [])
         in assertBool "name is non-empty" (not (Text.null name)),
      testCase "TypeVar strips non-alnum chars" $
        let name = Validator.generateValidatorName (Validator.FFITypeVar "my_var")
         in Text.isPrefixOf "_validate_Var_" name @?= True,
      testCase "nested types in name" $
        let name = Validator.generateValidatorName (Validator.FFIList (Validator.FFIMaybe Validator.FFIInt))
         in name @?= "_validate_List_Maybe_Int"
    ]

additionalValidatorTests :: TestTree
additionalValidatorTests =
  testGroup
    "additional validator generation"
    [ testCase "generates validator name for Record type" $
        let name = Validator.generateValidatorName (Validator.FFIRecord [("x", Validator.FFIInt)])
         in Text.isPrefixOf "_validate_Rec_" name @?= True,
      testCase "generates validator name for empty Tuple" $
        let name = Validator.generateValidatorName (Validator.FFITuple [])
         in name @?= "_validate_Tuple_",
      testCase "generates non-empty output for every primitive" $
        let prims = [Validator.FFIInt, Validator.FFIFloat, Validator.FFIString, Validator.FFIBool, Validator.FFIUnit]
         in assertBool "all primitives produce non-empty validator"
              (all (not . Text.null . stmtToText . Validator.generateValidator Validator.defaultConfig) prims),
      testCase "non-strict mode uses console.warn for Float" $
        let config = Validator.defaultConfig {Validator._configStrictMode = False}
            result = stmtToText (Validator.generateValidator config Validator.FFIFloat)
         in assertBool "contains console.warn" (Text.isInfixOf "console.warn" result),
      testCase "debug mode includes JSON.stringify for String" $
        let config = Validator.defaultConfig {Validator._configDebugMode = True}
            result = stmtToText (Validator.generateValidator config Validator.FFIString)
         in assertBool "contains JSON.stringify" (Text.isInfixOf "JSON.stringify" result),
      testCase "opaque type with type args still validates null" $
        let result = stmtToText (Validator.generateValidator Validator.defaultConfig (Validator.FFIOpaque "Decoder" [Validator.FFITypeVar "msg"]))
         in assertBool "contains null check" (Text.isInfixOf "==null" result)
    ]
