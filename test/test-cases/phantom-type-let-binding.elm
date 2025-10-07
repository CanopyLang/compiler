module PhantomTypeLetBinding exposing (..)

-- Test phantom types with helper function in let binding
-- This is the actual pattern from CMS that fails

type Id a = Id Int

type alias VacancyFilterOptionId = Id { vacancyFilterOptionId : () }
type alias CmsApplicationStatusId = Id { cmsApplicationStatusId : () }
type alias LocationId = Id { locationId : () }

toString : Id a -> String
toString (Id n) = String.fromInt n

type alias SearchParams =
    { status : Maybe (List CmsApplicationStatusId)
    , locationKey : Maybe (List LocationId)
    , disciplineKey : Maybe (List VacancyFilterOptionId)
    }

-- The problematic pattern: mParamList defined in let binding
toQueryParams : SearchParams -> List (List String)
toQueryParams params =
    let
        -- This helper is defined locally, just like in CMS
        mParamList : (a -> b) -> Maybe (List a) -> List b
        mParamList f maybeList =
            case maybeList of
                Nothing -> []
                Just list -> List.map f list
    in
    List.concat
        [ [ mParamList toString params.status ]
        , [ mParamList toString params.locationKey ]
        , [ mParamList toString params.disciplineKey ]
        ]
