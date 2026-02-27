{-# LANGUAGE OverloadedStrings #-}
module Parse.Expression
  ( expression
  )
  where


import qualified Data.Name as Name

import qualified AST.Source as Src
import qualified Parse.Keyword as Keyword
import qualified Parse.Number as Number
import qualified Parse.Pattern as Pattern
import qualified Parse.Shader as Shader
import qualified Parse.Space as Space
import qualified Parse.Symbol as Symbol
import qualified Parse.Type as Type
import qualified Parse.String as String
import qualified Parse.Variable as Var
import Parse.Primitives hiding (State)
import qualified Parse.Primitives as Parse
import qualified Reporting.Annotation as Ann
import qualified Reporting.Error.Syntax as SyntaxError



-- TERMS


term :: Parser SyntaxError.Expr Src.Expr
term =
  do  start <- getPosition
      oneOf SyntaxError.Start
        [ variable start >>= accessible start
        , string start
        , number start
        , Shader.shader start
        , list start
        , record start >>= accessible start
        , tuple start >>= accessible start
        , accessor start
        , character start
        ]


string :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
string start =
  do  str <- String.string SyntaxError.Start SyntaxError.String
      addEnd start (Src.Str str)


character :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
character start =
  do  chr <- String.character SyntaxError.Start SyntaxError.Char
      addEnd start (Src.Chr chr)


number :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
number start =
  do  nmbr <- Number.number SyntaxError.Start SyntaxError.Number
      addEnd start $
        case nmbr of
          Number.Int int -> Src.Int int
          Number.Float float -> Src.Float float


accessor :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
accessor start =
  do  word1 0x2E {-.-} SyntaxError.Dot
      field <- Var.lower SyntaxError.Access
      addEnd start (Src.Accessor field)


variable :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
variable start =
  do  var <- Var.foreignAlpha SyntaxError.Start
      addEnd start var


accessible :: Ann.Position -> Src.Expr -> Parser SyntaxError.Expr Src.Expr
accessible start expr =
  oneOfWithFallback
    [ do  word1 0x2E {-.-} SyntaxError.Dot
          pos <- getPosition
          field <- Var.lower SyntaxError.Access
          end <- getPosition
          accessible start $
            Ann.at start end (Src.Access expr (Ann.at pos end field))
    ]
    expr



-- LISTS


list :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
list start =
  inContext SyntaxError.List (word1 0x5B {-[-} SyntaxError.Start) $
    do  Space.chompAndCheckIndent SyntaxError.ListSpace SyntaxError.ListIndentOpen
        oneOf SyntaxError.ListOpen
          [ do  (entry, end) <- specialize SyntaxError.ListExpr expression
                Space.checkIndent end SyntaxError.ListIndentEnd
                chompListEnd start [entry]
          , do  word1 0x5D {-]-} SyntaxError.ListOpen
                addEnd start (Src.List [])
          ]


chompListEnd :: Ann.Position -> [Src.Expr] -> Parser SyntaxError.List Src.Expr
chompListEnd start entries =
  oneOf SyntaxError.ListEnd
    [ do  word1 0x2C {-,-} SyntaxError.ListEnd
          Space.chompAndCheckIndent SyntaxError.ListSpace SyntaxError.ListIndentExpr
          (entry, end) <- specialize SyntaxError.ListExpr expression
          Space.checkIndent end SyntaxError.ListIndentEnd
          chompListEnd start (entry:entries)
    , do  word1 0x5D {-]-} SyntaxError.ListEnd
          addEnd start (Src.List (reverse entries))
    ]



-- TUPLES


