{-# LANGUAGE CPP, ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances #-}
{-# LANGUAGE GADTs, KindSignatures, MultiParamTypeClasses, ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications, TypeFamilies #-}
module SeverityTypes where

import Control.Operation
import Control.Operation.Severity
import Data.Kind (Type)
import Data.Typeable (eqT, (:~:)(Refl))
#if defined(COERCE_CALLER) || defined(COERCE_SEVERITY) || defined(COERCE_RESULT) || defined(COERCE_PROGRAM)
import Data.Coerce (coerce)
#endif

data Caller = Customer | Signer
data Program (caller :: Caller) (severity :: Severity) a where
  ReadValue :: Integer -> Program 'Customer 'Safe Integer
  WriteValue :: IO Integer -> Program 'Signer 'Critical Integer

class Reading op where
  readValue :: op -> Program 'Customer 'Safe Integer
  readDSL :: op -> OperationDSL (Program 'Customer 'Safe Integer) op
  rejectDSL :: op -> OperationDSL (Program 'Customer 'Safe Integer) op
class Writing op where
  writeValue :: op -> Program 'Signer 'Critical Integer
  writeDSL :: op -> OperationDSL (Program 'Signer 'Critical Integer) op

newtype ReadNumber = ReadNumber Integer
instance Reading ReadNumber where
  readValue (ReadNumber n) = ReadValue n
  readDSL _ = OperationDSL ReadingDSL
  rejectDSL _ = OperationDSL RejectedDSL
instance Operation ReadNumber '[Reading] where
  type Context ReadNumber = Reading ReadNumber
  type Outcome ReadNumber = Program 'Customer 'Safe Integer
  data DSL ReadNumber where
    ReadingDSL :: Context ReadNumber => DSL ReadNumber
    RejectedDSL :: DSL ReadNumber
  interpret (SomeOperation (value :: actual)) ReadingDSL =
    case eqT @actual @ReadNumber of
      Just Refl -> Just (readValue value)
      Nothing -> Nothing
  interpret _ RejectedDSL = Nothing

newtype WriteNumber = WriteNumber (IO Integer)
instance Writing WriteNumber where
  writeValue (WriteNumber action) = WriteValue action
  writeDSL _ = OperationDSL WritingDSL
instance Operation WriteNumber '[Writing] where
  type Context WriteNumber = Writing WriteNumber
  type Outcome WriteNumber = Program 'Signer 'Critical Integer
  data DSL WriteNumber where
    WritingDSL :: Context WriteNumber => DSL WriteNumber
  interpret (SomeOperation (value :: actual)) WritingDSL =
    case eqT @actual @WriteNumber of
      Just Refl -> Just (writeValue value)
      Nothing -> Nothing

safeOperation :: Integer -> SomeOperationAt Program 'Customer 'Safe Integer
safeOperation n = prepareOperation readDSL (prepare (ReadNumber n))
criticalOperation :: IO Integer -> SomeOperationAt Program 'Signer 'Critical Integer
criticalOperation action = prepareOperation writeDSL (prepare (WriteNumber action))

-- The library type itself fits a partially applied Servant-style carrier.
data Carrier (m :: Type -> Type) = Carrier (m Integer)
carrier :: Carrier (SomeOperationAt Program 'Customer 'Safe)
carrier = Carrier (safeOperation 1)
data OtherProgram (caller :: Caller) (severity :: Severity) a = OtherProgram a

#if defined(WRONG_CALLER) || defined(COERCE_CALLER)
bad :: SomeOperationAt Program 'Customer 'Safe Integer -> SomeOperationAt Program 'Signer 'Safe Integer
#elif defined(WRONG_SEVERITY) || defined(COERCE_SEVERITY)
bad :: SomeOperationAt Program 'Customer 'Safe Integer -> SomeOperationAt Program 'Customer 'Critical Integer
#elif defined(WRONG_RESULT) || defined(COERCE_RESULT)
bad :: SomeOperationAt Program 'Customer 'Safe Integer -> SomeOperationAt Program 'Customer 'Safe Bool
#elif defined(WRONG_PROGRAM) || defined(COERCE_PROGRAM)
bad :: SomeOperationAt Program 'Customer 'Safe Integer -> SomeOperationAt OtherProgram 'Customer 'Safe Integer
#endif
#if defined(WRONG_CALLER) || defined(WRONG_SEVERITY) || defined(WRONG_RESULT) || defined(WRONG_PROGRAM)
bad = id
#elif defined(COERCE_CALLER) || defined(COERCE_SEVERITY) || defined(COERCE_RESULT) || defined(COERCE_PROGRAM)
bad = coerce
#endif
#ifdef PRIVATE_SCOPED
bad :: SomeOperationAt Program 'Customer 'Safe Integer
bad = Classified (SomeOperation (ReadNumber 1)) ReadingDSL
#endif
#ifdef WRONG_DSL
bad :: OperationDSL (Program 'Customer 'Critical Integer) ReadNumber
bad = OperationDSL ReadingDSL
#endif
#ifdef HIDDEN_SELECTOR
bad :: SomeOperationWith '[Reading] '[] -> SomeOperationAt Program 'Customer 'Safe Integer
bad = prepareOperation readDSL
#endif
