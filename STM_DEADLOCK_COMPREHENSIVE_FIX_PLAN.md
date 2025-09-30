# STM Deadlock Comprehensive Fix Plan - Canopy Compiler

## Problem Analysis

Despite implementing three layers of STM timeout mechanisms, we're still experiencing STM deadlocks in the Canopy compiler during large project compilation. The issue manifests as:

```
thread blocked indefinitely in an STM transaction
```

This occurs when packages are waiting for dependencies that never complete, creating infinite retry loops in the STM system.

## Root Cause Analysis

### 1. **Current STM Deadlock Points Identified**

We've fixed these STM deadlock points:
- ✅ **Primary**: `waitForDependencies` in dependency resolution
- ✅ **Secondary**: `traverse waitForResult` in final status collection
- ✅ **Tertiary**: `waitForSpecificDependency` in package verification

### 2. **Remaining STM Deadlock Sources**

Based on the latest failure, additional STM deadlock points exist:

#### A. **Circular Dependency Chains**
- Packages waiting for each other in circular patterns
- Example: A waits for B, B waits for C, C waits for A
- Current timeout mechanisms don't break these cycles effectively

#### B. **Resource Contention STM Operations**
- Multiple packages competing for the same shared STM resources
- File system locks, registry access, cache operations
- Missing timeout protection on auxiliary STM operations

#### C. **Dependency Resolution Cascade Failures**
- When one package fails, dependent packages wait indefinitely
- Error propagation not reaching all waiting packages
- STM operations don't have proper failure handling

#### D. **Package State Transition STM Operations**
- State transitions from "building" to "completed" use STM
- Multiple threads trying to update package states simultaneously
- Missing timeouts on state transition operations

#### E. **Registry and Cache STM Operations**
- Package registry lookups using STM
- Cache invalidation and updates using STM
- Network timeouts not properly handled in STM context

## Comprehensive Solution Strategy

### Phase 1: STM Operation Audit and Mapping

#### 1.1 Complete STM Operation Inventory
```bash
# Find all STM operations in codebase
grep -r "atomically" --include="*.hs" compiler/ builder/ > stm_operations.txt
grep -r "STM" --include="*.hs" compiler/ builder/ >> stm_operations.txt
grep -r "TVar" --include="*.hs" compiler/ builder/ >> stm_operations.txt
grep -r "TMVar" --include="*.hs" compiler/ builder/ >> stm_operations.txt
grep -r "retry" --include="*.hs" compiler/ builder/ >> stm_operations.txt
```

#### 1.2 Categorize STM Operations by Risk Level
- **HIGH RISK**: Dependency waiting, package state transitions
- **MEDIUM RISK**: Cache operations, registry access
- **LOW RISK**: Simple state reads, logging operations

#### 1.3 Create STM Dependency Graph
Map all STM operations and their dependencies to identify:
- Circular dependency potential
- Resource contention points
- Critical path bottlenecks

### Phase 2: Universal STM Timeout Framework

#### 2.1 STM Timeout Wrapper Function
```haskell
-- Universal STM timeout wrapper
atomicallyWithTimeout :: Int -> STM a -> IO (Either String a)
atomicallyWithTimeout timeoutSeconds action = do
  result <- timeout (timeoutSeconds * 1000000) (atomically action)
  case result of
    Nothing -> return $ Left $ "STM operation timed out after " ++ show timeoutSeconds ++ " seconds"
    Just value -> return $ Right value

-- Enhanced version with retry counting
atomicallyWithTimeoutAndRetries :: Int -> Int -> STM a -> IO (Either String a)
atomicallyWithTimeoutAndRetries timeoutSeconds maxRetries action = do
  retryCount <- newTVarIO 0
  let actionWithRetryCount = do
        count <- readTVar retryCount
        if count >= maxRetries
          then error $ "STM operation exceeded " ++ show maxRetries ++ " retries"
          else do
            writeTVar retryCount (count + 1)
            action
  atomicallyWithTimeout timeoutSeconds actionWithRetryCount
```

