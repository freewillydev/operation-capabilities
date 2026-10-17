{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs, MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables, TypeApplications, TypeFamilies, TypeOperators #-}
module VariableOutputs where

import Control.Operation
import Control.Operation.Outputs
import Data.Proxy (Proxy(..))
import Data.Typeable (eqT, (:~:)(Refl))

newtype Amount = Amount Integer
newtype Notice = Notice String
class RenderOutput a where
  renderOutput :: a -> String
instance RenderOutput Amount where
  renderOutput (Amount n) = show n ++ " sats"
instance RenderOutput Notice where
  renderOutput (Notice message) = message

data DisplayOutputs
instance OutputSchema DisplayOutputs where
  type OutputCapability DisplayOutputs = RenderOutput
  resolveOutput _ (_ :: Proxy a) = case eqT @a @Amount of
    Just Refl -> Just OutputDict
    Nothing -> case eqT @a @Notice of
      Just Refl -> Just OutputDict
      Nothing -> Nothing
instance OutputRendering DisplayOutputs where
  type RenderedOutput DisplayOutputs = String
  renderOne _ = renderOutput

instance OutputInterpreter DisplayOutputs where
  data OutputDSL DisplayOutputs result where
    DisplayBatch :: OutputRendering DisplayOutputs => OutputDSL DisplayOutputs [String]
  interpretOutputs raw DisplayBatch = render (Proxy @DisplayOutputs) raw

produce :: [Either Integer String] -> SomeOutputs
produce = foldr (either (consOutput . Amount) (consOutput . Notice)) emptyOutputs

-- Arity depends on runtime data: optional change plus any number of notices.
settlementOutputs :: Integer -> [String] -> SomeOutputs
settlementOutputs change notices =
  let rest = foldr (consOutput . Notice) emptyOutputs notices
  in if change > 0 then consOutput (Amount change) rest else rest

class Produce op where
  produceOutputs :: op -> SomeOutputs
class Inspect op where
  inspectRequest :: op -> Either String op
newtype Request = Request [Either Integer String]
instance Produce Request where
  produceOutputs (Request selections) = produce selections
instance Inspect Request where
  inspectRequest request@(Request selections)
    | length selections > 1000 = Left "Too many outputs"
    | otherwise = Right request

type RequestCaps = '[Produce, Inspect]
outputPipeline :: Pipeline RequestCaps RequestCaps '[Produce]
outputPipeline = Restrict (Proxy @'[Inspect]) :>>> Preserve (Stage inspectRequest)
  :>>> Expand (Proxy @RequestCaps) :>>> Restrict (Proxy @'[Produce])

runRequest :: Request -> Either String [String]
runRequest request = do
  prepared <- pipeline outputPipeline (prepare request)
  maybe (Left "Unregistered output type") Right $
    interpretOutputs (withCapabilities produceOutputs prepared) DisplayBatch

-- The source can be a live poller. Preparation keeps each batch existential;
-- even its optional Amount and runtime-sized Notice suffix remain uninterpreted.
settlementStream :: Monad m => (s -> m (Maybe ((Integer, [String]), s))) -> s -> OutputStream m
settlementStream pull = unfoldOutputs $ \state -> do
  next <- pull state
  pure (fmap (\((change, notices), rest) -> (settlementOutputs change notices, rest)) next)

instance Operation Request RequestCaps where
  type Context Request = Produce Request
  type Outcome Request = Either String [String]
  data DSL Request where Render :: DSL Request
  interpret (SomeOperation (value :: actual)) request = case eqT @actual @Request of
    Just Refl -> case request of Render -> Just (runRequest value)
    Nothing -> Nothing

-- The shapes of both batches are existential. Append retains their type-level
-- concatenation, rather than turning their values into an untyped container.
appendChecked :: SomeCheckedOutputs cap -> SomeCheckedOutputs cap -> SomeCheckedOutputs cap
appendChecked (SomeCheckedOutputs first) (SomeCheckedOutputs second) =
  SomeCheckedOutputs (appendOutputs first second)
