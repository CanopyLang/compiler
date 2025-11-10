# Test Implementation Prompt — Canopy Compiler Missing Test Case Generation (Non-Negotiable)

**Task:**
Please implement all missing test cases based on the test gap analysis: `$ARGUMENTS`.

- **Target**: Complete test implementation based on provided gap analysis results
- **Standards**: Follow **CLAUDE.md testing guidelines** exactly - all rules are **non-negotiable**
- **Quality**: Generate production-ready test cases with proper documentation and structure
- **Architecture**: Apply systematic test patterns from exemplar test modules

---

## Test Implementation Strategy & Architecture

### Comprehensive Test Generation Framework

### Gap Analysis Input Processing

**Expected Analysis Input Format:**

```haskell
-- =================================================================
-- TEST COVERAGE ANALYSIS REPORT
-- Module: Make.Parser
-- Test File: test/Unit/Make/ParserTest.hs
-- Analysis Date: 2024-08-14
-- =================================================================

-- CRITICAL GAPS (Must Fix Immediately):
-- ═══════════════════════════════════

-- 🔴 UNTESTED PUBLIC FUNCTIONS:
--   ❌ parseConfig :: Text -> Either ParseError Config
--   ❌ validateInput :: Input -> Either ValidationError ValidatedInput
--   ❌ processData :: Config -> ValidatedInput -> Either ProcessError Result

-- 🔴 MISSING ERROR PATH TESTS:
--   ❌ Input validation failures
--   ❌ Resource exhaustion scenarios
--   ❌ Network/IO error conditions

-- 🔴 MISSING EDGE CASE TESTS:
--   ❌ Empty/null inputs
--   ❌ Maximum/minimum boundary values
--   ❌ Unicode/special character handling

-- HIGH PRIORITY GAPS (Fix Soon):
-- ══════════════════════════════

-- 🟡 INCOMPLETE PROPERTY TESTS:
--   ⚠ Missing algebraic property verification
--   ⚠ No invariant preservation tests

-- RECOMMENDED TEST ADDITIONS:
-- ═══════════════════════════
-- [Specific test recommendations...]
```

**Analysis Input Parsing Strategy:**

1. **Extract Module Information**: Parse target module and test file paths
2. **Parse Gap Categories**: Identify critical, high-priority, and medium gaps
3. **Function Mapping**: Extract untested functions with their signatures
4. **Error Analysis**: Identify missing error scenarios and edge cases
5. **Generate Implementation**: Create complete test code for all identified gaps

**Test Architecture Patterns:**

```
Complete Test Suite Structure:
├── Function Coverage Tests    -- Every public function tested
├── Edge Case Test Groups     -- Systematic boundary testing
├── Error Path Test Groups    -- Comprehensive failure testing
├── Property Test Groups      -- Law and invariant verification
├── Integration Test Groups   -- Module interaction testing
├── Performance Test Groups   -- Resource and timing validation

```

---

## Systematic Test Implementation Process

### 1. **Analysis Input Processing**

**Gap Analysis Report Parsing:**

```haskell
-- IMPLEMENTATION PATTERN: Process gap analysis input
-- Input: Complete test gap analysis report from /analyze-tests
-- Output: Targeted test implementation for identified gaps

-- Example analysis input processing:
-- INPUT: "❌ parseConfig :: Text -> Either ParseError Config"
-- OUTPUT: Complete test implementation with all scenarios

testParseConfig :: TestTree
testParseConfig = testGroup "parseConfig" -- GENERATED FROM ANALYSIS
  [ testValidInputs      -- Based on function signature analysis
  , testInvalidInputs    -- Based on error type analysis
  , testEdgeCases       -- Based on edge case gaps identified
  , testErrorConditions -- Based on missing error path analysis
  , testBoundaryViolations -- Based on boundary analysis
  ]
```

### 2. **Targeted Function Test Generation**

**Analysis-Driven Function Implementation:**

```haskell
-- PATTERN: Generate comprehensive tests based on specific analysis gaps
-- From analysis: "❌ parseConfig :: Text -> Either ParseError Config"
-- Generate: Complete function test coverage with all edge cases

-- Analysis Input Processing:
-- Function: parseConfig
-- Signature: Text -> Either ParseError Config
-- Missing: All test coverage
-- Error Type: ParseError
-- Return Type: Config

testParseConfig :: TestTree  -- GENERATED FROM ANALYSIS
testParseConfig = testGroup "parseConfig"
  [ testGroup "valid configurations"
    [ testCase "minimal valid config" $
        Component.parseConfig minimalConfig @?= Right expectedMinimal
    , testCase "complete valid config" $
        Component.parseConfig completeConfig @?= Right expectedComplete
    , testCase "config with defaults" $
        Component.parseConfig configWithDefaults @?= Right expectedWithDefaults
    , testCase "config with optional fields" $
        Component.parseConfig configWithOptionals @?= Right expectedWithOptionals
    ]
  , testGroup "invalid configurations" -- BASED ON ParseError ANALYSIS
    [ testCase "empty config" $
        Component.parseConfig "" @?= Left (ParseError "empty configuration")
    , testCase "malformed JSON" $
        Component.parseConfig "{invalid" @?= Left (ParseError "malformed JSON")
    , testCase "missing required fields" $
        Component.parseConfig missingRequired @?= Left (ParseError "missing required field")
    , testCase "invalid field types" $
        Component.parseConfig invalidTypes @?= Left (ParseError "invalid field type")
    , testCase "unknown fields" $
        Component.parseConfig unknownFields @?= Left (ParseError "unknown field")
    ]
  , testGroup "edge cases" -- BASED ON EDGE CASE GAP ANALYSIS
    [ testCase "very large config" $
        Component.parseConfig largeConfig @?= Right expectedLarge
    , testCase "unicode characters" $
        Component.parseConfig unicodeConfig @?= Right expectedUnicode
    , testCase "special characters" $
        Component.parseConfig specialCharConfig @?= Right expectedSpecialChar
    , testCase "deeply nested structure" $
        Component.parseConfig deeplyNestedConfig @?= Right expectedDeeplyNested
    , testCase "maximum string length" $
        Component.parseConfig maxStringConfig @?= Right expectedMaxString
    ]
  , testGroup "boundary conditions" -- SYSTEMATIC BOUNDARY TESTING
    [ testCase "minimum valid JSON" $
        Component.parseConfig "{}" @?= Left (ParseError "missing required fields")
    , testCase "maximum nesting depth" $
        Component.parseConfig maxNestingConfig @?= Right expectedMaxNesting
    , testCase "exceed nesting limit" $
        Component.parseConfig exceedNestingConfig @?= Left (ParseError "nesting too deep")
    , testCase "maximum array size" $
        Component.parseConfig maxArrayConfig @?= Right expectedMaxArray
    , testCase "exceed array limit" $
        Component.parseConfig exceedArrayConfig @?= Left (ParseError "array too large")
    ]
  , testGroup "security scenarios" -- SECURITY VULNERABILITY TESTING
    [ testCase "potential injection attempt" $
        Component.parseConfig injectionConfig @?= Left (ParseError "security violation")
    , testCase "excessively long string" $
        Component.parseConfig excessivelyLongConfig @?= Left (ParseError "string too long")
    , testCase "malicious unicode" $
        Component.parseConfig maliciousUnicodeConfig @?= Left (ParseError "invalid characters")
    ]
  , testGroup "performance constraints" -- PERFORMANCE BOUNDARY TESTING
    [ testCase "memory usage within bounds" $ do
        initialMemory <- getCurrentMemoryUsage
        result <- evaluate $ Component.parseConfig largeButValidConfig
        finalMemory <- getCurrentMemoryUsage
        result @?= Right expectedLargeButValid
        (finalMemory - initialMemory) `shouldSatisfy` (< maxMemoryIncrease)
    , testCase "parsing time within bounds" $ do
        start <- getCurrentTime
        result <- evaluate $ Component.parseConfig complexConfig
        end <- getCurrentTime
        result @?= Right expectedComplex
        diffUTCTime end start `shouldSatisfy` (< maxParsingTime)
    ]
  ]

-- Auto-generated test data based on analysis
minimalConfig :: Text  -- GENERATED BASED ON Config TYPE ANALYSIS
minimalConfig = "{ \"name\": \"test\", \"version\": \"1.0\" }"

expectedMinimal :: Config  -- GENERATED BASED ON CONSTRUCTOR ANALYSIS
expectedMinimal = Config
  { configName = "test"
  , configVersion = Version 1 0 0
  , configDescription = Nothing
  , configDependencies = []
  , configFlags = defaultFlags
  }

-- Security test data
injectionConfig :: Text
injectionConfig = "{ \"name\": \"'; DROP TABLE configs; --\", \"version\": \"1.0\" }"

-- Performance test data
largeButValidConfig :: Text
largeButValidConfig = "{ \"name\": \"test\", \"version\": \"1.0\", \"deps\": ["
  ++ intercalate "," (replicate 10000 "\"dep\"") ++ "] }"

-- Resource constraint constants
maxMemoryIncrease :: Int
maxMemoryIncrease = 10 * 1024 * 1024  -- 10MB

maxParsingTime :: NominalDiffTime
maxParsingTime = 1  -- 1 second
```

