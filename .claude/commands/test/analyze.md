# Test Analysis Prompt — Canopy Compiler Test Coverage & Edge Case Detection (Non-Negotiable)

**Task:**
Please analyze the test files for module: `$ARGUMENTS`.

- **Target**: Test file analysis with automatic source module inference for comprehensive coverage
- **Standards**: Follow **CLAUDE.md testing guidelines** exactly - all rules are **non-negotiable**
- **Quality**: Identify ALL missing edge cases, test gaps, and coverage holes
- **Architecture**: Apply systematic test analysis patterns from exemplar test modules

---

## Test Analysis Strategy & Methodology

### Comprehensive Test Coverage Analysis

### Automatic Source Module Inference

**Test File to Source Module Mapping:**

```haskell
-- Automatic inference patterns:
test/Unit/Make/ParserTest.hs        -> src/Make/Parser.hs
test/Unit/Publish/EnvironmentTest.hs -> src/Publish/Environment.hs
test/Property/Data/NameProps.hs     -> src/Data/Name.hs
test/Golden/JsGenGolden.hs          -> src/JsGen.hs
test/Integration/Make/BuildTest.hs  -> src/Make.hs (+ sub-modules)
```

**Source Module Discovery Process:**

1. **Parse test file path**: Extract module path from test file location
2. **Map to source structure**: Convert test path to corresponding source module
3. **Identify target modules**: Find primary module and related sub-modules
4. **Load module exports**: Parse public API from source files
5. **Cross-reference coverage**: Compare exports against test coverage

**Coverage Categories:**

```
Test Analysis Framework:
├── Function Coverage      -- Every public function tested
├── Edge Case Coverage     -- Boundary conditions and limits
├── Error Path Coverage    -- All failure modes tested
├── Property Coverage      -- Laws and invariants verified
├── Integration Coverage   -- Module interaction patterns
└── Performance Coverage   -- Resource usage and limits
```

---

## Systematic Test Gap Analysis

### 1. **Function Coverage Audit**

**Public API Mapping:**

```haskell
-- ANALYSIS PATTERN: Map all public exports to test coverage
module ModuleName exports:
  ✓ function1 -> Test.Unit.ModuleName.function1Tests
  ✗ function2 -> MISSING: No test coverage found
  ⚠ function3 -> PARTIAL: Only happy path tested
  ✓ Type (..) -> Test.Unit.ModuleName.typeTests
```

**Missing Function Tests Detection:**

- Scan source module exports vs. test module coverage
- Identify untested public functions
- Flag functions with only partial coverage
- Verify all data constructors are tested

### 2. **Critical Edge Case Systematic Analysis**

**Boundary Condition Categories:**

❌ **Numeric Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING NUMERIC EDGE CASE TESTS to identify:
testNumericBoundaries = testGroup "numeric boundaries"
  [ testCase "zero value" $ processValue 0 @?= expectedZero
  , testCase "negative zero" $ processValue (-0) @?= expectedNegativeZero
  , testCase "positive one" $ processValue 1 @?= expectedOne
  , testCase "negative one" $ processValue (-1) @?= expectedNegativeOne
  , testCase "maximum integer" $ processValue maxBound @?= expectedMaxInt
  , testCase "minimum integer" $ processValue minBound @?= expectedMinInt
  , testCase "maximum safe integer" $ processValue 9007199254740991 @?= expectedMaxSafe
  , testCase "overflow boundary" $ processValue 9007199254740992 @?= Left OverflowError
  , testCase "small positive float" $ processFloat 0.0001 @?= expectedSmallFloat
  , testCase "small negative float" $ processFloat (-0.0001) @?= expectedSmallNegFloat
  , testCase "denormalized float" $ processFloat 1e-324 @?= expectedDenormalized
  , testCase "infinity handling" $ processFloat (1/0) @?= Left InfinityError
  , testCase "negative infinity" $ processFloat (-1/0) @?= Left NegInfinityError
  , testCase "NaN handling" $ processFloat (0/0) @?= Left NaNError
  , testCase "underflow to zero" $ processFloat 1e-400 @?= expectedUnderflow
  ]
```

❌ **String/Text Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING TEXT EDGE CASE TESTS to identify:
testTextBoundaries = testGroup "text boundaries"
  [ testCase "empty string" $ parseText "" @?= expectedEmpty
  , testCase "single space" $ parseText " " @?= expectedSingleSpace
  , testCase "only whitespace" $ parseText "   \t\n\r  " @?= expectedWhitespace
  , testCase "single character" $ parseText "a" @?= expectedSingleChar
  , testCase "single unicode" $ parseText "α" @?= expectedSingleUnicode
  , testCase "null character" $ parseText "\0" @?= expectedNullChar
  , testCase "control characters" $ parseText "\x01\x02\x03" @?= expectedControlChars
  , testCase "unicode BOM" $ parseText "\xFEFF" @?= expectedBOM
  , testCase "unicode normalization" $ parseText "é" @?= expectedNormalized  -- e + ´
  , testCase "emoji sequences" $ parseText "👨‍👩‍👧‍👦" @?= expectedEmojiSequence
  , testCase "right-to-left text" $ parseText "العربية" @?= expectedRTL
  , testCase "mixed text direction" $ parseText "Hello العربية World" @?= expectedMixedDir
  , testCase "special characters" $ parseText "!@#$%^&*()[]{}|\\:;\"'<>,.?/" @?= expectedSpecial
  , testCase "very long string" $ parseText (replicate 100000 'a') @?= expectedVeryLong
  , testCase "maximum unicode" $ parseText "\x10FFFF" @?= expectedMaxUnicode
  , testCase "invalid UTF-8" $ parseInvalidUTF8 "\xFF\xFE" @?= Left UTF8Error
  , testCase "truncated multibyte" $ parseText "α\x80" @?= Left TruncatedError
  , testCase "overlong encoding" $ parseText "\xC0\x80" @?= Left OverlongError
  , testCase "surrogate pairs" $ parseText "\xD800\xDC00" @?= expectedSurrogate
  ]
```

