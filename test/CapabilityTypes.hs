{-# LANGUAGE CPP, ConstraintKinds, DataKinds, FlexibleContexts, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, TypeFamilies #-}
-- Compile the positive case and intentionally ill-typed variants separately.
module CapabilityTypes where

import Data.Proxy (Proxy(..))
import Control.Operation
#ifdef COERCE_VIEW
import Data.Coerce (coerce)
#endif

data Request = Request
class Named op where
  name :: op -> String
#ifndef MISSING
instance Named Request where
  name _ = "request"
#endif

#ifdef DUPLICATE
instance Operation Request '[Named, Named] where
#else
instance Operation Request '[Named] where
#endif
  type Context Request = Named Request
  type Outcome Request = String
  data DSL Request where
    Naming :: Context Request => DSL Request
  interpret _ Naming = Just (name Request)

#ifdef CONFLICT
instance Operation Request '[] where
  interpret _ _ = Nothing
#endif

declared :: Operation op caps => op -> Proxy caps
declared _ = Proxy

inferred :: Proxy '[Named]
inferred = declared Request

pack :: (Operation op caps, Capabilities caps op) => op -> SomeOperation
pack = SomeOperation

packed :: SomeOperation
packed = pack Request

#ifdef EXTRA_DUPLICATE
additional :: Pipeline String (SomeOperationWith '[Named] '[Named]) (SomeOperationWith '[Named] '[Named, Named])
additional = Expand Proxy
#endif

#ifdef ARBITRARY
class Unrelated op
instance Unrelated Request
additional :: Pipeline String (SomeOperationWith '[Named] '[Named]) (SomeOperationWith '[Named] '[Named, Unrelated])
additional = Expand Proxy
#endif

#ifdef RESTRICTED
restricted :: Stage String '[]
restricted = Stage $ \request -> Right (if name request == "request" then request else request)
#endif

#ifdef RESTRICT_EXPANDS
additional :: Pipeline String (SomeOperationWith '[Named] '[]) (SomeOperationWith '[Named] '[Named])
additional = Restrict Proxy
#endif

#ifdef EXPAND_RESTRICTS
additional :: Pipeline String (SomeOperationWith '[Named] '[Named]) (SomeOperationWith '[Named] '[])
additional = Expand Proxy
#endif

#ifdef COERCE_VIEW
widen :: SomeOperationWith '[Named] '[] -> SomeOperationWith '[Named] '[Named]
widen = coerce
#endif

#ifdef PRIVATE_CONSTRUCTOR
forged :: SomeOperationWith '[Named] '[]
forged = WithCapabilities Request
#endif

-- Repack using only the dictionaries recovered from the existential.
repacked :: SomeOperation
repacked = case packed of SomeOperation request -> pack request

oldInterpret :: SomeOperation -> DSL Request -> Maybe String
oldInterpret = interpret

scoped :: Pipeline String (SomeOperationWith '[Named] '[Named]) (SomeOperationWith '[Named] '[Named])
scoped = Restrict (Proxy :: Proxy '[]) :>>> Preserve (Stage Right) :>>> Expand Proxy

prepared :: Either String (SomeOperationWith '[Named] '[Named])
prepared = pipeline scoped (prepare Request)

-- The dependency is op -> caps, not caps -> op: another payload can reuse Named.
data Other = Other
instance Named Other where
  name _ = "other"
instance Operation Other '[Named] where
  type Context Other = Named Other
  type Outcome Other = String
  data DSL Other where
    OtherName :: Context Other => DSL Other
  interpret _ OtherName = Just (name Other)

#ifdef BAD_COMPOSITION
badComposition :: Pipeline String Int Bool
badComposition = Transform (Right . show) :>>> Transform (Right . not)
#endif
#ifdef BAD_OUTCOME
badOutcome :: Selection Bool Request
badOutcome = Select Naming
#endif
#ifdef BAD_ERROR
badError :: Pipeline Bool Int String
badError = Transform (const $ Left "wrong error type")
#endif
#ifdef HIDDEN_SELECTION
hiddenSelection :: Pipeline String (SomeOperationWith '[Named] '[]) String
hiddenSelection = Interpret "mismatch" (\value -> name value `seq` error "unreachable")
#endif