### 3. **Analysis-Based Edge Case Implementation**

**Gap-Driven Boundary Testing:**

```haskell
-- PATTERN: Implement comprehensive edge cases based on specific analysis gaps
-- From analysis: "❌ Empty/null inputs", "❌ Unicode/special character handling"
-- Generate: Systematic edge case test implementation

testComprehensiveEdgeCases :: TestTree  -- GENERATED FROM EDGE CASE GAP ANALYSIS
testComprehensiveEdgeCases = testGroup "comprehensive edge cases"
  [ testGroup "numeric boundary conditions" -- FROM ANALYSIS: "❌ Numeric boundaries"
    [ testCase "zero value" $
        Component.processNumeric 0 @?= Right (NumericResult 0)
    , testCase "negative zero" $
        Component.processNumeric (-0) @?= Right (NumericResult 0)
    , testCase "positive one" $
        Component.processNumeric 1 @?= Right (NumericResult 1)
    , testCase "negative one" $
        Component.processNumeric (-1) @?= Right (NumericResult (-1))
    , testCase "maximum integer" $
        Component.processNumeric maxBound @?= Right (NumericResult maxBound)
    , testCase "minimum integer" $
        Component.processNumeric minBound @?= Right (NumericResult minBound)
    , testCase "overflow detection" $
        Component.processNumeric (fromIntegral (maxBound :: Int) + 1) @?= Left OverflowError
    , testCase "underflow detection" $
        Component.processNumeric (fromIntegral (minBound :: Int) - 1) @?= Left UnderflowError
    , testCase "infinity handling" $
        Component.processFloat (1/0) @?= Left InfinityError
    , testCase "negative infinity" $
        Component.processFloat (-1/0) @?= Left NegativeInfinityError
    , testCase "NaN handling" $
        Component.processFloat (0/0) @?= Left NaNError
    , testCase "denormalized numbers" $
        Component.processFloat 1e-324 @?= Right (FloatResult 1e-324)
    ]
  , testGroup "text boundary conditions" -- FROM ANALYSIS: "❌ String boundaries"
    [ testCase "empty string" $
        Component.processText "" @?= Right (TextResult "")
    , testCase "single space" $
        Component.processText " " @?= Right (TextResult " ")
    , testCase "only whitespace" $
        Component.processText "   \t\n\r  " @?= Right (TextResult "   \t\n\r  ")
    , testCase "single character" $
        Component.processText "a" @?= Right (TextResult "a")
    , testCase "single unicode character" $
        Component.processText "α" @?= Right (TextResult "α")
    , testCase "null character" $
        Component.processText "\0" @?= Right (TextResult "\0")
    , testCase "control characters" $
        Component.processText "\x01\x02\x03" @?= Right (TextResult "\x01\x02\x03")
    , testCase "unicode BOM" $
        Component.processText "\xFEFF" @?= Right (TextResult "\xFEFF")
    , testCase "combined unicode characters" $
        Component.processText "é" @?= Right (TextResult "é")  -- e + ´
    , testCase "emoji sequences" $
        Component.processText "👨‍👩‍👧‍👦" @?= Right (TextResult "👨‍👩‍👧‍👦")
    , testCase "right-to-left text" $
        Component.processText "العربية" @?= Right (TextResult "العربية")
    , testCase "mixed text direction" $
        Component.processText "Hello العربية World" @?= Right (TextResult "Hello العربية World")
    , testCase "special characters" $
        Component.processText "!@#$%^&*()[]{}|\\:;\"'<>,.?/" @?= Right (TextResult "!@#$%^&*()[]{}|\\:;\"'<>,.?/")
    , testCase "very long string" $
        Component.processText (replicate 100000 'a') @?= Right (TextResult (replicate 100000 'a'))
    , testCase "maximum unicode codepoint" $
        Component.processText "\x10FFFF" @?= Right (TextResult "\x10FFFF")
    , testCase "invalid UTF-8 sequences" $
        Component.processInvalidUTF8 "\xFF\xFE" @?= Left UTF8Error
    , testCase "truncated multibyte sequence" $
        Component.processText "α\x80" @?= Left TruncatedUnicodeError
    , testCase "overlong encoding" $
        Component.processText "\xC0\x80" @?= Left OverlongEncodingError
    , testCase "surrogate pair handling" $
        Component.processText "\xD800\xDC00" @?= Right (TextResult "\xD800\xDC00")
    ]
  , testGroup "collection boundary conditions" -- FROM ANALYSIS: "❌ Collection boundaries"
    [ testCase "empty list" $
        Component.processList [] @?= Right (ListResult [])
    , testCase "single element list" $
        Component.processList [item] @?= Right (ListResult [item])
    , testCase "two element list" $
        Component.processList [item1, item2] @?= Right (ListResult [item1, item2])
    , testCase "very large list" $
        Component.processList (replicate 1000000 item) @?= Right (ListResult (replicate 1000000 item))
    , testCase "nested empty lists" $
        Component.processNested [[]] @?= Right (NestedResult [[]])
    , testCase "deeply nested lists" $
        Component.processNested (replicate 1000 [item]) @?= Right (NestedResult (replicate 1000 [item]))
    , testCase "circular reference detection" $
        Component.processCircular circularList @?= Left CircularReferenceError
    , testCase "empty map" $
        Component.processMap Map.empty @?= Right (MapResult Map.empty)
    , testCase "single entry map" $
        Component.processMap (Map.singleton key value) @?= Right (MapResult (Map.singleton key value))
    , testCase "null keys handling" $
        Component.processMap (Map.singleton Nothing value) @?= Left NullKeyError
    , testCase "empty string keys" $
        Component.processMap (Map.singleton "" value) @?= Right (MapResult (Map.singleton "" value))
    , testCase "unicode keys" $
        Component.processMap (Map.singleton "αβγ" value) @?= Right (MapResult (Map.singleton "αβγ" value))
    , testCase "very large map" $
        Component.processMap (Map.fromList largeKVPairs) @?= Right (MapResult (Map.fromList largeKVPairs))
    , testCase "maximum collection size" $
        Component.processMaxSize maxSizeCollection @?= Right (MaxSizeResult maxSizeCollection)
    , testCase "exceed maximum size" $
        Component.processMaxSize oversizeCollection @?= Left SizeExceededError
    , testCase "memory exhaustion protection" $
        Component.processHugeCollection hugeCollection @?= Left OutOfMemoryError
    ]
  , testGroup "file system boundary conditions" -- FROM ANALYSIS: "❌ File system boundaries"
    [ testCase "nonexistent file" $
        Component.readFile "nonexistent.txt" @?= Left FileNotFoundError
    , testCase "empty file" $
        Component.readFile "empty.txt" @?= Right ""
    , testCase "unreadable file permissions" $
        Component.readFile "/root/secret.txt" @?= Left PermissionDeniedError
    , testCase "directory treated as file" $
        Component.readFile "directory/" @?= Left IsDirectoryError
    , testCase "device file handling" $
        Component.readFile "/dev/null" @?= Right ""
    , testCase "pipe file handling" $
        Component.readFile "/proc/self/fd/0" @?= Left PipeError
    , testCase "very long filename" $
        Component.readFile (replicate 1000 'a') @?= Left FilenameTooLongError
    , testCase "invalid filename characters" $
        Component.readFile "file\0name" @?= Left InvalidFilenameError
    , testCase "path traversal protection" $
        Component.readFile "../../../etc/passwd" @?= Left PathTraversalError
    , testCase "absolute path restriction" $
        Component.readFile "/etc/passwd" @?= Left AbsolutePathError
    , testCase "broken symlink handling" $
        Component.readFile "broken-symlink" @?= Left SymlinkError
    , testCase "circular symlink detection" $
        Component.readFile "circular-symlink" @?= Left CircularSymlinkError
    , testCase "nonexistent directory" $
        Component.readFile "missing/file.txt" @?= Left DirectoryNotFoundError
    , testCase "unicode filename support" $
        Component.readFile "αβγ.txt" @?= Right expectedUnicodeFileContent
    , testCase "case sensitivity handling" $
        Component.testCaseSensitiveFiles @?= expectedCaseSensitiveResult
    ]
  ]

-- Edge case test data
item :: TestItem
item = TestItem "test"

circularList :: [TestItem]
circularList = let xs = TestItem "circular" : xs in take 10 xs

largeKVPairs :: [(Text, TestValue)]
largeKVPairs = [(Text.pack (show i), TestValue i) | i <- [1..100000]]

maxSizeCollection :: [TestItem]
maxSizeCollection = replicate maxCollectionSize item

oversizeCollection :: [TestItem]
oversizeCollection = replicate (maxCollectionSize + 1) item

hugeCollection :: [TestItem]
hugeCollection = replicate (10 * maxCollectionSize) item

maxCollectionSize :: Int
maxCollectionSize = 1000000
```