❌ **Collection Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING COLLECTION EDGE CASE TESTS to identify:
testCollectionBoundaries = testGroup "collection boundaries"
  [ testCase "empty list" $ processList [] @?= expectedEmptyList
  , testCase "single element" $ processList [item] @?= expectedSingleList
  , testCase "two elements" $ processList [item1, item2] @?= expectedTwoList
  , testCase "very large list" $ processList (replicate 1000000 item) @?= expectedLargeList
  , testCase "nested empty" $ processNested [[]] @?= expectedNestedEmpty
  , testCase "deeply nested" $ processNested (replicate 1000 [item]) @?= expectedDeeplyNested
  , testCase "circular references" $ processCircular circularList @?= Left CircularError
  , testCase "empty map" $ processMap Map.empty @?= expectedEmptyMap
  , testCase "single entry map" $ processMap (Map.singleton key value) @?= expectedSingleMap
  , testCase "duplicate keys" $ processMap duplicateKeyMap @?= Left DuplicateKeyError
  , testCase "null keys" $ processMap (Map.singleton Nothing value) @?= Left NullKeyError
  , testCase "empty string keys" $ processMap (Map.singleton "" value) @?= expectedEmptyKeyMap
  , testCase "unicode keys" $ processMap (Map.singleton "αβγ" value) @?= expectedUnicodeKeyMap
  , testCase "very large map" $ processMap (Map.fromList largeKVPairs) @?= expectedLargeMap
  , testCase "empty set" $ processSet Set.empty @?= expectedEmptySet
  , testCase "single element set" $ processSet (Set.singleton item) @?= expectedSingleSet
  , testCase "maximum size" $ processMaxSize maxSizeCollection @?= expectedMaxSize
  , testCase "exceed maximum" $ processMaxSize oversizeCollection @?= Left SizeExceededError
  , testCase "memory exhaustion" $ processHugeCollection hugeCollection @?= Left OutOfMemoryError
  ]
```

❌ **File System Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING FILE SYSTEM EDGE CASE TESTS to identify:
testFileSystemBoundaries = testGroup "file system boundaries"
  [ testCase "nonexistent file" $ readFile "nonexistent.txt" @?= Left FileNotFoundError
  , testCase "empty file" $ readFile "empty.txt" @?= Right ""
  , testCase "unreadable file" $ readFile "/root/secret.txt" @?= Left PermissionDeniedError
  , testCase "directory as file" $ readFile "directory/" @?= Left IsDirectoryError
  , testCase "device file" $ readFile "/dev/null" @?= Right ""
  , testCase "pipe file" $ readFile "/proc/self/fd/0" @?= Left PipeError
  , testCase "very long filename" $ readFile (replicate 1000 'a') @?= Left FilenameTooLongError
  , testCase "invalid filename chars" $ readFile "file\0name" @?= Left InvalidFilenameError
  , testCase "path traversal" $ readFile "../../../etc/passwd" @?= Left PathTraversalError
  , testCase "absolute path" $ readFile "/etc/passwd" @?= Left AbsolutePathError
  , testCase "broken symlink" $ readFile "broken-symlink" @?= Left SymlinkError
  , testCase "circular symlink" $ readFile "circular-symlink" @?= Left CircularSymlinkError
  , testCase "nonexistent directory" $ readFile "missing/file.txt" @?= Left DirectoryNotFoundError
  , testCase "file during deletion" $ testFileUnderDeletion @?= Left FileDeletedError
  , testCase "concurrent access" $ testConcurrentFileAccess @?= expectedConcurrentResult
  , testCase "locked file" $ readLockedFile @?= Left FileLockError
  , testCase "disk full" $ writeToFullDisk largeData @?= Left DiskFullError
  , testCase "unicode filename" $ readFile "αβγ.txt" @?= expectedUnicodeFilename
  , testCase "case sensitivity" $ testCaseSensitiveFiles @?= expectedCaseSensitive
  ]
```

❌ **Parser Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING PARSER EDGE CASE TESTS to identify:
testParserBoundaries = testGroup "parser boundaries"
  [ testCase "empty input" $ parse "" @?= Left EmptyInputError
  , testCase "single token" $ parse "token" @?= expectedSingleToken
  , testCase "whitespace only" $ parse "   " @?= Left WhitespaceOnlyError
  , testCase "comments only" $ parse "-- comment" @?= Left CommentsOnlyError
  , testCase "unterminated string" $ parse "\"unterminated" @?= Left UnterminatedStringError
  , testCase "unterminated comment" $ parse "/* unterminated" @?= Left UnterminatedCommentError
  , testCase "nested comments" $ parse "/* outer /* inner */ */" @?= expectedNestedComments
  , testCase "escaped quotes" $ parse "\"\\\"quoted\\\"\"" @?= expectedEscapedQuotes
  , testCase "invalid escape" $ parse "\"\\x\"" @?= Left InvalidEscapeError
  , testCase "unicode in string" $ parse "\"αβγ\"" @?= expectedUnicodeString
  , testCase "very deep nesting" $ parse (replicate 1000 "(") @?= Left NestingTooDeepError
  , testCase "unexpected EOF" $ parse "if (true" @?= Left UnexpectedEOFError
  , testCase "invalid characters" $ parse "\x01\x02" @?= Left InvalidCharacterError
  , testCase "very long identifier" $ parse (replicate 10000 'a') @?= Left IdentifierTooLongError
  , testCase "reserved keywords" $ parse "class interface" @?= Left ReservedKeywordError
  , testCase "ambiguous grammar" $ parse ambiguousInput @?= Left AmbiguousGrammarError
  , testCase "left recursion" $ parseLeftRecursive leftRecursiveInput @?= expectedLeftRecursion
  , testCase "operator precedence" $ parse "1 + 2 * 3" @?= expectedPrecedence
  , testCase "right associativity" $ parse "1 :: 2 :: 3" @?= expectedRightAssoc
  , testCase "mixed operators" $ parse "a + b * c - d / e" @?= expectedMixedOps
  , testCase "parentheses precedence" $ parse "(1 + 2) * 3" @?= expectedParenPrecedence
  ]
