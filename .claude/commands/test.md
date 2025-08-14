# Test Creation Prompt — Canopy Compiler Coding Guidelines (Non-Negotiable)

**Task:**

- Please create comprehensive **tests** for the module: `$ARGUMENTS`.
- Follow **CLAUDE.md standards** exactly - all rules are **non-negotiable**.
- Tests must achieve **≥80% coverage** and follow Canopy's testing architecture.
- Use **Haskell Tasty** framework with proper import qualification patterns.
- Check the result of functions, do not just compare 2 of the same arguments. Test that we get the expected and desired outcome from functions.

---

## Test Architecture & Structure

### Directory Organization

```
test/
├── Unit/                    -- Pure function testing
│   ├── AST/                 -- AST module tests
│   ├── Canopy/              -- Core Canopy module tests
│   ├── Data/                -- Data structure tests
│   ├── Json/                -- JSON codec tests
│   └── Parse/               -- Parser tests
├── Property/                -- QuickCheck property tests
│   ├── AST/                 -- AST property tests
│   ├── Canopy/              -- Core property tests
│   └── Data/                -- Data structure properties
├── Integration/             -- End-to-end integration tests
└── Golden/                  -- Output matching tests
    ├── expected/            -- Golden reference files
    └── sources/             -- Test input files
```

### Module Naming Conventions

- **Unit tests**: `test/Unit/<ModulePath>Test.hs` (e.g., `Unit/Parse/PatternTest.hs`)
- **Property tests**: `test/Property/<ModulePath>Props.hs` (e.g., `Property/Data/NameProps.hs`)
- **Golden tests**: `test/Golden/<ModulePath>Golden.hs` (e.g., `Golden/JsGenGolden.hs`)
- **Integration tests**: `test/Integration/<Feature>Test.hs` (e.g., `Integration/CompilerTest.hs`)

---

## Steps

### 1. **Review Module Architecture**

- Analyze the target module's public API, types, and functions
- Identify pure vs. effectful operations
- Map dependencies and integration points
- Document edge cases, error conditions, and invariants

### 2. **Audit Existing Coverage**

- Search test suite for existing coverage: `grep -r "ModuleName" test/`
- Check `test/Main.hs` for registered test modules
- Identify gaps in unit, property, golden, and integration coverage
- Review current test patterns and quality

### 3. **Apply Test Classification Strategy**

**Unit Tests (Primary):**

- Pure function behavior verification
- Type constructor and field validation
- Error condition handling
- Boundary value testing

**Property Tests (Laws & Invariants):**

- Round-trip properties (encode/decode, parse/serialize)
- Algebraic laws (monoid, functor, monad laws)
- Invariant preservation under operations
- Generated input validation

**Golden Tests (Output Verification):**

- Parser output against known-good files
- Code generation consistency
- Documentation generation
- Complex transformation results

**Integration Tests (End-to-End):**

- Module interaction workflows
- File system operations
- Build pipeline testing
- Error propagation chains

### 4. **Follow CLAUDE.md Import Standards**

**Mandatory Pattern (NO EXCEPTIONS):**

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Unit tests for Parse.Pattern module.
--
-- Tests pattern parsing functionality including basic patterns,
-- constructors, lists, tuples, and error conditions.
module Unit.Parse.PatternTest (tests) where

-- Pattern: Types unqualified, functions qualified
import qualified AST.Source as Src
import qualified Data.Name as Name
import qualified Parse.Pattern as Pat
import qualified Reporting.Error.Syntax as E
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertFailure)
import Test.Tasty.QuickCheck (testProperty)
```

### 5. **Implement Comprehensive Test Patterns**

**Unit Test Structure:**

```haskell
tests :: TestTree
tests = testGroup "ModuleName Tests"
  [ testBasicFunctionality
  , testErrorConditions
  , testBoundaryValues
  , testTypeConstructors
  ]
```

**Property Test Structure:**

```haskell
tests :: TestTree
tests = testGroup "ModuleName Properties"
  [ testProperty "roundtrip encode/decode" $ \input ->
      decode (encode input) == Just input
  , testProperty "invariant preservation" $ \input ->
      isValid input ==> isValid (transform input)
  ]
