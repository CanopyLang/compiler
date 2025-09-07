# Batch Commit Orchestration Command

**Task:** Execute systematic commit batching for current working directory changes with intelligent categorization and professional commit messages.

- **Scope**: Dynamic analysis and logical grouping of any current changes
- **Standards**: Conventional commit format with technical accuracy
- **Process**: Analysis → Categorization → Batch Creation → Execution
- **Quality**: No AI attribution, professional technical descriptions

---

## 🚀 COMMIT ORCHESTRATION OVERVIEW

### Mission Statement

Analyze current working directory changes and transform them into a series of logical, professionally crafted commits that accurately reflect the technical work accomplished. Each commit follows conventional commit standards and provides clear technical context without any AI attribution.

### Core Principles

- **Dynamic Analysis**: Analyze whatever changes exist when command is executed
- **Intelligent Categorization**: Group related changes for coherent commit history
- **Technical Accuracy**: Commit messages reflect actual technical accomplishments
- **Professional Standards**: Conventional commit format with clear descriptions
- **Clean Attribution**: No AI or Claude authorship references

---

## 🔍 PHASE 1: DYNAMIC CHANGE ANALYSIS

### Change Discovery and Categorization

**Mission**: Analyze current working directory status and intelligently categorize all changes.

**Analysis Protocol**:

1. **Discover All Changes**:
   ```bash
   # Get comprehensive change overview
   git status --porcelain
   git diff --name-only
   git diff --cached --name-only
   git ls-files --others --exclude-standard
   ```

2. **Categorize by File Patterns**:
   - **Test Changes**: `test/`, `*Test.hs`, `*Spec.hs`, `*.golden`, `*.js` (in test directories)
   - **Compiler Changes**: `compiler/src/`, `*.hs` (in compiler directories)
   - **Builder Changes**: `builder/src/`, build system files
   - **Terminal Changes**: `terminal/`, CLI-related files
   - **Documentation**: `*.md`, `README*`, `docs/`, `CHANGELOG*`
   - **Build System**: `*.cabal`, `Makefile`, `stack.yaml`, `package.json`
   - **Scripts**: `scripts/`, executable files, automation
   - **Configuration**: `.claude/`, `.gitignore`, `.github/`, config files

3. **Analyze Change Types**:
   ```bash
   # Detect change patterns in diffs
   git diff | grep -E '(\+.*TODO|\+.*FIXME|\+.*test|\+.*Test|\+.*fix|\+.*Fix)'
   ```

**Deliverables**:
- Complete inventory of all changed files with categories
- Change type analysis (new features, fixes, tests, docs, refactoring)
- Logical grouping recommendations for commit batches

---

## 🏗️ PHASE 2: INTELLIGENT COMMIT BATCH CREATION

### Dynamic Batch Generation Protocol

**Mission**: Create logical commit batches based on discovered changes with appropriate commit messages.

### Test-Related Changes Batch

**Criteria**: Files matching test patterns or containing test-related content

**Command Generation**:
```bash
# Dynamically add test files
git add $(git status --porcelain | grep -E '(test/|Test\.hs|Spec\.hs|\.golden|test.*\.js)' | awk '{print $2}')

# Generate commit message based on test types found
if git diff --cached --name-only | grep -q 'Golden.*Test'; then
  COMMIT_MSG="test: implement golden test suite additions"
elif git diff --cached --name-only | grep -q 'Test\.hs'; then
  COMMIT_MSG="test: add unit test coverage"
elif git diff --cached --name-only | grep -q '\.golden\|\.js.*test'; then
  COMMIT_MSG="test: add test reference files"
else
  COMMIT_MSG="test: enhance test infrastructure"
fi

git commit -m "$COMMIT_MSG

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nTotal files: " $1}')"
```

### Compiler Enhancement Batch

**Criteria**: Files in compiler/src/ or core compiler functionality

**Command Generation**:
```bash
# Add compiler-related files
git add $(git status --porcelain | grep -E 'compiler/src/' | awk '{print $2}')

# Analyze for specific compiler areas
if git diff --cached --name-only | grep -q 'Parse/'; then
  SCOPE="parser"
  DESC="enhance parsing functionality"
elif git diff --cached --name-only | grep -q 'Type/'; then
  SCOPE="type-system"
  DESC="improve type system operations"
elif git diff --cached --name-only | grep -q 'Generate/'; then
  SCOPE="codegen"
  DESC="enhance code generation"
elif git diff --cached --name-only | grep -q 'Data/'; then
  SCOPE="data-structures"
  DESC="improve core data structures"
else
  SCOPE="compiler"
  DESC="enhance compiler functionality"
fi

git commit -m "feat($SCOPE): $DESC

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nFiles modified: " $1}')"
```

