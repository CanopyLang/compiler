# Refactor Analysis — CLAUDE.md Compliance Assessment

**Task:**
Perform comprehensive architectural analysis and CLAUDE.md compliance assessment for module: `$ARGUMENTS`.

- **Scope**: Primary module and all sub-modules (e.g., `Make.hs` + `Make/*.hs`)
- **Analysis**: Deep architectural assessment and violation inventory
- **Standards**: Map current state against CLAUDE.md requirements
- **Strategy**: Design modularization and compliance roadmap

---

## 1. Module Scope Assessment

### Current Architecture Analysis

**Module Structure Discovery:**

```bash
# Inventory existing modules and dependencies
find . -name "$ARGUMENTS.hs" -o -name "$ARGUMENTS/*.hs" | head -20
grep -r "^module " --include="$ARGUMENTS*.hs" . | head -10
grep -r "^import " --include="$ARGUMENTS*.hs" . | wc -l
```

**API Surface Mapping:**

- Public exports and interface boundaries
- Inter-module dependencies and coupling
- External dependencies and integration points
- Type definitions and data flow

**Responsibility Analysis:**

- Single vs. multiple concerns per module
- Shared responsibilities across modules
- Missing abstractions and encapsulation
- Potential extraction opportunities

---

## 2. CLAUDE.md Violation Inventory

### Function Constraints Audit

**Size & Complexity Violations:**

```bash
# Find functions exceeding 15-line limit
grep -n "^[a-zA-Z].*::" $ARGUMENTS.hs | while read line; do
  func_line=$(echo "$line" | cut -d: -f1)
  next_func=$(tail -n +$((func_line + 1)) $ARGUMENTS.hs | grep -n "^[a-zA-Z].*::" | head -1 | cut -d: -f1)
  if [ -z "$next_func" ]; then
    length=$(wc -l < $ARGUMENTS.hs)
    length=$((length - func_line))
  else
    length=$((next_func - 1))
  fi
  if [ "$length" -gt 15 ]; then
    echo "VIOLATION: Function at line $func_line exceeds 15 lines ($length lines)"
  fi
done

# Find functions with >4 parameters
grep -n " -> .*-> .*-> .*-> .*-> " $ARGUMENTS.hs | head -10

# Find complex branching (>4 paths)
grep -n "case\|if.*then\||\s*otherwise\||\s*[A-Z]" $ARGUMENTS.hs | wc -l
```

**Parameter & Branching Analysis:**

- Functions with excessive parameters (>4)
- Deep nesting and branching complexity
- Case expressions with many alternatives
- Guard patterns exceeding limits

### Import Pattern Violations

**Qualification Assessment:**

```bash
# Find unqualified function imports (violations)
grep "^import [^(]*$" $ARGUMENTS.hs | grep -v "qualified"

# Find abbreviated aliases (violations)
grep "qualified.*as [A-Z]$\|qualified.*as [A-Z][A-Z]$" $ARGUMENTS.hs

# Find mixed qualification patterns
grep "import.*(" $ARGUMENTS.hs | grep -v "qualified"
```

**Import Structure Issues:**

- Unqualified function imports
- Abbreviated aliases (`as M`, `as DD`)
- Inconsistent qualification patterns
- Missing type-selective imports

### Record Access Violations

**Lens Usage Assessment:**

```bash
# Find record-dot syntax violations
grep -n "\._\|\..*=" $ARGUMENTS.hs

# Find direct record updates
grep -n "{\s*.*=" $ARGUMENTS.hs

# Check for lens definitions
grep -n "makeLenses\|^[a-z].*Lens" $ARGUMENTS.hs
```

**Record Pattern Issues:**

- Record-dot syntax usage (`record.field`)
- Direct record updates (`record { field = value }`)
- Missing lens definitions and imports
- Inconsistent access patterns

### Documentation Violations

**Haddock Completeness Audit:**

```bash
# Check module-level documentation
head -50 $ARGUMENTS.hs | grep "-- |"

# Find undocumented public functions
grep -n "^[a-zA-Z].*::" $ARGUMENTS.hs | while read line; do
  line_num=$(echo "$line" | cut -d: -f1)
  prev_line=$((line_num - 1))
  if ! sed -n "${prev_line}p" $ARGUMENTS.hs | grep -q "-- |"; then
    echo "UNDOCUMENTED: $(echo "$line" | cut -d: -f2-)"
  fi
done

# Check for examples and @since tags
grep -c ">>>\|@since\|Examples\|Error" $ARGUMENTS.hs
```

**Documentation Gaps:**

- Missing module-level documentation
- Undocumented public functions
- Missing examples and error descriptions
- Absent `@since` version tags

---

## 3. Architectural Assessment

### Modularization Opportunities

**Responsibility Extraction:**

- **Types & Data Structures** → `Types.hs`
- **Environment Setup** → `Environment.hs`
- **Input Parsing** → `Parser.hs`
- **Business Logic** → `Processing.hs`
- **Output Generation** → `Output.hs`

**Coupling Analysis:**

- Tight coupling between concerns
- Shared state and side effects
- Missing abstraction boundaries
- Circular dependency risks

### Design Pattern Assessment

**Current vs. Target Architecture:**

```
CURRENT:                    TARGET:
MonolithicModule.hs    →    ModuleName/
├── All concerns           ├── Types.hs          
├── Mixed responsibilities ├── Environment.hs    
├── Complex dependencies   ├── Parser.hs         
└── Large function size    ├── Processing.hs     
                           └── Output.hs         
```

