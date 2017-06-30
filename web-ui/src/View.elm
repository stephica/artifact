module View exposing (..)

import Html exposing (..)
import Messages exposing (AppMsg(..), Route(..))
import Models exposing (..)
import Artifacts.Models exposing (..)
import Artifacts.List
import Artifacts.Edit


-- partof: #SPC-web-view


view : Model -> Html AppMsg
view model =
    div []
        [ page model ]


page : Model -> Html AppMsg
page model =
    case model.route of
        ArtifactsRoute ->
            Artifacts.List.view model model.artifacts

        ArtifactNameRoute raw_name ->
            case indexName raw_name of
                Ok name ->
                    case getArtifact name model of
                        Just artifact ->
                            Artifacts.Edit.view model <| getOption model artifact

                        Nothing ->
                            notFoundView

                Err error ->
                    div []
                        [ text <| "invalid artifact name: " ++ error
                        ]

        ArtifactEditingRoute ->
            Artifacts.Edit.viewEditing model

        ArtifactCreateRoute ->
            getCreateArtifact model
                |> CreateChoice
                |> EditChoice
                |> Artifacts.Edit.view model

        NotFoundRoute ->
            notFoundView


{-| get the viewing option for an existing artifact
-}
getOption : Model -> Artifact -> ViewOption
getOption model artifact =
    if model.settings.readonly then
        ReadChoice artifact
    else
        case artifact.edited of
            Just e ->
                EditChoice <| ChangeChoice artifact e

            Nothing ->
                ReadChoice <| artifact


notFoundView : Html a
notFoundView =
    div []
        [ text "Artifact Name Not Found"
        ]