### 4. **Analysis-Based Error Path Implementation**

**Gap-Driven Error Scenario Testing:**

```haskell
-- PATTERN: Implement comprehensive error tests based on specific analysis gaps
-- From analysis: "❌ Input validation failures", "❌ Resource exhaustion scenarios"
-- Generate: Systematic error path test implementation

testComprehensiveErrorPaths :: TestTree  -- GENERATED FROM ERROR GAP ANALYSIS
testComprehensiveErrorPaths = testGroup "comprehensive error paths"
  [ testGroup "input validation errors" -- FROM ANALYSIS: "❌ Input validation failures"
    [ testCase "null input validation" $
        Component.validateInput Nothing @?= Left (ValidationError "input cannot be null")
    , testCase "undefined input handling" $
        Component.validateInput undefined @?= Left (ValidationError "input cannot be undefined")
    , testCase "wrong type input" $
        Component.validateInput wrongTypeInput @?= Left (ValidationError "input type mismatch")
    , testCase "out of range input" $
        Component.validateInput outOfRangeInput @?= Left (ValidationError "input out of valid range")
    , testCase "negative where positive expected" $
        Component.validateInput negativeInput @?= Left (ValidationError "positive value required")
    , testCase "zero where positive expected" $
        Component.validateInput zeroInput @?= Left (ValidationError "non-zero value required")
    , testCase "invalid format detection" $
        Component.validateInput invalidFormatInput @?= Left (ValidationError "invalid input format")
    , testCase "malformed structure detection" $
        Component.validateInput malformedStructureInput @?= Left (ValidationError "malformed input structure")
    , testCase "missing required fields" $
        Component.validateInput missingRequiredFields @?= Left (ValidationError "missing required fields")
    , testCase "unexpected extra fields" $
        Component.validateInput extraFieldsInput @?= Left (ValidationError "unexpected fields present")
    , testCase "readonly field modification attempt" $
        Component.validateInput readonlyModificationInput @?= Left (ValidationError "readonly field modification")
    , testCase "circular reference detection" $
        Component.validateInput circularRefInput @?= Left (ValidationError "circular reference detected")
    , testCase "constraint violation detection" $
        Component.validateInput constraintViolatingInput @?= Left (ValidationError "constraint violation")

    , testCase "encoding error detection" $
        Component.validateInput invalidEncodingInput @?= Left (ValidationError "invalid character encoding")
    , testCase "checksum failure detection" $
        Component.validateInput corruptedChecksumInput @?= Left (ValidationError "checksum validation failed")
    ]
  , testGroup "state corruption errors" -- FROM ANALYSIS: "❌ State corruption scenarios"
    [ testCase "invalid state transition" $
        Component.transitionState invalidTransition @?= Left (StateError "invalid state transition")
    , testCase "state inconsistency detection" $
        Component.checkStateConsistency inconsistentState @?= Left (StateError "state inconsistency detected")
    , testCase "corrupted internal data" $
        Component.processCorruptedData corruptedInternalData @?= Left (StateError "corrupted internal data")
    , testCase "version mismatch handling" $
        Component.loadState newerVersionState @?= Left (StateError "incompatible state version")
    , testCase "schema mismatch detection" $
        Component.loadState schemaMismatchState @?= Left (StateError "state schema mismatch")
    , testCase "checksum validation failure" $
        Component.validateChecksum corruptedChecksumState @?= Left (StateError "state checksum validation failed")
    , testCase "magic number validation" $
        Component.validateMagicNumber wrongMagicState @?= Left (StateError "invalid state magic number")
    , testCase "invariant violation detection" $
        Component.checkInvariants invariantViolatingState @?= Left (StateError "state invariant violation")
    , testCase "rollback failure handling" $
        Component.rollbackState failingRollbackState @?= Left (StateError "state rollback failed")
    , testCase "concurrent modification detection" $
        Component.detectConcurrentMod concurrentModState @?= Left (StateError "concurrent state modification")
    , testCase "stale state access detection" $
        Component.accessStaleState staleState @?= Left (StateError "stale state access attempt")
    , testCase "state lock timeout" $
        Component.lockState timeoutLockState @?= Left (StateError "state lock acquisition timeout")
    ]
  , testGroup "resource exhaustion scenarios" -- FROM ANALYSIS: "❌ Resource exhaustion scenarios"
    [ testCase "memory exhaustion protection" $ do
        result <- runExceptT $ Component.processHugeData hugeMemoryData
        result @?= Left (ResourceError "memory limit exceeded")
    , testCase "stack overflow protection" $ do
        result <- runExceptT $ Component.deepRecursion excessiveDepth
        result @?= Left (ResourceError "stack overflow detected")
    , testCase "heap exhaustion detection" $ do
        result <- runExceptT $ Component.allocateHugeStructure massiveAllocation
        result @?= Left (ResourceError "heap exhaustion")
    , testCase "file descriptor exhaustion" $ do
        result <- runExceptT $ Component.openManyFiles tooManyFiles
        result @?= Left (ResourceError "file descriptor limit exceeded")
    , testCase "thread exhaustion protection" $ do
        result <- runExceptT $ Component.spawnManyThreads excessiveThreads
        result @?= Left (ResourceError "thread limit exceeded")
    , testCase "process limit enforcement" $ do
        result <- runExceptT $ Component.forkManyProcesses tooManyProcesses
        result @?= Left (ResourceError "process limit exceeded")
    , testCase "disk space exhaustion" $ do
        result <- runExceptT $ Component.writeHugeFile massiveFileData
        result @?= Left (ResourceError "disk space exhausted")
    , testCase "inode exhaustion detection" $ do
        result <- runExceptT $ Component.createManyFiles excessiveFileCount
        result @?= Left (ResourceError "inode limit exceeded")
    , testCase "CPU time limit enforcement" $ do
        result <- runExceptT $ Component.infiniteLoop
        result @?= Left (ResourceError "CPU time limit exceeded")
    , testCase "wall clock timeout" $ do
        result <- runExceptT $ Component.longRunningTask excessiveWaitTime
        result @?= Left (ResourceError "wall clock timeout")
    ]
  , testGroup "external dependency errors" -- FROM ANALYSIS: "❌ External dependency failures"
    [ testCase "service unavailable handling" $ do
        result <- runExceptT $ Component.callService unavailableService
        result @?= Left (ExternalError "service unavailable")
    , testCase "service degraded handling" $ do
        result <- runExceptT $ Component.callDegradedService
        result @?= Left (ExternalError "service degraded")
    , testCase "authentication failure" $ do
        result <- runExceptT $ Component.authenticate invalidCredentials
        result @?= Left (ExternalError "authentication failed")
    , testCase "authorization denial" $ do
        result <- runExceptT $ Component.authorize insufficientPermissions
        result @?= Left (ExternalError "authorization denied")
    , testCase "expired token handling" $ do
        result <- runExceptT $ Component.callWithExpiredToken
        result @?= Left (ExternalError "token expired")
    , testCase "API version incompatibility" $ do
        result <- runExceptT $ Component.callAPI incompatibleAPIVersion
        result @?= Left (ExternalError "API version incompatible")
    , testCase "rate limit enforcement" $ do
        result <- runExceptT $ Component.makeRapidCalls excessiveCallRate
        result @?= Left (ExternalError "rate limit exceeded")
    , testCase "quota exhaustion" $ do
        result <- runExceptT $ Component.exceedQuota
        result @?= Left (ExternalError "quota exceeded")
    , testCase "circuit breaker activation" $ do
        result <- runExceptT $ Component.callThroughCircuitBreaker
        result @?= Left (ExternalError "circuit breaker open")
    , testCase "external service timeout" $ do
        result <- runExceptT $ Component.callSlowService excessiveTimeout
        result @?= Left (ExternalError "external service timeout")
    , testCase "malformed response handling" $ do
        result <- runExceptT $ Component.processMalformedResponse
        result @?= Left (ExternalError "malformed response")
    , testCase "partial response handling" $ do
        result <- runExceptT $ Component.processPartialResponse
        result @?= Left (ExternalError "partial response received")
    , testCase "protocol violation detection" $ do
        result <- runExceptT $ Component.testProtocolViolation
        result @?= Left (ExternalError "protocol violation")
    , testCase "encryption failure handling" $ do
        result <- runExceptT $ Component.encryptData corruptedEncryptionKey
        result @?= Left (ExternalError "encryption failed")
    , testCase "decryption failure handling" $ do
        result <- runExceptT $ Component.decryptData corruptedCiphertext
        result @?= Left (ExternalError "decryption failed")
    , testCase "certificate validation failure" $ do
        result <- runExceptT $ Component.validateCertificate expiredCertificate
        result @?= Left (ExternalError "certificate validation failed")
    ]
  ]

-- Error test data generators
wrongTypeInput :: TestInput
wrongTypeInput = TestInput { inputData = 123, inputExpectedType = "String" }

outOfRangeInput :: TestInput
outOfRangeInput = TestInput { inputValue = -1, inputValidRange = (0, 100) }

malformedStructureInput :: TestInput
malformedStructureInput = TestInput { inputStructure = "{ incomplete" }

corruptedInternalData :: TestState
corruptedInternalData = TestState { stateData = "corrupted", stateChecksum = "invalid" }

hugeMemoryData :: TestData
hugeMemoryData = TestData (replicate (1000 * 1024 * 1024) 'x')  -- 1GB

excessiveDepth :: Int
excessiveDepth = 100000

massiveAllocation :: AllocationRequest
massiveAllocation = AllocationRequest (10 * 1024 * 1024 * 1024)  -- 10GB

unavailableService :: ServiceConfig
unavailableService = ServiceConfig "http://nonexistent.service" 5000

invalidCredentials :: Credentials
invalidCredentials = Credentials "invalid_user" "wrong_password"
```

