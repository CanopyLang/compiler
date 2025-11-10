module PhantomTypeExactCms exposing (..)

-- Exact reproduction of the CMS pattern that fails

type Id a = Id Int

type alias VacancyFilterOptionId = Id { vacancyFilterOptionId : () }
type alias CmsApplicationStatusId = Id { cmsApplicationStatusId : () }
type alias LocationId = Id { locationId : () }

idToString : Id a -> String
idToString (Id n) = String.fromInt n

type alias QueryParameter = String

buildString : String -> String -> QueryParameter
buildString key value = key ++ "=" ++ value

statusParam : String
statusParam = "st"

locationParam : String
locationParam = "l"

disciplineParam : String
disciplineParam = "d"

type alias SearchParams =
    { status : Maybe (List CmsApplicationStatusId)
    , locationKey : Maybe (List LocationId)
    , disciplineKey : Maybe (List VacancyFilterOptionId)
    }

-- Exact reproduction of the CMS toParams function
toParams : SearchParams -> List QueryParameter
toParams params =
    let
        mParamList f s =
            Maybe.withDefault [] <|
                Maybe.map (List.map f) s
    in
    List.concat
        [ mParamList (buildString statusParam << idToString) params.status
        , mParamList (buildString locationParam << idToString) params.locationKey
        , mParamList (buildString disciplineParam << idToString) params.disciplineKey
        ]
