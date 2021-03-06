module App.Components.Home where

import Prelude

import App.Components.Builder (FormConfig')
import Data.Argonaut (decodeJson)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Effect.Aff (Aff)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Lynx.Data.Graph (FormConfig(..), FormId(..))
import Network.HTTP.Affjax (get)
import Network.HTTP.Affjax.Response (json) as Response
import Web.HTML (window)
import Web.HTML.Location (setHash)
import Web.HTML.Window (location)

----------
-- Router

data Query a
  = Initialize a
  | Navigate Location a

data Location
  = Form FormId
  | Builder FormId

type Input = Unit
type State = { forms :: Array FormConfig' }

component :: H.Component HH.HTML Query Input Void Aff
component =
  H.lifecycleComponent
  { initialState: const { forms: [] }
  , render
  , eval
  , receiver: const Nothing
  , initializer: Just $ H.action Initialize
  , finalizer: Nothing
  }
  where
    render
      :: State
      -> H.ComponentHTML Query
    render st = case length st.forms of
      0 ->
        HH.div_
          [ HH.text "There are no forms! Try adding a new one."
          , HH.br_
          , HH.a
            [ HE.onClick $ HE.input_ $ Navigate (Builder $ FormId 0) ]
            [ HH.text "/#/builder/0" ]
          ]
      n ->
        HH.div_
          [ HH.text "Use an existing form below, or try adding a new one."
          , HH.br_
          , HH.a
            [ HE.onClick $ HE.input_ $ Navigate (Builder $ FormId (n + 1)) ]
            [ HH.text $ "/#/forms/" <> show (n + 1) ]
          , HH.br_
          , HH.ul_ $ st.forms <#> \(FormConfig { id }) ->
              HH.li
              [ HE.onClick $ HE.input_ $ Navigate (Form id) ]
              [ HH.text $ "/#/forms/" <> (show <<< unwrap) id ]
          ]

    eval :: Query ~> H.ComponentDSL State Query Void Aff
    eval = case _ of
      Initialize a -> do
        forms <- H.liftAff getForms
        case forms of
          Left _ -> pure a
          Right f -> H.modify_ _ { forms = f } *> pure a

      Navigate loc a -> do
        let run str formId = H.liftEffect $ setHash ("#/" <> str <> "/" <> (show <<< unwrap) formId) =<< location =<< window
        case loc of
          Form fid -> run "forms" fid
          Builder fid -> run "builder" fid
        pure a

getForms :: Aff (Either String (Array FormConfig'))
getForms =
  decodeJson <<< _.response <$> get Response.json ("http://localhost:3000/forms/")