tuple :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
tuple start@(Ann.Position row col) =
  inContext SyntaxError.Tuple (word1 0x28 {-(-} SyntaxError.Start) $
    do  before <- getPosition
        Space.chompAndCheckIndent SyntaxError.TupleSpace SyntaxError.TupleIndentExpr1
        after <- getPosition
        if before /= after
          then
            do  (entry, end) <- specialize SyntaxError.TupleExpr expression
                Space.checkIndent end SyntaxError.TupleIndentEnd
                chompTupleEnd start entry []
          else
            oneOf SyntaxError.TupleIndentExpr1
              [
                do  op <- Symbol.operator SyntaxError.TupleIndentExpr1 SyntaxError.TupleOperatorReserved
                    if op == "-"
                      then
                        oneOf SyntaxError.TupleOperatorClose
                          [
                            do  word1 0x29 {-)-} SyntaxError.TupleOperatorClose
                                addEnd start (Src.Op op)
                          ,
                            do  (entry, end) <-
                                  specialize SyntaxError.TupleExpr $
                                    do  negatedExpr@(Ann.At (Ann.Region _ end) _) <- term
                                        Space.chomp SyntaxError.Space
                                        let exprStart = Ann.Position row (col + 2)
                                        let expr = Ann.at exprStart end (Src.Negate negatedExpr)
                                        chompExprEnd exprStart (State [] expr [] end)
                                Space.checkIndent end SyntaxError.TupleIndentEnd
                                chompTupleEnd start entry []
                          ]
                      else
                        do  word1 0x29 {-)-} SyntaxError.TupleOperatorClose
                            addEnd start (Src.Op op)
              ,
                do  word1 0x29 {-)-} SyntaxError.TupleIndentExpr1
                    addEnd start Src.Unit
              ,
                do  (entry, end) <- specialize SyntaxError.TupleExpr expression
                    Space.checkIndent end SyntaxError.TupleIndentEnd
                    chompTupleEnd start entry []
              ]


chompTupleEnd :: Ann.Position -> Src.Expr -> [Src.Expr] -> Parser SyntaxError.Tuple Src.Expr
chompTupleEnd start firstExpr revExprs =
  oneOf SyntaxError.TupleEnd
    [ do  word1 0x2C {-,-} SyntaxError.TupleEnd
          Space.chompAndCheckIndent SyntaxError.TupleSpace SyntaxError.TupleIndentExprN
          (entry, end) <- specialize SyntaxError.TupleExpr expression
          Space.checkIndent end SyntaxError.TupleIndentEnd
          chompTupleEnd start firstExpr (entry : revExprs)
    , do  word1 0x29 {-)-} SyntaxError.TupleEnd
          case reverse revExprs of
            [] ->
              return firstExpr

            secondExpr : otherExprs ->
              addEnd start (Src.Tuple firstExpr secondExpr otherExprs)
    ]



-- RECORDS


record :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
record start =
  inContext SyntaxError.Record (word1 0x7B {- { -} SyntaxError.Start) $
    do  Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentOpen
        oneOf SyntaxError.RecordOpen
          [ do  word1 0x7D {-}-} SyntaxError.RecordOpen
                addEnd start (Src.Record [])
          , do  starter <- addLocation (Var.lower SyntaxError.RecordField)
                Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentEquals
                oneOf SyntaxError.RecordEquals
                  [ do  word1 0x7C {-|-} SyntaxError.RecordEquals
                        Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentField
                        firstField <- chompField
                        fields <- chompFields [firstField]
                        addEnd start (Src.Update starter fields)
                  , do  word1 0x3D {-=-} SyntaxError.RecordEquals
                        Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentExpr
                        (value, end) <- specialize SyntaxError.RecordExpr expression
                        Space.checkIndent end SyntaxError.RecordIndentEnd
                        fields <- chompFields [(starter, value)]
                        addEnd start (Src.Record fields)
                  ]
          ]


type Field = ( Ann.Located Name.Name, Src.Expr )


chompFields :: [Field] -> Parser SyntaxError.Record [Field]
chompFields fields =
  oneOf SyntaxError.RecordEnd
    [ do  word1 0x2C {-,-} SyntaxError.RecordEnd
          Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentField
          f <- chompField
          chompFields (f : fields)
    , do  word1 0x7D {-}-} SyntaxError.RecordEnd
          return (reverse fields)
    ]


chompField :: Parser SyntaxError.Record Field
chompField =
  do  key <- addLocation (Var.lower SyntaxError.RecordField)
      Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentEquals
      word1 0x3D {-=-} SyntaxError.RecordEquals
      Space.chompAndCheckIndent SyntaxError.RecordSpace SyntaxError.RecordIndentExpr
      (value, end) <- specialize SyntaxError.RecordExpr expression
      Space.checkIndent end SyntaxError.RecordIndentEnd
      return (key, value)



-- EXPRESSIONS


expression :: Space.Parser SyntaxError.Expr Src.Expr
expression =
  do  start <- getPosition
      oneOf SyntaxError.Start
        [ let_ start
        , if_ start
        , case_ start
        , function start
        , do  expr <- possiblyNegativeTerm start
              end <- getPosition
              Space.chomp SyntaxError.Space
              chompExprEnd start (State [] expr [] end)
        ]