```

**Golden Test Structure:**

```haskell
tests :: TestTree
tests = testGroup "ModuleName Golden"
  [ goldenVsFile
      "test description"
      "test/Golden/expected/output.golden"
      "test/Golden/actual/output.result"
      (generateOutput testInput)
  ]
```

## Systematic Edge Case & Negative Input Testing Framework

### **Critical Edge Case Categories (Mandatory)**

#### 🔴 **Numeric Edge Cases (Test ALL):**

```haskell
testNumericBoundaries :: TestTree
testNumericBoundaries = testGroup "numeric boundary conditions"
  [ testCase "zero value" $ processNumber 0 @?= expectedZero
  , testCase "negative zero" $ processNumber (-0) @?= expectedNegativeZero
  , testCase "positive one" $ processNumber 1 @?= expectedOne
  , testCase "negative one" $ processNumber (-1) @?= expectedNegativeOne
  , testCase "maximum integer" $ processNumber maxBound @?= expectedMaxInt
  , testCase "minimum integer" $ processNumber minBound @?= expectedMinInt
  , testCase "maximum safe integer" $ processNumber 9007199254740991 @?= expectedMaxSafe
  , testCase "maximum safe + 1" $ processNumber 9007199254740992 @?= expectedOverflow
  , testCase "small positive float" $ processFloat 0.0001 @?= expectedSmallFloat
  , testCase "small negative float" $ processFloat (-0.0001) @?= expectedSmallNegFloat
  , testCase "infinity" $ processFloat (1/0) @?= Left InfinityError
  , testCase "negative infinity" $ processFloat (-1/0) @?= Left NegInfinityError
  , testCase "NaN" $ processFloat (0/0) @?= Left NaNError
  , testCase "denormalized numbers" $ processFloat 1e-324 @?= expectedDenormalized
  ]
```

#### 🔴 **String/Text Edge Cases (Test ALL):**

```haskell
testTextBoundaries :: TestTree
testTextBoundaries = testGroup "text boundary conditions"
  [ testCase "empty string" $ parseText "" @?= expectedEmpty
  , testCase "single space" $ parseText " " @?= expectedSingleSpace
  , testCase "only whitespace" $ parseText "   \t\n\r  " @?= expectedWhitespace
  , testCase "single character" $ parseText "a" @?= expectedSingleChar
  , testCase "single unicode" $ parseText "α" @?= expectedSingleUnicode
  , testCase "null character" $ parseText "\0" @?= expectedNullChar
  , testCase "control characters" $ parseText "\x01\x02\x03" @?= expectedControlChars
  , testCase "tab and newline" $ parseText "\t\n\r" @?= expectedTabNewline
  , testCase "unicode BOM" $ parseText "\xFEFF" @?= expectedBOM
  , testCase "unicode categories" $ parseText "αβγ中文العربية🚀" @?= expectedUnicodeCategories
  , testCase "emoji sequences" $ parseText "👨‍👩‍👧‍👦" @?= expectedEmojiSequence
  , testCase "combining characters" $ parseText "é" @?= expectedCombining  -- e + ´
  , testCase "right-to-left text" $ parseText "العربية" @?= expectedRTL
  , testCase "mixed direction" $ parseText "Hello العربية World" @?= expectedMixedDir
  , testCase "special characters" $ parseText "!@#$%^&*()[]{}|\\:;\"'<>,.?/" @?= expectedSpecial
  , testCase "very long string" $ parseText (replicate 100000 'a') @?= expectedVeryLong
  , testCase "maximum unicode codepoint" $ parseText "\x10FFFF" @?= expectedMaxUnicode
  , testCase "invalid UTF-8 sequences" $ parseInvalidUTF8 "\xFF\xFE" @?= Left UTF8Error
  , testCase "truncated unicode" $ parseText "α\x80" @?= Left TruncatedUnicodeError
  , testCase "overlong encoding" $ parseText "\xC0\x80" @?= Left OverlongEncodingError
  ]