### 5. **Analysis-Based Property Test Implementation**

**Gap-Driven Property Testing:**

```haskell
-- PATTERN: Implement comprehensive properties based on specific analysis gaps
-- From analysis: "⚠ Missing algebraic property verification", "⚠ No invariant preservation tests"
-- Generate: Systematic property test implementation

testComprehensiveProperties :: TestTree  -- GENERATED FROM PROPERTY GAP ANALYSIS
testComprehensiveProperties = testGroup "comprehensive property tests"
  [ testGroup "algebraic properties" -- FROM ANALYSIS: "⚠ Missing algebraic property verification"
    [ testProperty "associativity law" $ \a b c ->
        Component.combine (Component.combine a b) c === Component.combine a (Component.combine b c)
    , testProperty "commutativity law" $ \a b ->
        Component.combine a b === Component.combine b a
    , testProperty "left identity law" $ \a ->
        Component.combine Component.identity a === a
    , testProperty "right identity law" $ \a ->
        Component.combine a Component.identity === a
    , testProperty "left inverse law" $ \a ->
        Component.combine (Component.inverse a) a === Component.identity
    , testProperty "right inverse law" $ \a ->
        Component.combine a (Component.inverse a) === Component.identity
    , testProperty "left distributivity" $ \a b c ->
        Component.multiply a (Component.add b c) === Component.add (Component.multiply a b) (Component.multiply a c)
    , testProperty "right distributivity" $ \a b c ->
        Component.multiply (Component.add a b) c === Component.add (Component.multiply a c) (Component.multiply b c)
    , testProperty "absorption laws" $ \a b ->
        (Component.meet a (Component.join a b) === a) .&&. (Component.join a (Component.meet a b) === a)
    , testProperty "idempotence law" $ \a ->
        Component.operation (Component.operation a) === Component.operation a
    , testProperty "double negation" $ \a ->
        Component.negate (Component.negate a) === a
    , testProperty "de morgan laws" $ \a b ->
        (Component.negate (Component.and a b) === Component.or (Component.negate a) (Component.negate b)) .&&.
        (Component.negate (Component.or a b) === Component.and (Component.negate a) (Component.negate b))
    ]
  , testGroup "transformation properties" -- FROM ANALYSIS: "⚠ Missing transformation properties"
    [ testProperty "transformation idempotence" $ \input ->
        Component.transform (Component.transform input) === Component.transform input
    , testProperty "transformation reversibility" $ \input ->
        isValid input ==> Component.reverse (Component.transform input) === input
    , testProperty "composition associativity" $ \input ->
        Component.transform3 (Component.transform2 (Component.transform1 input)) ===
        (Component.transform3 . Component.transform2 . Component.transform1) input
    , testProperty "composition with identity" $ \input ->
        (Component.identity . Component.transform) input === Component.transform input .&&.
        (Component.transform . Component.identity) input === Component.transform input
    , testProperty "homomorphism property" $ \a b ->
        Component.transform (Component.combine a b) === Component.combine (Component.transform a) (Component.transform b)
    , testProperty "anti-homomorphism property" $ \a b ->
        Component.reverseTransform (Component.combine a b) === Component.combine (Component.reverseTransform b) (Component.reverseTransform a)
    , testProperty "monotonicity property" $ \a b ->
        a <= b ==> Component.transform a <= Component.transform b
    , testProperty "bijection property" $ \input ->
        isValid input ==> Component.inverse (Component.transform input) === input
    , testProperty "structure preservation" $ \input ->
        Component.structure (Component.transform input) === Component.structure input
    , testProperty "cardinality preservation" $ \input ->
        Component.cardinality (Component.transform input) === Component.cardinality input
    ]
  , testGroup "invariant properties" -- FROM ANALYSIS: "⚠ No invariant preservation tests"
    [ testProperty "size preservation" $ \input ->
        length (Component.process input) === length input
    , testProperty "type preservation" $ \input ->
        Component.typeOf (Component.process input) === Component.typeOf input
    , testProperty "constraint preservation" $ \input ->
        isValid input ==> isValid (Component.process input)
    , testProperty "ordering preservation" $ \input ->
        isSorted input ==> isSorted (Component.process input)
    , testProperty "uniqueness preservation" $ \input ->
        isUnique input ==> isUnique (Component.process input)
    , testProperty "balance preservation" $ \tree ->
        isBalanced tree ==> forAll arbitrary $ \item ->
          isBalanced (Component.insert item tree)
    , testProperty "heap property preservation" $ \heap ->
        isHeap heap ==> forAll arbitrary $ \item ->
          isHeap (Component.insertHeap item heap)
    , testProperty "memory safety invariant" $ \input ->
        all isValidPointer (Component.extractPointers (Component.process input))
    , testProperty "resource cleanup invariant" $ \input ->
        Component.resourcesAfter (Component.process input) === Component.resourcesBefore input

    ]
  , testGroup "error handling properties" -- FROM ANALYSIS: "⚠ Missing error handling properties"
    [ testProperty "error preservation" $ \invalidInput ->
        isLeft (Component.validate invalidInput) ==> isLeft (Component.process invalidInput)
    , testProperty "graceful degradation" $ \input ->
        hasRecoverableErrors input ==> isPartialSuccess (Component.process input)
    , testProperty "error propagation" $ \errorInput ->
        containsError errorInput ==> containsError (Component.pipeline errorInput)
    , testProperty "error locality" $ \mixedInput ->
        Component.localErrors (Component.process mixedInput) `isSubsetOf` Component.localErrors mixedInput
    , testProperty "fail-fast behavior" $ \criticalError ->
        isCritical criticalError ==> isFailFast (Component.process criticalError)
    , testProperty "error recovery invariant" $ \input ->
        isRecoverable (Component.process input) ==> canRecover (Component.process input)
    , testProperty "error isolation" $ \input errorInput ->
        Component.isolate errorInput input ==> not (containsError (Component.process input))
    , testProperty "error aggregation" $ \errors ->
        Component.aggregateErrors errors === Component.flattenErrors (map Component.processError errors)
    ]
  , testGroup "concurrency properties" -- FROM ANALYSIS: "⚠ Missing concurrency properties"
    [ testProperty "thread safety" $ \input ->
        monadicIO $ do
          results <- run $ replicateConcurrently 10 (Component.process input)
          assert (all (== head results) results)
    , testProperty "race condition freedom" $ \sharedState ->
        monadicIO $ do
          finalStates <- run $ replicateConcurrently 10 (Component.modifySharedState sharedState)
          assert (isConsistent finalStates)
    , testProperty "deadlock freedom" $ \resources ->
        monadicIO $ do
          result <- run $ timeout 5000000 (Component.acquireResources resources)  -- 5 seconds
          assert (isJust result)
    , testProperty "starvation freedom" $ \resource ->
        monadicIO $ do
          accessTimes <- run $ replicateConcurrently 10 (Component.accessResource resource)
          assert (all (< maxAccessTime) accessTimes)
    , testProperty "atomicity preservation" $ \operation ->
        monadicIO $ do
          intermediateStates <- run $ Component.monitorAtomicOperation operation
          assert (all isConsistentState intermediateStates)
    ]
  , testGroup "performance properties" -- FROM ANALYSIS: "⚠ Missing performance properties"
    [ testProperty "time complexity bound" $ \n ->
        n > 0 && n < 10000 ==> monadicIO $ do
          let input = Component.generateInput n
          duration <- run $ Component.timeExecution (Component.process input)
          assert (duration < fromIntegral n * maxTimePerItem)
    , testProperty "space complexity bound" $ \n ->
        n > 0 && n < 1000 ==> monadicIO $ do
          let input = Component.generateInput n
          memoryUsage <- run $ Component.measureMemoryUsage (Component.process input)
          assert (memoryUsage < maxMemoryPerItem * fromIntegral n)
    , testProperty "cache efficiency" $ \repeatedInput ->
        monadicIO $ do
          time1 <- run $ Component.timeExecution (Component.process repeatedInput)
          time2 <- run $ Component.timeExecution (Component.process repeatedInput)
          assert (time2 <= time1)  -- Second execution should be faster due to caching
    ]
  ]

-- Property test helpers and generators
instance Arbitrary TestInput where
  arbitrary = TestInput
    <$> arbitrary
    <*> arbitrary `suchThat` isValid

instance Arbitrary TestState where
  arbitrary = TestState
    <$> arbitrary `suchThat` isValidState
    <*> arbitrary
    <*> arbitrary

-- Custom property combinators
(===) :: (Eq a, Show a) => a -> a -> Property
x === y = counterexample (show x ++ " /= " ++ show y) (x == y)

-- Performance test constants
maxTimePerItem :: NominalDiffTime
maxTimePerItem = 0.001  -- 1ms per item

maxMemoryPerItem :: Int
maxMemoryPerItem = 1024  -- 1KB per item

maxAccessTime :: NominalDiffTime
maxAccessTime = 1  -- 1 second maximum access time
```

