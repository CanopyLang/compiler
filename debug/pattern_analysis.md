# Pattern Analysis: Expected vs Actual

## Key Differences Identified

### 1. Function Declaration Pattern

**EXPECTED:**
```javascript
var $author$project$Main$add = F2( g(x)); return f( function (f, g, x) { var $author$project$Main$compose = F3( return x * y; function (x, y) { var $author$project$Main$mul = F2(
```

**ACTUAL:**
```javascript  
var $author$project$Main$add = F2(function (x, y) { return f(g(x)); var $author$project$Main$compose = F3(function (f, g, x) { return x * y; var $author$project$Main$mul = F2(function (x, y) {
```

**Issue**: Expected shows `F2( g(x));` but actual shows `F2(function (x, y) { return f(g(x));`

### 2. Function Body Structure

**EXPECTED:** Functions appear to be using a shorthand reference syntax: `F2( g(x));`
**ACTUAL:** Functions use full function declarations: `F2(function (x, y) { ... });`

### 3. Argument Ordering in A3 Calls

**EXPECTED:** `$author$project$Main$mul(2), $author$project$Main$add(1), $author$project$Main$compose, A3(`
**ACTUAL:** `$author$project$Main$compose,$author$project$Main$add(1),$author$project$Main$mul(2), var $author$project$Main$main = $elm$html$Html$text($elm$core$String$fromInt(A3(`

**Issue**: The order of arguments is completely reversed.

## Root Cause Analysis

The fundamental issue is not spacing - it's that we're generating completely different JavaScript structures:

1. **Function Reference vs Function Declaration**: Expected uses function references, actual uses inline function declarations
2. **Argument Order**: The arguments to A3 calls are in reverse order  
3. **Function Syntax**: Expected uses compact syntax, actual uses verbose syntax

This suggests the issue is in the Expression generation logic, not just the Builder formatting.