### Build System and Scripts Batch

**Criteria**: Build configuration, scripts, automation files

**Command Generation**:
```bash
# Add build system files
git add $(git status --porcelain | grep -E '(Makefile|\.cabal|stack\.yaml|scripts/|package\.json)' | awk '{print $2}')

if [ $(git diff --cached --name-only | wc -l) -gt 0 ]; then
  if git diff --cached --name-only | grep -q 'scripts/'; then
    git commit -m "build(scripts): add automation and utility scripts

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nScript files: " $1}')"
  else
    git commit -m "build: update build system configuration

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nConfiguration files: " $1}')"
  fi
fi
```

### Documentation Batch

**Criteria**: Documentation files, README, markdown files

**Command Generation**:
```bash
# Add documentation files
git add $(git status --porcelain | grep -E '(\.md|README|docs/|CHANGELOG)' | awk '{print $2}')

if [ $(git diff --cached --name-only | wc -l) -gt 0 ]; then
  git commit -m "docs: update project documentation

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nDocumentation files: " $1}')"
fi
```

### Terminal/CLI Improvements Batch

**Criteria**: Terminal interface, CLI functionality

**Command Generation**:
```bash
# Add terminal-related files
git add $(git status --porcelain | grep -E '(terminal/|CLI|cli)' | awk '{print $2}')

if [ $(git diff --cached --name-only | wc -l) -gt 0 ]; then
  # Analyze for fixes vs enhancements
  if git diff --cached | grep -q -E '(fix|Fix|bug|Bug|error|Error)'; then
    git commit -m "fix(terminal): resolve CLI interface issues

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nTerminal files: " $1}')"
  else
    git commit -m "feat(terminal): enhance CLI functionality

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nTerminal files: " $1}')"
  fi
fi
```

### Configuration and Miscellaneous Batch

**Criteria**: Configuration files, project setup, miscellaneous changes

**Command Generation**:
```bash
# Add remaining files
git add $(git status --porcelain | awk '{print $2}')

if [ $(git diff --cached --name-only | wc -l) -gt 0 ]; then
  git commit -m "chore: update project configuration and miscellaneous files

$(git diff --cached --name-only | sed 's/^/- /')
$(git log --format=format: --name-only -1 | wc -l | awk '{print "\nMiscellaneous files: " $1}')"
fi
```

---

## ⚙️ PHASE 3: COMMIT MESSAGE INTELLIGENCE

### Dynamic Message Generation Rules

**Message Structure Template**:
```
{type}({scope}): {description}

{file_list}
{change_summary}
{impact_description}
```

### Commit Type Detection Logic

**Automatic Type Classification**:
- **feat**: New files, significant additions, new functionality
- **fix**: Bug fixes, error corrections, issue resolutions
- **test**: Test files, test infrastructure, testing improvements
- **build**: Build files, scripts, configuration, tooling
- **docs**: Documentation, README files, comments
- **refactor**: Code reorganization without functional changes
- **perf**: Performance improvements, optimizations
- **chore**: Maintenance, configuration, cleanup

### Scope Detection Patterns

**Dynamic Scope Assignment**:
```bash
# Extract scope based on file paths
if echo "$FILES" | grep -q "compiler/src/Parse/"; then SCOPE="parser"
elif echo "$FILES" | grep -q "compiler/src/Type/"; then SCOPE="type-system"  
elif echo "$FILES" | grep -q "compiler/src/Generate/"; then SCOPE="codegen"
elif echo "$FILES" | grep -q "compiler/src/Data/"; then SCOPE="data-structures"
elif echo "$FILES" | grep -q "terminal/"; then SCOPE="terminal"
elif echo "$FILES" | grep -q "builder/"; then SCOPE="builder"
elif echo "$FILES" | grep -q "test/"; then SCOPE="test"
elif echo "$FILES" | grep -q "scripts/"; then SCOPE="scripts"
else SCOPE="core"
fi
```

### Description Generation Intelligence

