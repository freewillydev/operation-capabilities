{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, PolyKinds, ScopedTypeVariables, TypeApplications, TypeFamilies #-}
module CapableOutputs where

import Control.Operation
import Control.Operation.Capability
import Control.Operation.Indexed
import Control.Operation.Outputs
import Data.Proxy (Proxy(..))
import Data.Kind (Constraint, Type)
import GHC.TypeLits (Nat, Symbol)
import Type.Reflection (typeRep)

-- The same capability class accepts Symbol and Slot parameters.
class Describe (label :: k) op where
  describe :: Proxy label -> op -> String
class Adjust op where
  adjust :: Integer -> op -> op
class Quote (unit :: Symbol) (slot :: Nat) op result where
  quote :: Proxy unit -> Proxy slot -> op -> result
data View = TextView | QuoteView
data Slot = Slot Nat
newtype Balance = Balance Integer
instance Describe "sats" Balance where
  describe _ (Balance n) = show n ++ " sats"
instance Describe ('Slot 24) Balance where
  describe _ (Balance n) = "slot 24: " ++ show n
instance Adjust Balance where
  adjust delta (Balance n) = Balance (n+delta)
instance Quote "BTC" 24 Balance String where
  quote _ _ (Balance n) = "BTC / slot 24: " ++ show n

type TextDescription = 'OnPayload ('Apply ('Class (Describe :: Symbol -> Type -> Constraint)) "sats")
type SlotDescription = 'OnPayload ('Apply ('Class (Describe :: Slot -> Type -> Constraint)) ('Slot 24))
type Adjustment = 'OnPayload ('Class Adjust)
-- Payload is the third of four arguments, not necessarily the last argument.
type Quotation = 'Apply ('OnPayload ('Apply ('Apply ('Class Quote) "BTC") 24)) String
type BalanceCaps = '[TextDescription, SlotDescription, Adjustment, Quotation]
instance Operation Balance BalanceCaps where
  type Context Balance = (Describe "sats" Balance, Describe ('Slot 24) Balance, Adjust Balance)
  type Outcome Balance = String
  data DSL Balance where ReadBalance :: Context Balance => DSL Balance
  interpret operation request = withOperation @Balance operation $ \value ->
    case request of ReadBalance -> Just (describe (Proxy @"sats") value)

-- These index classes generate different method dictionaries and input types.
instance IndexedCapability 'TextView '[TextDescription] where
  type IndexInput 'TextView = ()
  type IndexOutput 'TextView = String
  runIndexed _ value () = describe (Proxy @"sats") value
instance IndexedCapability ('Slot 24) '[Adjustment, SlotDescription] where
  type IndexInput ('Slot 24) = Integer
  type IndexOutput ('Slot 24) = String
  runIndexed _ value delta = describe (Proxy @('Slot 24)) (adjust delta value)
instance IndexedCapability 'QuoteView '[Quotation] where
  type IndexInput 'QuoteView = ()
  type IndexOutput 'QuoteView = String
  runIndexed _ (value :: op) () = withCapability (quoteApplication @op) $
    quote (Proxy @"BTC") (Proxy @24) value

quoteApplication :: forall op. Quote "BTC" 24 op String
  => Application Quote (Quote "BTC" 24 op String)
quoteApplication = Argument (Proxy @"BTC") $ Argument (Proxy @24) $
  Argument (Proxy @op) $ Argument (Proxy @String) Resolved

textOutput :: Integer -> Either String SomeCapabilityOutput
textOutput n = SomeCapabilityOutput . CapabilityOutput (typeRep @'TextView) <$>
  pipeline (Restrict (Proxy @'[TextDescription])) (prepare (Balance n))

slotOutput :: Integer -> Either String SomeCapabilityOutput
slotOutput n = SomeCapabilityOutput . CapabilityOutput (typeRep @('Slot 24)) <$>
  pipeline (Restrict (Proxy @'[Adjustment, SlotDescription])) (prepare (Balance n))

quoteOutput :: Integer -> Either String SomeCapabilityOutput
quoteOutput n = SomeCapabilityOutput . CapabilityOutput (typeRep @'QuoteView) <$>
  pipeline (Restrict (Proxy @'[Quotation])) (prepare (Balance n))

-- A runtime-sized batch of outputs, each with its own existential payload and
-- methods. No rendering or adjustment happens while assembling or streaming it.
capableBatch :: [(Bool, Integer)] -> Either String SomeOutputs
capableBatch = fmap (foldr consOutput emptyOutputs) . traverse (\(slot,n) ->
  if slot then slotOutput n else textOutput n)