#### 2.2 Apply Universal Timeout to All STM Operations
Replace every `atomically` call with `atomicallyWithTimeout`:

```haskell
-- Before
result <- atomically $ waitForDependencies store deps

-- After
result <- atomicallyWithTimeout 120 $ waitForDependencies store deps
case result of
  Left errorMsg -> return $ Left errorMsg
  Right deps -> continue processing...
```

### Phase 3: Circular Dependency Detection and Breaking

#### 3.1 Dependency Cycle Detection Algorithm
```haskell
data DependencyGraph = DependencyGraph
  { _nodes :: Set PackageName
  , _edges :: Map PackageName [PackageName]
  }

detectCycles :: DependencyGraph -> [DependencyGraph.Cycle]
detectCycles graph =
  -- Implement Tarjan's strongly connected components algorithm
  -- Return all cycles found in dependency graph

breakCycle :: DependencyGraph.Cycle -> IO ()
breakCycle cycle = do
  -- Strategy 1: Identify weakest dependency in cycle
  -- Strategy 2: Mark one package as "building" to break wait
  -- Strategy 3: Fail cycle with detailed error message
```

#### 3.2 Real-time Cycle Detection
```haskell
monitorDependencyDeadlocks :: DepStore -> IO ()
monitorDependencyDeadlocks store = do
  -- Run every 30 seconds
  -- Check for packages waiting longer than threshold
  -- Analyze dependency chains for cycles
  -- Break cycles automatically or with warnings
```

### Phase 4: Enhanced Error Propagation

#### 4.1 Cascading Failure System
```haskell
data PackageFailure = PackageFailure
  { _failedPackage :: PackageName
  , _failureReason :: String
  , _affectedPackages :: [PackageName]
  , _timestamp :: UTCTime
  }

propagateFailure :: PackageFailure -> DepStore -> IO ()
propagateFailure failure store = do
  -- Find all packages waiting for failed package
  -- Mark them as failed with dependency failure reason
  -- Release STM locks and wake up waiting threads
  -- Prevent infinite waiting chains
```

#### 4.2 STM Operation Error Context
```haskell
data STMContext = STMContext
  { _operation :: String
  , _packageName :: PackageName
  , _dependencies :: [PackageName]
  , _startTime :: UTCTime
  }

withSTMContext :: STMContext -> STM a -> STM a
withSTMContext context action = do
  -- Add context information to STM operation
  -- Enable better error reporting
  -- Track operation duration and dependencies
```

### Phase 5: Resource Contention Management

#### 5.1 STM Resource Pool
```haskell
data ResourcePool = ResourcePool
  { _fileSystemLocks :: TVar (Set FilePath)
  , _registryLocks :: TVar (Set PackageName)
  , _cacheLocks :: TVar (Set CacheKey)
  , _maxConcurrentOperations :: Int
  }

acquireResource :: ResourcePool -> ResourceType -> STM Bool
acquireResource pool resourceType = do
  -- Check if resource is available
  -- Acquire resource if available
  -- Return False if resource is locked
  -- Implement fair scheduling
```

#### 5.2 Deadlock Prevention through Resource Ordering
```haskell
-- Define global resource acquisition order
data ResourceOrder = FileSystem | Registry | Cache | Dependency

acquireResourcesInOrder :: [ResourceType] -> STM a -> STM a
acquireResourcesInOrder resources action = do
  -- Sort resources by global order
  -- Acquire resources in sorted order
  -- Prevent circular resource dependencies
  -- Release resources in reverse order
```

### Phase 6: STM Monitoring and Diagnostics