```

#### 🔴 **Collection Edge Cases (Test ALL):**

```haskell
testCollectionBoundaries :: TestTree
testCollectionBoundaries = testGroup "collection boundary conditions"
  [ testCase "empty list" $ processList [] @?= expectedEmptyList
  , testCase "single element list" $ processList [item] @?= expectedSingleList
  , testCase "two element list" $ processList [item1, item2] @?= expectedTwoList
  , testCase "very large list" $ processList (replicate 1000000 item) @?= expectedLargeList
  , testCase "nested empty lists" $ processNested [[]] @?= expectedNestedEmpty
  , testCase "deeply nested lists" $ processNested (replicate 1000 [item]) @?= expectedDeeplyNested
  , testCase "circular references" $ processCircular circularList @?= Left CircularError
  , testCase "empty map" $ processMap Map.empty @?= expectedEmptyMap
  , testCase "single entry map" $ processMap (Map.singleton key value) @?= expectedSingleMap
  , testCase "duplicate keys" $ processMap duplicateKeyMap @?= Left DuplicateKeyError
  , testCase "null keys" $ processMap (Map.singleton Nothing value) @?= Left NullKeyError
  , testCase "empty keys" $ processMap (Map.singleton "" value) @?= expectedEmptyKeyMap
  , testCase "very large map" $ processMap largeMap @?= expectedLargeMap
  , testCase "empty set" $ processSet Set.empty @?= expectedEmptySet
  , testCase "single element set" $ processSet (Set.singleton item) @?= expectedSingleSet
  , testCase "maximum size collections" $ processMaxSize maxSizeCollection @?= expectedMaxSize
  , testCase "exceed maximum size" $ processMaxSize oversizeCollection @?= Left SizeExceededError
  ]
```

#### 🔴 **File System Edge Cases (Test ALL):**

```haskell
testFileSystemBoundaries :: TestTree
testFileSystemBoundaries = testGroup "file system boundary conditions"
  [ testCase "nonexistent file" $ readFile "nonexistent.txt" @?= Left FileNotFoundError
  , testCase "empty file" $ readFile "empty.txt" @?= Right ""
  , testCase "unreadable file" $ readFile "/root/secret.txt" @?= Left PermissionDeniedError
  , testCase "directory as file" $ readFile "directory/" @?= Left IsDirectoryError
  , testCase "device file" $ readFile "/dev/null" @?= Right ""
  , testCase "pipe file" $ readFile "/proc/self/fd/0" @?= Left PipeError
  , testCase "very long filename" $ readFile longFilename @?= Left FilenameTooLongError
  , testCase "invalid characters in filename" $ readFile "file\0name" @?= Left InvalidFilenameError
  , testCase "relative path traversal" $ readFile "../../../etc/passwd" @?= Left PathTraversalError
  , testCase "absolute path" $ readFile "/etc/passwd" @?= Left AbsolutePathError
  , testCase "symlink to nonexistent" $ readFile "broken-symlink" @?= Left SymlinkError
  , testCase "circular symlink" $ readFile "circular-symlink" @?= Left CircularSymlinkError
  , testCase "file in nonexistent directory" $ readFile "missing/file.txt" @?= Left DirectoryNotFoundError
  , testCase "temporary file deletion" $ withTempFile $ \f -> deleteAndRead f @?= Left FileDeletedError
  , testCase "concurrent file access" $ testConcurrentAccess file @?= expectedConcurrentResult
  , testCase "file locked by process" $ readLockedFile lockedFile @?= Left FileLockError
  , testCase "disk full scenario" $ writeToFullDisk largeData @?= Left DiskFullError
  , testCase "filename with unicode" $ readFile "αβγ.txt" @?= expectedUnicodeFilename
  ]
