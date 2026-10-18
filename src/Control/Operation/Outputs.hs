{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, GADTs, KindSignatures, PolyKinds, RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Runtime-variable heterogeneous outputs. Resolve the complete type spine
-- before inspecting values or invoking methods. A registry supplies dictionaries;
-- type equality alone cannot manufacture them.
module Control.Operation.Outputs
  (OutputTypes(..), SomeOutputs(..), emptyOutputs, consOutput,
   OutputDict(..), OutputSchema(..), OutputRendering(..), OutputInterpreter(..), CheckedOutputs, SomeCheckedOutputs(..),
   resolveOutputs, withOutputs, foldOutputsM, mapOutputs,
   Append, appendOutputs, composeOutputs,
   OutputStream(..), unfoldOutputs, throughOutputs, takeOutputs, foldStreamM,
   CapabilityOutput(..), SomeCapabilityOutput(..), interpretOutput) where

import Control.Operation (SomeOperationWith, withCapabilities)
import Control.Operation.Flow (Values(..))
import Control.Operation.Indexed (IndexedCapability(..))
import Data.Kind (Constraint, Type)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable)
import Type.Reflection (TypeRep, eqTypeRep, (:~~:)(HRefl))

-- | Each output hides its own operation payload and declared capabilities.
-- The index class generates the visible constraints, including partially
-- applied classes with parameters of different kinds. Prepare the view using
-- the ordinary Restrict/Preserve/Expand pipeline before constructing an output.
data CapabilityOutput (index :: k) where
  CapabilityOutput :: IndexedCapability index caps
    => TypeRep index -> SomeOperationWith declared caps -> CapabilityOutput index

data SomeCapabilityOutput where
  SomeCapabilityOutput :: CapabilityOutput index -> SomeCapabilityOutput

-- | Like interpret: mismatch is Nothing; effects/domain failure remain in the
-- selected result. HRefl also refines the capability list, bringing its methods
-- into scope for the independently kinded selected index.
interpretOutput :: SomeCapabilityOutput -> TypeRep selected -> IndexInput selected
  -> Maybe (IndexOutput selected)
interpretOutput (SomeCapabilityOutput (CapabilityOutput actual prepared)) selected input =
  case eqTypeRep actual selected of
    Nothing -> Nothing
    Just HRefl -> Just (withCapabilities (\value -> runIndexed selected value input) prepared)

