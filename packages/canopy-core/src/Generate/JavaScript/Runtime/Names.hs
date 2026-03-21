{-# LANGUAGE OverloadedStrings #-}

-- | Centralized registry of well-known kernel runtime function names.
--
-- All hardcoded references to kernel-named JavaScript globals (e.g.
-- @_Utils_eq@, @_Platform_export@) are defined here as named constants.
-- This makes the runtime naming convention a single source of truth
-- rather than scattered @JsName.fromKernel@ calls across codegen modules.
--
-- The kernel naming convention produces globals of the form @_Module_name@
-- (e.g. @_Utils_eq@, @_List_Nil@, @_Platform_worker@). These names are
-- defined in the embedded @runtime.js@ and referenced by generated code.
--
-- === Usage
--
-- Import this module qualified and use the named constants:
--
-- @
-- import qualified Generate.JavaScript.Runtime.Names as KN
--
-- -- Instead of: JsName.fromKernel Name.utils "eq"
-- -- Use:        KN.utilsEq
-- @
--
-- @since 0.20.2
module Generate.JavaScript.Runtime.Names
  ( -- * Utils module
    utilsEq,
    utilsCmp,
    utilsAp,
    utilsUpdate,
    utilsChr,
    utilsTuple0,
    utilsTuple2,
    utilsTuple3,

    -- * List module
    listNil,
    listCons,
    listFromArray,

    -- * Platform module
    platformEffectManagers,
    platformCreateManager,
    platformExport,
    platformLeaf,
    platformWorker,

    -- * Debug module
    debugToAnsiString,
    debugTodo,
    debugTodoCase,

    -- * VirtualDom module
    virtualDomInit,
  )
where

import qualified Canopy.Data.Name as Name
import qualified Generate.JavaScript.Name as JsName

-- UTILS MODULE

-- | @_Utils_eq@ — structural equality check.
--
-- @since 0.20.2
utilsEq :: JsName.Name
utilsEq = JsName.fromKernel Name.utils "eq"

-- | @_Utils_cmp@ — structural comparison returning -1, 0, or 1.
--
-- @since 0.20.2
utilsCmp :: JsName.Name
utilsCmp = JsName.fromKernel Name.utils "cmp"

-- | @_Utils_ap@ — list append.
--
-- @since 0.20.2
utilsAp :: JsName.Name
utilsAp = JsName.fromKernel Name.utils "ap"

-- | @_Utils_update@ — record update (shallow copy with field override).
--
-- @since 0.20.2
utilsUpdate :: JsName.Name
utilsUpdate = JsName.fromKernel Name.utils "update"

-- | @_Utils_chr@ — wrap a string as a Char value.
--
-- @since 0.20.2
utilsChr :: JsName.Name
utilsChr = JsName.fromKernel Name.utils "chr"

-- | @_Utils_Tuple0@ — the unit value in dev mode.
--
-- @since 0.20.2
utilsTuple0 :: JsName.Name
utilsTuple0 = JsName.fromKernel Name.utils "Tuple0"

-- | @_Utils_Tuple2@ — 2-tuple constructor.
--
-- @since 0.20.2
utilsTuple2 :: JsName.Name
utilsTuple2 = JsName.fromKernel Name.utils "Tuple2"

-- | @_Utils_Tuple3@ — 3-tuple constructor.
--
-- @since 0.20.2
utilsTuple3 :: JsName.Name
utilsTuple3 = JsName.fromKernel Name.utils "Tuple3"

-- LIST MODULE

-- | @_List_Nil@ — empty list constructor.
--
-- @since 0.20.2
listNil :: JsName.Name
listNil = JsName.fromKernel Name.list "Nil"

-- | @_List_Cons@ — two-argument cons constructor. Used to inline small list
-- literals without an intermediate JS array allocation.
--
-- @since 0.19.2
listCons :: JsName.Name
listCons = JsName.fromKernel Name.list "Cons"

-- | @_List_fromArray@ — convert JS array to linked list.
--
-- @since 0.20.2
listFromArray :: JsName.Name
listFromArray = JsName.fromKernel Name.list "fromArray"

-- PLATFORM MODULE

-- | @_Platform_effectManagers@ — global effect manager registry object.
--
-- @since 0.20.2
platformEffectManagers :: JsName.Name
platformEffectManagers = JsName.fromKernel Name.platform "effectManagers"

-- | @_Platform_createManager@ — register an effect manager.
--
-- @since 0.20.2
platformCreateManager :: JsName.Name
platformCreateManager = JsName.fromKernel Name.platform "createManager"

-- | @_Platform_export@ — export trie builder for @scope['Elm']@.
--
-- @since 0.20.2
platformExport :: JsName.Name
platformExport = JsName.fromKernel Name.platform "export"

-- | @_Platform_leaf@ — leaf effect (Cmd or Sub) constructor.
--
-- @since 0.20.2
platformLeaf :: JsName.Name
platformLeaf = JsName.fromKernel Name.platform "leaf"

-- | @_Platform_worker@ — application initializer for headless programs.
--
-- @since 0.20.2
platformWorker :: JsName.Name
platformWorker = JsName.fromKernel Name.platform "worker"

-- DEBUG MODULE

-- | @_Debug_toAnsiString@ — convert a value to its ANSI string representation.
--
-- @since 0.20.2
debugToAnsiString :: JsName.Name
debugToAnsiString = JsName.fromKernel Name.debug "toAnsiString"

-- | @_Debug_todo@ — crash with a @Debug.todo@ message.
--
-- @since 0.20.2
debugTodo :: JsName.Name
debugTodo = JsName.fromKernel Name.debug "todo"

-- | @_Debug_todoCase@ — crash with a @Debug.todo@ message in a case branch.
--
-- @since 0.20.2
debugTodoCase :: JsName.Name
debugTodoCase = JsName.fromKernel Name.debug "todoCase"

-- VIRTUALDOM MODULE

-- | @_VirtualDom_init@ — initialize a browser application.
--
-- @since 0.20.2
virtualDomInit :: JsName.Name
virtualDomInit = JsName.fromKernel Name.virtualDom "init"