#### 6.1 STM Operation Tracking
```haskell
data STMOperation = STMOperation
  { _opId :: UUID
  , _opType :: String
  , _packageName :: PackageName
  , _startTime :: UTCTime
  , _endTime :: Maybe UTCTime
  , _status :: STMStatus
  , _retryCount :: Int
  }

data STMStatus = Running | Completed | TimedOut | Failed String

trackSTMOperation :: String -> PackageName -> STM a -> IO (Either String a)
trackSTMOperation opType pkg action = do
  opId <- generateUUID
  startTime <- getCurrentTime
  let operation = STMOperation opId opType pkg startTime Nothing Running 0
  recordSTMOperation operation
  result <- atomicallyWithTimeout 120 action
  endTime <- getCurrentTime
  updateSTMOperation opId endTime result
  return result
```

#### 6.2 Real-time STM Dashboard
```haskell
generateSTMReport :: IO STMReport
generateSTMReport = do
  -- Current active STM operations
  -- Packages waiting for dependencies
  -- Detected circular dependencies
  -- Resource contention hotspots
  -- Timeout statistics
  -- Performance metrics
```

### Phase 7: Package Compilation State Machine

#### 7.1 Explicit Package State Management
```haskell
data PackageState
  = NotStarted
  | DownloadPending
  | Downloaded
  | DependencyResolution
  | Compiling ModuleName
  | CompilingComplete
  | Failed String
  | Completed
  deriving (Eq, Show)

data PackageStateTransition = PackageStateTransition
  { _fromState :: PackageState
  , _toState :: PackageState
  , _timestamp :: UTCTime
  , _threadId :: ThreadId
  }

isValidTransition :: PackageState -> PackageState -> Bool
isValidTransition fromState toState =
  -- Define valid state transitions
  -- Prevent invalid state changes
  -- Ensure state machine consistency
```

#### 7.2 State Transition STM Operations
```haskell
transitionPackageState :: PackageName -> PackageState -> PackageState -> STM Bool
transitionPackageState pkg fromState toState = do
  currentState <- readPackageState pkg
  if currentState == fromState && isValidTransition fromState toState
    then do
      writePackageState pkg toState
      recordStateTransition pkg fromState toState
      return True
    else return False

safeTransitionPackageState :: PackageName -> PackageState -> PackageState -> IO (Either String Bool)
safeTransitionPackageState pkg fromState toState =
  atomicallyWithTimeout 30 $ transitionPackageState pkg fromState toState
```

### Phase 8: Testing and Validation Framework

#### 8.1 STM Deadlock Simulation
```haskell
simulateSTMDeadlock :: [PackageName] -> IO TestResult
simulateSTMDeadlock packages = do
  -- Create artificial circular dependencies
  -- Trigger multiple concurrent builds
  -- Verify timeout mechanisms work
  -- Measure recovery time
  -- Test error propagation
```

#### 8.2 Stress Testing Suite
```bash
#!/bin/bash
# STM Stress Test Suite

# Test 1: Large project compilation (100+ packages)
test_large_project() {
  cd test/large-project
  timeout 600 canopy make src/Main.can
}

# Test 2: Concurrent builds
test_concurrent_builds() {
  for i in {1..10}; do
    (cd test/project-$i && canopy make src/Main.can) &
  done
  wait
}

# Test 3: Circular dependency handling
test_circular_dependencies() {
  cd test/circular-deps
  canopy make src/Main.can 2>&1 | grep -q "circular dependency detected"
}

# Test 4: Resource contention
test_resource_contention() {
  # Multiple processes accessing same package cache
  # Verify no STM deadlocks occur
}
```

## Implementation Timeline

### Week 1: STM Operation Audit
- [ ] Complete inventory of all STM operations
- [ ] Categorize by risk level
- [ ] Create dependency graphs
- [ ] Identify circular dependency patterns

### Week 2: Universal STM Timeout Framework
- [ ] Implement `atomicallyWithTimeout` wrapper
- [ ] Replace all `atomically` calls
- [ ] Add retry counting and limits
- [ ] Test timeout mechanisms

### Week 3: Circular Dependency Detection
- [ ] Implement cycle detection algorithm
- [ ] Add real-time monitoring
- [ ] Create cycle breaking strategies
- [ ] Test with known circular dependencies