```

❌ **Network/IO Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING NETWORK/IO EDGE CASE TESTS to identify:
testNetworkBoundaries = testGroup "network/IO boundaries"
  [ testCase "invalid URL" $ fetchURL "not-a-url" @?= Left InvalidURLError
  , testCase "nonexistent host" $ fetchURL "http://nonexistent.invalid" @?= Left HostNotFoundError
  , testCase "connection refused" $ fetchURL "http://localhost:9999" @?= Left ConnectionRefusedError
  , testCase "connection timeout" $ fetchURL "http://httpbin.org/delay/30" @?= Left TimeoutError
  , testCase "DNS timeout" $ fetchURL "http://slow-dns.invalid" @?= Left DNSTimeoutError
  , testCase "empty response" $ fetchURL "http://httpbin.org/status/204" @?= Right ""
  , testCase "huge response" $ fetchURL hugeResponseUrl @?= Left ResponseTooLargeError
  , testCase "invalid SSL cert" $ fetchURL "https://self-signed.invalid" @?= Left SSLError
  , testCase "expired SSL cert" $ fetchURL "https://expired.invalid" @?= Left SSLExpiredError
  , testCase "redirect loop" $ fetchURL "http://httpbin.org/redirect/20" @?= Left RedirectLoopError
  , testCase "too many redirects" $ fetchURL tooManyRedirectsUrl @?= Left TooManyRedirectsError
  , testCase "malformed HTTP" $ fetchURL malformedResponseUrl @?= Left MalformedResponseError
  , testCase "interrupted transfer" $ interruptedFetch url @?= Left TransferInterruptedError
  , testCase "partial content" $ fetchPartial url @?= expectedPartialContent
  , testCase "proxy auth required" $ fetchThroughProxy url @?= Left ProxyAuthError
  , testCase "rate limiting" $ rapidFetch url @?= Left RateLimitError
  , testCase "service unavailable" $ fetchFromDownService url @?= Left ServiceUnavailableError
  ]
```

❌ **Memory/Resource Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING RESOURCE EDGE CASE TESTS to identify:
testResourceBoundaries = testGroup "resource boundaries"
  [ testCase "memory exhaustion" $ processHugeData hugeDataset @?= Left OutOfMemoryError
  , testCase "stack overflow" $ deepRecursion 100000 @?= Left StackOverflowError
  , testCase "heap exhaustion" $ allocateHugeStructure @?= Left HeapExhaustionError
  , testCase "file descriptor limit" $ openManyFiles @?= Left TooManyFilesError
  , testCase "thread limit" $ spawnManyThreads @?= Left TooManyThreadsError
  , testCase "process limit" $ forkManyProcesses @?= Left TooManyProcessesError
  , testCase "disk space full" $ writeHugeFile @?= Left DiskFullError
  , testCase "inode exhaustion" $ createManyFiles @?= Left InodeExhaustionError
  , testCase "CPU time limit" $ infiniteLoop @?= Left CPUTimeLimitError
  , testCase "wall clock limit" $ longRunningTask @?= Left WallClockTimeoutError
  , testCase "memory leak detection" $ detectMemoryLeak @?= expectedNoLeak
  , testCase "resource cleanup" $ testResourceCleanup @?= expectedCleanup
  , testCase "resource contention" $ testResourceContention @?= expectedFairAccess
  , testCase "resource starvation" $ testResourceStarvation @?= Left ResourceStarvationError
  , testCase "deadlock detection" $ testDeadlock @?= Left DeadlockError
  , testCase "livelock detection" $ testLivelock @?= Left LivelockError
  ]
```

❌ **Concurrency Boundaries (MUST TEST ALL)**:

```haskell
-- MISSING CONCURRENCY EDGE CASE TESTS to identify:
testConcurrencyBoundaries = testGroup "concurrency boundaries"
  [ testCase "race condition" $ testRaceCondition @?= expectedDeterministic
  , testCase "data race" $ testDataRace @?= expectedDataRaceFree
  , testCase "thread safety" $ testThreadSafety @?= expectedThreadSafe
  , testCase "deadlock prevention" $ testDeadlockPrevention @?= expectedNoDeadlock
  , testCase "livelock prevention" $ testLivelockPrevention @?= expectedNoLivelock
  , testCase "starvation prevention" $ testStarvationPrevention @?= expectedFairness
  , testCase "resource contention" $ testResourceContention @?= expectedFairAccess
  , testCase "thread interruption" $ testThreadInterruption @?= expectedGracefulStop
  , testCase "exception propagation" $ testExceptionPropagation @?= expectedExceptionHandling
  , testCase "atomic operations" $ testAtomicity @?= expectedAtomic
  , testCase "memory ordering" $ testMemoryOrdering @?= expectedConsistentOrdering
  , testCase "lock-free safety" $ testLockFree @?= expectedLockFreeSafe
  , testCase "wait-free safety" $ testWaitFree @?= expectedWaitFreeSafe
  , testCase "load balancing" $ testLoadBalancing @?= expectedBalancedLoad
  , testCase "backpressure handling" $ testBackpressure @?= expectedBackpressureHandling
  , testCase "circuit breaker" $ testCircuitBreaker @?= expectedCircuitBreakerTrip
  ]
```

### 3. **Comprehensive Error Path Coverage Analysis**

**Error Scenario Mapping:**

❌ **Input Validation Errors (MUST TEST ALL)**:

```haskell
-- MISSING INPUT VALIDATION ERROR TESTS to identify:
testInputValidationErrors = testGroup "input validation errors"
  [ testCase "null input" $ validateInput Nothing @?= Left NullInputError
  , testCase "undefined input" $ validateInput undefined @?= Left UndefinedInputError
  , testCase "wrong type" $ validateInput wrongTypeInput @?= Left TypeMismatchError
  , testCase "out of range" $ validateInput outOfRangeInput @?= Left RangeError
  , testCase "negative where positive expected" $ validateInput negativeInput @?= Left NegativeValueError
  , testCase "zero where positive expected" $ validateInput zeroInput @?= Left ZeroValueError
  , testCase "invalid format" $ validateInput invalidFormatInput @?= Left FormatError
  , testCase "malformed structure" $ validateInput malformedInput @?= Left StructureError
  , testCase "missing required fields" $ validateInput missingFields @?= Left MissingFieldError
  , testCase "extra unexpected fields" $ validateInput extraFields @?= Left UnexpectedFieldError
  , testCase "readonly field modification" $ validateInput readonlyModification @?= Left ReadonlyFieldError
  , testCase "circular references" $ validateInput circularRef @?= Left CircularReferenceError
  , testCase "constraint violations" $ validateInput violatingInput @?= Left ConstraintViolationError
  , testCase "security violations" $ validateInput securityViolation @?= Left SecurityViolationError
  , testCase "encoding errors" $ validateInput invalidEncoding @?= Left EncodingError
  , testCase "checksum failures" $ validateInput corruptedChecksum @?= Left ChecksumError
  ]
