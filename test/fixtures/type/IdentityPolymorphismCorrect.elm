module IdentityPolymorphismCorrect exposing (..)

-- Correct minimal reproduction:
-- - helper function in let binding
-- - first branch uses (PageMsg << AnalyticsNewMsg) with Page AnalyticsNewMsg
-- - second branch uses identity with Page msg (polymorphic!)
-- - identity should unify as MainMsg -> MainMsg, not get polluted

type Page msg
    = Page String


type MainMsg
    = PageMsg PageMsg


type PageMsg
    = AnalyticsNewMsg AnalyticsNewMsg


type AnalyticsNewMsg
    = NewMsg


type Model
    = AnalyticsNew
    | Analytics


-- viewPage expects (pageMsg -> mainMsg) and returns Page mainMsg
viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg (Page title) =
    Page title


-- AnalyticsNew.view returns Page AnalyticsNewMsg
analyticsNewView : Page AnalyticsNewMsg
analyticsNewView =
    Page "Analytics New"


-- Analytics.view returns Page msg (polymorphic!)
analyticsView : Page msg
analyticsView =
    Page "Analytics"


view : Model -> Page MainMsg
view model =
    let
        -- helper is polymorphic
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew ->
            -- PageMsg << AnalyticsNewMsg : AnalyticsNewMsg -> MainMsg
            -- Page AnalyticsNewMsg
            -- Result: Page MainMsg ✓
            helper (PageMsg << AnalyticsNewMsg) analyticsNewView

        Analytics ->
            -- identity : a -> a
            -- Page msg (polymorphic)
            -- Should unify: a ~ MainMsg, msg ~ MainMsg
            -- Result: Page MainMsg ✓
            helper identity analyticsView
