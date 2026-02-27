{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | WebIDL Abstract Syntax Tree
--
-- Represents the complete WebIDL grammar as defined by WHATWG.
-- Reference: https://webidl.spec.whatwg.org/
--
-- @since 0.20.0
module WebIDL.AST
  ( -- * Top-level definitions
    Definition(..)
  , Definitions

    -- * Interface types
  , Interface(..)
  , InterfaceMember(..)
  , PartialInterface(..)
  , Mixin(..)
  , MixinMember(..)

    -- * Operations and attributes
  , Operation(..)
  , Attribute(..)
  , Const(..)
  , Constructor(..)

    -- * Arguments
  , Argument(..)
  , DefaultValue(..)

    -- * Dictionaries
  , Dictionary(..)
  , DictionaryMember(..)

    -- * Enums and typedefs
  , IDLEnum(..)
  , Typedef(..)
  , Callback(..)
  , CallbackInterface(..)

    -- * Types
  , IDLType(..)
  , PrimitiveType(..)
  , StringType(..)
  , BufferType(..)

    -- * Extended attributes
  , ExtendedAttribute(..)
  , ExtendedAttributes

    -- * Modifiers
  , Special(..)
  , Inheritance(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

-- | Collection of definitions (a WebIDL file)
type Definitions = [Definition]

-- | Collection of extended attributes
type ExtendedAttributes = [ExtendedAttribute]

-- | Top-level WebIDL definition
data Definition
  = DefInterface !Interface
  | DefPartialInterface !PartialInterface
  | DefMixin !Mixin
  | DefPartialMixin !Mixin
  | DefDictionary !Dictionary
  | DefPartialDictionary !Dictionary
  | DefEnum !IDLEnum
  | DefTypedef !Typedef
  | DefCallback !Callback
  | DefCallbackInterface !CallbackInterface
  | DefIncludes !Text !Text  -- target includes mixin
  | DefNamespace !Text ![InterfaceMember]
  | DefPartialNamespace !Text ![InterfaceMember]
  deriving (Eq, Show, Generic)

-- | WebIDL interface definition
data Interface = Interface
  { intfExtended :: !ExtendedAttributes
  , intfName :: !Text
  , intfInherits :: !(Maybe Inheritance)
  , intfMembers :: ![InterfaceMember]
  } deriving (Eq, Show, Generic)

-- | Partial interface definition
data PartialInterface = PartialInterface
  { partialIntfExtended :: !ExtendedAttributes
  , partialIntfName :: !Text
  , partialIntfMembers :: ![InterfaceMember]
  } deriving (Eq, Show, Generic)

-- | Interface member types
data InterfaceMember
  = IMConst !Const
  | IMOperation !Operation
  | IMAttribute !Attribute
  | IMConstructor !Constructor
  | IMStringifier !(Maybe Attribute)
  | IMStaticMember !InterfaceMember
  | IMIterable !IDLType !(Maybe IDLType)
  | IMAsyncIterable !IDLType !(Maybe IDLType) ![Argument]
  | IMMaplike !IDLType !IDLType !Bool  -- key, value, readonly
  | IMSetlike !IDLType !Bool           -- value, readonly
  deriving (Eq, Show, Generic)

-- | Interface mixin definition
data Mixin = Mixin
  { mixinExtended :: !ExtendedAttributes
  , mixinName :: !Text
  , mixinMembers :: ![MixinMember]
  } deriving (Eq, Show, Generic)

-- | Mixin member types
data MixinMember
  = MMConst !Const
  | MMOperation !Operation
  | MMAttribute !Attribute
  | MMStringifier !(Maybe Attribute)
  deriving (Eq, Show, Generic)

-- | Operation (method) definition
data Operation = Operation
  { opExtended :: !ExtendedAttributes
  , opSpecial :: !(Maybe Special)
  , opReturnType :: !IDLType
  , opName :: !(Maybe Text)
  , opArguments :: ![Argument]
  } deriving (Eq, Show, Generic)

-- | Attribute definition
data Attribute = Attribute
  { attrExtended :: !ExtendedAttributes
  , attrReadonly :: !Bool
  , attrInherit :: !Bool
  , attrType :: !IDLType
  , attrName :: !Text
  } deriving (Eq, Show, Generic)

-- | Constant definition
data Const = Const
  { constExtended :: !ExtendedAttributes
  , constType :: !IDLType
  , constName :: !Text
  , constValue :: !DefaultValue
  } deriving (Eq, Show, Generic)

-- | Constructor definition
data Constructor = Constructor
  { ctorExtended :: !ExtendedAttributes
  , ctorArguments :: ![Argument]
  } deriving (Eq, Show, Generic)

-- | Operation argument
data Argument = Argument
  { argExtended :: !ExtendedAttributes
  , argOptional :: !Bool
  , argType :: !IDLType
  , argVariadic :: !Bool
  , argName :: !Text
  , argDefault :: !(Maybe DefaultValue)
  } deriving (Eq, Show, Generic)

-- | Default values for arguments and dictionary members
data DefaultValue
  = DVNull
  | DVBool !Bool
  | DVInteger !Integer
  | DVFloat !Double
  | DVString !Text
  | DVEmptySequence
  | DVEmptyDictionary
  | DVIdentifier !Text
  deriving (Eq, Show, Generic)

-- | Dictionary definition
data Dictionary = Dictionary
  { dictExtended :: !ExtendedAttributes
  , dictName :: !Text
  , dictInherits :: !(Maybe Inheritance)
  , dictMembers :: ![DictionaryMember]
  } deriving (Eq, Show, Generic)

-- | Dictionary member
data DictionaryMember = DictionaryMember
  { dmExtended :: !ExtendedAttributes
  , dmRequired :: !Bool
  , dmType :: !IDLType
  , dmName :: !Text
  , dmDefault :: !(Maybe DefaultValue)
  } deriving (Eq, Show, Generic)

-- | Enum definition
data IDLEnum = IDLEnum
  { enumExtended :: !ExtendedAttributes
  , enumName :: !Text
  , enumValues :: ![Text]
  } deriving (Eq, Show, Generic)

-- | Typedef definition
data Typedef = Typedef
  { typedefExtended :: !ExtendedAttributes
  , typedefType :: !IDLType
  , typedefName :: !Text
  } deriving (Eq, Show, Generic)

-- | Callback definition
data Callback = Callback
  { cbExtended :: !ExtendedAttributes
  , cbName :: !Text
  , cbReturnType :: !IDLType
  , cbArguments :: ![Argument]
  } deriving (Eq, Show, Generic)

-- | Callback interface definition
data CallbackInterface = CallbackInterface
  { cbiExtended :: !ExtendedAttributes
  , cbiName :: !Text
  , cbiMembers :: ![InterfaceMember]
  } deriving (Eq, Show, Generic)

-- | WebIDL type
data IDLType
  = TyPrimitive !PrimitiveType
  | TyString !StringType
  | TyBuffer !BufferType
  | TyIdentifier !Text
  | TySequence !IDLType
  | TyFrozenArray !IDLType
  | TyObservableArray !IDLType
  | TyRecord !StringType !IDLType
  | TyPromise !IDLType
  | TyUnion ![IDLType]
  | TyNullable !IDLType
  | TyAny
  | TyVoid
  | TyUndefined
  | TyObject
  | TySymbol
  deriving (Eq, Show, Generic)

-- | Primitive types
data PrimitiveType
  = PrimBoolean
  | PrimByte
  | PrimOctet
  | PrimShort
  | PrimUnsignedShort
  | PrimLong
  | PrimUnsignedLong
  | PrimLongLong
  | PrimUnsignedLongLong
  | PrimFloat
  | PrimUnrestrictedFloat
  | PrimDouble
  | PrimUnrestrictedDouble
  | PrimBigint
  deriving (Eq, Show, Generic)

-- | String types
data StringType
  = StrDOMString
  | StrByteString
  | StrUSVString
  deriving (Eq, Show, Generic)

-- | Buffer/ArrayBufferView types
data BufferType
  = BufArrayBuffer
  | BufSharedArrayBuffer
  | BufDataView
  | BufInt8Array
  | BufInt16Array
  | BufInt32Array
  | BufUint8Array
  | BufUint16Array
  | BufUint32Array
  | BufUint8ClampedArray
  | BufBigInt64Array
  | BufBigUint64Array
  | BufFloat32Array
  | BufFloat64Array
  deriving (Eq, Show, Generic)

-- | Extended attribute
data ExtendedAttribute
  = EANoArgs !Text
  | EAIdent !Text !Text
  | EAIdentList !Text ![Text]
  | EAArgList !Text ![Argument]
  | EANamedArgList !Text !Text ![Argument]
  deriving (Eq, Show, Generic)

-- | Special operation types
data Special
  = SpecialGetter
  | SpecialSetter
  | SpecialDeleter
  deriving (Eq, Show, Generic)

-- | Inheritance specification
newtype Inheritance = Inheritance Text
  deriving (Eq, Show, Generic)