```

❌ **State Corruption Errors (MUST TEST ALL)**:

```haskell
-- MISSING STATE CORRUPTION ERROR TESTS to identify:
testStateCorruptionErrors = testGroup "state corruption errors"
  [ testCase "invalid state transition" $ transitionState invalidTransition @?= Left InvalidTransitionError
  , testCase "state inconsistency" $ checkStateConsistency inconsistentState @?= Left InconsistentStateError
  , testCase "corrupted internal data" $ processCorruptedData corruptedData @?= Left DataCorruptionError
  , testCase "version mismatch" $ loadState newerVersionState @?= Left VersionMismatchError
  , testCase "schema mismatch" $ loadState schemaMismatchState @?= Left SchemaMismatchError
  , testCase "checksum failure" $ validateChecksum corruptedChecksum @?= Left ChecksumError
  , testCase "magic number wrong" $ validateMagicNumber wrongMagicState @?= Left MagicNumberError
  , testCase "invariant violation" $ checkInvariants violatingState @?= Left InvariantViolationError
  , testCase "state rollback failure" $ rollbackState failingRollback @?= Left RollbackError
  , testCase "concurrent modification" $ detectConcurrentMod concurrentState @?= Left ConcurrentModificationError
  , testCase "stale state access" $ accessStaleState staleState @?= Left StaleStateError
  , testCase "state lock timeout" $ lockState timeoutState @?= Left StateLockTimeoutError
  ]
```

❌ **External Dependency Errors (MUST TEST ALL)**:

```haskell
-- MISSING EXTERNAL DEPENDENCY ERROR TESTS to identify:
testExternalDependencyErrors = testGroup "external dependency errors"
  [ testCase "service unavailable" $ callService unavailableService @?= Left ServiceUnavailableError
  , testCase "service degraded" $ callDegradedService @?= Left ServiceDegradedError
  , testCase "authentication failure" $ authenticate invalidCredentials @?= Left AuthenticationError
  , testCase "authorization denied" $ authorize insufficientPermissions @?= Left AuthorizationError
  , testCase "token expired" $ callWithExpiredToken @?= Left TokenExpiredError
  , testCase "API version incompatible" $ callAPI incompatibleVersion @?= Left APIVersionError
  , testCase "rate limit exceeded" $ makeRapidCalls @?= Left RateLimitExceededError
  , testCase "quota exceeded" $ exceedQuota @?= Left QuotaExceededError
  , testCase "circuit breaker open" $ callThroughCircuitBreaker @?= Left CircuitBreakerOpenError
  , testCase "external timeout" $ callSlowService @?= Left ExternalTimeoutError
  , testCase "malformed response" $ processMalformedResponse @?= Left MalformedResponseError
  , testCase "partial response" $ processPartialResponse @?= Left PartialResponseError
  , testCase "protocol violation" $ testProtocolViolation @?= Left ProtocolViolationError
  , testCase "encryption failure" $ encryptData corruptedKey @?= Left EncryptionError
  , testCase "decryption failure" $ decryptData corruptedCiphertext @?= Left DecryptionError
  , testCase "certificate validation" $ validateCertificate expiredCert @?= Left CertificateError
  ]
```

### 4. **Property-Based Test Gap Analysis**

**Missing Property Categories:**

❌ **Algebraic Properties (MUST TEST ALL)**:

```haskell
-- MISSING ALGEBRAIC PROPERTY TESTS to identify:
testAlgebraicProperties = testGroup "algebraic properties"
  [ testProperty "associativity" $ \a b c ->
      combine (combine a b) c === combine a (combine b c)
  , testProperty "commutativity" $ \a b ->
      combine a b === combine b a
  , testProperty "identity left" $ \a ->
      combine identity a === a
  , testProperty "identity right" $ \a ->
      combine a identity === a
  , testProperty "inverse left" $ \a ->
      combine (inverse a) a === identity
  , testProperty "inverse right" $ \a ->
      combine a (inverse a) === identity
  , testProperty "distributivity left" $ \a b c ->
      multiply a (add b c) === add (multiply a b) (multiply a c)
  , testProperty "distributivity right" $ \a b c ->
      multiply (add a b) c === add (multiply a c) (multiply b c)
  , testProperty "absorption" $ \a b ->
      meet a (join a b) === a .&&. join a (meet a b) === a
  , testProperty "idempotence" $ \a ->
      operation (operation a) === operation a
  ]
```

❌ **Transformation Properties (MUST TEST ALL)**:

```haskell
-- MISSING TRANSFORMATION PROPERTY TESTS to identify:
testTransformationProperties = testGroup "transformation properties"
  [ testProperty "idempotence" $ \input ->
      transform (transform input) === transform input
  , testProperty "reversibility" $ \input ->
      isValid input ==> reverse (transform input) === input
  , testProperty "composition associativity" $ \input ->
      transform3 (transform2 (transform1 input)) === compose3 transform1 transform2 transform3 input
  , testProperty "composition identity" $ \input ->
      compose identity transform input === transform input
  , testProperty "homomorphism" $ \a b ->
      transform (combine a b) === combine (transform a) (transform b)
  , testProperty "monotonicity" $ \a b ->
      a <= b ==> transform a <= transform b
  , testProperty "bijection" $ \input ->
      isValid input ==> inverse (transform input) === input
  , testProperty "preservation of structure" $ \input ->
      structure (transform input) === structure input
  ]
```

❌ **Invariant Properties (MUST TEST ALL)**:

```haskell
-- MISSING INVARIANT PROPERTY TESTS to identify:
testInvariantProperties = testGroup "invariant properties"
  [ testProperty "size preservation" $ \input ->
      length (process input) === length input
  , testProperty "type preservation" $ \input ->
      typeOf (process input) === typeOf input
  , testProperty "constraint maintenance" $ \input ->
      isValid input ==> isValid (process input)
  , testProperty "ordering preservation" $ \input ->
      isSorted input ==> isSorted (process input)
  , testProperty "uniqueness preservation" $ \input ->
      isUnique input ==> isUnique (process input)
  , testProperty "balance preservation" $ \tree ->
      isBalanced tree ==> isBalanced (insert item tree)
  , testProperty "memory safety" $ \input ->
      all isValidPointer (extractPointers (process input))
  , testProperty "resource cleanup" $ \input ->
      resourcesAfter (process input) === resourcesBefore input
  ]