```

#### 🔴 **Network/IO Edge Cases (Test ALL):**

```haskell
testNetworkBoundaries :: TestTree
testNetworkBoundaries = testGroup "network/IO boundary conditions"
  [ testCase "invalid URL" $ fetchURL "not-a-url" @?= Left InvalidURLError
  , testCase "nonexistent host" $ fetchURL "http://nonexistent.invalid" @?= Left HostNotFoundError
  , testCase "connection refused" $ fetchURL "http://localhost:9999" @?= Left ConnectionRefusedError
  , testCase "connection timeout" $ fetchURL "http://httpbin.org/delay/30" @?= Left TimeoutError
  , testCase "empty response" $ fetchURL "http://httpbin.org/status/204" @?= Right ""
  , testCase "very large response" $ fetchURL hugeResponseUrl @?= Left ResponseTooLargeError
  , testCase "invalid SSL certificate" $ fetchURL "https://self-signed.invalid" @?= Left SSLError
  , testCase "redirect loop" $ fetchURL "http://httpbin.org/redirect/20" @?= Left RedirectLoopError
  , testCase "malformed response" $ fetchURL malformedResponseUrl @?= Left MalformedResponseError
  , testCase "interrupted transfer" $ interruptedFetch url @?= Left TransferInterruptedError
  , testCase "DNS resolution failure" $ fetchURL "http://no-such-domain.invalid" @?= Left DNSError
  , testCase "proxy authentication" $ fetchThroughProxy url @?= Left ProxyAuthError
  , testCase "rate limit exceeded" $ rapidFetch url @?= Left RateLimitError
  ]
```

#### 🔴 **Memory/Resource Edge Cases (Test ALL):**

```haskell
testResourceBoundaries :: TestTree
testResourceBoundaries = testGroup "resource boundary conditions"  
  [ testCase "memory exhaustion" $ processHugeData hugeDataset @?= Left OutOfMemoryError
  , testCase "stack overflow" $ deepRecursion 100000 @?= Left StackOverflowError
  , testCase "file descriptor exhaustion" $ openManyFiles @?= Left TooManyFilesError
  , testCase "thread exhaustion" $ spawnManyThreads @?= Left TooManyThreadsError
  , testCase "disk space exhaustion" $ fillDisk @?= Left DiskFullError
  , testCase "CPU time limit" $ infiniteLoop @?= Left CPUTimeLimitError
  , testCase "network timeout" $ slowNetworkOp @?= Left NetworkTimeoutError
  , testCase "memory leak detection" $ detectMemoryLeak @?= expectedNoLeak
  , testCase "resource cleanup" $ testResourceCleanup @?= expectedCleanup
  , testCase "concurrent resource access" $ testConcurrentResources @?= expectedConcurrentSafe
  , testCase "resource starvation" $ testResourceStarvation @?= Left ResourceStarvationError
  , testCase "deadlock detection" $ testDeadlock @?= Left DeadlockError
  ]
```

#### 🔴 **Concurrency Edge Cases (Test ALL):**

```haskell
testConcurrencyBoundaries :: TestTree
testConcurrencyBoundaries = testGroup "concurrency boundary conditions"
  [ testCase "race condition detection" $ testRaceCondition @?= expectedDeterministic
  , testCase "thread safety validation" $ testThreadSafety @?= expectedThreadSafe
  , testCase "deadlock prevention" $ testDeadlockPrevention @?= expectedNoDeadlock
  , testCase "resource contention" $ testResourceContention @?= expectedFairAccess
  , testCase "thread interruption" $ testThreadInterruption @?= expectedGracefulStop
  , testCase "exception propagation" $ testExceptionPropagation @?= expectedExceptionHandling
  , testCase "atomic operations" $ testAtomicity @?= expectedAtomic
  , testCase "memory ordering" $ testMemoryOrdering @?= expectedConsistentOrdering
  , testCase "lock-free algorithms" $ testLockFree @?= expectedLockFreeSafe
  , testCase "load balancing" $ testLoadBalancing @?= expectedBalancedLoad
  ]
