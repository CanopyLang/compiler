module PhantomTypeTest exposing (..)

-- Minimal reproduction of phantom type bug
-- The Id type parameter should remain polymorphic across all uses

type Id a = Id Int

type alias VacancyFilterOptionId = Id { vacancyFilterOptionId : () }
type alias CmsApplicationStatusId = Id { cmsApplicationStatusId : () }

toString : Id a -> String
toString (Id n) = String.fromInt n

-- This function should accept Id with any phantom type parameter
mParamList : (a -> b) -> Maybe (List a) -> List b
mParamList f maybeList =
    case maybeList of
        Nothing -> []
        Just list -> List.map f list

-- This should work: VacancyFilterOptionId should unify with Id a
testVacancyFilter : Maybe (List VacancyFilterOptionId) -> List String
testVacancyFilter ids =
    mParamList toString ids

-- This should also work: CmsApplicationStatusId should unify with Id a
testStatusFilter : Maybe (List CmsApplicationStatusId) -> List String
testStatusFilter ids =
    mParamList toString ids

-- Test record field access (reproduces the exact error)
type alias SearchParams =
    { disciplineKey : Maybe (List VacancyFilterOptionId)
    , status : Maybe (List CmsApplicationStatusId)
    }

testRecordAccess : SearchParams -> List String
testRecordAccess params =
    mParamList toString params.disciplineKey
