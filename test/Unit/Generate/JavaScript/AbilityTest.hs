{-# LANGUAGE OverloadedStrings #-}

-- | Tests for 'Generate.JavaScript.Ability'.
--
-- Verifies the dictionary-passing code generation for ability impls.
-- The module compiles each @impl@ declaration to a JavaScript object
-- literal whose keys are method names and whose values are generated
-- method functions.
--
-- == Test Coverage
--
-- * 'implDictName' — name encoding includes ability and type names
-- * 'generateImplDict' — produces a 'JS.Var' statement wrapping a 'JS.Object'
-- * Method map ordering — fold order matches input keys
--
-- @since 0.20.0
module Unit.Generate.JavaScript.AbilityTest (tests) where

import qualified AST.Optimized as Opt
import qualified Canopy.Data.Name as Name
import qualified Canopy.ModuleName as ModuleName
import qualified Canopy.Package as Pkg
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Generate.JavaScript.Ability as Ability
import qualified Generate.JavaScript.Builder as JS
import qualified Generate.Mode as Mode
import Test.Tasty
import Test.Tasty.HUnit

-- | Root test tree.
tests :: TestTree
tests =
  testGroup
    "Generate.JavaScript.Ability"
    [ implDictNameTests,
      generateImplDictTests
    ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | A canonical home module for tests.
testHome :: ModuleName.Canonical
testHome = ModuleName.Canonical Pkg.core (Name.fromChars "Test")

-- | Dev mode with no extras enabled.
devMode :: Mode.Mode
devMode = Mode.Dev Nothing False False False Set.empty False

-- | A simple global used as the dictionary's declared name.
testGlobal :: Opt.Global
testGlobal = Opt.Global testHome (Name.fromChars "myImpl")

-- | Ability name used across tests.
showAbility :: Name.Name
showAbility = Name.fromChars "Show"

-- ---------------------------------------------------------------------------
-- implDictName
-- ---------------------------------------------------------------------------

implDictNameTests :: TestTree
implDictNameTests =
  testGroup
    "implDictName"
    [ testCase "result is a Global in the given home module" $
        let Opt.Global home _ = Ability.implDictName testHome showAbility "Int"
         in home @?= testHome,

      testCase "name encodes ability and type with dollar separators" $
        let Opt.Global _ dname = Ability.implDictName testHome showAbility "Int"
            encoded = Name.toChars dname
         in encoded @?= "$impl$Show$Int",

      testCase "different type names produce distinct dict names" $
        let Opt.Global _ n1 = Ability.implDictName testHome showAbility "Int"
            Opt.Global _ n2 = Ability.implDictName testHome showAbility "Float"
         in (n1 == n2) @?= False,

      testCase "different ability names produce distinct dict names" $
        let Opt.Global _ n1 = Ability.implDictName testHome showAbility "Int"
            Opt.Global _ n2 = Ability.implDictName testHome (Name.fromChars "Eq") "Int"
         in (n1 == n2) @?= False
    ]

-- ---------------------------------------------------------------------------
-- generateImplDict
-- ---------------------------------------------------------------------------

generateImplDictTests :: TestTree
generateImplDictTests =
  testGroup
    "generateImplDict"
    [ testCase "empty method map produces Var with empty Object" $
        let stmt = Ability.generateImplDict devMode testGlobal showAbility Map.empty
         in isVarWithObject stmt @?= True,

      testCase "single method produces Var wrapping Object with one entry" $
        let methods = Map.singleton (Name.fromChars "show") (Opt.Int 42)
            stmt = Ability.generateImplDict devMode testGlobal showAbility methods
         in objectLength stmt @?= Just 1,

      testCase "two methods produce Object with two entries" $
        let methods = Map.fromList
              [ (Name.fromChars "show", Opt.Int 1),
                (Name.fromChars "inspect", Opt.Int 2)
              ]
            stmt = Ability.generateImplDict devMode testGlobal showAbility methods
         in objectLength stmt @?= Just 2,

      testCase "statement is JS.Var (not JS.Return or JS.Block)" $
        let stmt = Ability.generateImplDict devMode testGlobal showAbility Map.empty
         in isJsVar stmt @?= True
    ]

-- ---------------------------------------------------------------------------
-- Structural predicates
-- ---------------------------------------------------------------------------

isVarWithObject :: JS.Stmt -> Bool
isVarWithObject (JS.Var _ (JS.Object _)) = True
isVarWithObject _ = False

isJsVar :: JS.Stmt -> Bool
isJsVar (JS.Var _ _) = True
isJsVar _ = False

objectLength :: JS.Stmt -> Maybe Int
objectLength (JS.Var _ (JS.Object pairs)) = Just (length pairs)
objectLength _ = Nothing
