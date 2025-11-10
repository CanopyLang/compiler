module PhantomTypeMultiUse exposing (..)

-- Test multiple uses of polymorphic function with different phantom types
-- This should work but currently fails

type Id a = Id Int

type alias VacancyFilterOptionId = Id { vacancyFilterOptionId : () }
type alias CmsApplicationStatusId = Id { cmsApplicationStatusId : () }
type alias LocationId = Id { locationId : () }

toString : Id a -> String
toString (Id n) = String.fromInt n

-- This function should accept Id with any phantom type parameter
mParamList : (a -> b) -> Maybe (List a) -> List b
mParamList f maybeList =
    case maybeList of
        Nothing -> []
        Just list -> List.map f list

-- Test record with multiple Id types
type alias SearchParams =
    { status : Maybe (List CmsApplicationStatusId)
    , locationKey : Maybe (List LocationId)
    , disciplineKey : Maybe (List VacancyFilterOptionId)
    }

-- This is the problematic pattern: using mParamList multiple times
-- with different phantom type parameters in the same expression
toQueryParams : SearchParams -> List String
toQueryParams params =
    List.concat
        [ mParamList toString params.status
        , mParamList toString params.locationKey
        , mParamList toString params.disciplineKey
        ]
