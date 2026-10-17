{-# LANGUAGE CPP, DataKinds, GADTs, ScopedTypeVariables, TypeApplications, TypeOperators #-}
module OutputTypes where

import Control.Operation
import Control.Operation.Outputs
import Control.Operation.Indexed
import qualified CapableOutputs as C
import Type.Reflection (typeRep)
import VariableOutputs

valid :: CheckedOutputs RenderOutput '[Amount] -> CheckedOutputs RenderOutput '[Notice]
  -> CheckedOutputs RenderOutput '[Amount, Notice]
valid = appendOutputs

#ifdef WRONG_SEQUENCE
bad :: CheckedOutputs RenderOutput '[Amount] -> Maybe (CheckedOutputs RenderOutput '[Notice])
bad = composeOutputs Just (Just :: CheckedOutputs RenderOutput '[Notice] -> Maybe (CheckedOutputs RenderOutput '[Notice]))
#endif
#ifdef WRONG_APPEND
bad :: CheckedOutputs RenderOutput '[Amount] -> CheckedOutputs RenderOutput '[Notice]
  -> CheckedOutputs RenderOutput '[Notice, Amount]
bad = appendOutputs
#endif
#ifdef FORGED_METHODS
bad :: CheckedOutputs Show xs -> [String]
bad = mapOutputs renderOutput
#endif
#ifdef HIDDEN_CAPABILITY
bad :: SomeOperationWith RequestCaps '[Produce] -> Either String ()
bad = withCapabilities (\value -> inspectRequest value >> Right ())
#endif

visible :: SomeOperationWith RequestCaps '[Produce] -> SomeOutputs
visible = withCapabilities produceOutputs

-- Heterogeneous equality recovers generated constraints even when the selected
-- index kind is initially independent. The declared set still bounds them.
registered :: Maybe (IndexMatch C.BalanceCaps 'C.TextView 'C.TextView)
registered = matchIndex (typeRep @'C.TextView) (typeRep @'C.TextView)

#ifdef OUTPUT_ARBITRARY
bad :: SomeOperationWith C.BalanceCaps '[] -> CapabilityOutput 'C.TextView
bad = CapabilityOutput (typeRep @'C.TextView)
#endif
#ifdef REGISTRY_ARBITRARY
bad :: Maybe (IndexMatch '[] 'C.TextView 'C.TextView)
bad = matchIndex (typeRep @'C.TextView) (typeRep @'C.TextView)
#endif
#ifdef WRONG_REQUEST_RESULT
bad :: SomeOutputs -> Maybe Int
bad raw = interpretOutputs raw DisplayBatch
#endif