```

#### 🔴 **Parser Edge Cases (Test ALL):**

```haskell
testParserBoundaries :: TestTree
testParserBoundaries = testGroup "parser boundary conditions"
  [ testCase "empty input" $ parse "" @?= Left EmptyInputError
  , testCase "single token" $ parse "token" @?= expectedSingleToken
  , testCase "whitespace only" $ parse "   " @?= Left WhitespaceOnlyError
  , testCase "unterminated string" $ parse "\"unterminated" @?= Left UnterminatedStringError
  , testCase "unterminated comment" $ parse "/* unterminated" @?= Left UnterminatedCommentError
  , testCase "nested comments" $ parse "/* outer /* inner */ */" @?= expectedNestedComments
  , testCase "invalid escape sequence" $ parse "\"\\x\"" @?= Left InvalidEscapeError
  , testCase "unicode in string" $ parse "\"αβγ\"" @?= expectedUnicodeString
  , testCase "very deep nesting" $ parse deeplyNestedInput @?= Left NestingTooDeepError
  , testCase "unexpected EOF" $ parse "if (true" @?= Left UnexpectedEOFError
  , testCase "invalid character" $ parse "\x01" @?= Left InvalidCharacterError
  , testCase "very long identifier" $ parse longIdentifier @?= Left IdentifierTooLongError
  , testCase "reserved keyword as identifier" $ parse "class" @?= Left ReservedKeywordError
  , testCase "ambiguous grammar" $ parse ambiguousInput @?= Left AmbiguousGrammarError
  , testCase "left recursion" $ parseLeftRecursive leftRecursiveInput @?= expectedLeftRecursion
  , testCase "operator precedence" $ parse "1 + 2 * 3" @?= expectedPrecedence
  , testCase "associativity" $ parse "1 - 2 - 3" @?= expectedAssociativity
  ]
```

#### 🔴 **Type System Edge Cases (Test ALL):**

```haskell
testTypeSystemBoundaries :: TestTree
testTypeSystemBoundaries = testGroup "type system boundary conditions"
  [ testCase "polymorphic recursion" $ typeCheck polymorphicRecursive @?= expectedPolyRecType
  , testCase "infinite types" $ typeCheck infiniteType @?= Left InfiniteTypeError
  , testCase "occurs check" $ typeCheck occursCheckCase @?= Left OccursCheckError
  , testCase "ambiguous types" $ typeCheck ambiguousTypes @?= Left AmbiguousTypeError
  , testCase "underdetermined types" $ typeCheck underdetermined @?= Left UnderdeterminedError
  , testCase "higher-kinded types" $ typeCheck higherKinded @?= expectedHigherKinded
  , testCase "existential types" $ typeCheck existentialTypes @?= expectedExistential
  , testCase "rank-n polymorphism" $ typeCheck rankNPoly @?= expectedRankN
  , testCase "type class constraints" $ typeCheck constrainedTypes @?= expectedConstrained
  , testCase "overlapping instances" $ typeCheck overlappingInstances @?= Left OverlapError
  , testCase "orphan instances" $ typeCheck orphanInstances @?= Left OrphanInstanceError
  , testCase "coherence violations" $ typeCheck coherenceViolation @?= Left CoherenceError
  ]
```

### **Comprehensive Error Testing Patterns**

#### 🔴 **Input Validation Errors (Test ALL):**

```haskell
testInputValidationErrors :: TestTree
testInputValidationErrors = testGroup "input validation error conditions"
  [ testCase "null input" $ validateInput Nothing @?= Left NullInputError
  , testCase "undefined input" $ validateInput undefined @?= Left UndefinedInputError
  , testCase "wrong type" $ validateInput wrongTypeInput @?= Left TypeMismatchError
  , testCase "out of range" $ validateInput outOfRangeInput @?= Left RangeError
  , testCase "invalid format" $ validateInput invalidFormatInput @?= Left FormatError
  , testCase "malformed structure" $ validateInput malformedInput @?= Left StructureError
  , testCase "missing required fields" $ validateInput missingFields @?= Left MissingFieldError
  , testCase "extra unexpected fields" $ validateInput extraFields @?= Left UnexpectedFieldError
  , testCase "circular references" $ validateInput circularRef @?= Left CircularReferenceError
  , testCase "constraint violations" $ validateInput violatingInput @?= Left ConstraintViolationError
  , testCase "security violations" $ validateInput securityViolation @?= Left SecurityViolationError
  , testCase "encoding errors" $ validateInput invalidEncoding @?= Left EncodingError
  ]