```

❌ **Error Handling Properties (MUST TEST ALL)**:

```haskell
-- MISSING ERROR HANDLING PROPERTY TESTS to identify:
testErrorHandlingProperties = testGroup "error handling properties"
  [ testProperty "error preservation" $ \invalidInput ->
      isLeft (validate invalidInput) ==> isLeft (process invalidInput)
  , testProperty "graceful degradation" $ \input ->
      hasErrors input ==> isPartialSuccess (process input)
  , testProperty "error propagation" $ \errorInput ->
      containsError errorInput ==> containsError (pipeline errorInput)
  , testProperty "recovery invariant" $ \input ->
      isRecoverable (process input) ==> canRecover (process input)
  , testProperty "error locality" $ \mixedInput ->
      localErrors (process mixedInput) `isSubsetOf` localErrors mixedInput
  , testProperty "fail-fast behavior" $ \criticalError ->
      isCritical criticalError ==> isFailFast (process criticalError)
  ]
```

### 5. **Negative Input Testing Analysis**

**Malicious Input Detection:**

❌ **Security Attack Vectors (MUST TEST ALL)**:

```haskell
-- MISSING SECURITY ATTACK VECTOR TESTS to identify:
testSecurityAttackVectors = testGroup "security attack vectors"
  [ testCase "SQL injection" $ processInput sqlInjectionPayload @?= Left SecurityViolationError
  , testCase "script injection" $ processInput scriptInjectionPayload @?= Left SecurityViolationError
  , testCase "XSS attack" $ processInput xssPayload @?= Left SecurityViolationError
  , testCase "path traversal" $ processInput pathTraversalPayload @?= Left SecurityViolationError
  , testCase "buffer overflow" $ processInput bufferOverflowPayload @?= Left SecurityViolationError
  , testCase "format string attack" $ processInput formatStringPayload @?= Left SecurityViolationError
  , testCase "XML external entity" $ processInput xxePayload @?= Left SecurityViolationError
  , testCase "deserialization bomb" $ processInput deserializationBombPayload @?= Left SecurityViolationError
  , testCase "billion laughs attack" $ processInput billionLaughsPayload @?= Left SecurityViolationError
  , testCase "zip bomb" $ processInput zipBombPayload @?= Left SecurityViolationError
  , testCase "LDAP injection" $ processInput ldapInjectionPayload @?= Left SecurityViolationError
  , testCase "NoSQL injection" $ processInput nosqlInjectionPayload @?= Left SecurityViolationError
  , testCase "command injection" $ processInput commandInjectionPayload @?= Left SecurityViolationError
  , testCase "directory traversal" $ processInput directoryTraversalPayload @?= Left SecurityViolationError
  , testCase "timing attack" $ testTimingAttack @?= expectedTimingAttackResistance
  ]
```

❌ **Malformed Input Handling (MUST TEST ALL)**:

```haskell
-- MISSING MALFORMED INPUT TESTS to identify:
testMalformedInputHandling = testGroup "malformed input handling"
  [ testCase "truncated data" $ processInput truncatedData @?= Left TruncatedDataError
  , testCase "corrupted headers" $ processInput corruptedHeaders @?= Left CorruptedHeaderError
  , testCase "invalid checksums" $ processInput invalidChecksum @?= Left ChecksumError
  , testCase "wrong encoding" $ processInput wrongEncoding @?= Left EncodingError
  , testCase "mixed line endings" $ processInput mixedLineEndings @?= expectedNormalizedLineEndings
  , testCase "embedded null bytes" $ processInput embeddedNulls @?= Left EmbeddedNullError
  , testCase "non-printable chars" $ processInput nonPrintable @?= Left NonPrintableError
  , testCase "incomplete multibyte" $ processInput incompleteMultibyte @?= Left IncompleteMultibyteError
  , testCase "BOM in middle" $ processInput bomInMiddle @?= Left InvalidBOMError
  , testCase "wrong byte order" $ processInput wrongByteOrder @?= Left ByteOrderError
  , testCase "invalid magic number" $ processInput wrongMagicNumber @?= Left MagicNumberError
  , testCase "version mismatch" $ processInput futureVersion @?= Left VersionMismatchError
  , testCase "checksum mismatch" $ processInput checksumMismatch @?= Left ChecksumMismatchError
  , testCase "size mismatch" $ processInput sizeMismatch @?= Left SizeMismatchError
  ]
```

❌ **Boundary Violation Detection (MUST TEST ALL)**:

```haskell
-- MISSING BOUNDARY VIOLATION TESTS to identify:
testBoundaryViolations = testGroup "boundary violations"
  [ testCase "exceed maximum length" $ processInput tooLongInput @?= Left LengthExceededError
  , testCase "below minimum length" $ processInput tooShortInput @?= Left LengthTooShortError
  , testCase "exceed maximum depth" $ processInput tooDeepInput @?= Left DepthExceededError
  , testCase "exceed maximum width" $ processInput tooWideInput @?= Left WidthExceededError
  , testCase "exceed maximum count" $ processInput tooManyItems @?= Left CountExceededError
  , testCase "exceed memory limit" $ processInput memoryExceedingInput @?= Left MemoryLimitError
  , testCase "exceed time limit" $ processInput timeExceedingInput @?= Left TimeLimitError
  , testCase "exceed recursion limit" $ processInput recursionExceedingInput @?= Left RecursionLimitError
  , testCase "exceed nesting limit" $ processInput nestingExceedingInput @?= Left NestingLimitError
  , testCase "exceed complexity limit" $ processInput complexityExceedingInput @?= Left ComplexityLimitError
  , testCase "exceed precision limit" $ processInput precisionExceedingInput @?= Left PrecisionLimitError
  , testCase "exceed scale limit" $ processInput scaleExceedingInput @?= Left ScaleLimitError
  ]
```

### 6. **Integration Test Coverage Analysis**

**Missing Integration Scenarios:**

❌ **Module Interaction Tests (MUST TEST ALL)**:

```haskell
-- MISSING MODULE INTERACTION TESTS to identify:
testModuleIntegration = testGroup "module integration"
  [ testCase "happy path pipeline" $
      (parseInput >=> validateInput >=> processInput >=> generateOutput) rawInput @?= Right expectedOutput
  , testCase "error propagation pipeline" $
      (parseInput >=> validateInput >=> processInput) invalidRawInput @?= Left expectedPipelineError
  , testCase "partial failure pipeline" $
      (parseInput >=> validateInput >=> processInput) partiallyValidInput @?= Right expectedPartialOutput
  , testCase "concurrent module access" $
      testConcurrentAccess modules @?= expectedConcurrentSafe
  , testCase "module state consistency" $
      testStateConsistency modules @?= expectedConsistentState
  , testCase "cross-module dependencies" $
      testCrossModuleDependencies @?= expectedDependencyResolution
  , testCase "module lifecycle" $
      testModuleLifecycle @?= expectedLifecycleHandling
  , testCase "module communication" $
      testModuleCommunication @?= expectedCommunicationProtocol
  , testCase "module isolation" $
      testModuleIsolation @?= expectedIsolationMaintained
  , testCase "module composition" $
      testModuleComposition @?= expectedCompositionBehavior
  ]