data State =
  State
    { _ops  :: ![(Src.Expr, Ann.Located Name.Name)]
    , _expr :: !Src.Expr
    , _args :: ![Src.Expr]
    , _end  :: !Ann.Position
    }


chompExprEnd :: Ann.Position -> State -> Space.Parser SyntaxError.Expr Src.Expr
chompExprEnd start (State ops expr args end) =
  oneOfWithFallback
    [ -- argument
      do  Space.checkIndent end SyntaxError.Start
          arg <- term
          newEnd <- getPosition
          Space.chomp SyntaxError.Space
          chompExprEnd start (State ops expr (arg:args) newEnd)

    , -- operator
      do  Space.checkIndent end SyntaxError.Start
          op@(Ann.At (Ann.Region opStart opEnd) opName) <- addLocation (Symbol.operator SyntaxError.Start SyntaxError.OperatorReserved)
          Space.chompAndCheckIndent SyntaxError.Space (SyntaxError.IndentOperatorRight opName)
          newStart <- getPosition
          if "-" == opName && end /= opStart && opEnd == newStart
            then
              -- negative terms
              do  negatedExpr <- term
                  newEnd <- getPosition
                  Space.chomp SyntaxError.Space
                  let arg = Ann.at opStart newEnd (Src.Negate negatedExpr)
                  chompExprEnd start (State ops expr (arg:args) newEnd)
            else
              let err = SyntaxError.OperatorRight opName in
              oneOf err
                [ -- term
                  do  newExpr <- possiblyNegativeTerm newStart
                      newEnd <- getPosition
                      Space.chomp SyntaxError.Space
                      let newOps = (toCall expr args, op) : ops
                      chompExprEnd start (State newOps newExpr [] newEnd)

                , -- final term
                  do  (newLast, newEnd) <-
                        oneOf err
                          [ let_ newStart
                          , case_ newStart
                          , if_ newStart
                          , function newStart
                          ]
                      let newOps = (toCall expr args, op) : ops
                      let finalExpr = Src.Binops (reverse newOps) newLast
                      return ( Ann.at start newEnd finalExpr, newEnd )
                ]

    ]
    -- done
    (
      case ops of
        [] ->
          ( toCall expr args
          , end
          )

        _ ->
          ( Ann.at start end (Src.Binops (reverse ops) (toCall expr args))
          , end
          )
    )


possiblyNegativeTerm :: Ann.Position -> Parser SyntaxError.Expr Src.Expr
possiblyNegativeTerm start =
  oneOf SyntaxError.Start
    [ do  word1 0x2D {---} SyntaxError.Start
          expr <- term
          addEnd start (Src.Negate expr)
    , term
    ]


toCall :: Src.Expr -> [Src.Expr] -> Src.Expr
toCall func revArgs =
  case revArgs of
    [] ->
      func

    lastArg : _ ->
      Ann.merge func lastArg (Src.Call func (reverse revArgs))



-- IF EXPRESSION


if_ :: Ann.Position -> Space.Parser SyntaxError.Expr Src.Expr
if_ start =
  inContext SyntaxError.If (Keyword.if_ SyntaxError.Start) $
    chompIfEnd start []


chompIfEnd :: Ann.Position -> [(Src.Expr, Src.Expr)] -> Space.Parser SyntaxError.If Src.Expr
chompIfEnd start branches =
  do  Space.chompAndCheckIndent SyntaxError.IfSpace SyntaxError.IfIndentCondition
      (condition, condEnd) <- specialize SyntaxError.IfCondition expression
      Space.checkIndent condEnd SyntaxError.IfIndentThen
      Keyword.then_ SyntaxError.IfThen
      Space.chompAndCheckIndent SyntaxError.IfSpace SyntaxError.IfIndentThenBranch
      (thenBranch, thenEnd) <- specialize SyntaxError.IfThenBranch expression
      Space.checkIndent thenEnd SyntaxError.IfIndentElse
      Keyword.else_ SyntaxError.IfElse
      Space.chompAndCheckIndent SyntaxError.IfSpace SyntaxError.IfIndentElseBranch
      let newBranches = (condition, thenBranch) : branches
      oneOf SyntaxError.IfElseBranchStart
        [
          do  Keyword.if_ SyntaxError.IfElseBranchStart
              chompIfEnd start newBranches
        ,
          do  (elseBranch, elseEnd) <- specialize SyntaxError.IfElseBranch expression
              let ifExpr = Src.If (reverse newBranches) elseBranch
              return ( Ann.at start elseEnd ifExpr, elseEnd )
        ]