```

#### 🔴 **State Corruption Errors (Test ALL):**

```haskell
testStateCorruptionErrors :: TestTree  
testStateCorruptionErrors = testGroup "state corruption error conditions"
  [ testCase "invalid state transition" $ transitionState invalidTransition @?= Left InvalidTransitionError
  , testCase "state inconsistency" $ checkStateConsistency inconsistentState @?= Left InconsistentStateError
  , testCase "corrupted internal data" $ processCorruptedData corruptedData @?= Left DataCorruptionError
  , testCase "version mismatch" $ loadState newerVersionState @?= Left VersionMismatchError
  , testCase "checksum failure" $ validateChecksum corruptedChecksum @?= Left ChecksumError
  , testCase "invariant violation" $ checkInvariants violatingState @?= Left InvariantViolationError
  , testCase "state rollback failure" $ rollbackState failingRollback @?= Left RollbackError
  , testCase "concurrent modification" $ detectConcurrentMod concurrentState @?= Left ConcurrentModificationError
  ]
```

#### 🔴 **External Dependency Errors (Test ALL):**

```haskell
testExternalDependencyErrors :: TestTree
testExternalDependencyErrors = testGroup "external dependency error conditions"
  [ testCase "service unavailable" $ callService unavailableService @?= Left ServiceUnavailableError
  , testCase "authentication failure" $ authenticate invalidCredentials @?= Left AuthenticationError
  , testCase "authorization denied" $ authorize insufficientPermissions @?= Left AuthorizationError
  , testCase "API version incompatible" $ callAPI incompatibleVersion @?= Left APIVersionError
  , testCase "rate limit exceeded" $ makeRapidCalls @?= Left RateLimitExceededError
  , testCase "service degraded" $ callDegradedService @?= Left ServiceDegradedError
  , testCase "circuit breaker open" $ callThroughCircuitBreaker @?= Left CircuitBreakerOpenError
  , testCase "external timeout" $ callSlowService @?= Left ExternalTimeoutError
  , testCase "malformed response" $ processMalformedResponse @?= Left MalformedResponseError
  , testCase "protocol violation" $ testProtocolViolation @?= Left ProtocolViolationError
  ]
```

### **Negative Input Testing Framework**

```haskell
-- | Comprehensive negative input testing strategy
-- Tests all possible ways inputs can be invalid, malformed, or harmful

testNegativeInputs :: TestTree
testNegativeInputs = testGroup "negative input testing"
  [ testMaliciousInputs
  , testMalformedInputs  
  , testBoundaryViolations
  , testIncompatibleInputs
  , testCorruptedInputs
  ]

testMaliciousInputs :: TestTree
testMaliciousInputs = testGroup "malicious input detection"
  [ testCase "SQL injection attempt" $ processInput sqlInjection @?= Left SecurityViolationError
  , testCase "script injection" $ processInput scriptInjection @?= Left SecurityViolationError
  , testCase "path traversal" $ processInput pathTraversal @?= Left SecurityViolationError
  , testCase "buffer overflow attempt" $ processInput bufferOverflow @?= Left SecurityViolationError
  , testCase "denial of service" $ processInput dosAttack @?= Left SecurityViolationError
  , testCase "format string attack" $ processInput formatStringAttack @?= Left SecurityViolationError
  , testCase "XML external entity" $ processInput xmlExternalEntity @?= Left SecurityViolationError
  , testCase "deserialization bomb" $ processInput deserializationBomb @?= Left SecurityViolationError
  ]

