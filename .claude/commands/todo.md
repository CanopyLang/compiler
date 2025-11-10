# /todo - Automated Todo Processor Command

This command automatically processes the next unchecked item from the main todo.md checklist.

## Usage

When called with `/todo`, this command:

1. Finds the next unchecked item in `/home/quinten/fh/canopy/todo.md`
2. Executes the appropriate action (`/refactor FILENAME` or `/test FILENAME`)
3. Continues until completely done with no exceptions
4. Marks the checkbox as completed when finished
5. Validate build and tests with `make build` and `make test`
6. Commit all Changes in batches, without mentioning claude as an author

## Current Item Processing

### Finding Next Item

Looking for next unchecked item in todo.md...

```bash
# Find the first unchecked item
grep -n "^- \[ \]" /home/quinten/fh/canopy/todo.md | head -1
```

### Processing Logic

1. **Parse Command**: Extract `/refactor FILENAME` or `/test FILENAME` from checklist item
2. **Execute Action**: Run appropriate command with specialized tools
3. **Validate**: Ensure completion meets CLAUDE.md standards
4. **Validate Build and Tests**: BEFORE finishing a checklist task you should always validate that everything works with `make build` and `make test`. Everything should compile, all test should pass and no lint warnings should be given. Only then you can check of an item.
5. **Mark Complete**: Update checkbox from `- [ ]` to `- [x]`

## Dynamic Processing

### Execution Plan:

1. **Find Next Item**: Dynamically locate next unchecked item from todo.md
2. **Parse Command**: Extract `/refactor FILENAME` or `/test FILENAME` from item
3. **Analyze**: Use appropriate agent to assess violations and requirements
4. **Execute**: Run specialized refactoring/testing agents as needed
5. **Validate**: Ensure completion meets CLAUDE.md standards
6. **Test**: Run `make build && make test` to verify functionality

### Agent Selection:

The command automatically selects the appropriate agent based on task type:

- `/refactor` tasks → `validate-functions`, `analyze-architecture`, or related agents
- `/test` tasks → `validate-test-creation`, `analyze-tests`, or related agents

## Progress Tracking

For each processed item:

1. **Complete Task**: Execute until all violations resolved
2. **Mark Complete**: Update checkbox from `- [ ]` to `- [x]`
3. **Find Next**: Automatically locate next unchecked item
4. **Continue**: Process until all items completed

## Success Criteria

Each item is only marked complete when:

- ✅ All function size violations fixed (≤15 lines)
- ✅ All parameter violations fixed (≤4 parameters)
- ✅ All architectural violations resolved
- ✅ Tests pass with `make test`
- ✅ Build succeeds with `make build`
- ✅ No regressions introduced
- ✅ All changes are commited
