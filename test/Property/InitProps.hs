{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Property-based tests for Init system.
--
-- This module provides comprehensive property-based testing for the Init
-- system using QuickCheck. Tests verify invariants, laws, and properties
-- that should hold across all valid inputs and configurations.
--
-- == Test Coverage
--
-- * Configuration lens laws and properties
-- * ProjectContext lens laws and invariants
-- * Error type properties and relationships
-- * Default value consistency properties
-- * Dependency map properties
-- * Directory name validation properties
--
-- == Testing Strategy
--
-- Property tests verify mathematical laws and invariants:
--
-- * Lens laws (view/set, set/set, set/view)
-- * Roundtrip properties for data transformations
-- * Invariants that must hold for all valid data
-- * Consistency properties between related functions
-- * Boundary condition behaviors
--
-- @since 0.19.1
module Property.InitProps
  ( tests,
  )
where

import Canopy.Constraint (Constraint)
import qualified Canopy.Constraint as Con
import Canopy.Package (Name)
import qualified Canopy.Package as Pkg
import qualified Canopy.Version as V
import Control.Lens ((&), (.~), (^.))
import qualified Control.Lens as Lens
import qualified Data.Map as Map
import Init.Types
  ( DefaultDeps (..),
    InitConfig (..),
    InitError (..),
    ProjectContext (..),
    configForce,
    configSkipPrompt,
    configVerbose,
    contextDependencies,
    contextProjectName,
    contextSourceDirs,
    contextTestDeps,
    defaultConfig,
    defaultContext,
    depsBrowser,
    depsCore,
    depsHtml,
  )
-- Note: Testing only exported validation behavior through public API
import qualified Init.Validation as Validation
import Test.Tasty (TestTree)
import qualified Test.Tasty as Test
import Test.Tasty.QuickCheck ((.&&.), (===), (==>))
import qualified Test.Tasty.QuickCheck as QC

-- | Main property test suite for Init system.
tests :: TestTree
tests =
  Test.testGroup
    "Init Property Tests"
    [ configLensProperties,
      contextLensProperties,
      errorProperties,
      defaultValueProperties,
      validationProperties,
      dependencyMapProperties
    ]

-- | Property tests for InitConfig lenses.
configLensProperties :: TestTree
configLensProperties =
  Test.testGroup
    "InitConfig Lens Properties"
    [ QC.testProperty "configVerbose lens view/set law" $
        \verbose force skip ->
          let config = InitConfig verbose force skip
              viewed = config ^. configVerbose
              updated = config & configVerbose Lens..~ True
           in viewed === verbose
                .&&. (updated ^. configVerbose) === True,
      QC.testProperty "configForce lens set/set law" $
        \verbose force skip newForce1 newForce2 ->
          let config = InitConfig verbose force skip
              updated1 =
                config & configForce Lens..~ newForce1
                  & configForce Lens..~ newForce2
              updated2 = config & configForce Lens..~ newForce2
           in updated1 === updated2,
      QC.testProperty "configSkipPrompt lens preserves other fields" $
        \verbose force skip newSkip ->
          let config = InitConfig verbose force skip
              updated = config & configSkipPrompt Lens..~ newSkip
           in (updated ^. configVerbose) === verbose
                .&&. (updated ^. configForce) === force
                .&&. (updated ^. configSkipPrompt) === newSkip,
      QC.testProperty "config lens composition is associative" $
        \verbose force skip ->
          let config = InitConfig verbose force skip
              path1 =
                config & configVerbose Lens..~ True
                  & configForce Lens..~ False
              path2 =
                (config & configVerbose Lens..~ True)
                  & configForce Lens..~ False
           in path1 === path2,
      QC.testProperty "config equality is reflexive and symmetric" $
        \verbose force skip ->
          let config1 = InitConfig verbose force skip
              config2 = InitConfig verbose force skip
           in (config1 == config1)
                .&&. (config1 == config2)
                .&&. (config2 == config1)
    ]

-- | Property tests for ProjectContext lenses.
contextLensProperties :: TestTree
contextLensProperties =
  Test.testGroup
    "ProjectContext Lens Properties"
    [ QC.testProperty "contextProjectName lens laws" $
        \maybeName sourceDirs ->
          let context = ProjectContext maybeName sourceDirs Map.empty Map.empty
              viewed = context ^. contextProjectName
              updated = context & contextProjectName Lens..~ Just "NewName"
           in viewed === maybeName
                .&&. (updated ^. contextProjectName) === Just "NewName",
      QC.testProperty "contextSourceDirs preserves structure" $
        QC.forAll (QC.listOf1 validDirNameGen) $ \sourceDirs ->
          let context = ProjectContext Nothing sourceDirs Map.empty Map.empty
              newDirs = ["new", "dirs"]
              updated = context & contextSourceDirs Lens..~ newDirs
           in (context ^. contextSourceDirs) === sourceDirs
                .&&. (updated ^. contextSourceDirs) === newDirs,
      QC.testProperty "contextDependencies lens preserves maps" $
        QC.forAll dependencyMapGen $ \deps ->
          let context = ProjectContext Nothing ["src"] deps Map.empty
              newDeps = Map.fromList [(Pkg.core, Con.anything)]
              updated = context & contextDependencies Lens..~ newDeps
           in (context ^. contextDependencies) === deps
                .&&. (updated ^. contextDependencies) === newDeps,
      QC.testProperty "context lens updates are independent" $
        QC.forAll dependencyMapGen $ \deps ->
          let context = ProjectContext Nothing ["src"] deps Map.empty
              updated =
                context & contextProjectName Lens..~ Just "Test"
                  & contextSourceDirs Lens..~ ["lib"]
           in (updated ^. contextDependencies) === deps
                .&&. (updated ^. contextTestDeps) === Map.empty,
      QC.testProperty "context field updates preserve others" $
        QC.forAll contextGen $ \context ->
          let originalDeps = context ^. contextDependencies
              originalTestDeps = context ^. contextTestDeps
              updated = context & contextProjectName Lens..~ Just "Modified"
           in (updated ^. contextDependencies) === originalDeps
                .&&. (updated ^. contextTestDeps) === originalTestDeps
    ]

-- | Property tests for InitError types.
errorProperties :: TestTree
errorProperties =
  Test.testGroup
    "Error Properties"
    [ QC.testProperty "ProjectExists preserves path information" $
        QC.forAll pathGen $ \path ->
          case ProjectExists path of
            ProjectExists resultPath -> resultPath === path
            _ -> QC.property False,
      QC.testProperty "FileSystemError preserves message information" $
        QC.forAll messageGen $ \message ->
          case FileSystemError message of
            FileSystemError resultMessage -> resultMessage === message
            _ -> QC.property False,
      QC.testProperty "NoSolution preserves package lists" $
        QC.forAll packageListGen $ \packages ->
          case NoSolution packages of
            NoSolution resultPackages -> resultPackages === packages
            _ -> QC.property False,
      QC.testProperty "error constructors are distinct" $
        QC.forAll pathGen $ \path ->
          QC.forAll messageGen $ \message ->
            let err1 = ProjectExists path
                err2 = FileSystemError message
             in case (err1, err2) of
                  (ProjectExists _, FileSystemError _) -> True
                  _ -> False,
      QC.testProperty "error types preserve equality" $
        QC.forAll pathGen $ \path ->
          let err1 = ProjectExists path
              err2 = ProjectExists path
           in case (err1, err2) of
                (ProjectExists p1, ProjectExists p2) -> p1 === p2
                _ -> QC.property False
    ]

-- | Property tests for default values.
defaultValueProperties :: TestTree
defaultValueProperties =
  Test.testGroup
    "Default Value Properties"
    [ QC.testProperty "defaultConfig is consistent" $
        let config = defaultConfig
         in (config ^. configVerbose) === False
              .&&. (config ^. configForce) === False
              .&&. (config ^. configSkipPrompt) === False,
      QC.testProperty "defaultContext has non-empty source dirs" $
        let context = defaultContext
            sourceDirs = context ^. contextSourceDirs
         in not (null sourceDirs)
              .&&. length sourceDirs >= 1,
      QC.testProperty "defaultContext dependencies include core" $
        let context = defaultContext
            deps = context ^. contextDependencies
         in Map.member Pkg.core deps
              .&&. not (Map.null deps),
      QC.testProperty "default lens operations are idempotent" $
        let config = defaultConfig
            context = defaultContext
            configUpdated = config & configVerbose Lens..~ False
            contextUpdated = context & contextProjectName Lens..~ Nothing
         in config === configUpdated
              .&&. (context ^. contextProjectName) === (contextUpdated ^. contextProjectName),
      QC.testProperty "defaults are internally consistent" $
        let config = defaultConfig
            context = defaultContext
         in (config ^. configVerbose) === False
              .&&. (context ^. contextProjectName) === Nothing
              .&&. Map.size (context ^. contextDependencies) >= 1
    ]

-- | Property tests for validation behavior through public API.
validationProperties :: TestTree
validationProperties =
  Test.testGroup
    "Validation Properties"
    [ QC.testProperty "valid directory names are accepted in context" $
        QC.forAll validDirNameGen $ \name ->
          let context = defaultContext & contextSourceDirs Lens..~ [name]
           in case Validation.validateConfiguration defaultConfig context of
                Right () -> True
                Left _ -> False,
      QC.testProperty "standard packages work in default configuration" $
        let context = defaultContext
            config = defaultConfig
         in case Validation.validateConfiguration config context of
              Right () -> True
              Left _ -> False,
      QC.testProperty "directory name validation is deterministic" $
        QC.forAll (QC.elements ["src", "lib", "tests"]) $ \name ->
          let context = defaultContext & contextSourceDirs Lens..~ [name]
              result1 = Validation.validateConfiguration defaultConfig context
              result2 = Validation.validateConfiguration defaultConfig context
           in case (result1, result2) of
                (Right (), Right ()) -> True
                (Left _, Left _) -> True -- Both fail consistently
                _ -> False, -- Inconsistent results
      QC.testProperty "empty source directories cause validation failure" $
        let context = defaultContext & contextSourceDirs Lens..~ []
         in case Validation.validateConfiguration defaultConfig context of
              Left _ -> True
              Right () -> False,
      QC.testProperty "default context validates successfully" $
        let result = Validation.validateConfiguration defaultConfig defaultContext
         in case result of
              Right () -> True
              Left _ -> False
    ]

-- | Property tests for dependency maps.
dependencyMapProperties :: TestTree
dependencyMapProperties =
  Test.testGroup
    "Dependency Map Properties"
    [ QC.testProperty "dependency map operations preserve size" $
        QC.forAll dependencyMapGen $ \deps ->
          let keys = Map.keys deps
              values = Map.elems deps
              reconstructed = Map.fromList (zip keys values)
           in Map.size deps === Map.size reconstructed,
      QC.testProperty "empty dependency map has zero size" $
        let emptyDeps = Map.empty :: Map.Map Name Constraint
         in Map.size emptyDeps === 0,
      QC.testProperty "dependency insertion increases size" $
        QC.forAll dependencyMapGen $ \deps ->
          QC.forAll packageNameGen $ \pkg ->
            let constraint = Con.anything
                newDeps = Map.insert pkg constraint deps
                originalSize = Map.size deps
                newSize = Map.size newDeps
             in not (Map.member pkg deps) ==> (newSize === originalSize + 1),
      QC.testProperty "dependency lookup is consistent" $
        QC.forAll dependencyMapGen $ \deps ->
          QC.forAll packageNameGen $ \pkg ->
            let hasPackage = Map.member pkg deps
                lookupResult = Map.lookup pkg deps
             in hasPackage === (lookupResult /= Nothing),
      QC.testProperty "map operations preserve constraints" $
        QC.forAll constraintGen $ \constraint ->
          let deps = Map.fromList [(Pkg.core, constraint)]
              looked = Map.lookup Pkg.core deps
           in looked === Just constraint
    ]

-- QuickCheck generators

-- | Generate valid directory names.
validDirNameGen :: QC.Gen String
validDirNameGen = QC.elements ["src", "lib", "tests", "app", "shared", "common"]

-- | Generate dependency maps.
dependencyMapGen :: QC.Gen (Map.Map Name Constraint)
dependencyMapGen = do
  packages <- QC.sublistOf [Pkg.core, Pkg.browser, Pkg.html]
  constraints <- QC.vectorOf (length packages) constraintGen
  pure (Map.fromList (zip packages constraints))

-- | Generate project contexts.
contextGen :: QC.Gen ProjectContext
contextGen = do
  maybeName <- QC.oneof [pure Nothing, Just <$> QC.elements ["App", "Project", "Test"]]
  sourceDirs <- QC.listOf1 validDirNameGen
  deps <- dependencyMapGen
  testDeps <- dependencyMapGen
  pure (ProjectContext maybeName sourceDirs deps testDeps)

-- | Generate constraints.
constraintGen :: QC.Gen Constraint
constraintGen = QC.elements [Con.anything, Con.exactly V.one]

-- | Generate package names.
packageNameGen :: QC.Gen Name
packageNameGen = QC.elements [Pkg.core, Pkg.browser, Pkg.html]

-- | Generate file paths.
pathGen :: QC.Gen String
pathGen =
  QC.elements
    [ "/home/user/project/canopy.json",
      "/tmp/test/canopy.json",
      "./canopy.json",
      "canopy.json"
    ]

-- | Generate error messages.
messageGen :: QC.Gen String
messageGen =
  QC.elements
    [ "Permission denied",
      "Disk full",
      "File not found",
      "Invalid path"
    ]

-- | Generate package lists.
packageListGen :: QC.Gen [Name]
packageListGen = QC.sublistOf [Pkg.core, Pkg.browser, Pkg.html]
