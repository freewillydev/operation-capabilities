{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, GADTs, PolyKinds #-}
{-# LANGUAGE RankNTypes, RoleAnnotations, TypeFamilies, TypeOperators #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Typed dispatch envelopes. Indices preserve an application's classification;
-- they do not authorize effects or replace runtime security checks.
module Control.Operation.Severity
  ( Severity(..), OperationDSL(..), SomeOperationAt
  , prepareOperation, resolveOperation ) where

import Control.Operation
import Data.Kind (Type)

data Severity = Safe | Critical

-- | The selected DSL must produce exactly the indexed application's program.
data OperationDSL result op where
  OperationDSL :: Outcome op ~ result => DSL op -> OperationDSL result op

-- | Partially apply through severity for a Servant-style @Type -> Type@ carrier.
-- The constructor is private. Neither coercion nor capability-view changes can
-- relabel the program, caller, severity or result.
type role SomeOperationAt nominal nominal nominal nominal
data SomeOperationAt (program :: callerKind -> Severity -> Type -> Type)
                     (caller :: callerKind) (severity :: Severity) a where
  Classified :: (Operation op caps, Outcome op ~ program caller severity a)
    => SomeOperation -> DSL op -> SomeOperationAt program caller severity a

-- | Select using only visible capabilities; retain canonical evidence for the
-- interpreter. This selects a DSL without interpreting it or executing IO.
prepareOperation
  :: (forall op. (Operation op declared, Capabilities visible op)
      => op -> OperationDSL (program caller severity a) op)
  -> SomeOperationWith declared visible -> SomeOperationAt program caller severity a
prepareOperation select prepared = withCapabilities (\value -> case select value of
  OperationDSL dsl -> Classified (forgetCapabilities prepared) dsl) prepared

-- | Interpret explicitly. Payload mismatch remains 'Nothing'; an IO-valued field
-- in the returned program is not executed. Evaluation belongs to the application.
resolveOperation :: SomeOperationAt program caller severity a -> Maybe (program caller severity a)
resolveOperation (Classified value dsl) = interpret value dsl