### 6. **Negative Input & Security Test Implementation**

**Comprehensive Attack Vector Testing:**

```haskell
-- PATTERN: Systematic security and negative input testing
-- Generate tests for malicious inputs, attack vectors, and security vulnerabilities

testNegativeInputsAndSecurity :: TestTree
testNegativeInputsAndSecurity = testGroup "negative inputs and security"
  [ testGroup "malicious input detection"
    [ testCase "SQL injection attempt" $
        Component.processInput sqlInjectionPayload @?= Left (SecurityError "SQL injection detected")
    , testCase "script injection attempt" $
        Component.processInput scriptInjectionPayload @?= Left (SecurityError "script injection detected")
    , testCase "XSS attack attempt" $
        Component.processInput xssPayload @?= Left (SecurityError "XSS attack detected")
    , testCase "path traversal attempt" $
        Component.processInput pathTraversalPayload @?= Left (SecurityError "path traversal detected")
    , testCase "buffer overflow attempt" $
        Component.processInput bufferOverflowPayload @?= Left (SecurityError "buffer overflow detected")
    , testCase "format string attack" $
        Component.processInput formatStringPayload @?= Left (SecurityError "format string attack detected")
    , testCase "XML external entity attack" $
        Component.processInput xxePayload @?= Left (SecurityError "XXE attack detected")
    , testCase "deserialization attack" $
        Component.processInput deserializationBombPayload @?= Left (SecurityError "deserialization attack detected")
    , testCase "billion laughs attack" $
        Component.processInput billionLaughsPayload @?= Left (SecurityError "billion laughs attack detected")
    , testCase "zip bomb attack" $
        Component.processInput zipBombPayload @?= Left (SecurityError "zip bomb detected")
    , testCase "LDAP injection attempt" $
        Component.processInput ldapInjectionPayload @?= Left (SecurityError "LDAP injection detected")
    , testCase "NoSQL injection attempt" $
        Component.processInput nosqlInjectionPayload @?= Left (SecurityError "NoSQL injection detected")
    , testCase "command injection attempt" $
        Component.processInput commandInjectionPayload @?= Left (SecurityError "command injection detected")
    , testCase "directory traversal attempt" $
        Component.processInput directoryTraversalPayload @?= Left (SecurityError "directory traversal detected")
    , testCase "timing attack resistance" $
        Component.testTimingAttack @?= True
    ]
  , testGroup "malformed input handling"
    [ testCase "truncated data handling" $
        Component.processInput truncatedDataPayload @?= Left (MalformedError "truncated data")
    , testCase "corrupted header handling" $
        Component.processInput corruptedHeaderPayload @?= Left (MalformedError "corrupted header")
    , testCase "invalid checksum handling" $
        Component.processInput invalidChecksumPayload @?= Left (MalformedError "invalid checksum")
    , testCase "wrong encoding handling" $
        Component.processInput wrongEncodingPayload @?= Left (MalformedError "wrong encoding")
    , testCase "mixed line ending handling" $
        Component.processInput mixedLineEndingPayload @?= Right expectedNormalizedOutput
    , testCase "embedded null byte handling" $
        Component.processInput embeddedNullPayload @?= Left (MalformedError "embedded null bytes")
    , testCase "non-printable character handling" $
        Component.processInput nonPrintablePayload @?= Left (MalformedError "non-printable characters")
    , testCase "incomplete multibyte handling" $
        Component.processInput incompleteMultibytePayload @?= Left (MalformedError "incomplete multibyte sequence")
    , testCase "BOM in wrong position" $
        Component.processInput bomInMiddlePayload @?= Left (MalformedError "BOM in wrong position")
    , testCase "wrong byte order handling" $
        Component.processInput wrongByteOrderPayload @?= Left (MalformedError "wrong byte order")
    , testCase "invalid magic number" $
        Component.processInput wrongMagicNumberPayload @?= Left (MalformedError "invalid magic number")
    , testCase "version mismatch handling" $
        Component.processInput futureVersionPayload @?= Left (MalformedError "unsupported version")
    , testCase "checksum mismatch handling" $
        Component.processInput checksumMismatchPayload @?= Left (MalformedError "checksum mismatch")
    , testCase "size mismatch handling" $
        Component.processInput sizeMismatchPayload @?= Left (MalformedError "size mismatch")
    ]
  , testGroup "boundary violation detection"
    [ testCase "length limit enforcement" $
        Component.processInput tooLongInputPayload @?= Left (BoundaryError "input too long")
    , testCase "minimum length enforcement" $
        Component.processInput tooShortInputPayload @?= Left (BoundaryError "input too short")
    , testCase "depth limit enforcement" $
        Component.processInput tooDeepInputPayload @?= Left (BoundaryError "nesting too deep")
    , testCase "width limit enforcement" $
        Component.processInput tooWideInputPayload @?= Left (BoundaryError "structure too wide")
    , testCase "count limit enforcement" $
        Component.processInput tooManyItemsPayload @?= Left (BoundaryError "too many items")
    , testCase "memory limit enforcement" $
        Component.processInput memoryExceedingPayload @?= Left (BoundaryError "memory limit exceeded")
    , testCase "time limit enforcement" $
        Component.processInput timeExceedingPayload @?= Left (BoundaryError "time limit exceeded")
    , testCase "recursion limit enforcement" $
        Component.processInput recursionExceedingPayload @?= Left (BoundaryError "recursion limit exceeded")
    , testCase "complexity limit enforcement" $
        Component.processInput complexityExceedingPayload @?= Left (BoundaryError "complexity limit exceeded")
    , testCase "precision limit enforcement" $
        Component.processInput precisionExceedingPayload @?= Left (BoundaryError "precision limit exceeded")
    , testCase "scale limit enforcement" $
        Component.processInput scaleExceedingPayload @?= Left (BoundaryError "scale limit exceeded")
    ]
  ]

-- Attack payload generators
sqlInjectionPayload :: TestInput
sqlInjectionPayload = TestInput "'; DROP TABLE users; --"

scriptInjectionPayload :: TestInput
scriptInjectionPayload = TestInput "<script>alert('XSS')</script>"

xssPayload :: TestInput
xssPayload = TestInput "javascript:alert('XSS')"

pathTraversalPayload :: TestInput
pathTraversalPayload = TestInput "../../../etc/passwd"

bufferOverflowPayload :: TestInput
bufferOverflowPayload = TestInput (replicate 100000 'A')

formatStringPayload :: TestInput
formatStringPayload = TestInput "%x%x%x%x%x%x%x%x%x%x%n"

xxePayload :: TestInput
xxePayload = TestInput "<?xml version=\"1.0\"?><!DOCTYPE test [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><test>&xxe;</test>"

deserializationBombPayload :: TestInput
deserializationBombPayload = TestInput "rO0ABXNyABFqYXZhLnV0aWwuSGFzaE1hcAUH2sHDFmDRAwACRgAKbG9hZEZhY3RvckkACXRocmVzaG9sZHhwP0AAAAAAAAx3CAAAABAAAAABdAABYXNyAA5qYXZhLmxhbmcuTG9uZzuL5JDMjyPfAgABSgAFdmFsdWV4cgAQamF2YS5sYW5nLk51bWJlcoaslR0LlOCLAgAAeHAAAAAAAAAAAXg="

billionLaughsPayload :: TestInput
billionLaughsPayload = TestInput "<?xml version=\"1.0\"?><!DOCTYPE lolz [<!ENTITY lol \"lol\"><!ENTITY lol2 \"&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;\"><!ENTITY lol3 \"&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;\">]><lolz>&lol3;</lolz>"

-- Boundary violation test data
tooLongInputPayload :: TestInput
tooLongInputPayload = TestInput (replicate (maxInputLength + 1) 'x')

tooDeepInputPayload :: TestInput
tooDeepInputPayload = TestInput (concat (replicate (maxNestingDepth + 1) "{\"nested\":"))

memoryExceedingPayload :: TestInput
memoryExceedingPayload = TestInput (replicate (maxMemoryUsage + 1) 'M')

-- Limits and constants
maxInputLength :: Int
maxInputLength = 1000000

maxNestingDepth :: Int
maxNestingDepth = 100

maxMemoryUsage :: Int
maxMemoryUsage = 100 * 1024 * 1024  -- 100MB
```

