# Canopy Benchmark Test Projects

This directory contains test projects of varying sizes for performance benchmarking of the Canopy compiler.

## Project Overview

| Project | Modules | Lines of Code | Description |
|---------|---------|---------------|-------------|
| Small   | 1       | 10           | Minimal HTML application |
| Medium  | 4       | 260          | Multi-module blog application |
| Large   | 13      | 1,086        | Complex multi-module application |

## Small Project

**Location:** `small/`

**Structure:**
```
small/
├── canopy.json
└── src/
    └── Main.canopy
```

**Description:**
A minimal "Hello World" application using Html. Tests basic compilation without module dependencies.

**Compile Command:**
```bash
cd small && stack exec -- canopy make src/Main.canopy --output=/tmp/small.js
```

**Expected Compilation Time:** < 1 second

**Use Cases:**
- Baseline compilation performance
- Minimal overhead testing
- Quick sanity checks

---

## Medium Project

**Location:** `medium/`

**Structure:**
```
medium/
├── canopy.json
└── src/
    ├── Main.can          (92 lines)
    ├── Types.can         (49 lines)
    ├── Utils.can         (53 lines)
    └── Logic.can         (66 lines)
```

**Description:**
A blog-style application with type definitions, utility functions, and business logic. Features:
- User and Post data types
- String utilities (capitalize, truncate, format)
- Post management logic (create, update, like)
- Simple HTML rendering

**Module Dependencies:**
```
Main.can
├── Types.can (no dependencies)
├── Utils.can (no dependencies)
└── Logic.can
    └── Types.can
```

**Compile Command:**
```bash
cd medium && stack exec -- canopy make src/Main.can --output=/tmp/medium.js
```

**Expected Compilation Time:** 1-3 seconds

**Use Cases:**
- Module import resolution testing
- Type inference across modules
- Realistic small-to-medium application compilation

---

## Large Project

**Location:** `large/`

**Structure:**
```
large/
├── canopy.json
└── src/
    ├── Main.can (221 lines)
    ├── Models/
    │   ├── User.can (69 lines)
    │   ├── Post.can (78 lines)
    │   └── Comment.can (44 lines)
    ├── Views/
    │   ├── UserView.can (71 lines)
    │   ├── PostView.can (75 lines)
    │   └── CommentView.can (32 lines)
    ├── Logic/
    │   ├── Auth.can (77 lines)
    │   ├── Validation.can (93 lines)
    │   └── API.can (70 lines)
    └── Utils/
        ├── StringUtils.can (66 lines)
        ├── ListUtils.can (91 lines)
        └── DateUtils.can (51 lines)
```

**Description:**
A comprehensive social media-style application with complex module dependencies. Features:
- Multi-level directory structure
- Custom data types (User, Post, Comment)
- Authentication and validation logic
- View components for rendering
- Utility functions for strings, lists, and dates

**Module Dependency Graph:**
```
Main.can
├── Models/
│   ├── User.can
│   ├── Post.can
│   └── Comment.can
├── Logic/
│   ├── Auth.can → Models.User
│   ├── Validation.can → Models.Post, Models.Comment
│   └── API.can → Models.Post, Models.User
├── Views/
│   ├── UserView.can → Models.User
│   ├── PostView.can → Models.Post, Utils.StringUtils, Utils.DateUtils
│   └── CommentView.can → Models.Comment, Utils.DateUtils
└── Utils/
    ├── StringUtils.can
    ├── ListUtils.can
    └── DateUtils.can
```

**Compile Command:**
```bash
cd large && stack exec -- canopy make src/Main.can --output=/tmp/large.js
```

**Expected Compilation Time:** 3-10 seconds (depending on system)

**Use Cases:**
- Complex dependency resolution
- Multi-directory module loading
- Type inference performance with large codebases
- Real-world application compilation patterns

---

## Running Benchmarks

### Individual Project Compilation

```bash
# Small project
cd benchmark/projects/small
time stack exec -- canopy make src/Main.canopy --output=/tmp/small.js

# Medium project
cd benchmark/projects/medium
time stack exec -- canopy make src/Main.can --output=/tmp/medium.js

# Large project
cd benchmark/projects/large
time stack exec -- canopy make src/Main.can --output=/tmp/large.js
```

### Batch Testing

```bash
# From the benchmark/projects directory
for project in small medium large; do
  echo "Testing $project..."
  cd $project
  if [ "$project" = "small" ]; then
    time stack exec -- canopy make src/Main.canopy --output=/tmp/${project}.js
  else
    time stack exec -- canopy make src/Main.can --output=/tmp/${project}.js
  fi
  cd ..
  echo ""
done
```

## Performance Metrics to Track

When benchmarking, consider measuring:

1. **Compilation Time**
   - Total time from invocation to completion
   - Time per module
   - Time per line of code

2. **Memory Usage**
   - Peak memory consumption
   - Memory per module
   - Memory growth rate

3. **Module Loading**
   - Time to resolve dependencies
   - Time to parse modules
   - Time to type-check

4. **Scalability**
   - How compilation time scales with code size
   - How memory usage scales with module count
   - Impact of dependency depth

## Expected Performance Characteristics

Based on typical compiler performance:

| Metric | Small | Medium | Large |
|--------|-------|--------|-------|
| Modules | 1 | 4 | 13 |
| Lines | 10 | 260 | 1,086 |
| Expected Time | < 1s | 1-3s | 3-10s |
| Memory (est.) | < 50MB | 50-100MB | 100-200MB |

*Note: These are rough estimates and will vary based on system performance and compiler optimizations.*

## Extending the Test Suite

To add new test projects:

1. Create a new directory under `benchmark/projects/`
2. Add a `canopy.json` configuration file
3. Create your source files under `src/`
4. Test compilation: `stack exec -- canopy make src/Main.can --output=/tmp/test.js`
5. Update this README with project details

## Troubleshooting

### Common Issues

**Issue:** "ImportNotFound" error
- **Solution:** Ensure all imported modules exist and module names match file names

**Issue:** "DuplicateCtor" error
- **Solution:** Check for naming conflicts between type aliases and type constructors

**Issue:** "NotFoundVar" error
- **Solution:** Verify that functions are exposed in module definitions

### Debugging Tips

1. Compile with verbose output to see module loading order
2. Check canopy.json source-directories configuration
3. Verify module names match file paths
4. Ensure all exposed functions are listed in module definitions