**Interface Design:**

- Clean public API boundaries
- Type-safe interfaces between modules
- Error handling consistency
- Performance considerations

---

## 4. Quality Metrics Analysis

### Current Compliance Scoring

**Function Design (Weight: 25%)**
- Size compliance (≤15 lines): __/100
- Parameter compliance (≤4 params): __/100
- Branching compliance (≤4 paths): __/100

**Import Standards (Weight: 20%)**
- Qualification patterns: __/100
- Alias conventions: __/100
- Type/function separation: __/100

**Lens Integration (Weight: 15%)**
- Lens definitions: __/100
- Record access patterns: __/100
- Update operations: __/100

**Documentation (Weight: 20%)**
- Module documentation: __/100
- Function documentation: __/100
- Examples and error handling: __/100

**Architecture (Weight: 20%)**
- Single responsibility: __/100
- Modular design: __/100
- Error handling: __/100

**Overall Compliance Score: __/100**

### Gap Analysis Summary

**Critical Violations (Must Fix):**
- [ ] Function size/complexity violations
- [ ] Import qualification issues
- [ ] Record access patterns
- [ ] Missing documentation

**Architectural Improvements:**
- [ ] Module responsibility extraction
- [ ] Interface boundary cleanup
- [ ] Error handling standardization
- [ ] Performance optimization opportunities

---

## 5. Test Coverage Assessment

### Current Test State

**Test Inventory:**

```bash
# Find existing tests for module
find test/ -name "*$ARGUMENTS*" -type f
grep -r "$ARGUMENTS" test/ --include="*.hs" | head -10

# Coverage analysis
make test-coverage | grep "$ARGUMENTS"
```

**Coverage Gaps:**

- Missing unit tests for functions
- Inadequate property test coverage
- Missing integration tests
- Golden test opportunities

### Test Strategy Requirements

**Required Test Types:**

- **Unit Tests**: All public functions
- **Property Tests**: Laws and invariants
- **Integration Tests**: Module interactions
- **Golden Tests**: Deterministic outputs
- **Error Tests**: All failure paths

---

## 6. Dependencies & Integration

### External Dependencies

**Library Usage Analysis:**

```bash
# Analyze import dependencies
grep "^import" $ARGUMENTS.hs | sort | uniq -c | sort -nr

# Check for outdated patterns
grep -n "String\|[^_]IO\s" $ARGUMENTS.hs
```

**Dependency Health:**

- Modern library usage (Text vs String)
- Consistent effect patterns
- Lens library integration
- Testing framework alignment

### Internal Coupling

**Module Relationships:**

- Cross-module dependencies
- Circular dependency risks
- Interface stability
- Version compatibility

---

## 7. Performance Considerations

### Efficiency Analysis

**Performance Patterns:**

```bash
# Find potential inefficiencies
grep -n "++\|length.*==\|reverse.*reverse" $ARGUMENTS.hs

# Check for lazy evaluation issues
grep -n "foldl\|head\|tail" $ARGUMENTS.hs
```

**Optimization Opportunities:**

- String vs Text usage
- List concatenation patterns
- Unnecessary computations
- Memory allocation patterns

---

## 8. Refactoring Priority Matrix

### High Priority (Critical)

1. **Function Size Violations** - Extract oversized functions
2. **Import Pattern Fixes** - Apply mandatory qualification
3. **Lens Integration** - Replace record access patterns
4. **Module Documentation** - Add comprehensive Haddock

### Medium Priority (Important)

1. **Modular Extraction** - Create specialized sub-modules
2. **Error Handling** - Implement rich error types
3. **Test Coverage** - Achieve ≥80% coverage
4. **Performance** - Address efficiency concerns

### Low Priority (Enhancement)

1. **API Polish** - Improve interface ergonomics
2. **Documentation Examples** - Add comprehensive examples
3. **Benchmark Tests** - Performance regression detection
4. **Integration Tests** - Cross-module validation

---

## 9. Implementation Roadmap

### Phase 1: Foundation (Days 1-2)

- Fix critical CLAUDE.md violations
- Establish lens infrastructure
- Standardize import patterns
- Add basic documentation

### Phase 2: Modularization (Days 3-4)

- Extract specialized sub-modules
- Design clean interfaces
- Implement comprehensive error handling
- Create test infrastructure

### Phase 3: Quality (Days 5-6)

- Achieve full test coverage
- Complete documentation
- Performance optimization
- Integration validation

### Phase 4: Validation (Day 7)

- Agent compliance verification
- Build system integration
- Documentation review
- Final quality assessment

---

## 10. Success Criteria

### Compliance Checkpoints

**Technical Standards:**
- [ ] All functions ≤15 lines, ≤4 parameters, ≤4 branches
- [ ] Import qualification patterns applied consistently
- [ ] Zero record-dot syntax, full lens integration
- [ ] Complete Haddock documentation with examples

**Architectural Quality:**
- [ ] Clear single responsibility per module
- [ ] Specialized sub-modules with focused concerns
- [ ] Rich error types with comprehensive validation
- [ ] Clean interfaces and minimal coupling

**Testing Excellence:**
- [ ] ≥80% test coverage across all modules
- [ ] Unit/property/integration/golden test coverage
- [ ] All error conditions tested
- [ ] Build system integration validated

**Documentation Standard:**
- [ ] Comprehensive module-level documentation
- [ ] All public functions documented with examples
- [ ] Architecture and design decisions explained
- [ ] Error handling patterns documented

---

**Next Step:** Execute comprehensive implementation following `refactor/implement.md`