### 7. **Integration & Performance Test Implementation**

**System-Level Testing:**

```haskell
-- PATTERN: Comprehensive integration and performance testing
-- Generate tests for module interactions, external dependencies, and performance

testIntegrationAndPerformance :: TestTree
testIntegrationAndPerformance = testGroup "integration and performance"
  [ testGroup "module integration scenarios"
    [ testCase "complete processing pipeline" $ do
        let rawInput = "test input data"
        result <- runPipeline rawInput
        result @?= Right expectedPipelineOutput
    , testCase "error propagation through pipeline" $ do
        let invalidInput = "invalid input"
        result <- runPipeline invalidInput
        result @?= Left expectedPipelineError
    , testCase "partial failure recovery" $ do
        let partialInput = "partially valid input"
        result <- runPipeline partialInput
        case result of
          Right output -> assertBool "should contain partial results" (isPartialResult output)
          Left _ -> assertFailure "should recover from partial failures"
    , testCase "concurrent pipeline execution" $ do
        let inputs = replicate 10 "concurrent input"
        results <- mapConcurrently runPipeline inputs
        assertBool "all results should be successful" (all isRight results)
    , testCase "pipeline state consistency" $ do
        initialState <- getPipelineState
        _ <- runPipeline "state test input"
        finalState <- getPipelineState
        assertBool "state should remain consistent" (isConsistentState initialState finalState)
    ]
  , testGroup "external dependency integration"
    [ testCase "database integration with connection failure" $ do
        result <- withFailedDatabase $ \db ->
          processWithDatabase db testData
        result @?= Left (ExternalError "database connection failed")
    , testCase "database integration with slow responses" $ do
        result <- withSlowDatabase $ \db ->
          processWithDatabase db testData
        result @?= Left (ExternalError "database timeout")
    , testCase "API integration with service unavailable" $ do
        result <- withUnavailableAPI $ \api ->
          processWithAPI api testData
        result @?= Left (ExternalError "API service unavailable")
    , testCase "file system integration with readonly filesystem" $ do
        result <- withReadOnlyFilesystem $ \fs ->
          processWithFilesystem fs testData
        result @?= Left (ExternalError "filesystem permission denied")
    , testCase "network integration with connection issues" $ do
        result <- withNetworkPartition $ \network ->
          processWithNetwork network testData
        result @?= Left (ExternalError "network partition detected")
    ]
  , testGroup "performance validation"
    [ testCase "memory usage remains within bounds" $ do
        initialMemory <- getCurrentMemoryUsage
        result <- processLargeDataset largeTestDataset
        finalMemory <- getCurrentMemoryUsage
        result @?= Right expectedLargeResult
        let memoryIncrease = finalMemory - initialMemory
        assertBool "memory usage within bounds" (memoryIncrease < maxAllowedMemoryIncrease)
    , testCase "processing time meets requirements" $ do
        start <- getCurrentTime
        result <- processStandardDataset standardTestDataset
        end <- getCurrentTime
        result @?= Right expectedStandardResult
        let duration = diffUTCTime end start
        assertBool "processing time within bounds" (duration < maxAllowedProcessingTime)
    , testCase "memory leak detection over time" $ do
        initialMemory <- getCurrentMemoryUsage
        replicateM_ 1000 $ do
          _ <- processSmallDataset smallTestDataset
          performGC
        finalMemory <- getCurrentMemoryUsage
        let memoryGrowth = finalMemory - initialMemory
        assertBool "no significant memory leaks" (memoryGrowth < maxAllowedMemoryGrowth)
    , testCase "concurrent processing performance" $ do
        start <- getCurrentTime
        results <- replicateConcurrently 10 $ processStandardDataset standardTestDataset
        end <- getCurrentTime
        assertBool "all concurrent processes successful" (all isRight results)
        let duration = diffUTCTime end start
        let sequentialTime = maxAllowedProcessingTime * 10
        assertBool "concurrent processing more efficient" (duration < sequentialTime * 0.8)
    , testCase "resource cleanup verification" $ do
        initialResources <- getCurrentResourceUsage
        result <- processWithManyResources resourceIntensiveDataset
        finalResources <- getCurrentResourceUsage
        result @?= Right expectedResourceIntensiveResult
        finalResources @?= initialResources
    ]
  , testGroup "scalability validation"
    [ testProperty "linear time complexity validation" $ \n ->
        n > 0 && n < 1000 ==> monadicIO $ do
          let input = generateDataset n
          duration <- run $ timeProcessing input
          assert (duration < fromIntegral n * maxTimePerItem)
    , testProperty "constant space complexity validation" $ \n ->
        n > 0 && n < 1000 ==> monadicIO $ do
          let input = generateDataset n
          memoryUsage <- run $ measureProcessingMemory input
          assert (memoryUsage < maxConstantMemory)
    , testProperty "throughput scaling validation" $ \concurrency ->
        concurrency > 0 && concurrency < 100 ==> monadicIO $ do
          start <- run getCurrentTime
          results <- run $ replicateConcurrently concurrency (processStandardDataset standardTestDataset)
          end <- run getCurrentTime
          let duration = diffUTCTime end start
          let throughput = fromIntegral concurrency / realToFrac duration
          assert (all isRight results)
          assert (throughput > minRequiredThroughput)
    ]
  ]

-- Integration test helpers
runPipeline :: Text -> IO (Either PipelineError PipelineOutput)
runPipeline input = runExceptT $ do
  parsed <- ExceptT $ return $ parseInput input
  validated <- ExceptT $ return $ validateInput parsed
  processed <- ExceptT $ return $ processInput validated
  ExceptT $ return $ generateOutput processed

withFailedDatabase :: (Database -> IO a) -> IO a
withFailedDatabase action = do
  db <- createFailingDatabase
  result <- action db
  closeDatabase db
  return result

withSlowDatabase :: (Database -> IO a) -> IO a
withSlowDatabase action = do
  db <- createSlowDatabase 10000  -- 10 second delay
  result <- timeout 5000000 (action db)  -- 5 second timeout
  closeDatabase db
  case result of
    Nothing -> return $ error "database timeout"
    Just r -> return r

-- Performance test data
largeTestDataset :: TestDataset
largeTestDataset = TestDataset (replicate 1000000 testItem)

standardTestDataset :: TestDataset
standardTestDataset = TestDataset (replicate 1000 testItem)

smallTestDataset :: TestDataset
smallTestDataset = TestDataset (replicate 10 testItem)

resourceIntensiveDataset :: TestDataset
resourceIntensiveDataset = TestDataset (replicate 100 resourceIntensiveItem)

-- Performance constraints
maxAllowedMemoryIncrease :: Int
maxAllowedMemoryIncrease = 100 * 1024 * 1024  -- 100MB

maxAllowedProcessingTime :: NominalDiffTime
maxAllowedProcessingTime = 5  -- 5 seconds

maxAllowedMemoryGrowth :: Int
maxAllowedMemoryGrowth = 10 * 1024 * 1024  -- 10MB over 1000 iterations

maxConstantMemory :: Int
maxConstantMemory = 50 * 1024 * 1024  -- 50MB regardless of input size

minRequiredThroughput :: Double
minRequiredThroughput = 100  -- 100 operations per second
```