```

❌ **External Dependency Integration (MUST TEST ALL)**:

```haskell
-- MISSING EXTERNAL DEPENDENCY TESTS to identify:
testExternalDependencies = testGroup "external dependencies"
  [ testCase "database connection failure" $
      testWithFailedDB operation @?= Left DBConnectionError
  , testCase "database timeout" $
      testWithSlowDB operation @?= Left DBTimeoutError
  , testCase "database transaction rollback" $
      testWithFailingTransaction operation @?= Left TransactionRollbackError
  , testCase "external API unavailable" $
      testWithUnavailableAPI operation @?= Left APIUnavailableError
  , testCase "external API rate limiting" $
      testWithRateLimitedAPI operation @?= Left APIRateLimitError
  , testCase "external API version mismatch" $
      testWithIncompatibleAPI operation @?= Left APIVersionError
  , testCase "file system permissions" $
      testWithReadOnlyFS operation @?= Left PermissionError
  , testCase "file system full" $
      testWithFullFS operation @?= Left FileSystemFullError
  , testCase "network partition" $
      testWithNetworkPartition operation @?= Left NetworkPartitionError
  , testCase "service mesh failure" $
      testWithServiceMeshFailure operation @?= Left ServiceMeshError
  ]
```

### 7. **Performance & Resource Test Analysis**

**Missing Performance Tests:**

❌ **Resource Usage Tests (MUST TEST ALL)**:

```haskell
-- MISSING RESOURCE USAGE TESTS to identify:
testResourceUsage = testGroup "resource usage"
  [ testCase "memory usage within bounds" $ do
      initialMemory <- getCurrentMemoryUsage
      result <- processLargeInput largeInput
      finalMemory <- getCurrentMemoryUsage
      let memoryIncrease = finalMemory - initialMemory
      result @?= Right expectedLargeOutput
      memoryIncrease `shouldSatisfy` (< maxAllowedMemoryIncrease)
  , testCase "memory leak detection" $ do
      initialMemory <- getCurrentMemoryUsage
      replicateM_ 1000 (processInput smallInput)
      performGC
      finalMemory <- getCurrentMemoryUsage
      let memoryGrowth = finalMemory - initialMemory
      memoryGrowth `shouldSatisfy` (< memoryLeakThreshold)
  , testCase "CPU usage bounds" $ do
      startTime <- getCurrentTime
      result <- processCPUIntensiveInput cpuIntensiveInput
      endTime <- getCurrentTime
      let duration = diffUTCTime endTime startTime
      result @?= Right expectedCPUIntensiveOutput
      duration `shouldSatisfy` (< maxAllowedCPUTime)
  , testCase "file descriptor cleanup" $ do
      initialFDs <- getCurrentFileDescriptors
      result <- processWithManyFiles manyFiles
      finalFDs <- getCurrentFileDescriptors
      result @?= Right expectedManyFilesOutput
      finalFDs @?= initialFDs
  , testCase "thread cleanup" $ do
      initialThreads <- getCurrentThreadCount
      result <- processWithManyThreads threadedInput
      finalThreads <- getCurrentThreadCount
      result @?= Right expectedThreadedOutput
      finalThreads @?= initialThreads
  ]
```

❌ **Scalability Tests (MUST TEST ALL)**:

```haskell
-- MISSING SCALABILITY TESTS to identify:
testScalability = testGroup "scalability"
  [ testProperty "linear time complexity" $ \n ->
      n > 0 && n < 1000 ==> monadicIO $ do
        let input = generateScalabilityInput n
        duration <- run $ timeAction (processScalableData input)
        assert (duration < fromIntegral n * maxTimePerItem)
  , testProperty "logarithmic time complexity" $ \n ->
      n > 0 && n < 10000 ==> monadicIO $ do
        let input = generateLogScalabilityInput n
        duration <- run $ timeAction (processLogScalableData input)
        assert (duration < logBase 2 (fromIntegral n) * maxLogTimePerItem)
  , testProperty "constant space complexity" $ \n ->
      n > 0 && n < 1000 ==> monadicIO $ do
        let input = generateScalabilityInput n
        memoryUsage <- run $ measureMemoryUsage (processConstantSpace input)
        assert (memoryUsage < maxConstantMemory)
  , testProperty "throughput scaling" $ \n ->
      n > 0 && n < 100 ==> monadicIO $ do
        let inputs = replicate n standardInput
        startTime <- run getCurrentTime
        results <- run $ mapM processInput inputs
        endTime <- run getCurrentTime
        let duration = diffUTCTime endTime startTime
            throughput = fromIntegral n / realToFrac duration
        assert (all isRight results)
        assert (throughput > minRequiredThroughput)
  ]
```

---

## Test Analysis Report Generation

### **Comprehensive Gap Detection Output**

**Missing Test Report Template:**

```haskell
-- =================================================================
-- COMPREHENSIVE TEST COVERAGE ANALYSIS REPORT
-- Module: [ModuleName]
-- Test File: [TestFile]
-- Analysis Date: [Date]
-- =================================================================

-- CRITICAL GAPS (Must Fix Immediately):
-- ═══════════════════════════════════

-- 🔴 UNTESTED PUBLIC FUNCTIONS:
--   ❌ function1 :: Type -> IO Result
--   ❌ function2 :: Config -> Either Error Output
--   ❌ dataConstructor :: Field -> Type

-- 🔴 MISSING EDGE CASE TESTS:
--   ❌ Numeric boundaries (zero, maxBound, minBound, infinity, NaN)
--   ❌ String boundaries (empty, unicode, control chars, very long)
--   ❌ Collection boundaries (empty, single, huge, circular, nested)
--   ❌ File system boundaries (nonexistent, unreadable, locked, full disk)
--   ❌ Parser boundaries (empty input, malformed, deeply nested, invalid chars)
--   ❌ Network boundaries (timeout, refused, malformed response, SSL errors)
--   ❌ Memory boundaries (exhaustion, leak detection, cleanup verification)
--   ❌ Concurrency boundaries (races, deadlocks, contention, interruption)

