module Artifacts.Edit exposing (..)

import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)
import Regex
import Markdown exposing (toHtml)
import Utils exposing (..)
import Models exposing (Model, getArtifact, memberArtifact, getCreateArtifact)
import Styles exposing (warning)
import Artifacts.Models exposing (..)
import Messages exposing (createUrl, AppMsg(..))
import Artifacts.Messages exposing (..)
import Artifacts.View as View
import Artifacts.Select as Select
import Artifacts.Nav as Nav


{-| regex to search for and replace [[ART-name]]
-}
artifactLinkRegex : Regex.Regex
artifactLinkRegex =
    Regex.caseInsensitive <| Regex.regex <| "\\[\\[(" ++ artifactValidRaw ++ ")\\]\\]"


{-| the entire view
-}
view : Model -> ViewOption -> Html AppMsg
view model option =
    let
        nav =
            if model.settings.readonly then
                Nav.bar model <| Nav.readBar
            else
                Nav.bar model <| Nav.editBar model option

        original =
            case option of
                ReadChoice choice ->
                    []

                EditChoice choice ->
                    case choice of
                        ChangeChoice artifact _ ->
                            -- Header for original view
                            [ h1 [ id "original_head" ] [ text "Previous:" ]
                            , form model (ReadChoice artifact)
                            ]

                        CreateChoice _ ->
                            []
    in
        div [ viewIdAttr option ] <|
            List.concat
                [ [ nav ]
                , revisionWarnings model option
                , [ form model option ]
                , original
                ]


viewIdAttr : ViewOption -> Attribute m
viewIdAttr option =
    id <|
        case option of
            ReadChoice _ ->
                "read_view"

            EditChoice choice ->
                case choice of
                    ChangeChoice _ _ ->
                        "edit_view"

                    CreateChoice _ ->
                        "create_view"


{-| display a warning if the artifact changed from under the user
-}
revisionWarnings : Model -> ViewOption -> List (Html AppMsg)
revisionWarnings model option =
    case option of
        ReadChoice _ ->
            []

        EditChoice choice ->
            case choice of
                ChangeChoice artifact edited ->
                    if artifact.revision == edited.revision then
                        []
                    else
                        [ h1
                            [ class "h1 red"
                            , id "warn_edit_change"
                            ]
                            [ text <|
                                "!! This artifact has been changed"
                                    ++ " by another user since editing"
                                    ++ " started !!"
                            ]
                        ]

                CreateChoice _ ->
                    []


form : Model -> ViewOption -> Html AppMsg
form model option =
    div [ class "m3" ]
        ((nameElements model option)
            ++ [ div [ class "clearfix py1" ]
                    [ formColumnOne model option
                    , formColumnTwo model option
                    ]
               ]
        )


{-| attributes column (non-text)
-}
formColumnOne : Model -> ViewOption -> Html AppMsg
formColumnOne model option =
    let
        partofEls =
            [ h3 [] [ text "Partof" ]
            , Select.partof model option
            ]

        elements =
            case option of
                ReadChoice artifact ->
                    -- display all information
                    [ View.completion artifact
                    , Select.defined model option
                    , View.implemented model artifact
                    , div [ class "clearfix py1" ]
                        [ div [ class "col col-6" ] partofEls
                        , div [ class "col col-6" ]
                            [ h3 [] [ text "Parts" ]
                            , View.parts model artifact
                            ]
                        ]
                    ]

                EditChoice _ ->
                    -- only display editable information
                    [ Select.defined model option ] ++ partofEls
    in
        div [ class "col col-6" ] elements


{-| Text column
-}
formColumnTwo : Model -> ViewOption -> Html AppMsg
formColumnTwo model option =
    div [ class "col col-6" ]
        [ h3 [] [ text "Text" ]
        , selectRenderedBtns model option
        , displayText model option
        ]



-- NAME


nameElements : Model -> ViewOption -> List (Html AppMsg)
nameElements model option =
    let
        name_id =
            View.idAttr "name" option
    in
        case option of
            ReadChoice artifact ->
                [ h1 [ name_id ] [ text artifact.name.raw ] ]

            EditChoice choice ->
                let
                    edited =
                        getEdited choice

                    warn_els =
                        case Nav.checkName model edited.name choice of
                            Ok _ ->
                                []

                            Err e ->
                                [ warning e ]

                    editMsg t =
                        ArtifactsMsg <|
                            EditArtifact <|
                                setEdited choice { edited | name = t }

                    input_el =
                        input
                            [ class "h1"
                            , name_id
                            , onInput editMsg
                            , value edited.name
                            ]
                            []
                in
                    [ input_el ] ++ warn_els



-- TEXT