testMalformedInputs :: TestTree
testMalformedInputs = testGroup "malformed input handling"
  [ testCase "truncated data" $ processInput truncatedData @?= Left TruncatedDataError
  , testCase "corrupted headers" $ processInput corruptedHeaders @?= Left CorruptedHeaderError
  , testCase "invalid checksums" $ processInput invalidChecksum @?= Left ChecksumError
  , testCase "wrong encoding" $ processInput wrongEncoding @?= Left EncodingError
  , testCase "mixed line endings" $ processInput mixedLineEndings @?= expectedNormalizedLineEndings
  , testCase "embedded null bytes" $ processInput embeddedNulls @?= Left EmbeddedNullError
  , testCase "non-printable characters" $ processInput nonPrintable @?= Left NonPrintableError
  , testCase "incomplete multibyte" $ processInput incompleteMultibyte @?= Left IncompleteMultibyteError
  ]

testBoundaryViolations :: TestTree
testBoundaryViolations = testGroup "boundary violation detection"
  [ testCase "exceed maximum length" $ processInput tooLongInput @?= Left LengthExceededError
  , testCase "below minimum length" $ processInput tooShortInput @?= Left LengthTooShortError
  , testCase "exceed maximum depth" $ processInput tooDeepInput @?= Left DepthExceededError
  , testCase "exceed maximum width" $ processInput tooWideInput @?= Left WidthExceededError
  , testCase "exceed memory limit" $ processInput memoryExceedingInput @?= Left MemoryLimitError
  , testCase "exceed time limit" $ processInput timeExceedingInput @?= Left TimeLimitError
  , testCase "exceed recursion limit" $ processInput recursionExceedingInput @?= Left RecursionLimitError
  ]
```

## Anti-Fake Testing Rules

### ❌ FORBIDDEN PATTERNS (Will cause test failure):
- **Mock functions**: `isValid _ = True`, `alwaysPasses _ = False`
- **Reflexive equality**: `version == version`, `name == name`  
- **Meaningless distinctness**: `mainName /= trueName`, `basics /= maybe`
- **Constant comparisons**: Testing that different constants are different
- **Non-empty checks**: `assertBool "shows non-empty" (not (null (show x)))`
- **Weak contains testing**: `assertBool "contains X" ("X" `isInfixOf` result)`
- **Partial string checks**: Using `isInfixOf`, `elem . words` instead of exact equality

### ✅ REQUIRED PATTERNS (Test exact values and behavior):
- **Exact value verification**: `Name.toChars Name._main @?= "main"`
- **Complete show testing**: `show Package.core @?= "Name {_author = elm, _project = core}"`
- **Actual behavior**: `Name.toChars (Name.fromChars "test") @?= "test"`
- **Business logic**: `Version.compare v1 v2 @?= expectedOrder`
- **Error conditions**: `parseInvalid "bad input" @?= Left expectedError`

**Good patterns:**

```haskell
-- ✅ Test exact string values
testCase "name constants have correct string values" $ do
  Name.toChars Name._main @?= "main"
  Name.toChars Name.true @?= "True" 
  Name.toChars Name.false @?= "False"

-- ✅ Test exact show output
testCase "types show with exact format" $ do
  show Version.one @?= "Version {_major = 1, _minor = 0, _patch = 0}"
  show Package.core @?= "Name {_author = elm, _project = core}"

-- ✅ Test actual behavior and transformations  
testCase "name roundtrip works correctly" $ do
  let original = "test"
      name = Name.fromChars original
      result = Name.toChars name
  result @?= original
```

**Bad patterns:**

```haskell
-- ❌ MEANINGLESS: Testing that constants are different
testCase "predefined names have expected properties" $ do
  let mainName = Name._main
      trueName = Name.true
      falseName = Name.false
  assertBool "_main and true are different" (mainName /= trueName)  -- MEANINGLESS!
  assertBool "true and false are different" (trueName /= falseName)  -- MEANINGLESS!

-- ❌ MEANINGLESS: Testing that same constants are equal
testCase "version one has consistent value" $ do
  let v1 = Version.one
      v2 = Version.one
  v1 @?= v2  -- MEANINGLESS!

