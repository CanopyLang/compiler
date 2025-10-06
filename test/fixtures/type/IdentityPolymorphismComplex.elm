module IdentityPolymorphismComplex exposing (..)

-- More complex test with multiple uses of helper
-- to see if type variables are being shared incorrectly

type Page msg
    = Page String (List msg)


type MainMsg
    = PageMsg PageMsg


type PageMsg
    = AnalyticsNewMsg AnalyticsNewMsg
    | AnalyticsMsg AnalyticsMsg


type AnalyticsNewMsg
    = NewMsg1
    | NewMsg2


type AnalyticsMsg
    = OldMsg


type Model
    = AnalyticsNew Int
    | Analytics String


viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg (Page title msgs) =
    Page title (List.map toMsg msgs)


-- AnalyticsNew.view returns Page AnalyticsNewMsg (concrete)
analyticsNewView : Int -> Page AnalyticsNewMsg
analyticsNewView n =
    if n > 0 then
        Page "Analytics New" [ NewMsg1, NewMsg2 ]
    else
        Page "Empty" []


-- Analytics.view returns Page msg (polymorphic!)
analyticsView : String -> Page msg
analyticsView str =
    Page str []


view : Model -> Page MainMsg
view model =
    let
        -- Helper is polymorphic - should be generalized at let binding
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew n ->
            -- Call helper with concrete types
            -- toMsg : AnalyticsNewMsg -> MainMsg
            -- page : Page AnalyticsNewMsg
            helper (PageMsg << AnalyticsNewMsg) (analyticsNewView n)

        Analytics str ->
            -- Call helper with polymorphic page
            -- identity : a -> a
            -- page : Page msg (polymorphic)
            -- Should unify: a ~ MainMsg, msg ~ MainMsg
            helper identity (analyticsView str)
