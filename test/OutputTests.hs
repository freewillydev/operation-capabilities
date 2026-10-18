{-# LANGUAGE DataKinds, GADTs, ScopedTypeVariables, TypeApplications, TypeOperators #-}
module OutputTests (outputProperties) where

import Control.Operation
import Control.Operation.Capability
import Control.Operation.Flow (Values(..))
import Control.Operation.Outputs
import Control.Operation.Indexed
import qualified CapableOutputs as C
import Data.Maybe (isNothing)
import Data.Proxy (Proxy(..))
import Demo (Note(..))
import Test.QuickCheck
import VariableOutputs
import Type.Reflection (typeRep)
import GHC.TypeLits (Symbol)

newtype Unregistered = Unregistered Int
instance RenderOutput Unregistered where
  renderOutput (Unregistered n) = show n

outputProperties :: [(String, Property)]
outputProperties =
  [("outputs / variable arity and capability preparation", property variableArity),
   ("outputs / optional output plus runtime-sized suffix", property settlement),
   ("outputs / concatenation and equality-constrained composition", property concatenation),
   ("outputs / complete schema check before values", once lazyResolution),
   ("outputs / consumer failure skips later values", once lazyConsumption),
   ("outputs / preparation failure and dispatch mismatch", once preparation),
   ("outputs / existential capabilities with independently kinded parameters", property capable),
   ("outputs / curried capabilities resolve at arities zero, one, two and four", property applications),
   ("outputs / descriptor restriction, preparation and expansion", property descriptorPipeline),
   ("outputs / generic streams preserve variable batches", property streaming),
   ("outputs / bounded demand and failed consumers stop pulls", once streamBoundaries)]

expected :: [Either Integer String] -> [String]
expected = map (either (\n -> show n ++ " sats") id)

settlement :: Integer -> [String] -> Property
settlement change notices = render (Proxy @DisplayOutputs) (settlementOutputs change notices)
  === Just ([show change ++ " sats" | change > 0] ++ notices)

variableArity :: [Either Integer String] -> Property
variableArity inputs = conjoin
  [render (Proxy @DisplayOutputs) (produce inputs) === Just (expected inputs),
   runRequest (Request inputs) === if length inputs > 1000 then Left "Too many outputs"
     else Right (expected inputs)]

concatenation :: [Either Integer String] -> [Either Integer String] -> Property
concatenation first second = case (resolveOutputs (Proxy @DisplayOutputs) (produce first),
                                   resolveOutputs (Proxy @DisplayOutputs) (produce second)) of
  (Just a,Just b) ->
    let joined = withOutputs (mapOutputs renderOutput) (appendChecked a b)
        doubled = withOutputs (\values -> fmap (mapOutputs renderOutput) $
          composeOutputs (Just . (\xs -> appendOutputs xs xs)) Just values) a
    in conjoin [joined === expected (first ++ second), doubled === Just (expected (first ++ first))]
  _ -> counterexample "registered schema was rejected" False

lazyResolution :: Property
lazyResolution = conjoin
  [property (isNothing (resolveOutputs (Proxy @DisplayOutputs)
     (consOutput (error "unregistered value forced" :: Unregistered) emptyOutputs))),
   property (isNothing (resolveOutputs (Proxy @DisplayOutputs)
     (SomeOutputs (MoreTypes (Proxy @Amount) (MoreTypes (Proxy @Bool) NoTypes))
       (error "value spine forced before rejecting later type")))),
   property (case resolveOutputs (Proxy @DisplayOutputs)
     (SomeOutputs (MoreTypes (Proxy @Amount) NoTypes) (error "known values forced during resolution")) of
       Just _ -> True
       Nothing -> False)]

lazyConsumption :: Property
lazyConsumption = case resolveOutputs (Proxy @DisplayOutputs)
    (consOutput (Notice "stop") (consOutput (error "value after failure forced" :: Amount) emptyOutputs)) of
  Nothing -> counterexample "registered schema was rejected" False
  Just values -> withOutputs (foldOutputsM step (0 :: Int)) values === Left "stop"
  where
    step count value = if renderOutput value == "stop" then Left "stop" else Right (count+1)

preparation :: Property
preparation = conjoin
  [runRequest (Request (replicate 1001 (error "outputs forced after preparation failed"))) === Left "Too many outputs",
   interpret (SomeOperation (Request [])) Render === Just (Right []),
   interpret (SomeOperation (error "mismatched payload forced" :: Note))
     (error "mismatched DSL forced" :: DSL Request) === Nothing,
   render (Proxy @DisplayOutputs) (SomeOutputs NoTypes VNil) === Just []]

capable :: Integer -> Integer -> Property
capable n delta = case (C.textOutput n, C.slotOutput n) of
  (Right textValue, Right slotValue) -> conjoin
    [interpretOutput textValue (typeRep @'C.TextView) () === Just (show n ++ " sats"),
     interpretOutput slotValue (typeRep @('C.Slot 24)) delta === Just ("slot 24: " ++ show (n+delta)),
     interpretOutput textValue (typeRep @('C.Slot 24)) (error "wrong-kind input forced") === Nothing,
     interpretOutput slotValue (typeRep @'C.TextView) (error "wrong-kind input forced") === Nothing,
     property (isNothing (interpretOutput slotValue (typeRep @('C.Slot 25))
       (error "unregistered index input forced"))),
     property (case C.textOutput (error "hidden payload forced during mismatched dispatch") of
       Right lazyValue -> isNothing (interpretOutput lazyValue (typeRep @('C.Slot 24)) undefined)
       Left _ -> False),
     property (isNothing (discoverRequest @C.BalanceCaps (typeRep @'C.TextView)
       (typeRep @('C.Slot 24)) (error "mismatched request input forced"))),
     property (case matchIndex @C.BalanceCaps (typeRep @'C.TextView) (typeRep @'C.TextView) of
       Just IndexMatch -> True
       Nothing -> False)]
  _ -> counterexample "capability restriction failed" False

applications :: Integer -> Property
applications n = conjoin
  [applicationArity (Resolved :: Application (Eq Int) (Eq Int)) === 0,
   applicationArity (Argument (Proxy @Int) Resolved :: Application Show (Show Int)) === 1,
   applicationArity (Argument (Proxy @"sats") (Argument (Proxy @C.Balance) Resolved)
     :: Application (C.Describe @Symbol) (C.Describe "sats" C.Balance)) === 2,
   applicationArity (C.quoteApplication @C.Balance) === 4,
   withCapability (C.quoteApplication @C.Balance)
     (C.quote (Proxy @"BTC") (Proxy @24) (C.Balance n)) === "BTC / slot 24: " ++ show n,
   (C.quoteOutput n >>= \o -> Right (interpretOutput o (typeRep @'C.QuoteView) ()))
     === Right (Just ("BTC / slot 24: " ++ show n)),
   (C.quoteOutput n >>= \o -> Right (interpretOutput o (typeRep @'C.TextView) undefined))
     === Right Nothing]

descriptorPipeline :: Integer -> Integer -> Property
descriptorPipeline n delta =
  let stages = Restrict (Proxy @'[C.Adjustment]) :>>>
        Preserve (Stage (Right . C.adjust delta)) :>>>
        Expand (Proxy @C.BalanceCaps) :>>> Restrict (Proxy @'[C.Quotation])
  in case pipeline stages (prepare (C.Balance n)) of
    Left message -> counterexample message False
    Right prepared -> interpretOutput
      (SomeCapabilityOutput (CapabilityOutput (typeRep @'C.QuoteView) prepared))
      (typeRep @'C.QuoteView) () === Just ("BTC / slot 24: " ++ show (n+delta))

streaming :: [[Either Integer String]] -> Property
streaming batches =
  let source = unfoldOutputs pull batches
      prepared = throughOutputs (Right . consOutput (Notice "prepared")) $
        throughOutputs Right source
      consume acc batch = case interpretOutputs batch DisplayBatch of
        Nothing -> Left "schema mismatch"
        Just rendered -> Right (rendered:acc)
  in fmap reverse (foldStreamM consume [] prepared) ===
      Right (map (("prepared":) . expected) batches)
  where
    pull [] = Right Nothing
    pull (batch:rest) = Right (Just (produce batch,rest))

streamBoundaries :: Property
streamBoundaries = conjoin
  [foldStreamM count (0 :: Int) (takeOutputs 0 (error "zero limit pulled source")) === Right 0,
   foldStreamM count (0 :: Int) (takeOutputs 200000 infinite) === Right 200000,
   foldStreamM reject () (OutputStream (Right (Just (emptyOutputs,error "failed consumer pulled tail"))))
     === Left "stop",
   foldStreamM count (0 :: Int) (throughOutputs (const (Left "stage failed"))
     (OutputStream (Right (Just (emptyOutputs,error "failed stage pulled tail"))))) === Left "stage failed",
   foldStreamM count (0 :: Int) (throughOutputs (error "empty source invoked stage")
     (OutputStream (Right Nothing))) === Right 0,
   foldStreamM count (0 :: Int) (throughOutputs (error "failed source invoked stage")
     (OutputStream (Left "source failed"))) === Left "source failed",
   foldStreamM count (0 :: Int) (OutputStream (Left "source failed")) === Left "source failed"]
  where
    count n _ = Right (n+1) :: Either String Int
    reject _ _ = Left "stop" :: Either String ()
    infinite = unfoldOutputs (\() -> Right (Just (emptyOutputs,()))) ()
