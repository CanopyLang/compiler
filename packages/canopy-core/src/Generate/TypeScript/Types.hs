{-# LANGUAGE OverloadedStrings #-}

-- | TypeScript type intermediate representation.
--
-- Defines the 'TsType' and 'DtsDecl' types used to represent TypeScript
-- type declarations before rendering to @.d.ts@ text. This intermediate
-- representation decouples Canopy canonical types from TypeScript syntax.
--
-- @since 0.20.0
module Generate.TypeScript.Types
  ( TsType (..),
    DtsDecl (..),
  )
where

import Canopy.Data.Name (Name)

-- | TypeScript type representation.
--
-- Models the subset of TypeScript's type system needed to represent
-- Canopy module exports in @.d.ts@ declaration files.
--
-- @since 0.20.0
data TsType
  = -- | @string@
    TsString
  | -- | @number@
    TsNumber
  | -- | @boolean@
    TsBoolean
  | -- | @void@
    TsVoid
  | -- | Type variable: @A@, @B@, etc.
    TsTypeVar !Name
  | -- | @ReadonlyArray\<T\>@
    TsReadonlyArray !TsType
  | -- | Uncurried function: @(p0: A, p1: B) => C@
    TsFunction ![TsType] !TsType
  | -- | Object with readonly fields: @{ readonly x: number; ... }@
    TsObject ![(Name, TsType)]
  | -- | Union of types: @A | B | C@
    TsUnion ![TsType]
  | -- | Discriminated union variant: @{ readonly $: 'Tag'; readonly a: A }@
    TsTaggedVariant !Name ![(Name, TsType)]
  | -- | Opaque branded type: @{ readonly __brand: unique symbol }@
    TsBranded !Name ![Name]
  | -- | Object with index signature: @{ readonly x: A; [key: string]: unknown }@
    TsObjectWithIndex ![(Name, TsType)]
  | -- | Reference to another named type (possibly cross-module)
    TsNamed !Name ![TsType]
  | -- | @unknown@ for types we cannot represent
    TsUnknown
  deriving (Eq, Show)

-- | A top-level TypeScript declaration in a @.d.ts@ file.
--
-- @since 0.20.0
data DtsDecl
  = -- | @export const name: Type@
    DtsValue !Name !TsType
  | -- | @export type Name\<A, B\> = Type@
    DtsTypeAlias !Name ![Name] !TsType
  | -- | @export type Name\<A, B\> = { $ : 'Tag1'; ... } | ...@
    DtsUnionType !Name ![Name] !TsType
  | -- | @export type Name\<A, B\> = { readonly __brand: unique symbol }@
    DtsBrandedType !Name ![Name]
  deriving (Eq, Show)
