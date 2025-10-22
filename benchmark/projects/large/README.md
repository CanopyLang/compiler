# Large Test Project

A comprehensive social media-style application with complex module dependencies and multi-level directory structure.

## Stats

- **Modules:** 13
- **Lines of Code:** 1,086
- **Dependencies:** elm/core, elm/html

## Structure

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

## Module Dependency Graph

```
Main.can
├── Models/
│   ├── User.can
│   │   └── Exports: User, Role(..), defaultUser, isAdmin, isModerator, hasPermission, fullName
│   ├── Post.can
│   │   └── Exports: Post, Category(..), defaultPost, isPublished, canEdit, categoryToString
│   └── Comment.can
│       └── Exports: Comment, defaultComment, canDelete, isEdited
│
├── Logic/
│   ├── Auth.can
│   │   ├── → Models.User
│   │   └── Exports: login, logout, register, validatePassword, validateEmail
│   ├── Validation.can
│   │   ├── → Models.Post, Models.Comment
│   │   └── Exports: validatePost, validateComment, ValidationError(..)
│   └── API.can
│       ├── → Models.Post, Models.User
│       └── Exports: fetchPosts, fetchUser, createPost, updatePost, deletePost
│
├── Views/
│   ├── UserView.can
│   │   ├── → Models.User
│   │   └── Exports: viewUser, viewUserCard, viewUserList
│   ├── PostView.can
│   │   ├── → Models.Post, Utils.StringUtils, Utils.DateUtils
│   │   └── Exports: viewPost, viewPostCard, viewPostList
│   └── CommentView.can
│       ├── → Models.Comment, Utils.DateUtils
│       └── Exports: viewComment, viewCommentList
│
└── Utils/
    ├── StringUtils.can
    │   └── Exports: capitalize, slugify, ellipsis, wordCount, readingTime
    ├── ListUtils.can
    │   └── Exports: chunk, unique, groupBy, findBy, removeAt
    └── DateUtils.can
        └── Exports: formatTimestamp, timeAgo, isToday, daysSince
```

## Features

### Data Models

- **User:** Complete user profile with roles (Admin, Moderator, RegularUser, Guest)
- **Post:** Blog-style posts with categories, tags, and engagement metrics
- **Comment:** Threaded comments with likes/dislikes and flagging

### Authentication & Authorization

- Login/logout functionality
- User registration with validation
- Role-based permissions
- Email and password validation

### Business Logic

- Post creation, updating, and publishing workflows
- Comprehensive validation for posts and comments
- API interaction layer
- Complex filtering and sorting

### Views

- User profile and list views
- Post detail and card views
- Comment thread rendering
- Dynamic category filtering

### Utilities

- **String:** Capitalize, slugify, ellipsis, word count, reading time
- **List:** Chunking, uniqueness, grouping, finding, removal
- **Date:** Formatting, time-ago display, date comparisons

## Compile

```bash
stack exec -- canopy make src/Main.can --output=/tmp/large.js
```

## What It Tests

### Compilation Complexity

- Multi-level directory structure (Models/, Views/, Logic/, Utils/)
- 13 interconnected modules
- Complex import graphs with multiple dependency levels
- Circular dependency avoidance

### Type System

- Custom types with multiple constructors
- Type aliases with nested structures
- Qualified type references (Models.User.Role)
- Maybe types and Result types
- Record update syntax

### Module System

- Explicit module exports
- Qualified imports
- Module namespacing with dots (Models.User)
- Cross-directory imports

### Language Features

- Pattern matching on custom types
- Let bindings
- Record updates
- List operations (map, filter, foldl)
- String manipulation
- Arithmetic operations

### Performance Characteristics

This project is designed to stress-test:
- Module loading and dependency resolution
- Type inference across large codebases
- Memory usage with many type definitions
- Compilation time scaling with code size
- Import graph traversal efficiency

## Expected Compilation Time

- **First compile:** 3-10 seconds (full dependency resolution)
- **Incremental:** < 3 seconds (cached dependencies)
- **Peak memory:** 100-200 MB

*Times vary based on system performance*
