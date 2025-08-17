# /todo - Automated Todo Processor Command

This command automatically processes the next unchecked item from the main todo.md checklist.

## Usage
When called with `/todo`, this command:
1. Finds the next unchecked item in `/home/quinten/fh/canopy/todo.md`
2. Executes the appropriate action (`/refactor FILENAME` or `/test FILENAME`)
3. Continues until completely done with no exceptions
4. Marks the checkbox as completed when finished

## Current Item Processing

### Finding Next Item
Looking for next unchecked item in todo.md...

```bash
# Find the first unchecked item
grep -n "^- \[ \]" /home/quinten/fh/canopy/todo.md | head -1
```

### Processing Logic
1. **Parse Command**: Extract `/refactor FILENAME` or `/test FILENAME` from checklist item
2. **Execute Action**: Run appropriate agent with specialized tools
3. **Validate**: Ensure completion meets CLAUDE.md standards
4. **Mark Complete**: Update checkbox from `- [ ]` to `- [x]`

## Next Action Required

The next unchecked item from todo.md is:

**`/refactor /home/quinten/fh/canopy/builder/src/Build.hs`** - 59-line function, 10 parameters, architectural debt

### Execution Plan:
1. **Analyze**: Use `analyze-architecture` agent to assess violations
2. **Refactor**: Use `validate-functions` agent to decompose oversized functions
3. **Modularize**: Split into focused sub-modules following CLAUDE.md
4. **Validate**: Ensure ≤15 lines, ≤4 parameters, proper lens usage
5. **Test**: Run `make build && make test` to verify functionality

### Agent Command:
```
Task(
  subagent_type="validate-functions",
  description="Refactor Build.hs critical violations", 
  prompt="Refactor /home/quinten/fh/canopy/builder/src/Build.hs to fix critical CLAUDE.md violations:

1. CRITICAL: checkModule function (59 lines) - violates 15-line limit
2. CRITICAL: checkDepsHelp function (10 parameters) - violates 4-parameter limit  
3. URGENT: fromPaths function (41 lines) - violates 15-line limit
4. URGENT: crawlModule function (37 lines) - violates 15-line limit

Requirements:
- Decompose all functions to ≤15 lines
- Reduce parameters to ≤4 using record types
- Add lens support for all records
- Split into focused sub-modules if needed
- Maintain all existing functionality
- Ensure tests pass after refactoring

Execute complete refactoring with no exceptions until fully CLAUDE.md compliant."
)
```

## Progress Tracking

Once the current item is completed:
1. Mark `- [x]` in todo.md line for Build.hs refactoring
2. Automatically find next unchecked item
3. Continue processing until all items completed

## Success Criteria

Each item is only marked complete when:
- ✅ All function size violations fixed (≤15 lines)
- ✅ All parameter violations fixed (≤4 parameters)  
- ✅ All architectural violations resolved
- ✅ Tests pass with `make test`
- ✅ Build succeeds with `make build`
- ✅ No regressions introduced