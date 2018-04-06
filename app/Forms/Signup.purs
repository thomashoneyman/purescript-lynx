module App.Forms.Signup where

import Prelude

import Control.Monad.Aff.Class (class MonadAff, liftAff)
import Control.Monad.Aff.Console as Console
import Control.Monad.State (class MonadState, get, modify)
import Data.Either (Either(..))
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.String as String
import Halogen (ComponentHTML) as H
import Halogen.HTML as HH
import Halogen.HTML.Events (input, input_, onBlur, onValueInput) as HE
import Halogen.HTML.Properties as HP
import Lynx.Component as Component
import Lynx.Graph (FormConfig, InputConfig(..), InputRef, input, relate, runFormBuilder, validate)

type SignupForm = FormConfig SignupValidate SignupInput SignupRelation

type User =
  { username :: String
  , password :: String
  }

data SignupInput
  = Text { label :: String }

data SignupRelation
  = MustEqual InputRef
  | Clear InputRef

data SignupValidate
  = InRange Int Int
  | NonEmpty


---------
-- FORM

-- A user signup form
form :: SignupForm
form = runFormBuilder do
  user  <- input (Text { label: "Username" })
    >>= validate NonEmpty
  pass1 <- input (Text { label: "Password 1" })
    >>= validate (InRange 5 15)
    >>= relate (MustEqual user)
  pass2 <- input (Text { label: "Password 2" })
    >>= validate (InRange 5 15)
    >>= relate (Clear pass1)
  pure =<< get

-- A function to run user validation
handleValidation :: SignupValidate -> String -> Either String String
handleValidation v str = case v of
  NonEmpty ->
    if String.null str
      then Left "Field cannot be empty"
      else Right str
  InRange i0 i1 ->
    if String.length str < i0 || String.length str > i1
      then Left $ "Field must be between " <> show i0 <> " and " <> show i1 <> " characters."
      else Right str

-- A function to run user relations
handleRelation :: ∀ eff m
   . MonadState (Component.State SignupValidate SignupInput SignupRelation) m
  => MonadAff (Component.Effects eff) m
  => SignupRelation
  -> InputRef
  -> m Unit
handleRelation relation refA = case relation of
  MustEqual refB -> do
    st <- get
    let equal = do
          v0 <- Map.lookup refA st.form
          v1 <- Map.lookup refB st.form
          pure $ v0 == v1
    case equal of
      Just true -> pure unit
      otherwise -> do
        liftAff $ Console.log $ show refA <> " is NOT equal to " <> show refB
        pure unit

  Clear refB -> do
    modify \st -> st { form = Map.insert refB "" st.form }
    liftAff $ Console.logShow $ "Deleted " <> show refB
    pure unit

-- A function to render user inputs
renderInput
  :: Component.State SignupValidate SignupInput SignupRelation
  -> InputRef
  -> H.ComponentHTML Component.Query
renderInput st ref =
  let attr = HP.attr (HH.AttrName "data-inputref") (show $ unwrap ref)
      config = Map.lookup ref (_.inputs $ unwrap st.config)
   in case config of
        Just (InputConfig { inputType }) -> case inputType of
          Text { label } ->
            HH.div_
              [ HH.text label
              , HH.input
                  [ attr
                  , HE.onValueInput $ HE.input $ Component.UpdateValue ref
                  , HE.onBlur $ HE.input_ $ Component.Blur ref
                  , HP.value $ fromMaybe "field not found in form! nooo" $ Map.lookup ref st.form
                  ]
              ]
        otherwise -> HH.div_ []