-- LAMBDA EXPRESSION


function :: Ann.Position -> Space.Parser SyntaxError.Expr Src.Expr
function start =
  inContext SyntaxError.Func (word1 0x5C {-\-} SyntaxError.Start) $
    do  Space.chompAndCheckIndent SyntaxError.FuncSpace SyntaxError.FuncIndentArg
        arg <- specialize SyntaxError.FuncArg Pattern.term
        Space.chompAndCheckIndent SyntaxError.FuncSpace SyntaxError.FuncIndentArrow
        revArgs <- chompArgs [arg]
        Space.chompAndCheckIndent SyntaxError.FuncSpace SyntaxError.FuncIndentBody
        (body, end) <- specialize SyntaxError.FuncBody expression
        let funcExpr = Src.Lambda (reverse revArgs) body
        return (Ann.at start end funcExpr, end)


chompArgs :: [Src.Pattern] -> Parser SyntaxError.Func [Src.Pattern]
chompArgs revArgs =
  oneOf SyntaxError.FuncArrow
    [ do  arg <- specialize SyntaxError.FuncArg Pattern.term
          Space.chompAndCheckIndent SyntaxError.FuncSpace SyntaxError.FuncIndentArrow
          chompArgs (arg:revArgs)
    , do  word2 0x2D 0x3E {-->-} SyntaxError.FuncArrow
          return revArgs
    ]



-- CASE EXPRESSIONS


case_ :: Ann.Position -> Space.Parser SyntaxError.Expr Src.Expr
case_ start =
  inContext SyntaxError.Case (Keyword.case_ SyntaxError.Start) $
    do  Space.chompAndCheckIndent SyntaxError.CaseSpace SyntaxError.CaseIndentExpr
        (expr, exprEnd) <- specialize SyntaxError.CaseExpr expression
        Space.checkIndent exprEnd SyntaxError.CaseIndentOf
        Keyword.of_ SyntaxError.CaseOf
        Space.chompAndCheckIndent SyntaxError.CaseSpace SyntaxError.CaseIndentPattern
        withIndent $
          do  (firstBranch, firstEnd) <- chompBranch
              (branches, end) <- chompCaseEnd [firstBranch] firstEnd
              return
                ( Ann.at start end (Src.Case expr branches)
                , end
                )


chompBranch :: Space.Parser SyntaxError.Case (Src.Pattern, Src.Expr)
chompBranch =
  do  (pattern, patternEnd) <- specialize SyntaxError.CasePattern Pattern.expression
      Space.checkIndent patternEnd SyntaxError.CaseIndentArrow
      word2 0x2D 0x3E {-->-} SyntaxError.CaseArrow
      Space.chompAndCheckIndent SyntaxError.CaseSpace SyntaxError.CaseIndentBranch
      (branchExpr, end) <- specialize SyntaxError.CaseBranch expression
      return ( (pattern, branchExpr), end )


chompCaseEnd :: [(Src.Pattern, Src.Expr)] -> Ann.Position -> Space.Parser SyntaxError.Case [(Src.Pattern, Src.Expr)]
chompCaseEnd branches end =
  oneOfWithFallback
    [ do  Space.checkAligned SyntaxError.CasePatternAlignment
          (branch, newEnd) <- chompBranch
          chompCaseEnd (branch:branches) newEnd
    ]
    (reverse branches, end)



-- LET EXPRESSION


let_ :: Ann.Position -> Space.Parser SyntaxError.Expr Src.Expr
let_ start =
  inContext SyntaxError.Let (Keyword.let_ SyntaxError.Start) $
    do  (defs, defsEnd) <-
          withBacksetIndent 3 $
            do  Space.chompAndCheckIndent SyntaxError.LetSpace SyntaxError.LetIndentDef
                withIndent $
                  do  (def, end) <- chompLetDef
                      chompLetDefs [def] end

        Space.checkIndent defsEnd SyntaxError.LetIndentIn
        Keyword.in_ SyntaxError.LetIn
        Space.chompAndCheckIndent SyntaxError.LetSpace SyntaxError.LetIndentBody
        (body, end) <- specialize SyntaxError.LetBody expression
        return
          ( Ann.at start end (Src.Let defs body)
          , end
          )


