{-# LANGUAGE CPP, ConstraintKinds, DataKinds, FlexibleContexts, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, TypeFamilies, TypeApplications #-}
-- Compile the positive case and intentionally ill-typed variants separately.
module CapabilityTypes where

import Data.Proxy (Proxy(..))
import Control.Operation
import Control.Operation.Indexed
import Type.Reflection (typeRep)
#ifdef COERCE_VIEW
import Data.Coerce (coerce)
#endif

data Request = Request
data NameIndex
instance IndexedCapability NameIndex where
#ifdef INDEX_DUPLICATE
  type IndexCaps NameIndex = '[Named, Named]
#else
  type IndexCaps NameIndex = '[Named]
#endif
  type IndexInput NameIndex = ()
  type IndexOutput NameIndex = String
  runIndexed _ value () = name value

#ifdef INDEX_ARBITRARY
indexed :: IndexedRequest '[] String
#else
indexed :: IndexedRequest '[Named] String
#endif
indexed = IndexedRequest (typeRep @NameIndex) ()

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
additional :: Pipeline '[Named] '[Named] '[Named, Named]
additional = Expand Proxy
#endif

#ifdef ARBITRARY
class Unrelated op
instance Unrelated Request
additional :: Pipeline '[Named] '[Named] '[Named, Unrelated]
additional = Expand Proxy
#endif

#ifdef RESTRICTED
restricted :: Stage '[]
restricted = Stage $ \request -> Right (if name request == "request" then request else request)
#endif

#ifdef RESTRICT_EXPANDS
additional :: Pipeline '[Named] '[] '[Named]
additional = Restrict Proxy
#endif

#ifdef EXPAND_RESTRICTS
additional :: Pipeline '[Named] '[Named] '[]
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

scoped :: Pipeline '[Named] '[Named] '[Named]
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
