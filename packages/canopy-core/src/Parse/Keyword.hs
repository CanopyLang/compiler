{-# LANGUAGE BangPatterns #-}

-- | Parse.Keyword — Reserved keyword parsers.
--
-- Every Canopy keyword has a dedicated parser that matches the exact byte
-- sequence and asserts that no identifier character follows (so @letFoo@
-- is not mistaken for the keyword @let@).
--
-- The primitive kernel parsers 'k4' and 'k5' are exported so that
-- external consumers (e.g. test suites) can build keyword parsers for
-- four- and five-character words using the same mechanism.
--
-- @since 0.19.1
module Parse.Keyword
  ( type_,
    alias_,
    port_,
    ffi_,
    ability_,
    impl_,
    if_,
    then_,
    else_,
    case_,
    of_,
    let_,
    in_,
    infix_,
    left_,
    right_,
    non_,
    module_,
    import_,
    exposing_,
    as_,
    effect_,
    where_,
    command_,
    subscription_,
    foreign_,
    javascript_,
    lazy_,
    guards_,
    comparable_,
    appendable_,
    number_,
    compappend_,
    deriving_,
    k4,
    k5,
  )
where

import Data.Word (Word8)
import Foreign.Ptr (plusPtr)
import Parse.Primitives (Col, Parser, Row)
import qualified Parse.Primitives as Parse
import qualified Parse.Variable as Var

-- DECLARATIONS

-- | Match the keyword @type@ (4 chars).
--
-- @since 0.19.1
type_ :: (Row -> Col -> x) -> Parser x ()
type_ = k4 0x74 0x79 0x70 0x65

-- | Match the keyword @alias@ (5 chars).
--
-- @since 0.19.1
alias_ :: (Row -> Col -> x) -> Parser x ()
alias_ = k5 0x61 0x6C 0x69 0x61 0x73

-- | Match the keyword @port@ (4 chars).
--
-- @since 0.19.1
port_ :: (Row -> Col -> x) -> Parser x ()
port_ = k4 0x70 0x6F 0x72 0x74

-- | Match the keyword @ffi@ (3 chars).
--
-- @since 0.19.1
ffi_ :: (Row -> Col -> x) -> Parser x ()
ffi_ = k3 0x66 0x66 0x69

-- | Match the keyword @ability@ (7 chars: a-b-i-l-i-t-y).
ability_ :: (Row -> Col -> x) -> Parser x ()
ability_ = k7 0x61 0x62 0x69 0x6C 0x69 0x74 0x79

-- | Match the keyword @impl@ (4 chars: i-m-p-l).
impl_ :: (Row -> Col -> x) -> Parser x ()
impl_ = k4 0x69 0x6D 0x70 0x6C

-- IF EXPRESSIONS

-- | Match the keyword @if@ (2 chars).
--
-- @since 0.19.1
if_ :: (Row -> Col -> x) -> Parser x ()
if_ = k2 0x69 0x66

-- | Match the keyword @then@ (4 chars).
--
-- @since 0.19.1
then_ :: (Row -> Col -> x) -> Parser x ()
then_ = k4 0x74 0x68 0x65 0x6E

-- | Match the keyword @else@ (4 chars).
--
-- @since 0.19.1
else_ :: (Row -> Col -> x) -> Parser x ()
else_ = k4 0x65 0x6C 0x73 0x65

-- CASE EXPRESSIONS

-- | Match the keyword @case@ (4 chars).
--
-- @since 0.19.1
case_ :: (Row -> Col -> x) -> Parser x ()
case_ = k4 0x63 0x61 0x73 0x65

-- | Match the keyword @of@ (2 chars).
--
-- @since 0.19.1
of_ :: (Row -> Col -> x) -> Parser x ()
of_ = k2 0x6F 0x66

-- LET EXPRESSIONS

-- | Match the keyword @let@ (3 chars).
--
-- @since 0.19.1
let_ :: (Row -> Col -> x) -> Parser x ()
let_ = k3 0x6C 0x65 0x74

-- | Match the keyword @in@ (2 chars).
--
-- @since 0.19.1
in_ :: (Row -> Col -> x) -> Parser x ()
in_ = k2 0x69 0x6E

-- INFIXES

-- | Match the keyword @infix@ (5 chars).
--
-- @since 0.19.1
infix_ :: (Row -> Col -> x) -> Parser x ()
infix_ = k5 0x69 0x6E 0x66 0x69 0x78

-- | Match the keyword @left@ (4 chars), used in infix associativity declarations.
--
-- @since 0.19.1
left_ :: (Row -> Col -> x) -> Parser x ()
left_ = k4 0x6C 0x65 0x66 0x74

-- | Match the keyword @right@ (5 chars), used in infix associativity declarations.
--
-- @since 0.19.1
right_ :: (Row -> Col -> x) -> Parser x ()
right_ = k5 0x72 0x69 0x67 0x68 0x74

-- | Match the keyword @non@ (3 chars), used for non-associative infix declarations.
--
-- @since 0.19.1
non_ :: (Row -> Col -> x) -> Parser x ()
non_ = k3 0x6E 0x6F 0x6E

-- IMPORTS

-- | Match the keyword @module@ (6 chars).
--
-- @since 0.19.1
module_ :: (Row -> Col -> x) -> Parser x ()
module_ = k6 0x6D 0x6F 0x64 0x75 0x6C 0x65

-- | Match the keyword @import@ (6 chars).
--
-- @since 0.19.1
import_ :: (Row -> Col -> x) -> Parser x ()
import_ = k6 0x69 0x6D 0x70 0x6F 0x72 0x74

-- | Match the keyword @exposing@ (8 chars).
--
-- @since 0.19.1
exposing_ :: (Row -> Col -> x) -> Parser x ()
exposing_ = k8 0x65 0x78 0x70 0x6F 0x73 0x69 0x6E 0x67

-- | Match the keyword @as@ (2 chars).
--
-- @since 0.19.1
as_ :: (Row -> Col -> x) -> Parser x ()
as_ = k2 0x61 0x73

-- EFFECTS

-- | Match the keyword @effect@ (6 chars), used in effect module declarations.
--
-- @since 0.19.1
effect_ :: (Row -> Col -> x) -> Parser x ()
effect_ = k6 0x65 0x66 0x66 0x65 0x63 0x74

-- | Match the keyword @where@ (5 chars).
--
-- @since 0.19.1
where_ :: (Row -> Col -> x) -> Parser x ()
where_ = k5 0x77 0x68 0x65 0x72 0x65

-- | Match the keyword @command@ (7 chars), used in effect module declarations.
--
-- @since 0.19.1
command_ :: (Row -> Col -> x) -> Parser x ()
command_ = k7 0x63 0x6F 0x6D 0x6D 0x61 0x6E 0x64

subscription_ :: (Row -> Col -> x) -> Parser x ()
subscription_ toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos12 = plusPtr pos 12
     in if pos12 <= end
          && Parse.unsafeIndex (pos) == 0x73
          && Parse.unsafeIndex (plusPtr pos 1) == 0x75
          && Parse.unsafeIndex (plusPtr pos 2) == 0x62
          && Parse.unsafeIndex (plusPtr pos 3) == 0x73
          && Parse.unsafeIndex (plusPtr pos 4) == 0x63
          && Parse.unsafeIndex (plusPtr pos 5) == 0x72
          && Parse.unsafeIndex (plusPtr pos 6) == 0x69
          && Parse.unsafeIndex (plusPtr pos 7) == 0x70
          && Parse.unsafeIndex (plusPtr pos 8) == 0x74
          && Parse.unsafeIndex (plusPtr pos 9) == 0x69
          && Parse.unsafeIndex (plusPtr pos 10) == 0x6F
          && Parse.unsafeIndex (plusPtr pos 11) == 0x6E
          && Var.getInnerWidth pos12 end == 0
          then let !s = Parse.State src pos12 end indent row (col + 12) in cok () s
          else eerr row col toError

-- LAZY IMPORTS

-- | Match the keyword @lazy@ (4 chars).
--
-- @since 0.19.1
lazy_ :: (Row -> Col -> x) -> Parser x ()
lazy_ = k4 0x6C 0x61 0x7A 0x79

-- TYPE GUARDS

-- | Match the keyword @guards@ (6 chars), used in type guard declarations.
--
-- @since 0.19.1
guards_ :: (Row -> Col -> x) -> Parser x ()
guards_ = k6 0x67 0x75 0x61 0x72 0x64 0x73

-- SUPERTYPE BOUND KEYWORDS

-- | Match the keyword @number@ (6 chars).
number_ :: (Row -> Col -> x) -> Parser x ()
number_ = k6 0x6E 0x75 0x6D 0x62 0x65 0x72

-- | Match the keyword @comparable@ (10 chars).
comparable_ :: (Row -> Col -> x) -> Parser x ()
comparable_ toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos10 = plusPtr pos 10
     in if pos10 <= end
          && Parse.unsafeIndex (pos) == 0x63
          && Parse.unsafeIndex (plusPtr pos 1) == 0x6F
          && Parse.unsafeIndex (plusPtr pos 2) == 0x6D
          && Parse.unsafeIndex (plusPtr pos 3) == 0x70
          && Parse.unsafeIndex (plusPtr pos 4) == 0x61
          && Parse.unsafeIndex (plusPtr pos 5) == 0x72
          && Parse.unsafeIndex (plusPtr pos 6) == 0x61
          && Parse.unsafeIndex (plusPtr pos 7) == 0x62
          && Parse.unsafeIndex (plusPtr pos 8) == 0x6C
          && Parse.unsafeIndex (plusPtr pos 9) == 0x65
          && Var.getInnerWidth pos10 end == 0
          then let !s = Parse.State src pos10 end indent row (col + 10) in cok () s
          else eerr row col toError

-- | Match the keyword @appendable@ (10 chars).
appendable_ :: (Row -> Col -> x) -> Parser x ()
appendable_ toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos10 = plusPtr pos 10
     in if pos10 <= end
          && Parse.unsafeIndex (pos) == 0x61
          && Parse.unsafeIndex (plusPtr pos 1) == 0x70
          && Parse.unsafeIndex (plusPtr pos 2) == 0x70
          && Parse.unsafeIndex (plusPtr pos 3) == 0x65
          && Parse.unsafeIndex (plusPtr pos 4) == 0x6E
          && Parse.unsafeIndex (plusPtr pos 5) == 0x64
          && Parse.unsafeIndex (plusPtr pos 6) == 0x61
          && Parse.unsafeIndex (plusPtr pos 7) == 0x62
          && Parse.unsafeIndex (plusPtr pos 8) == 0x6C
          && Parse.unsafeIndex (plusPtr pos 9) == 0x65
          && Var.getInnerWidth pos10 end == 0
          then let !s = Parse.State src pos10 end indent row (col + 10) in cok () s
          else eerr row col toError

-- | Match the keyword @compappend@ (10 chars).
compappend_ :: (Row -> Col -> x) -> Parser x ()
compappend_ toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos10 = plusPtr pos 10
     in if pos10 <= end
          && Parse.unsafeIndex (pos) == 0x63
          && Parse.unsafeIndex (plusPtr pos 1) == 0x6F
          && Parse.unsafeIndex (plusPtr pos 2) == 0x6D
          && Parse.unsafeIndex (plusPtr pos 3) == 0x70
          && Parse.unsafeIndex (plusPtr pos 4) == 0x61
          && Parse.unsafeIndex (plusPtr pos 5) == 0x70
          && Parse.unsafeIndex (plusPtr pos 6) == 0x70
          && Parse.unsafeIndex (plusPtr pos 7) == 0x65
          && Parse.unsafeIndex (plusPtr pos 8) == 0x6E
          && Parse.unsafeIndex (plusPtr pos 9) == 0x64
          && Var.getInnerWidth pos10 end == 0
          then let !s = Parse.State src pos10 end indent row (col + 10) in cok () s
          else eerr row col toError

-- DERIVING KEYWORDS

-- | Match the keyword @deriving@ (8 chars).
deriving_ :: (Row -> Col -> x) -> Parser x ()
deriving_ = k8 0x64 0x65 0x72 0x69 0x76 0x69 0x6E 0x67

-- FFI KEYWORDS

-- | Match the keyword @foreign@ (7 chars), used in FFI declarations.
--
-- @since 0.19.1
foreign_ :: (Row -> Col -> x) -> Parser x ()
foreign_ = k7 0x66 0x6F 0x72 0x65 0x69 0x67 0x6E

javascript_ :: (Row -> Col -> x) -> Parser x ()
javascript_ toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos10 = plusPtr pos 10
     in if pos10 <= end
          && Parse.unsafeIndex (pos) == 0x6A
          && Parse.unsafeIndex (plusPtr pos 1) == 0x61
          && Parse.unsafeIndex (plusPtr pos 2) == 0x76
          && Parse.unsafeIndex (plusPtr pos 3) == 0x61
          && Parse.unsafeIndex (plusPtr pos 4) == 0x73
          && Parse.unsafeIndex (plusPtr pos 5) == 0x63
          && Parse.unsafeIndex (plusPtr pos 6) == 0x72
          && Parse.unsafeIndex (plusPtr pos 7) == 0x69
          && Parse.unsafeIndex (plusPtr pos 8) == 0x70
          && Parse.unsafeIndex (plusPtr pos 9) == 0x74
          && Var.getInnerWidth pos10 end == 0
          then let !s = Parse.State src pos10 end indent row (col + 10) in cok () s
          else eerr row col toError

-- KEYWORDS

-- | Low-level 2-byte keyword matcher (not exported).
--
-- @since 0.19.1
k2 :: Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k2 w1 w2 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos2 = plusPtr pos 2
     in if pos2 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Var.getInnerWidth pos2 end == 0
          then let !s = Parse.State src pos2 end indent row (col + 2) in cok () s
          else eerr row col toError

k3 :: Word8 -> Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k3 w1 w2 w3 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos3 = plusPtr pos 3
     in if pos3 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Parse.unsafeIndex (plusPtr pos 2) == w3
          && Var.getInnerWidth pos3 end == 0
          then let !s = Parse.State src pos3 end indent row (col + 3) in cok () s
          else eerr row col toError

-- | Match an exact 4-byte keyword sequence.
--
-- Checks all four bytes in sequence, then asserts that no identifier
-- continuation character follows (preventing partial keyword matches).
-- Used directly by keyword parsers and exported for external consumers.
--
-- @since 0.19.1
k4 :: Word8 -> Word8 -> Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k4 w1 w2 w3 w4 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos4 = plusPtr pos 4
     in if pos4 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Parse.unsafeIndex (plusPtr pos 2) == w3
          && Parse.unsafeIndex (plusPtr pos 3) == w4
          && Var.getInnerWidth pos4 end == 0
          then let !s = Parse.State src pos4 end indent row (col + 4) in cok () s
          else eerr row col toError

-- | Match an exact 5-byte keyword sequence.
--
-- Like 'k4' but for 5-character keywords.  Exported for external consumers.
--
-- @since 0.19.1
k5 :: Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k5 w1 w2 w3 w4 w5 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos5 = plusPtr pos 5
     in if pos5 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Parse.unsafeIndex (plusPtr pos 2) == w3
          && Parse.unsafeIndex (plusPtr pos 3) == w4
          && Parse.unsafeIndex (plusPtr pos 4) == w5
          && Var.getInnerWidth pos5 end == 0
          then let !s = Parse.State src pos5 end indent row (col + 5) in cok () s
          else eerr row col toError

k6 :: Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k6 w1 w2 w3 w4 w5 w6 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos6 = plusPtr pos 6
     in if pos6 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Parse.unsafeIndex (plusPtr pos 2) == w3
          && Parse.unsafeIndex (plusPtr pos 3) == w4
          && Parse.unsafeIndex (plusPtr pos 4) == w5
          && Parse.unsafeIndex (plusPtr pos 5) == w6
          && Var.getInnerWidth pos6 end == 0
          then let !s = Parse.State src pos6 end indent row (col + 6) in cok () s
          else eerr row col toError

k7 :: Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k7 w1 w2 w3 w4 w5 w6 w7 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos7 = plusPtr pos 7
     in if pos7 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Parse.unsafeIndex (plusPtr pos 2) == w3
          && Parse.unsafeIndex (plusPtr pos 3) == w4
          && Parse.unsafeIndex (plusPtr pos 4) == w5
          && Parse.unsafeIndex (plusPtr pos 5) == w6
          && Parse.unsafeIndex (plusPtr pos 6) == w7
          && Var.getInnerWidth pos7 end == 0
          then let !s = Parse.State src pos7 end indent row (col + 7) in cok () s
          else eerr row col toError

k8 :: Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> Word8 -> (Row -> Col -> x) -> Parser x ()
k8 w1 w2 w3 w4 w5 w6 w7 w8 toError =
  Parse.Parser $ \(Parse.State src pos end indent row col) cok _ _ eerr ->
    let !pos8 = plusPtr pos 8
     in if pos8 <= end
          && Parse.unsafeIndex (pos) == w1
          && Parse.unsafeIndex (plusPtr pos 1) == w2
          && Parse.unsafeIndex (plusPtr pos 2) == w3
          && Parse.unsafeIndex (plusPtr pos 3) == w4
          && Parse.unsafeIndex (plusPtr pos 4) == w5
          && Parse.unsafeIndex (plusPtr pos 5) == w6
          && Parse.unsafeIndex (plusPtr pos 6) == w7
          && Parse.unsafeIndex (plusPtr pos 7) == w8
          && Var.getInnerWidth pos8 end == 0
          then let !s = Parse.State src pos8 end indent row (col + 8) in cok () s
          else eerr row col toError