**Content-Based Descriptions**:
```bash
# Analyze diff content for better descriptions
if git diff --cached | grep -q "TODO.*implement"; then
  DESC_SUFFIX="and implement pending functionality"
elif git diff --cached | grep -q "fix\|Fix\|error\|Error"; then
  DESC_SUFFIX="and resolve identified issues"
elif git diff --cached | grep -q "test\|Test\|spec\|Spec"; then
  DESC_SUFFIX="and expand test coverage"
elif git diff --cached | grep -q "doc\|Doc\|comment\|Comment"; then
  DESC_SUFFIX="and improve documentation"
else
  DESC_SUFFIX="and enhance functionality"
fi
```

---

## 🔄 PHASE 4: AUTOMATED EXECUTION WORKFLOW

### Complete Batch Processing Script

**Mission**: Execute all commit batches in logical sequence with validation.

**Full Automation Command**:
```bash
#!/bin/bash

# Comprehensive batch commit execution
echo "🚀 Starting intelligent batch commit process..."

# Check if there are changes to commit
if [ -z "$(git status --porcelain)" ]; then
  echo "✅ No changes to commit"
  exit 0
fi

echo "📊 Analyzing changes..."
TOTAL_FILES=$(git status --porcelain | wc -l)
echo "Found $TOTAL_FILES changed files"

# Test files batch
echo "🧪 Processing test-related changes..."
TEST_FILES=$(git status --porcelain | grep -E '(test/|Test\.hs|Spec\.hs|\.golden|test.*\.js)' | awk '{print $2}')
if [ -n "$TEST_FILES" ]; then
  echo "$TEST_FILES" | xargs git add
  COMMIT_MSG="test: enhance test infrastructure and coverage"
  git commit -m "$COMMIT_MSG

$(echo "$TEST_FILES" | sed 's/^/- /')

Files committed: $(echo "$TEST_FILES" | wc -l)"
  echo "✅ Committed test changes"
fi

# Compiler files batch
echo "⚙️ Processing compiler changes..."
COMPILER_FILES=$(git status --porcelain | grep -E 'compiler/src/' | awk '{print $2}')
if [ -n "$COMPILER_FILES" ]; then
  echo "$COMPILER_FILES" | xargs git add
  
  # Determine scope and description
  if echo "$COMPILER_FILES" | grep -q 'Data/'; then
    SCOPE="data-structures"
    DESC="enhance core data structure implementations"
  elif echo "$COMPILER_FILES" | grep -q 'Parse/'; then
    SCOPE="parser"
    DESC="improve parsing functionality"
  elif echo "$COMPILER_FILES" | grep -q 'Type/'; then
    SCOPE="type-system"
    DESC="enhance type system operations"
  else
    SCOPE="compiler"
    DESC="improve compiler functionality"
  fi
  
  git commit -m "feat($SCOPE): $DESC

$(echo "$COMPILER_FILES" | sed 's/^/- /')

Files committed: $(echo "$COMPILER_FILES" | wc -l)"
  echo "✅ Committed compiler changes"
fi

# Build system and scripts batch
echo "🔧 Processing build system changes..."
BUILD_FILES=$(git status --porcelain | grep -E '(Makefile|\.cabal|stack\.yaml|scripts/|package\.json)' | awk '{print $2}')
if [ -n "$BUILD_FILES" ]; then
  echo "$BUILD_FILES" | xargs git add
  
  if echo "$BUILD_FILES" | grep -q 'scripts/'; then
    git commit -m "build(scripts): add automation and utility scripts

$(echo "$BUILD_FILES" | sed 's/^/- /')

Files committed: $(echo "$BUILD_FILES" | wc -l)"
  else
    git commit -m "build: update build system configuration

$(echo "$BUILD_FILES" | sed 's/^/- /')

Files committed: $(echo "$BUILD_FILES" | wc -l)"
  fi
  echo "✅ Committed build system changes"
fi

# Terminal/CLI batch
echo "🖥️ Processing terminal changes..."
TERMINAL_FILES=$(git status --porcelain | grep -E '(terminal/|CLI|cli)' | awk '{print $2}')
if [ -n "$TERMINAL_FILES" ]; then
  echo "$TERMINAL_FILES" | xargs git add
  
  if git diff --cached | grep -q -E '(fix|Fix|bug|Bug|error|Error)'; then
    git commit -m "fix(terminal): resolve CLI interface issues

$(echo "$TERMINAL_FILES" | sed 's/^/- /')

Files committed: $(echo "$TERMINAL_FILES" | wc -l)"
  else
    git commit -m "feat(terminal): enhance CLI functionality  

$(echo "$TERMINAL_FILES" | sed 's/^/- /')

Files committed: $(echo "$TERMINAL_FILES" | wc -l)"
  fi
  echo "✅ Committed terminal changes"
fi

# Documentation batch
echo "📚 Processing documentation changes..."
DOC_FILES=$(git status --porcelain | grep -E '(\.md|README|docs/|CHANGELOG)' | awk '{print $2}')
if [ -n "$DOC_FILES" ]; then
  echo "$DOC_FILES" | xargs git add
  git commit -m "docs: update project documentation

$(echo "$DOC_FILES" | sed 's/^/- /')

Files committed: $(echo "$DOC_FILES" | wc -l)"
  echo "✅ Committed documentation changes"
fi

# Remaining files batch
echo "📁 Processing remaining changes..."
REMAINING_FILES=$(git status --porcelain | awk '{print $2}')
if [ -n "$REMAINING_FILES" ]; then
  echo "$REMAINING_FILES" | xargs git add
  git commit -m "chore: update miscellaneous project files

$(echo "$REMAINING_FILES" | sed 's/^/- /')

Files committed: $(echo "$REMAINING_FILES" | wc -l)"
  echo "✅ Committed remaining changes"
fi

# Final status
echo "🎉 Batch commit process complete!"
echo "📊 Final repository status:"
git status --porcelain

if [ -z "$(git status --porcelain)" ]; then
  echo "✅ All changes successfully committed"
else
  echo "⚠️  Some files may still need attention"
fi

echo "📝 Recent commits:"
git log --oneline -5
```

