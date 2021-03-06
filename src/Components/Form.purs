module Lynx.Components.Form where

import Prelude

import Control.Monad.State.Class (class MonadState)
import Data.Argonaut (class DecodeJson, decodeJson)
import Data.Array (fromFoldable) as Array
import Data.Either (Either(..))
import Data.Either.Nested (Either3)
import Data.Foldable (foldr)
import Data.Functor.Coproduct (Coproduct)
import Data.Functor.Coproduct.Nested (Coproduct3)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Newtype (unwrap)
import Data.Traversable (traverse_)
import Data.Tuple (Tuple(..))
import Effect.Aff.Class (class MonadAff)
import Effect.Console as Console
import Halogen as H
import Halogen.Component.ChildPath (ChildPath)
import Halogen.Component.ChildPath as CP
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Lynx.Data.Graph (FormConfig(..), InputConfig(..), InputRef, FormId(..))
import Network.HTTP.Affjax (get)
import Network.HTTP.Affjax.Response (json) as Response
import Ocelot.Components.DatePicker as DatePicker
import Ocelot.Components.TimePicker as TimePicker
import Ocelot.Components.Typeahead as TA

-- `i` is the Input type
data Query v i r a
  = HandleTypeahead InputRef (TA.Message (Query v i r) String) a
  | HandleDatePicker InputRef DatePicker.Message a
  | HandleTimePicker InputRef TimePicker.Message a
  | UpdateValue InputRef (i -> i) a
  | Blur InputRef (i -> i) a -- reset function
  | GetForm FormId a
  | Submit a
  | Initialize a
  | Receiver (Input v i r) a

type ComponentConfig v i r m =
  { handleInput
    :: State v i r
    -> InputRef
    -> ComponentHTML v i r m
  , handleValidate
    :: v
    -> i
    -> i
  , handleRelate
    :: r
    -> InputRef
    -> ComponentDSL v i r m Unit
  , initialize
    :: ComponentDSL v i r m Unit
  }

type Input v i r = Either (Tuple (FormConfig v i r) Boolean) FormId

data Message

type State v i r =
  { config       :: FormConfig v i r
  , form         :: Map InputRef i
  , selectedForm :: FormId
  , fromDB       :: Boolean
  , runForeign   :: Boolean
  }

