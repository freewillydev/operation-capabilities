{-# LANGUAGE AllowAmbiguousTypes, ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies, GADTs, RankNTypes, RoleAnnotations, ScopedTypeVariables, TypeApplications #-}
{-# LANGUAGE TypeFamilyDependencies, TypeOperators, UndecidableInstances, UndecidableSuperClasses #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Existential operations with declared capability dictionaries and typed
-- preparation pipelines. Capability visibility is an API discipline, not a
-- security sandbox against arbitrary Haskell code or nontermination.
module Control.Operation (Operation(..), SomeOperation(..), SomeOperationWith, Capabilities, UniqueCapabilities,
  Subset, Stage(..), Pipeline(..), prepare, pipeline, withCapabilities, forgetCapabilities, execute) where

import Data.Kind (Constraint, Type)
import Data.Maybe (fromMaybe)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable)
import GHC.TypeLits (ErrorMessage(..), TypeError)

-- | Each payload determines one duplicate-free list of capability classes.
-- Implement interpreters by matching the DSL constructor, proving payload-type
-- equality, and calling that constructor's specific class methods.
-- For a whole-workflow operation, construct its deferred @Flow@ / @F.do@ in
-- 'interpret' after payload equality, and return it in 'Outcome' for a separate
-- application evaluator. Interpreting leaf steps alone does not establish this
-- workflow boundary. Equality proves type identity, not runtime authorization.
class (Typeable op, Typeable (Context op), UniqueCapabilities caps)
    => Operation op (caps :: [Type -> Constraint]) | op -> caps where
  type Context op = (ctx :: Constraint) | ctx -> op -- ^ Constructor-specific constraint.
  type Outcome op -- ^ Domain-specific result, including effects when needed.
  data DSL op -- ^ GADT constructors carry their specific constraints.
  interpret :: SomeOperation -> DSL op -> Maybe (Outcome op) -- ^ 'Nothing' denotes a payload mismatch.

-- | Apply each capability class in a list to the same operation payload.
type family Capabilities (caps :: [Type -> Constraint]) op :: Constraint where
  Capabilities '[] op = ()
  Capabilities (cap ': caps) op = (cap op, Capabilities caps op)

-- | Reject repeated capability classes with a compile-time error.
type family UniqueCapabilities (caps :: [Type -> Constraint]) :: Constraint where
  UniqueCapabilities '[] = ()
  UniqueCapabilities (cap ': caps) = (Absent cap caps, UniqueCapabilities caps)

type family Absent (cap :: Type -> Constraint) caps :: Constraint where
  Absent cap '[] = ()
  Absent cap (cap ': caps) = TypeError ('Text "Duplicate operation capability: " ':<>: 'ShowType cap)
  Absent cap (other ': caps) = Absent cap caps

data Dict constraint where Dict :: constraint => Dict constraint

class Member cap (caps :: [Type -> Constraint]) where
  member :: Capabilities caps op => Proxy op -> Dict (cap op)
instance Member cap (cap ': caps) where
  member _ = Dict
instance {-# OVERLAPPABLE #-} Member cap caps => Member cap (other ': caps) where
  member = member @cap @caps

-- | Evidence that every requested capability occurs in the declared list.
-- Dictionary projection is internal; callers use pipeline constructors.
class Subset (subset :: [Type -> Constraint]) (caps :: [Type -> Constraint]) where
  subset :: Capabilities caps op => Proxy op -> Dict (Capabilities subset op)
instance Subset '[] caps where
  subset _ = Dict
instance (Member cap caps, Subset rest caps) => Subset (cap ': rest) caps where
  subset op = case member @cap @caps op of
    Dict -> case subset @rest @caps op of Dict -> Dict

-- | An uninterpreted payload carrying its operation and canonical capabilities.
data SomeOperation where
  SomeOperation :: (Operation op caps, Capabilities caps op) => op -> SomeOperation

-- | The constructor is private: a stage receives only its visible dictionaries,
-- while the envelope retains the declared ones for explicit later expansion.
type role SomeOperationWith nominal nominal
data SomeOperationWith declared visible where
  WithCapabilities :: (Operation op declared, Capabilities declared op, Capabilities visible op,
    UniqueCapabilities visible, Subset visible declared) => op -> SomeOperationWith declared visible

-- | Pack an operation with all its declared capabilities visible. Does not interpret.
prepare :: (Operation op caps, Capabilities caps op, Subset caps caps) => op -> SomeOperationWith caps caps
prepare = WithCapabilities

-- | Inspect or use only the currently visible dictionaries without revealing the payload type.
withCapabilities :: (forall op. (Operation op declared, Capabilities visible op) => op -> r)
  -> SomeOperationWith declared visible -> r
withCapabilities use (WithCapabilities value) = use value

-- | Erase the visibility index at the terminal dispatch boundary. Despite the
-- historical name, canonical dictionaries are retained. This does not interpret
-- the request, and must not be mistaken for permanent privilege revocation.
forgetCapabilities :: SomeOperationWith declared visible -> SomeOperation
forgetCapabilities (WithCapabilities value) = SomeOperation value

-- | A preparation step preserving the hidden payload type. It receives only the
-- visible dictionaries, not the full canonical capability dictionary.
newtype Stage visible = Stage
  (forall op declared. (Operation op declared, Capabilities visible op) => op -> Either String op)

-- | A typed path through capability views, never exceeding the declared set.
data Pipeline declared before after where
  Identity :: Pipeline declared caps caps -- ^ Leave payload and visibility unchanged.
  Preserve :: Stage caps -> Pipeline declared caps caps -- ^ Prepare without changing visibility.
  Restrict :: (UniqueCapabilities next, Subset next current, Subset next declared)
    => Proxy next -> Pipeline declared current next -- ^ Hide capabilities; never add them.
  Expand :: (UniqueCapabilities next, Subset current next, Subset next declared)
    => Proxy next -> Pipeline declared current next -- ^ Restore only declared capabilities.
  (:>>>) :: Pipeline declared before middle -> Pipeline declared middle after -> Pipeline declared before after
infixr 1 :>>>

-- | Run preparation left-to-right, stopping on the first 'Left'. No implicit interpretation.
pipeline :: Pipeline declared before after -> SomeOperationWith declared before
  -> Either String (SomeOperationWith declared after)
pipeline Identity value = Right value
pipeline (Preserve (Stage stage)) (WithCapabilities value) = WithCapabilities <$> stage value
pipeline (Restrict proxy) value = Right (reframe proxy value)
pipeline (Expand proxy) value = Right (reframe proxy value)
pipeline (first :>>> rest) value = pipeline first value >>= pipeline rest

reframe :: forall next declared previous. (UniqueCapabilities next, Subset next declared)
  => Proxy next -> SomeOperationWith declared previous -> SomeOperationWith declared next
reframe _ (WithCapabilities (value :: op)) = case subset @next @declared (Proxy @op) of
  Dict -> WithCapabilities value

-- | Pack and interpret a payload against its typed DSL. A faulty interpreter
-- returning 'Nothing' raises an error; domain rejection belongs in 'Outcome'.
execute :: (Operation op caps, Capabilities caps op) => op -> DSL op -> Outcome op
execute value = fromMaybe (error "operation payload type mismatch") . interpret (SomeOperation value)