-- 🔴 MISSING ERROR PATH TESTS:
--   ❌ Input validation failures (null, wrong type, out of range, malformed)
--   ❌ State corruption errors (invalid transition, inconsistency, version mismatch)
--   ❌ External dependency errors (unavailable, timeout, auth failure, protocol violation)
--   ❌ Resource exhaustion scenarios (memory, file descriptors, threads, disk space)
--   ❌ Security attack vectors (injection, XSS, buffer overflow, traversal)

-- 🔴 MISSING NEGATIVE INPUT TESTS:
--   ❌ Malicious input detection (SQL injection, script injection, path traversal)
--   ❌ Malformed input handling (truncated, corrupted, wrong encoding, embedded nulls)
--   ❌ Boundary violations (exceed limits, below minimums, wrong constraints)
--   ❌ Incompatible input (wrong version, schema mismatch, type mismatch)

-- HIGH PRIORITY GAPS (Fix Soon):
-- ══════════════════════════════

-- 🟡 INCOMPLETE PROPERTY TESTS:
--   ⚠ Missing algebraic property verification (associativity, commutativity, identity)
--   ⚠ No invariant preservation tests (size, type, constraint maintenance)
--   ⚠ Missing transformation property checks (idempotence, reversibility, composition)
--   ⚠ No error handling properties (error preservation, graceful degradation)

-- 🟡 PARTIAL COVERAGE AREAS:
--   ⚠ function3: Only happy path tested
--   ⚠ Type constructors: Missing field validation
--   ⚠ Configuration parsing: Missing malformed input tests
--   ⚠ Error handling: Only basic error cases covered

-- MEDIUM PRIORITY GAPS (Consider Adding):
-- ══════════════════════════════════════

-- 🟢 MISSING INTEGRATION TESTS:
--   ➤ Module interaction scenarios (pipeline processing, cross-module dependencies)
--   ➤ External dependency failure modes (database, API, file system, network)
--   ➤ Concurrent access patterns (thread safety, resource contention, deadlock prevention)

-- 🟢 MISSING PERFORMANCE TESTS:
--   ➤ Resource usage validation (memory bounds, CPU time, file descriptor cleanup)
--   ➤ Scalability verification (time complexity, space complexity, throughput)
--   ➤ Memory leak detection (long-running operations, resource cleanup)

-- RECOMMENDED TEST ADDITIONS:
-- ═══════════════════════════

testMissingCoverage :: TestTree
testMissingCoverage = testGroup "missing coverage additions"
  [ testGroup "untested functions"
    [ testCase "function1 with valid input" $
        function1 validInput @?= expectedOutput
    , testCase "function1 with invalid input" $
        function1 invalidInput @?= Left expectedError
    , testCase "function1 boundary conditions" $
        function1 boundaryInput @?= expectedBoundaryOutput
    ]
  , testGroup "missing edge cases"
    [ testCase "empty input handling" $
        processInput [] @?= expectedEmpty
    , testCase "maximum size input" $
        processInput maxInput @?= expectedMax
    , testCase "unicode handling" $
        processInput unicodeInput @?= expectedUnicode
    , testCase "very long input" $
        processInput veryLongInput @?= expectedVeryLong
    ]
  , testGroup "missing error paths"
    [ testCase "network failure scenario" $
        testWithNetworkFailure operation @?= Left NetworkError
    , testCase "resource exhaustion" $
        testWithExhaustedResources operation @?= Left ResourceError
    , testCase "security violation" $
        testWithMaliciousInput operation @?= Left SecurityError
    ]
  , testGroup "missing negative inputs"
    [ testCase "SQL injection attempt" $
        processInput sqlInjectionPayload @?= Left SecurityViolationError
    , testCase "malformed data" $
        processInput malformedData @?= Left MalformedDataError
    , testCase "boundary violation" $
        processInput boundaryViolatingData @?= Left BoundaryViolationError
    ]
  ]

-- PROPERTY TEST ADDITIONS:
-- ═══════════════════════

propMissingProperties :: TestTree
propMissingProperties = testGroup "missing property tests"
  [ testProperty "function composition associativity" $ \a b c ->
      compose (compose f g) h a === compose f (compose g h) a
  , testProperty "input/output size relationship" $ \input ->
      length (process input) `shouldSatisfy` (>= length input)
  , testProperty "error preservation" $ \invalidInput ->
      isLeft (validate invalidInput) ==> isLeft (process invalidInput)
  , testProperty "invariant preservation" $ \input ->
      isValid input ==> isValid (process input)
  , testProperty "memory safety" $ \input ->
      all isValidPointer (extractPointers (process input))
  ]
```

### **Test Quality Assessment Metrics**

**Coverage Scoring System:**

```haskell
-- COMPREHENSIVE COVERAGE METRICS ANALYSIS:
-- ═══════════════════════════════════════

-- Function Coverage:          [X]% ([Y]/[Z] functions tested)
-- Edge Case Coverage:         [X]% (estimated based on systematic boundary analysis)
-- Error Path Coverage:        [X]% ([Y]/[Z] error conditions tested)
-- Negative Input Coverage:    [X]% (malicious/malformed input scenarios)
-- Property Coverage:          [X]% (algebraic laws and invariants verified)
-- Integration Coverage:       [X]% (module interaction scenarios)
-- Performance Coverage:       [X]% (resource usage and scalability tests)
-- Security Coverage:          [X]% (attack vector and vulnerability tests)

-- OVERALL TEST QUALITY SCORE: [X]/100
--
-- Detailed Scoring Breakdown:
-- - Function Coverage (25 points):        [X]/25
-- - Edge Cases (20 points):              [X]/20
-- - Error Paths (15 points):             [X]/15
-- - Negative Inputs (15 points):         [X]/15
-- - Properties (10 points):              [X]/10
-- - Integration (8 points):              [X]/8
-- - Performance (4 points):              [X]/4
-- - Security (3 points):                 [X]/3