---

## Complete Test File Generation

### **Enhanced Test Module Structure**

```haskell
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

-- | Comprehensive test suite for [ModuleName]
--
-- This test module provides complete coverage for all functionality in
-- the [ModuleName] module, including:
--
-- * Function coverage for all public API functions with edge cases
-- * Comprehensive error path validation for all failure modes
-- * Property-based testing for algebraic laws and invariants
-- * Integration testing for module interactions and external dependencies
-- * Performance validation for resource usage and scalability
-- * Security testing for attack vectors and vulnerability detection
-- * Negative input testing for malicious and malformed input handling
--
-- The test suite follows CLAUDE.md testing guidelines and achieves
-- comprehensive coverage through systematic test generation based on
-- gap analysis results.
--
-- @since 0.19.1
module Test.Unit.ModuleName.ComponentTest
  ( tests
  ) where

-- Standard testing imports
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertFailure, assertBool)
import Test.Tasty.QuickCheck (testProperty, (==>), (.&&.), Property, monadicIO, run, assert)
import Test.Tasty.Golden (goldenVsString)

-- Testing utilities
import Control.Exception (bracket, timeout, evaluate)
import Control.Concurrent.Async (mapConcurrently, replicateConcurrently)
import Control.Monad.Except (runExceptT, ExceptT(..))
import Data.Time (getCurrentTime, diffUTCTime, NominalDiffTime)
import System.IO.Temp (withTempDirectory)
import System.Mem (performGC)

-- Module under test (types unqualified, functions qualified)
import ModuleName.Component
  ( Config (..)
  , Input (..)
  , Output (..)
  , Error (..)
  , TestInput (..)
  , TestOutput (..)
  )
import qualified ModuleName.Component as Component

-- Related modules for integration testing
import qualified ModuleName.Environment as Environment
import qualified ModuleName.Parser as Parser
import qualified ModuleName.Validation as Validation

-- | Complete test suite for ModuleName.Component
--
-- Provides comprehensive coverage including function tests, edge cases,
-- error paths, properties, integration scenarios, performance validation,
-- security testing, and negative input handling.
tests :: TestTree
tests = testGroup "ModuleName.Component"
  [ testFunctionCoverage
  , testComprehensiveEdgeCases
  , testComprehensiveErrorPaths
  , testComprehensiveProperties
  , testIntegrationAndPerformance
  , testNegativeInputsAndSecurity
  ]

-- | Test coverage for all public functions
--
-- Ensures every exported function has comprehensive test coverage
-- with valid inputs, invalid inputs, boundary conditions, and error scenarios.
testFunctionCoverage :: TestTree
testFunctionCoverage = testGroup "function coverage"
  [ testParseConfig
  , testValidateInput
  , testProcessData
  , testGenerateOutput
  , testTransformData
  ]

-- [Individual test implementations follow the patterns above...]
```

### **Test Data Management & Utilities**