chompLetDefs :: [Ann.Located Src.Def] -> Ann.Position -> Space.Parser SyntaxError.Let [Ann.Located Src.Def]
chompLetDefs revDefs end =
  oneOfWithFallback
    [ do  Space.checkAligned SyntaxError.LetDefAlignment
          (def, newEnd) <- chompLetDef
          chompLetDefs (def:revDefs) newEnd
    ]
    (reverse revDefs, end)



-- LET DEFINITIONS


chompLetDef :: Space.Parser SyntaxError.Let (Ann.Located Src.Def)
chompLetDef =
  oneOf SyntaxError.LetDefName
    [ definition
    , destructure
    ]



-- DEFINITION


definition :: Space.Parser SyntaxError.Let (Ann.Located Src.Def)
definition =
  do  aname@(Ann.At (Ann.Region start _) name) <- addLocation (Var.lower SyntaxError.LetDefName)
      specialize (SyntaxError.LetDef name) $
        do  Space.chompAndCheckIndent SyntaxError.DefSpace SyntaxError.DefIndentEquals
            oneOf SyntaxError.DefEquals
              [
                do  word1 0x3A {-:-} SyntaxError.DefEquals
                    Space.chompAndCheckIndent SyntaxError.DefSpace SyntaxError.DefIndentType
                    (tipe, _) <- specialize SyntaxError.DefType Type.expression
                    Space.checkAligned SyntaxError.DefAlignment
                    defName <- chompMatchingName name
                    Space.chompAndCheckIndent SyntaxError.DefSpace SyntaxError.DefIndentEquals
                    chompDefArgsAndBody start defName (Just tipe) []
              ,
                chompDefArgsAndBody start aname Nothing []
              ]


chompDefArgsAndBody :: Ann.Position -> Ann.Located Name.Name -> Maybe Src.Type -> [Src.Pattern] -> Space.Parser SyntaxError.Def (Ann.Located Src.Def)
chompDefArgsAndBody start name tipe revArgs =
  oneOf SyntaxError.DefEquals
    [ do  arg <- specialize SyntaxError.DefArg Pattern.term
          Space.chompAndCheckIndent SyntaxError.DefSpace SyntaxError.DefIndentEquals
          chompDefArgsAndBody start name tipe (arg : revArgs)
    , do  word1 0x3D {-=-} SyntaxError.DefEquals
          Space.chompAndCheckIndent SyntaxError.DefSpace SyntaxError.DefIndentBody
          (body, end) <- specialize SyntaxError.DefBody expression
          return
            ( Ann.at start end (Src.Define name (reverse revArgs) body tipe)
            , end
            )
    ]


chompMatchingName :: Name.Name -> Parser SyntaxError.Def (Ann.Located Name.Name)
chompMatchingName expectedName =
  let
    (Parse.Parser parserL) = Var.lower SyntaxError.DefNameRepeat
  in
  Parse.Parser $ \state@(Parse.State _ _ _ _ sr sc) cok eok cerr eerr ->
    let
      cokL name newState@(Parse.State _ _ _ _ er ec) =
        if expectedName == name
        then cok (Ann.At (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) name) newState
        else cerr sr sc (SyntaxError.DefNameMatch name)

      eokL name newState@(Parse.State _ _ _ _ er ec) =
        if expectedName == name
        then eok (Ann.At (Ann.Region (Ann.Position sr sc) (Ann.Position er ec)) name) newState
        else eerr sr sc (SyntaxError.DefNameMatch name)
    in
    parserL state cokL eokL cerr eerr




-- DESTRUCTURE


destructure :: Space.Parser SyntaxError.Let (Ann.Located Src.Def)
destructure =
  specialize SyntaxError.LetDestruct $
  do  start <- getPosition
      pattern <- specialize SyntaxError.DestructPattern Pattern.term
      Space.chompAndCheckIndent SyntaxError.DestructSpace SyntaxError.DestructIndentEquals
      word1 0x3D {-=-} SyntaxError.DestructEquals
      Space.chompAndCheckIndent SyntaxError.DestructSpace SyntaxError.DestructIndentBody
      (expr, end) <- specialize SyntaxError.DestructBody expression
      return ( Ann.at start end (Src.Destruct pattern expr), end )
