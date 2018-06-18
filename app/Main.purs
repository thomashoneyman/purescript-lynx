module Main where

import Prelude

import App.Router as R
import Effect.Aff (launchAff)
import Effect (Eff)
import Effect.Class (liftEff)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Routing.Hash (matches)

main :: ∀ eff. Eff (HA.HalogenEffects (R.Effects eff)) Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  driver <- runUI R.component R.Index body
  liftEff $ matches R.route $ \_ new -> do
    _ <- launchAff $ driver.query $ R.Navigate new unit
    pure unit
