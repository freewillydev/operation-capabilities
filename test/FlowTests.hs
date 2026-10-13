{-# LANGUAGE DataKinds, GADTs, QualifiedDo, TypeOperators #-}
module FlowTests (flowProperties) where

import Control.Operation
import Control.Operation.Flow (Flow, Values(..))
import qualified Control.Operation.Flow as F
import Control.Monad (replicateM_)
import Data.IORef
import Demo (Note(..))
import FlowExample
import qualified FlowRebindable as R
import Test.QuickCheck

flowProperties :: [(String, Property)]
flowProperties =
  [("flow qualified-do runtime continuations",property qualified),
   ("flow rebindable state branches",property rebound),
   ("flow bind identity, associativity and discarded results",property composition),
   ("flow rejection and payload mismatch are lazy",lazyFailures),
   ("flow effects are deferred, ordered, and repeatable",property effects)]
  where
    qualified :: NonNegative Integer -> Property
    qualified (NonNegative n) = execute (Account n) (RunPayment (n :& VNil) payment)
      === Right (n-if n > 100 then 2 else 1)
    rebound :: NonNegative Integer -> Property
    rebound (NonNegative n) = execute (Account n) (RunPayment (n :& VNil) R.payment)
      === Right (n-if n > 100 then n `div` 100 else 1)

lazyFailures :: Property
lazyFailures = once $ conjoin
  [execute (Account 0) (RunPayment (1 :& VNil)
     (F.Bind (F.Step VerifyAmount) (error "failed step forced continuation"))) === Left "invalid amount",
   execute (Account 10) (RunPayment (2 :& VNil) (F.Branch (const True) payment
     (error "unselected branch forced"))) === Right 1,
   execute (Account 10) (RunPayment (2 :& VNil) (F.Branch (const False)
     (error "unselected branch forced") payment)) === Right 1,
   interpret (SomeOperation (error "payload forced" :: Note))
     (error "mismatched DSL forced" :: DSL Account) === Nothing]

composition :: Integer -> Property
composition n =
  let run program = fst <$> F.runFlow (runAction (Account 0)) program VNil
      start :: Flow (Action Account) '[] '[] Integer
      start = F.pure n
      first x = F.pure (x+1)
      second x = F.pure (x*2)
  in conjoin
    [run (start F.>>= F.return) === run start,
     run (F.pure n F.>>= first) === run (first n),
     run ((start F.>>= first) F.>>= second) === run (start F.>>= (\x -> first x F.>>= second)),
     run (start F.>> F.return 7) === Right (7 :: Integer)]

data Effect xs ys a where
  Tick :: Int -> Effect '[] '[] Int

effects :: Int -> Property
effects n = ioProperty $ do
  seen <- newIORef []
  let handler :: Effect xs ys a -> Values xs -> IO (a, Values ys)
      handler (Tick value) VNil = modifyIORef' seen (++[value]) >> pure (value,VNil)
      program :: Flow Effect '[] '[] Int
      program = F.do
        value <- F.step (Tick n)
        F.step (Tick (if even value then 1 else 2))
  program `seq` pure ()
  before <- readIORef seen
  replicateM_ 2 (F.runFlow handler program VNil)
  after <- readIORef seen
  pure (conjoin [before === [], after === concat (replicate 2 [n,if even n then 1 else 2])])