```haskell
-- | Comprehensive test data and utilities for systematic testing
--
-- Provides reusable test data, generators, and utility functions
-- for consistent testing across all test categories.

-- Valid test data for happy path testing
validConfig :: Config
validConfig = Config
  { configName = "test-config"
  , configVersion = Version 1 0 0
  , configDescription = Just "Test configuration"
  , configDependencies = ["dep1", "dep2"]
  , configFlags = defaultFlags
  }

validInput :: Input
validInput = Input
  { inputData = "valid test data"
  , inputMetadata = Map.fromList [("key", "value")]
  , inputTimestamp = testTimestamp
  }

-- Edge case test data
edgeCaseInputs :: [(String, Input, Either Error Output)]
edgeCaseInputs =
  [ ("empty data", validInput { inputData = "" }, Right expectedEmptyOutput)
  , ("unicode data", validInput { inputData = "αβγδε" }, Right expectedUnicodeOutput)
  , ("large data", validInput { inputData = largeTestData }, Right expectedLargeOutput)
  , ("null character", validInput { inputData = "\0" }, Right expectedNullCharOutput)
  , ("control chars", validInput { inputData = "\x01\x02\x03" }, Right expectedControlCharsOutput)
  ]

-- Error test data with expected errors
errorInputs :: [(String, Input, Error)]
errorInputs =
  [ ("null input", emptyInput, ValidationError "null input")
  , ("malformed input", malformedInput, ValidationError "malformed structure")
  , ("out of range", outOfRangeInput, ValidationError "value out of range")
  , ("security violation", securityViolatingInput, SecurityError "security policy violation")
  ]

-- Attack vector test data
attackVectors :: [(String, TestInput, Error)]
attackVectors =
  [ ("SQL injection", sqlInjectionInput, SecurityError "SQL injection detected")
  , ("XSS attack", xssInput, SecurityError "XSS attack detected")
  , ("path traversal", pathTraversalInput, SecurityError "path traversal detected")
  , ("buffer overflow", bufferOverflowInput, SecurityError "buffer overflow detected")
  ]

-- Performance test data
performanceTestData :: [(String, TestDataset, NominalDiffTime)]
performanceTestData =
  [ ("small dataset", smallDataset, 0.1)
  , ("medium dataset", mediumDataset, 1.0)
  , ("large dataset", largeDataset, 5.0)
  ]

-- Property test generators
instance Arbitrary Config where
  arbitrary = Config
    <$> arbitrary `suchThat` (not . null)
    <*> arbitrary
    <*> arbitrary
    <*> listOf arbitrary
    <*> arbitrary

instance Arbitrary Input where
  arbitrary = Input
    <$> arbitrary `suchThat` isValidInputData
    <*> arbitrary
    <*> arbitrary

-- Custom generators for edge cases
genEdgeCaseInput :: Gen Input
genEdgeCaseInput = oneof
  [ return (validInput { inputData = "" })  -- empty
  , return (validInput { inputData = "\0" })  -- null char
  , return (validInput { inputData = replicate 100000 'x' })  -- very long
  , return (validInput { inputData = "αβγδε" })  -- unicode
  ]

genMaliciousInput :: Gen TestInput
genMaliciousInput = oneof
  [ return sqlInjectionInput
  , return xssInput
  , return pathTraversalInput
  , return bufferOverflowInput
  ]

-- Test utilities and helpers
testTimestamp :: UTCTime
testTimestamp = UTCTime (fromGregorian 2024 1 1) 0

largeTestData :: String
largeTestData = concat $ replicate 10000 "test data "

-- Resource monitoring utilities
getCurrentMemoryUsage :: IO Int
getCurrentMemoryUsage = do
  stats <- getGCStats
  return (fromIntegral $ bytesAllocated stats)

getCurrentResourceUsage :: IO ResourceUsage
getCurrentResourceUsage = ResourceUsage
  <$> getCurrentMemoryUsage
  <*> getCurrentFileDescriptors
  <*> getCurrentThreadCount

timeExecution :: IO a -> IO NominalDiffTime
timeExecution action = do
  start <- getCurrentTime
  _ <- action
  end <- getCurrentTime
  return (diffUTCTime end start)

-- Custom assertions for comprehensive testing
shouldSatisfy :: (Show a) => a -> (a -> Bool) -> IO ()
shouldSatisfy actual predicate
  | predicate actual = return ()
  | otherwise = assertFailure $ "Expected " ++ show actual ++ " to satisfy predicate"

shouldBeWithinBounds :: (Ord a, Show a) => a -> a -> a -> IO ()
shouldBeWithinBounds actual lower upper
  | actual >= lower && actual <= upper = return ()
  | otherwise = assertFailure $ show actual ++ " not within bounds [" ++ show lower ++ ", " ++ show upper ++ "]"

-- Security testing utilities
detectSecurityViolation :: TestInput -> IO (Either SecurityError TestOutput)
detectSecurityViolation input = do
  result <- tryProcessInput input
  case result of
    Left (SecurityError _) -> return (Left (SecurityError "security violation detected"))
    Left other -> return (Left (SecurityError ("unexpected error: " ++ show other)))
    Right output -> return (Right output)

-- Performance testing utilities
measureMemoryUsage :: IO a -> IO Int
measureMemoryUsage action = do
  performGC
  initialStats <- getGCStats
  _ <- action
  performGC
  finalStats <- getGCStats
  return (fromIntegral $ bytesAllocated finalStats - bytesAllocated initialStats)

-- Integration testing utilities
withTestEnvironment :: (Environment -> IO a) -> IO a
withTestEnvironment action = bracket
  setupTestEnvironment
  teardownTestEnvironment
  action

withMockExternalService :: (ServiceConfig -> IO a) -> IO a
withMockExternalService action = bracket
  startMockService
  stopMockService
  action

-- Error classification utilities
isRecoverableError :: Error -> Bool
isRecoverableError (ValidationError _) = True
isRecoverableError (SecurityError _) = False
isRecoverableError _ = True

isCriticalError :: Error -> Bool
isCriticalError (SecurityError _) = True
isCriticalError (SystemError _) = True
isCriticalError _ = False

-- Property test utilities
isConsistentState :: [State] -> Bool
isConsistentState states = all isValidState states && allEqual (map stateChecksum states)

allEqual :: Eq a => [a] -> Bool
allEqual [] = True
allEqual (x:xs) = all (== x) xs

-- Constants and limits
maxTestDataSize :: Int
maxTestDataSize = 1000000

maxTestExecutionTime :: NominalDiffTime
maxTestExecutionTime = 10  -- 10 seconds

maxMemoryUsageIncrease :: Int
maxMemoryUsageIncrease = 100 * 1024 * 1024  -- 100MB
```

---

## Test Implementation Checklist

### **Critical Implementation Requirements:**

- [ ] All untested public functions have comprehensive test coverage
- [ ] All identified edge cases implemented with proper test data
- [ ] All error paths tested with specific error type validation
- [ ] Property tests verify algebraic laws and invariants
- [ ] Integration tests cover module interaction scenarios
- [ ] Performance tests validate resource usage and timing
- [ ] Security tests cover attack vectors and vulnerabilities
- [ ] Negative input tests handle malicious and malformed data

### **Quality Standards:**

- [ ] Test documentation explains purpose and approach
- [ ] Test data is realistic and comprehensive
- [ ] Error messages are descriptive and actionable
- [ ] Test organization follows module structure
- [ ] All tests pass consistently and deterministically
- [ ] Test utilities are reusable and well-documented

### **Coverage Validation:**

- [ ] Function coverage ≥95% for all public functions
- [ ] Edge case coverage includes all boundary conditions
- [ ] Error path coverage includes all failure modes
- [ ] Property coverage verifies all stated laws
- [ ] Integration coverage tests all module interactions
- [ ] Security coverage tests all attack vectors
- [ ] Performance coverage validates all resource constraints

### **Implementation Excellence:**

- [ ] Generated tests follow existing test style and patterns
- [ ] Test utilities are reusable and well-documented
- [ ] Performance tests have realistic constraints
- [ ] Concurrent tests are reliable and race-condition free
- [ ] Security tests cover comprehensive attack scenarios
- [ ] All tests integrate properly with build system

---

## Reference Implementation Examples

**Exemplar Generated Test Patterns:**

- Complete function coverage with comprehensive test data
- Systematic edge case testing with boundary value analysis
- Robust error path testing with specific error validation
- Property-based testing with custom generators and properties
- Integration testing with realistic module interaction scenarios
- Performance testing with proper resource measurement and constraints
- Security testing with comprehensive attack vector coverage
- Negative input testing with malicious and malformed data handling

**Integration with Existing Tests:**

- Preserves all current test structure and organization
- Extends existing test groups with missing coverage
- Maintains consistent naming and documentation patterns
- Integrates seamlessly with current test data and utilities
- Follows established error handling and assertion patterns
- Enhances security testing without disrupting existing tests