### Week 4: Error Propagation Enhancement
- [ ] Implement cascading failure system
- [ ] Add STM operation context tracking
- [ ] Improve error messages
- [ ] Test failure propagation

### Week 5: Resource Contention Management
- [ ] Implement STM resource pool
- [ ] Add resource ordering system
- [ ] Prevent resource deadlocks
- [ ] Test resource contention scenarios

### Week 6: Monitoring and Diagnostics
- [ ] Implement STM operation tracking
- [ ] Create real-time dashboard
- [ ] Add performance metrics
- [ ] Test monitoring accuracy

### Week 7: State Machine Implementation
- [ ] Define package state machine
- [ ] Implement state transitions
- [ ] Add state validation
- [ ] Test state consistency

### Week 8: Testing and Validation
- [ ] Create deadlock simulation suite
- [ ] Implement stress testing
- [ ] Validate all scenarios
- [ ] Performance benchmarking

## Success Criteria

### Functional Requirements
1. **Zero STM Deadlocks**: No "thread blocked indefinitely" errors under any conditions
2. **Timeout Recovery**: All STM operations complete within defined timeouts
3. **Error Propagation**: Failed packages properly notify dependent packages
4. **Circular Dependency Detection**: Automatic detection and handling of dependency cycles
5. **Resource Management**: No resource contention deadlocks

### Performance Requirements
1. **Compilation Speed**: No more than 10% performance degradation
2. **Memory Usage**: STM monitoring overhead < 5% of total memory
3. **Timeout Response**: Failed operations detected within 2 minutes
4. **Error Recovery**: System recovers from failures within 30 seconds

### Reliability Requirements
1. **Large Projects**: Successfully compile 500+ package projects
2. **Concurrent Builds**: Handle 10+ concurrent compilation processes
3. **Stress Testing**: Pass 24-hour continuous compilation stress test
4. **Edge Cases**: Handle all known circular dependency patterns

## Monitoring and Maintenance

### Continuous Monitoring
- **STM Operation Metrics**: Track timeout rates, retry counts, success rates
- **Performance Monitoring**: Memory usage, CPU utilization, compilation times
- **Error Tracking**: Categorize and track all STM-related errors
- **User Feedback**: Monitor community reports of compilation issues

### Maintenance Schedule
- **Weekly**: Review STM operation metrics and timeout statistics
- **Monthly**: Update timeout thresholds based on performance data
- **Quarterly**: Review and optimize STM algorithms
- **Annually**: Comprehensive STM architecture review

## Risk Mitigation

### High-Risk Scenarios
1. **Timeout Too Aggressive**: May cause false failures for slow systems
   - **Mitigation**: Configurable timeouts, system capability detection
2. **Resource Pool Bottleneck**: May limit compilation parallelism
   - **Mitigation**: Dynamic resource pool sizing, performance monitoring
3. **State Machine Bugs**: Invalid state transitions causing inconsistency
   - **Mitigation**: Comprehensive testing, state validation, rollback mechanisms

### Fallback Strategies
1. **STM Timeout Failure**: Fall back to non-STM sequential processing
2. **Circular Dependency**: Provide manual dependency override options
3. **Resource Contention**: Implement fair scheduling and starvation prevention
4. **Performance Degradation**: Configurable STM feature toggles

## Conclusion

This comprehensive plan addresses all known STM deadlock sources and implements a robust framework for preventing future issues. The solution combines:

1. **Universal timeout protection** for all STM operations
2. **Circular dependency detection** and automatic resolution
3. **Enhanced error propagation** to prevent cascade failures
4. **Resource contention management** to prevent lock conflicts
5. **Comprehensive monitoring** for early problem detection
6. **Robust testing framework** to validate all scenarios

Implementation of this plan will eliminate STM deadlocks permanently while maintaining compilation performance and providing better error reporting for users.