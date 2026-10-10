{-# LANGUAGE ConstraintKinds, DataKinds, FlexibleContexts, FlexibleInstances, GADTs #-}
{-# LANGUAGE MultiParamTypeClasses, ScopedTypeVariables, TypeApplications, TypeFamilies #-}
module Main where

import Control.Monad (unless)
import Control.Operation
import Control.Operation.Validation
import Data.Char (toUpper)
import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Proxy (Proxy(..))
import Data.Typeable (eqT, (:~:)(Refl))
import Demo
import System.Exit (exitFailure)
import Test.QuickCheck hiding (Positive)
import Test.QuickCheck.Random (mkQCGen)

data Counter = Counter Integer (IORef Int)
class Observed op where
  observe :: op -> IO Integer
class Adjustable op where
  adjust :: (Integer -> Integer) -> op -> op
instance Observed Counter where
  observe (Counter value calls) = modifyIORef' calls (+1) >> pure value
instance Adjustable Counter where
  adjust f (Counter value calls) = Counter (f value) calls
type CounterCaps = '[Observed, Adjustable]
instance Operation Counter CounterCaps where
  type Context Counter = Observed Counter
  type Outcome Counter = IO Integer
  data DSL Counter where
    Observe :: Context Counter => DSL Counter
  interpret (SomeOperation (value :: actual)) Observe =
    case eqT @actual @Counter of
      Just Refl -> Just (observe value)
      Nothing -> Nothing

newtype Positive = Positive Integer
instance Validation Positive where
  type ValidationResult Positive = Bool
  validate (Positive n) = n > 0

demoWorks :: String -> Property
demoWorks text = renderNote text === Right (Just (map toUpper (unwords (words text))))

genericValidation :: Integer -> Property
genericValidation n = conjoin
  [execute (Check (Positive n)) Validate === (n > 0),
   interpret (SomeOperation (Check (Positive n))) (Validate @Positive) === Just (n > 0)]

dispatchMatrix :: Integer -> String -> Property
dispatchMatrix n text = ioProperty $ do
  calls <- newIORef 0
  let requests = [SomeOperation (Note text), SomeOperation (Counter n calls), SomeOperation (Check (Positive n))]
      expected index target value = if index == target then Just value else Nothing
  checks <- mapM (\(index,request) -> do
    result <- sequence (interpret request Observe)
    pure $ conjoin [interpret request Rendering === expected index 0 text,
                    result === expected index 1 n,
                    interpret request (Validate @Positive) === expected index 2 (n > 0)])
      (zip [0 :: Int ..] requests)
  count <- readIORef calls
  pure $ conjoin ((count === 1) : checks)

lazyMismatch :: Property
lazyMismatch = forAll (elements [0 :: Int,1,2]) $ \index -> ioProperty $ do
  let bottom = error "mismatched payload was forced"
      requests = [SomeOperation (bottom :: Note), SomeOperation (bottom :: Counter),
                  SomeOperation (bottom :: Check Positive)]
      request = requests !! index
  result <- if index == 1 then pure Nothing else sequence (interpret request Observe)
  pure $ conjoin [if index == 0 then property True else interpret request Rendering === Nothing,
                  result === Nothing,
                  if index == 2 then property True else interpret request (Validate @Positive) === Nothing]

counterPipeline :: Pipeline CounterCaps CounterCaps '[Observed]
counterPipeline = Restrict (Proxy @'[Adjustable]) :>>>
  Preserve (Stage (Right . adjust (+2))) :>>>
  Preserve (Stage (Right . adjust (*3))) :>>>
  Restrict (Proxy @'[]) :>>> Expand (Proxy @'[Observed])

deferredEffects :: Integer -> Property
deferredEffects n = ioProperty $ do
  calls <- newIORef 0
  case pipeline counterPipeline (prepare (Counter n calls)) of
    Left message -> pure (counterexample message False)
    Right pending -> do
      before <- readIORef calls
      -- The view can call Observed only after the explicit expansion.
      value <- withCapabilities observe pending
      after <- readIORef calls
      interpreted <- sequence (interpret (forgetCapabilities pending) Observe)
      final <- readIORef calls
      pure $ conjoin [before === 0, value === (n+2)*3, after === 1,
                      interpreted === Just value, final === 2]

composition :: Integer -> Property
composition n = ioProperty $ do
  calls <- newIORef 0
  let start = prepare (Counter n calls)
      first = Restrict (Proxy @'[Adjustable]) :>>> Preserve (Stage (Right . adjust (+2)))
      rest = Preserve (Stage (Right . adjust (*3))) :>>> Expand (Proxy @CounterCaps)
      finish = either (const (pure Nothing)) (sequence . (`interpret` Observe) . forgetCapabilities)
  direct <- finish (pipeline (first :>>> rest) start)
  split <- finish (pipeline first start >>= pipeline rest)
  identityResult <- finish (pipeline Identity start)
  pure $ conjoin [direct === split, direct === Just ((n+2)*3), identityResult === Just n]

shortCircuit :: Integer -> Property
shortCircuit n = ioProperty $ do
  calls <- newIORef 0
  let reject = Preserve (Stage (const (Left "rejected")))
      unreachable = Preserve (Stage (const (error "rejected pipeline continued")))
      result = pipeline (counterPipeline :>>> reject :>>> unreachable) (prepare (Counter n calls))
      message = either id (const "unexpected success") result
  count <- readIORef calls
  pure $ conjoin [message === "rejected", count === 0]

main :: IO ()
main = do
  results <- mapM (\(name,prop) -> putStrLn name >> quickCheckWithResult
    stdArgs {maxSuccess = 10000, replay = Just (mkQCGen 20261009, 0)} prop)
    [("runnable example",property demoWorks), ("generic validation instance",property genericValidation),
     ("all payload/constructor pairs",property dispatchMatrix), ("lazy mismatches",lazyMismatch),
     ("explicit capability restriction/restoration and deferred effects",property deferredEffects),
     ("pipeline identity and composition",property composition),
     ("rejection short-circuiting without interpretation",property shortCircuit)]
  unless (all isSuccess results) exitFailure