inputAp :: ∀ i. (i -> i) -> InputRef -> Map InputRef i -> Map InputRef i
inputAp f ref orig
  = fromMaybe orig new
  where
    new = do
      type' <- Map.lookup ref orig
      pure $ Map.insert ref (f type') orig


----------
-- Component Types

type Component v i r m
  = H.Component HH.HTML (Query v i r) (Input v i r) Message m

type ComponentHTML v i r m
  = H.ParentHTML (Query v i r) (ChildQuery v i r m) ChildSlot m

type ComponentDSL v i r m
  = H.ParentDSL (State v i r) (Query v i r) (ChildQuery v i r m) ChildSlot Message m

type ChildSlot = Either3
  String
  String
  String

type ChildQuery v i r m = Coproduct3
  ( TA.Query (Query v i r) String String m )
  DatePicker.Query
  TimePicker.Query

typeaheadCP
  :: forall f1 g p1 q
   . ChildPath f1 (Coproduct f1 g) p1 (Either p1 q)
typeaheadCP = CP.cp1

datePickerCP
  :: forall f1 f2 g p1 p2 q
   . ChildPath f2 (Coproduct f1 (Coproduct f2 g)) p2 (Either p1 (Either p2 q))
datePickerCP = CP.cp2

timePickerCP
  :: forall f1 f2 f3 g p1 p2 p3 q
   . ChildPath f3 (Coproduct f1 (Coproduct f2 (Coproduct f3 g))) p3 (Either p1 (Either p2 (Either p3 q)))
timePickerCP = CP.cp3

component :: ∀ v i r m
   . DecodeJson v
  => DecodeJson i
  => DecodeJson r
  => MonadAff m
  => ComponentConfig v i r m
  -> Component v i r m
component { handleInput, handleValidate, handleRelate, initialize } =
  H.lifecycleParentComponent
    { initialState
    , render
    , eval
    , receiver: HE.input Receiver
    , initializer: Just (H.action Initialize)
    , finalizer: Nothing
    }
  where
    initialState = case _ of
      Left (Tuple config runForeign) ->
        { form: (_.inputType <<< unwrap) <$> (_.inputs <<< unwrap $ config)
        , config
        , selectedForm: FormId (-1)
        , fromDB: false
        , runForeign
        }
      Right formId ->
        { config: FormConfig
          { id: FormId (-1)
          , supply: 0
          , inputs: Map.empty
          }
        , form: Map.empty
        , selectedForm: formId
        , fromDB: true
        , runForeign: false
        }

    eval
      :: Query v i r
      ~> ComponentDSL v i r m
    eval = case _ of
      Initialize a -> a <$ do
        state <- H.get
        if state.fromDB
          then do
            eval (GetForm state.selectedForm a)
            *> initialize
          else if state.runForeign
            then initialize
            else pure unit

      Receiver (Left (Tuple config runForeign)) a -> do
        H.modify_ _
          { config = config
          , form = (_.inputType <<< unwrap)
               <$> (_.inputs <<< unwrap $ config)
          , runForeign = runForeign
          }
        eval (Initialize a)
      Receiver (Right _) a -> pure a

      GetForm i a -> a <$ do
        res <- H.liftAff $
          _.response <$> get Response.json ("http://localhost:3000/forms/" <> (show $ unwrap i))
        case decodeJson res of
          Left s -> H.liftEffect $ Console.log s *> pure a
          Right config -> do
            H.modify_ _
              { config = config
              , form = (_.inputType <<< unwrap) <$> (_.inputs <<< unwrap $ config)
              }
            pure a

      HandleTypeahead ref m a -> case m of
        TA.Emit q -> eval q *> pure a
        TA.Searched _ -> pure a
        TA.SelectionsChanged _ items -> do
          -- Update the input with the new array
          let arr = case items of
               TA.Many xs -> xs
               TA.Limit _ xs -> xs
               TA.One x -> maybe [] pure x
          pure a
        TA.VisibilityChanged v -> pure a

      HandleDatePicker ref m a -> case m of
        DatePicker.SelectionChanged _ -> pure a
        DatePicker.VisibilityChanged _ -> pure a
        DatePicker.Searched _ -> pure a

      HandleTimePicker ref m a -> case m of
        TimePicker.SelectionChanged _ -> pure a
        TimePicker.VisibilityChanged v -> pure a
        TimePicker.Searched _ -> pure a

      UpdateValue ref func a -> a <$ do
        H.modify_ \st -> st { form = inputAp func ref st.form }

      Blur ref f a -> do
        runRelations ref handleRelate
        runValidations ref f handleValidate
        pure a

      Submit a -> a <$ do
        refs <- H.gets (Map.keys <<< _.form)
        traverse_ (flip runRelations $ handleRelate) refs

    render
      :: State v i r
      -> ComponentHTML v i r m
    render st = HH.div_
      [ HH.div_
        $ handleInput st <$> (Array.fromFoldable $ Map.keys st.form)
      , HH.button
          [ HE.onClick (HE.input_ Submit) ]
          [ HH.text "Submit" ]
      ]

-- Attempt to use the provided validation helper to run on the form validations
runValidations :: ∀ v i r m
  . MonadAff m
 => InputRef
 -> (i -> i) -- reset
 -> (v -> i -> i)
 -> H.ParentDSL
      (State v i r)
      (Query v i r)
      (ChildQuery v i r m)
      ChildSlot
      Message
      m
      Unit
runValidations ref reset validate = do
  st <- H.get
  case Map.lookup ref (_.inputs $ unwrap st.config) of
    Nothing -> do
       H.liftEffect $ Console.log $ "Could not find ref " <> show ref <> " in config."
       pure unit
    Just (InputConfig config) -> case Map.lookup ref st.form of
      Nothing -> do
        H.liftEffect $ Console.log $ "Could not find ref " <> show ref <> " in form."
        pure unit
      Just input -> do
        let type' = foldr (\v i -> validate v i) (reset input) config.validations
        H.modify_ _ { form = inputAp (const type') ref st.form }
        pure unit

-- Attempt to use the provided relations helper to run on form relations
runRelations :: ∀ v i r m
  . MonadState (State v i r) m
 => InputRef
 -> (r -> InputRef -> m Unit)
 -> m Unit
runRelations ref runRelation = do
  st <- H.get
  case Map.lookup ref (_.inputs $ unwrap st.config) of
    Nothing ->
       pure unit
    Just (InputConfig config) -> do
      traverse_ (flip runRelation $ ref) config.relations
      pure unit
