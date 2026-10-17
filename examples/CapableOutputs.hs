{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, PolyKinds, ScopedTypeVariables, TypeApplications, TypeFamilies #-}
module CapableOutputs where

import Control.Operation
import Control.Operation.Indexed
import Control.Operation.Outputs
import Data.Proxy (Proxy(..))
import Data.Typeable (eqT, (:~:)(Refl))
import GHC.TypeLits (Nat)
import Type.Reflection (typeRep)

-- The same capability class accepts Symbol and Slot parameters.
class Describe (label :: k) op where
  describe :: Proxy label -> op -> String
class Adjust op where
  adjust :: Integer -> op -> op
data View = TextView
data Slot = Slot Nat
newtype Balance = Balance Integer
instance Describe "sats" Balance where
  describe _ (Balance n) = show n ++ " sats"
instance Describe ('Slot 24) Balance where
  describe _ (Balance n) = "slot 24: " ++ show n
instance Adjust Balance where
  adjust delta (Balance n) = Balance (n+delta)

type BalanceCaps = '[Describe "sats", Describe ('Slot 24), Adjust]
instance Operation Balance BalanceCaps where
  type Context Balance = (Describe "sats" Balance, Describe ('Slot 24) Balance, Adjust Balance)
  type Outcome Balance = String
  data DSL Balance where ReadBalance :: Context Balance => DSL Balance
  interpret (SomeOperation (value :: actual)) request = case eqT @actual @Balance of
    Nothing -> Nothing
    Just Refl -> case request of ReadBalance -> Just (describe (Proxy @"sats") value)

-- These index classes generate different method dictionaries and input types.
instance IndexedCapability 'TextView where
  type IndexCaps 'TextView = '[Describe "sats"]
  type IndexInput 'TextView = ()
  type IndexOutput 'TextView = String
  runIndexed _ value () = describe (Proxy @"sats") value
instance IndexedCapability ('Slot 24) where
  type IndexCaps ('Slot 24) = '[Adjust, Describe ('Slot 24)]
  type IndexInput ('Slot 24) = Integer
  type IndexOutput ('Slot 24) = String
  runIndexed _ value delta = describe (Proxy @('Slot 24)) (adjust delta value)

textOutput :: Integer -> Either String SomeCapabilityOutput
textOutput n = SomeCapabilityOutput . CapabilityOutput (typeRep @'TextView) <$>
  pipeline (Restrict (Proxy @'[Describe "sats"])) (prepare (Balance n))

slotOutput :: Integer -> Either String SomeCapabilityOutput
slotOutput n = SomeCapabilityOutput . CapabilityOutput (typeRep @('Slot 24)) <$>
  pipeline (Restrict (Proxy @'[Adjust, Describe ('Slot 24)])) (prepare (Balance n))

-- A runtime-sized batch of outputs, each with its own existential payload and
-- methods. No rendering or adjustment happens while assembling or streaming it.
capableBatch :: [(Bool, Integer)] -> Either String SomeOutputs
capableBatch = fmap (foldr consOutput emptyOutputs) . traverse (\(slot,n) ->
  if slot then slotOutput n else textOutput n)
