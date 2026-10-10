{-# LANGUAGE AllowAmbiguousTypes, ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies, GADTs, RankNTypes, RoleAnnotations, ScopedTypeVariables, TypeApplications #-}
{-# LANGUAGE TypeFamilyDependencies, TypeOperators, UndecidableInstances, UndecidableSuperClasses #-}
-- Copyright (c) 2026 The Elements Core developers
-- Distributed under the MIT software license.
-- | Existential operations with declared capability dictionaries and typed
-- preparation pipelines. Capability visibility is an API discipline, not a
-- security sandbox against arbitrary Haskell code or nontermination.
module Control.Operation (Operation(..), SomeOperation(..), SomeOperationWith, Capabilities, UniqueCapabilities,
  Subset, Stage(..), Selection(..), Pipeline(..), prepare, pipeline, withCapabilities, forgetCapabilities, execute) where

import Data.Kind (Constraint, Type)
import Data.Maybe (fromMaybe)
import Data.Proxy (Proxy(..))
import Data.Typeable (Typeable)
import GHC.TypeLits (ErrorMessage(..), TypeError)

-- | Each payload determines one duplicate-free list of capability classes.
-- Implement interpreters by matching the DSL constructor, proving payload-type
-- equality, and calling that constructor's specific class methods.
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
newtype Stage error visible = Stage
  (forall op declared. (Operation op declared, Capabilities visible op) => op -> Either error op)

-- | A DSL selection whose operation produces exactly the next stage's input.
-- The equality is evidence about the result type, not financial authorization.
data Selection result op where
  Select :: (Outcome op ~ result) => DSL op -> Selection result op

-- | A path indexed by error, input and output types. Capability-view steps keep
-- the hidden payload; Transform changes a concrete value's type. It grants no
-- dictionaries and is not a sandbox for arbitrary functions or embedded IO.
data Pipeline error input output where
  Identity :: Pipeline error a a
  Transform :: (a -> Either error b) -> Pipeline error a b
  Preserve :: Stage error caps
    -> Pipeline error (SomeOperationWith declared caps) (SomeOperationWith declared caps)
  Restrict :: (UniqueCapabilities next, Subset next current, Subset next declared)
    => Proxy next -> Pipeline error (SomeOperationWith declared current) (SomeOperationWith declared next)
  Expand :: (UniqueCapabilities next, Subset current next, Subset next declared)
    => Proxy next -> Pipeline error (SomeOperationWith declared current) (SomeOperationWith declared next)
  -- Selection sees only visible capabilities. Canonical evidence is supplied
  -- internally to interpret, which remains responsible for checking the payload.
  Interpret :: error
    -> (forall op. (Operation op declared, Capabilities visible op) => op -> Selection result op)
    -> Pipeline error (SomeOperationWith declared visible) result
  (:>>>) :: Pipeline error a b -> Pipeline error b c -> Pipeline error a c
infixr 1 :>>>

-- | Run left-to-right, stopping on the first Left. Interpret is explicit;
-- returning an IO-valued outcome never executes that action here.
pipeline :: Pipeline error input output -> input -> Either error output
pipeline Identity value = Right value
pipeline (Transform step) value = step value
pipeline (Preserve (Stage stage)) (WithCapabilities value) = WithCapabilities <$> stage value
pipeline (Restrict proxy) value = Right (reframe proxy value)
pipeline (Expand proxy) value = Right (reframe proxy value)
pipeline (Interpret mismatch select) (WithCapabilities value) = case select value of
  Select dsl -> maybe (Left mismatch) Right (interpret (SomeOperation value) dsl)
pipeline (first :>>> rest) value = pipeline first value >>= pipeline rest

reframe :: forall next declared previous. (UniqueCapabilities next, Subset next declared)
  => Proxy next -> SomeOperationWith declared previous -> SomeOperationWith declared next
reframe _ (WithCapabilities (value :: op)) = case subset @next @declared (Proxy @op) of
  Dict -> WithCapabilities value

-- | Pack and interpret a payload against its typed DSL. A faulty interpreter
-- returning 'Nothing' raises an error; domain rejection belongs in 'Outcome'.
execute :: (Operation op caps, Capabilities caps op) => op -> DSL op -> Outcome op
execute value = fromMaybe (error "operation payload type mismatch") . interpret (SomeOperation value)