{-| select which text view to see (raw or rendered)
ids = {ed_, rd_}*text*{raw, rendered}
-}
selectRenderedBtns : Model -> ViewOption -> Html AppMsg
selectRenderedBtns model option =
    let
        newView render =
            let
                view =
                    model.state.textView
            in
                if isRead option then
                    { view | rendered_read = render }
                else
                    { view | rendered_edit = render }

        textView =
            model.state.textView

        ( rendered_clr, raw_clr ) =
            if isTextRendered model option then
                ( "black", "gray" )
            else
                ( "gray", "black" )
    in
        span []
            [ button
                -- rendered
                [ class ("btn bold " ++ rendered_clr)
                , id <| (View.idPrefix option) ++ "select_rendered_text"
                , onClick <| ArtifactsMsg <| ChangeTextViewState <| newView True
                ]
                [ text "rendered" ]
            , button
                -- raw
                [ class ("btn bold " ++ raw_clr)
                , id <| (View.idPrefix option) ++ "select_raw_text"
                , onClick <| ArtifactsMsg <| ChangeTextViewState <| newView False
                ]
                [ text "raw" ]
            ]


isTextRendered : Model -> ViewOption -> Bool
isTextRendered model option =
    let
        view =
            model.state.textView
    in
        if isRead option then
            view.rendered_read
        else
            view.rendered_edit



-- TEXT


displayText : Model -> ViewOption -> Html AppMsg
displayText model option =
    if isTextRendered model option then
        displayRenderedText model option
    else
        displayRawText model option


displayRenderedText : Model -> ViewOption -> Html AppMsg
displayRenderedText model option =
    let
        rawText =
            case option of
                ReadChoice a ->
                    a.text

                EditChoice c ->
                    (getEdited c).text

        rendered =
            replaceArtifactLinks model rawText
    in
        toHtml [ View.idAttr "rendered_text" option ] rendered


{-| display raw text in a way that can be edited
-}
displayRawText : Model -> ViewOption -> Html AppMsg
displayRawText model option =
    let
        ( rawText, editedAttrs ) =
            case option of
                ReadChoice artifact ->
                    ( artifact.text, [] )

                EditChoice choice ->
                    let
                        edited =
                            getEdited choice

                        changedMsg t =
                            ArtifactsMsg <|
                                EditArtifact <|
                                    setEdited choice { edited | text = t }
                    in
                        ( edited.text, [ onInput changedMsg ] )

        attrs =
            [ class "h3"

            -- class=h3 otherwise it is really tiny for some reason
            , rows 35
            , cols 80
            , readonly <| isRead option
            , View.idAttr "raw_text" option
            ]
    in
        textarea (attrs ++ editedAttrs) [ text rawText ]



-- HELPERS


{-| get the full url to a single artifact
-}
fullArtifactUrl : Model -> String -> String
fullArtifactUrl model indexName =
    let
        addrName =
            String.toLower (indexNameUnchecked indexName)

        -- super hacky way to get the origin: might fail for files
        -- I tried location.origin... doesn't work for some reason.
        -- neither does location.host + location.pathname
        origin =
            case List.head (String.split "#" model.location.href) of
                Just o ->
                    removeSlashEnd o

                Nothing ->
                    "ERROR-origin-no-head"
    in
        origin ++ "/" ++ artifactsUrl ++ "/" ++ addrName


removeSlashEnd : String -> String
removeSlashEnd path =
    if String.endsWith "/" path then
        removeSlashEnd (String.dropRight 1 path)
    else
        path


{-| replace [[ART-name]] with [ART-name](link)
-}
replaceArtifactLinks : Model -> String -> String
replaceArtifactLinks model text =
    let
        replace : Regex.Match -> String
        replace match =
            case List.head match.submatches of
                Just m ->
                    case m of
                        Just m ->
                            "[" ++ m ++ "](" ++ (fullArtifactUrl model m) ++ ")"

                        Nothing ->
                            "INTERNAL_ERROR"

                Nothing ->
                    "INTERNAL_ERROR"
    in
        Regex.replace Regex.All artifactLinkRegex replace text


viewEditing : Model -> Html AppMsg
viewEditing model =
    let
        creating : List (Html AppMsg)
        creating =
            case model.create of
                Just c ->
                    [ a
                        [ class "btn bold"
                        , id <| "CREATE_" ++ c.name
                        , onClick <| ArtifactsMsg <| CreateArtifact
                        , href <| "#" ++ createUrl
                        ]
                        [ text <| "Creating " ++ c.name ]
                    ]

                Nothing ->
                    []

        editing =
            Dict.values model.artifacts
                |> List.filter (\a -> isJust a.edited)
                |> List.map (\a -> div [] [ View.seeArtifact model a ])

        header =
            h1
                [ class "h1" ]
                [ text "Artifacts you have not yet saved." ]
    in
        div [ id "editing_view" ]
            (List.concat
                [ [ header ]
                , creating
                , editing
                ]
            )