---

## 📋 VALIDATION AND QUALITY GATES

### Pre-Commit Validation

**Mandatory Checks Before Any Commit**:
```bash
# Compilation validation
make build 2>&1 | grep -E '(error|Error)' && echo "❌ Build errors found" && exit 1

# Test validation  
make test 2>&1 | grep -E '(failed|Failed)' && echo "❌ Test failures found" && exit 1

# Sensitive data check
git diff --cached | grep -E '(password|secret|key|token)' && echo "⚠️  Potential sensitive data" && exit 1

echo "✅ Pre-commit validation passed"
```

### Post-Commit Verification

**Automatic Verification After Each Commit**:
```bash
# Verify commit message format
git log -1 --pretty=format:"%s" | grep -E '^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .+' || echo "⚠️  Commit message format may need improvement"

# Verify no uncommitted changes remain
[ -z "$(git status --porcelain)" ] && echo "✅ All changes committed" || echo "📋 Additional changes remain"

# Repository integrity check
git fsck --no-reflogs 2>/dev/null && echo "✅ Repository integrity confirmed"
```

---

## 🎯 SUCCESS CRITERIA MATRIX

### ✅ Dynamic Adaptability (100% REQUIRED)

- **Change Detection**: Accurately identifies all current working directory changes
- **Intelligent Categorization**: Groups related files for logical commit batches
- **Message Generation**: Creates appropriate commit messages based on actual changes
- **Scope Detection**: Automatically determines appropriate commit scopes and types

### ✅ Professional Quality (100% REQUIRED)

- **Conventional Commits**: All commits follow conventional commit specification
- **Technical Accuracy**: Messages accurately describe the changes made
- **No AI Attribution**: Zero references to Claude or AI assistance
- **Clean History**: Professional commit history suitable for team collaboration

### ✅ System Integration (100% REQUIRED)

- **Build Compatibility**: All commits maintain successful build status
- **Test Preservation**: No commits break existing test functionality  
- **Format Compliance**: Commits follow project formatting standards
- **Security Awareness**: No sensitive data committed to repository

---

## 🚨 EXECUTION PROTOCOL

### Manual Execution

For manual step-by-step execution:

1. **Run Change Analysis**: `git status --porcelain` to see what needs committing
2. **Execute Batch Script**: Copy and run the automation script above
3. **Verify Results**: Check `git log --oneline -10` for commit history
4. **Final Validation**: Run `git status` to confirm all changes committed

### Integration with Development Workflow  

**Daily Development Cycle**:
```bash
# At end of development session
./claude/commands/commit.md  # Run the automated batch process
git push origin $(git branch --show-current)  # Push commits when ready
```

**Feature Completion Workflow**:
```bash
# Before creating pull request
./claude/commands/commit.md  # Commit all current changes in logical batches
git push origin feature-branch  # Push for review
```

This dynamic commit orchestration command adapts to whatever changes exist in the working directory when executed, providing intelligent categorization, professional commit messages, and systematic batch processing for any development scenario.