module IdentityPolymorphismMultiBranch exposing (..)

-- Testing with 3+ branches to see if there's pollution across branches

type Page msg
    = Page String


type MainMsg
    = PageMsg PageMsg


type PageMsg
    = AnalyticsNewMsg AnalyticsNewMsg
    | AnalyticsMsg AnalyticsMsg
    | OtherMsg OtherMsg


type AnalyticsNewMsg
    = NewMsg


type AnalyticsMsg
    = OldMsg


type OtherMsg
    = OtherM


type Model
    = AnalyticsNew
    | Analytics
    | Other
    | YetAnother


viewPage : (pageMsg -> mainMsg) -> Page pageMsg -> Page mainMsg
viewPage toMsg (Page title) =
    Page title


analyticsNewView : Page AnalyticsNewMsg
analyticsNewView =
    Page "New"


analyticsView : Page msg
analyticsView =
    Page "Old"


otherView : Page msg
otherView =
    Page "Other"


yetAnotherView : Page msg
yetAnotherView =
    Page "YetAnother"


view : Model -> Page MainMsg
view model =
    let
        helper toMsg page =
            viewPage toMsg page
    in
    case model of
        AnalyticsNew ->
            helper (PageMsg << AnalyticsNewMsg) analyticsNewView

        Analytics ->
            helper identity analyticsView

        Other ->
            helper identity otherView

        YetAnother ->
            helper identity yetAnotherView