-- ❌ MEANINGLESS: Testing that show produces output
testCase "version one show instance" $ do
  let version = Version.one
      shown = show version
  assertBool "show produces non-empty result" (not (null shown))  -- MEANINGLESS!
```

### 6. **Ensure CLAUDE.md Compliance**

- **Function Size**: Test functions ≤15 lines, ≤4 params, ≤4 branches
- **Import Qualification**: Types unqualified, functions qualified, meaningful aliases
- **Lens Usage**: Use lenses for record access in test data setup
- **Documentation**: Complete Haddock docs for test module purpose
- **Error Handling**: Test all error paths with rich error types

### 7. **Register Tests in Main.hs**

Add new test module to `test/Main.hs`:

```haskell
import qualified Unit.YourModule.YourModuleTest as YourModuleTest

unitTests :: TestTree
unitTests = testGroup "Unit Tests"
  [ -- ... existing tests
  , YourModuleTest.tests
  ]
```

### 8. **Validate with Build Commands**

```bash
# Build and test
make build
make test

# Specific test suites
make test-unit           # Unit tests only
make test-property       # Property tests only
make test-integration    # Integration tests only
make test-match PATTERN="YourModule"  # Specific tests

# Quality assurance
make lint                # Check style compliance
make format              # Apply code formatting
make test-coverage       # Generate coverage report (≥80% required)

# Watch mode for development
make test-watch          # Continuous testing
```

### 9. **Coverage Analysis & Validation**

- Verify ≥80% coverage: `make test-coverage`
- Check coverage report in `.stack-work/install/*/doc/`
- Identify uncovered branches and add targeted tests
- Ensure all public APIs have corresponding tests

### 10. **Agent Validation & Quality Assurance**

- Use general-purpose agent to validate test completeness
- Verify adherence to CLAUDE.md standards
- Check test naming, structure, and documentation
- Validate integration with existing test suite

### 11. **Version Control & Integration**

**Conventional Commit Format:**

```bash
test(module): add comprehensive unit and property tests for ModuleName

- Add unit tests covering all public functions
- Implement property tests for invariants and laws
- Include golden tests for output verification
- Achieve 90% test coverage
- Follow CLAUDE.md testing standards
```

---

## Quality Benchmarks

### **Required Test Quality Standards:**

1. **Coverage**: Minimum 80% line coverage, aim for 90%+
2. **Completeness**: Every public function, type, and constructor tested
3. **Error Testing**: All error paths and edge cases covered
4. **Property Testing**: Laws and invariants verified with QuickCheck (Do not check if haskell works properly, do not just compare 2 values, the test are there to check if the functions give the expected output. So thats what we need to check)
5. **Documentation**: Clear test purpose and module behavior explanation
6. **Integration**: Proper registration in test suite with clear naming
7. **Performance**: Tests run efficiently without blocking development workflow

### **Reference Implementations:**

**Unit Test Excellence:**

- `test/Unit/Parse/PatternTest.hs` - Comprehensive parser testing
- `test/Unit/Data/NameTest.hs` - Data structure testing

**Property Test Excellence:**

- `test/Property/Data/NameProps.hs` - Invariant testing
- `test/Property/Canopy/VersionProps.hs` - Law verification

**Golden Test Excellence:**

- `test/Golden/JsGenGolden.hs` - Output verification
- `test/Golden/ParseModuleGolden.hs` - Parse result validation

**Integration Test Excellence:**

- `test/Integration/CompilerTest.hs` - End-to-end workflows

---

## Compliance Checklist

- [ ] Module analysis complete with public API mapping
- [ ] Existing test coverage audited and gaps identified
- [ ] Test classification applied (unit/property/golden/integration)
- [ ] CLAUDE.md import patterns followed exactly
- [ ] Test functions meet size/complexity limits
- [ ] Comprehensive test coverage implemented (≥80%)
- [ ] All error paths and edge cases tested
- [ ] Property tests for invariants and laws included
- [ ] Tests registered in Main.hs with proper naming
- [ ] Build commands pass (lint, format, test-coverage)
- [ ] Agent validation confirms completeness and quality
- [ ] Conventional commit message prepared