data OutputTypes (xs :: [Type]) where
  NoTypes :: OutputTypes '[]
  MoreTypes :: Typeable x => Proxy x -> OutputTypes xs -> OutputTypes (x ': xs)

data SomeOutputs where
  SomeOutputs :: OutputTypes xs -> Values xs -> SomeOutputs

emptyOutputs :: SomeOutputs
emptyOutputs = SomeOutputs NoTypes VNil

consOutput :: Typeable x => x -> SomeOutputs -> SomeOutputs
consOutput value (SomeOutputs types values) =
  SomeOutputs (MoreTypes Proxy types) (value :& values)

data OutputDict (cap :: Type -> Constraint) x where
  OutputDict :: cap x => OutputDict cap x

class OutputSchema schema where
  type OutputCapability schema :: Type -> Constraint
  resolveOutput :: Typeable x => Proxy schema -> Proxy x
    -> Maybe (OutputDict (OutputCapability schema) x)

-- | Optional pure rendering for a schema. Effectful consumers use foldOutputsM.
class OutputSchema schema => OutputRendering schema where
  type RenderedOutput schema :: Type
  renderOne :: OutputCapability schema x => Proxy schema -> x -> RenderedOutput schema
  render :: Proxy schema -> SomeOutputs -> Maybe [RenderedOutput schema]
  render schema raw = withOutputs (mapOutputs (renderOne schema)) <$> resolveOutputs schema raw

-- | Like Operation.interpret, a request GADT selects behavior and its result.
-- Resolve the complete batch before calling recovered methods. Nothing means
-- schema mismatch; put domain failures and effects inside the result type.
class OutputSchema schema => OutputInterpreter schema where
  data OutputDSL schema :: Type -> Type
  interpretOutputs :: SomeOutputs -> OutputDSL schema result -> Maybe result

data Methods cap xs where
  NoMethods :: Methods cap '[]
  MoreMethods :: cap x => Methods cap xs -> Methods cap (x ': xs)

data CheckedOutputs cap xs = CheckedOutputs (Methods cap xs) (Values xs)
data SomeCheckedOutputs cap where
  SomeCheckedOutputs :: CheckedOutputs cap xs -> SomeCheckedOutputs cap

resolveOutputs :: forall schema. OutputSchema schema => Proxy schema -> SomeOutputs
  -> Maybe (SomeCheckedOutputs (OutputCapability schema))
resolveOutputs schema (SomeOutputs types values) = do
  methods <- go types
  pure (SomeCheckedOutputs (CheckedOutputs methods values))
  where
    go :: OutputTypes xs -> Maybe (Methods (OutputCapability schema) xs)
    go NoTypes = Just NoMethods
    go (MoreTypes proxy rest) = case resolveOutput schema proxy of
      Nothing -> Nothing
      Just OutputDict -> MoreMethods <$> go rest

withOutputs :: (forall xs. CheckedOutputs cap xs -> r) -> SomeCheckedOutputs cap -> r
withOutputs use (SomeCheckedOutputs outputs) = use outputs

foldOutputsM :: forall cap m s xs. Monad m
  => (forall x. cap x => s -> x -> m s) -> s -> CheckedOutputs cap xs -> m s
foldOutputsM step initial (CheckedOutputs methods values) = go methods values initial
  where
    go :: Methods cap ys -> Values ys -> s -> m s
    go NoMethods VNil state = pure state
    go (MoreMethods rest) (value :& remaining) state =
      step state value >>= go rest remaining

mapOutputs :: forall cap b xs. (forall x. cap x => x -> b) -> CheckedOutputs cap xs -> [b]
mapOutputs project (CheckedOutputs methods values) = go methods values
  where
    go :: Methods cap ys -> Values ys -> [b]
    go NoMethods VNil = []
    go (MoreMethods rest) (value :& remaining) = project value : go rest remaining

type family Append xs ys where
  Append '[] ys = ys
  Append (x ': xs) ys = x ': Append xs ys

-- | The equality refines the output index; it is not a cast or a runtime test.
appendOutputs :: (Append xs ys ~ zs)
  => CheckedOutputs cap xs -> CheckedOutputs cap ys -> CheckedOutputs cap zs
appendOutputs (CheckedOutputs first xs) (CheckedOutputs second ys) =
  CheckedOutputs (methods first second) (values xs ys)
  where
    methods :: Methods cap as -> Methods cap bs -> Methods cap (Append as bs)
    methods NoMethods rest = rest
    methods (MoreMethods rest) suffix = MoreMethods (methods rest suffix)
    values :: Values as -> Values bs -> Values (Append as bs)
    values VNil rest = rest
    values (value :& rest) suffix = value :& values rest suffix

-- | Compose only when the complete intermediate output lists agree.
composeOutputs :: Monad m
  => (CheckedOutputs cap before -> m (CheckedOutputs cap middle))
  -> (CheckedOutputs cap middle -> m (CheckedOutputs cap after))
  -> CheckedOutputs cap before -> m (CheckedOutputs cap after)
composeOutputs first second values = first values >>= second

-- | Pull-based, uninterpreted finite batches; each batch has its own hidden
-- length and types. No buffering, background work, or implicit resource ownership.
newtype OutputStream m = OutputStream
  { nextOutputs :: m (Maybe (SomeOutputs, OutputStream m)) }

unfoldOutputs :: Functor m => (s -> m (Maybe (SomeOutputs, s))) -> s -> OutputStream m
unfoldOutputs pull state = OutputStream $
  fmap (fmap (\(batch, next) -> (batch, unfoldOutputs pull next))) (pull state)

-- | Transport/prepare batches without resolving an output schema. A stage may
-- change arity; the resulting existential package retains its new type spine.
throughOutputs :: Monad m => (SomeOutputs -> m SomeOutputs) -> OutputStream m -> OutputStream m
throughOutputs stage = unfoldOutputs $ \stream -> nextOutputs stream >>=
  traverse (\(batch, rest) -> (\prepared -> (prepared, rest)) <$> stage batch)

-- | Limit pulls, not individual outputs. A zero limit never touches the source.
takeOutputs :: Applicative m => Int -> OutputStream m -> OutputStream m
takeOutputs count stream
  | count <= 0 = OutputStream (pure Nothing)
  | otherwise = OutputStream $
      fmap (fmap (\(batch, rest) -> (batch, takeOutputs (count-1) rest))) (nextOutputs stream)

-- | Consume in order with a WHNF-strict accumulator. Monad failure stops pulls;
-- there is no rollback. Callers must bracket resources and bound each batch.
foldStreamM :: Monad m => (s -> SomeOutputs -> m s) -> s -> OutputStream m -> m s
foldStreamM consume state stream = state `seq` do
  next <- nextOutputs stream
  case next of
    Nothing -> pure state
    Just (batch, rest) -> consume state batch >>= \updated -> foldStreamM consume updated rest