-- QUALITY THRESHOLD: ≥85 points required for CLAUDE.md compliance
-- EXCELLENCE THRESHOLD: ≥95 points for production-ready modules
```

---

## Agent-Driven Test Analysis Process

### **Multi-Stage Analysis Pipeline**

**Stage 1: Test File Analysis & Source Module Discovery**

- Parse test file path and infer corresponding source module(s)
- Load source module exports and public API automatically
- Map test file structure to source module organization
- Identify primary and sub-module relationships

**Stage 2: Existing Test Inventory**

- Scan test modules for coverage patterns
- Map test cases to source functions
- Identify test categories and approaches
- Assess property test coverage

**Stage 3: Gap Detection Analysis**

- Cross-reference source exports with test coverage
- Identify untested functions and partial coverage
- Analyze edge case coverage systematically
- Flag missing error path scenarios

**Stage 4: Recommendation Generation**

- Generate specific test case recommendations
- Propose property test additions
- Suggest integration test scenarios
- Prioritize gaps by criticality level

### **Automated Test Generation Templates**

**Unit Test Template Generator:**

```haskell
-- GENERATED COMPREHENSIVE TEST TEMPLATE for function: [functionName]
-- Signature: [functionSignature]
-- Module: [moduleName]

test[FunctionName] :: TestTree
test[FunctionName] = testGroup "[functionName] tests"
  [ testGroup "valid inputs"
    [ testCase "typical case" $
        [functionName] typicalInput @?= expectedOutput
    , testCase "edge case: [specific edge]" $
        [functionName] edgeInput @?= expectedEdgeOutput
    , testCase "boundary case: [specific boundary]" $
        [functionName] boundaryInput @?= expectedBoundaryOutput
    ]
  , testGroup "invalid inputs"
    [ testCase "null/empty input" $
        [functionName] emptyInput @?= Left expectedError
    , testCase "malformed input" $
        [functionName] malformedInput @?= Left expectedParseError
    , testCase "out of range input" $
        [functionName] outOfRangeInput @?= Left expectedRangeError
    ]
  , testGroup "boundary conditions"
    [ testCase "minimum value" $
        [functionName] minInput @?= expectedMinOutput
    , testCase "maximum value" $
        [functionName] maxInput @?= expectedMaxOutput
    , testCase "zero value" $
        [functionName] zeroInput @?= expectedZeroOutput
    , testCase "negative value" $
        [functionName] negativeInput @?= expectedNegativeOutput
    ]
  , testGroup "error conditions"
    [ testCase "resource exhaustion" $
        [functionName] exhaustingInput @?= Left expectedResourceError
    , testCase "timeout scenario" $
        [functionName] slowInput @?= Left expectedTimeoutError
    , testCase "security violation" $
        [functionName] maliciousInput @?= Left expectedSecurityError
    ]
  ]
```

**Property Test Template Generator:**

```haskell
-- GENERATED COMPREHENSIVE PROPERTY TEMPLATE for function: [functionName]

prop[FunctionName]Properties :: TestTree
prop[FunctionName]Properties = testGroup "[functionName] properties"
  [ testProperty "idempotence" $ \input ->
      [functionName] ([functionName] input) === [functionName] input
  , testProperty "input/output relationship" $ \input ->
      length ([functionName] input) `shouldSatisfy` (>= 0)
  , testProperty "error preservation" $ \invalidInput ->
      isLeft (validate invalidInput) ==> isLeft ([functionName] invalidInput)
  , testProperty "monotonicity" $ \a b ->
      a <= b ==> [functionName] a <= [functionName] b
  , testProperty "constraint preservation" $ \input ->
      satisfiesConstraint input ==> satisfiesConstraint ([functionName] input)
  , testProperty "resource cleanup" $ \input ->
      resourcesAfter ([functionName] input) === resourcesBefore input
  ]
```

---

## Test Gap Resolution Checklist

### **Critical Gap Resolution (Required):**

- [ ] All public functions have comprehensive unit test coverage
- [ ] All edge cases systematically identified and tested
- [ ] All error paths tested with specific error type validation
- [ ] All negative input scenarios covered (malicious, malformed, boundary violations)
- [ ] Property tests verify algebraic laws and invariants
- [ ] Security attack vectors tested and mitigated
- [ ] Resource exhaustion scenarios tested
- [ ] Concurrency safety verified

### **Quality Enhancement (Recommended):**

- [ ] Integration tests cover all module interactions
- [ ] Performance tests validate resource usage and scalability
- [ ] Memory leak detection and resource cleanup verification
- [ ] Golden tests capture deterministic outputs
- [ ] Regression tests prevent previously fixed bugs
- [ ] Stress tests validate system under load

### **Documentation & Maintenance:**

- [ ] Test documentation explains comprehensive coverage strategy
- [ ] Test organization follows systematic module structure
- [ ] Test utilities provide reusable components for edge cases
- [ ] Coverage reports generated and systematically reviewed
- [ ] Test maintenance automated with CI/CD
- [ ] Test data generators provide comprehensive input coverage

### **Compliance Validation:**

- [ ] All tests pass consistently and deterministically
- [ ] Coverage threshold ≥85% achieved across all categories
- [ ] HLint rules applied to all test code
- [ ] Test code follows CLAUDE.md guidelines exactly
- [ ] Integration with build system verified and automated
- [ ] Security testing integrated into CI/CD pipeline

---

## Reference Excellence Examples

**Exemplar Test Files:**

- `test/Unit/Parse/PatternTest.hs` - Comprehensive edge case coverage
- `test/Property/Data/NameProps.hs` - Property test excellence
- `test/Golden/JsGenGolden.hs` - Golden test architecture
- `test/Integration/Make/BuildTest.hs` - Integration test patterns

**Coverage Analysis Models:**

- Complete function coverage with systematic edge cases
- Comprehensive error path testing with specific error validation
- Property-based law verification with custom generators
- Integration scenario validation with external dependencies
- Performance characteristic testing with resource monitoring
- Security vulnerability testing with attack vector coverage

---

## Test Analysis Command Integration

**Usage Pattern:**

```bash
# Analyze test coverage for specific test file (auto-infers source module)
/analyze-tests test/Unit/Make/ParserTest.hs

# Generate missing test recommendations from test file
/analyze-tests test/Property/Data/NameProps.hs

# Integration test analysis with sub-module discovery
/analyze-tests test/Integration/Make/BuildTest.hs
```

**Output Integration:**

- Detailed gap analysis report with systematic categorization
- Prioritized test addition recommendations with implementation templates
- Generated test templates for missing coverage areas
- Comprehensive coverage metrics and quality scores
- Specific action items with implementation guidance
- Security and performance testing recommendations