# operation-capabilities

A small Haskell library for preparing existential operations without interpreting
them prematurely. Each operation declares its capability classes once. Pipelines
make changes to the visible subset explicit and statically checked.

The library depends only on `base`. QuickCheck is a test-only dependency.
Tested with GHC 9.6.7; the severity extension is verified with GHC 9.14.1. MIT licensed. This package is not yet published to Hackage.

**Workflow design:** construct the complete `F.do` in `interpret`, after
`eqT`/`Refl`, and evaluate it separately. This is an important integration
boundary; see [Value-dependent workflows](#value-dependent-workflows).

## Get started

```sh
git clone https://github.com/freewillydev/operation-capabilities.git
cd operation-capabilities
cabal update
cabal build all
cabal run operation-capabilities-example
```

The example prints `HELLO CAPABILITIES`. See [examples/Demo.hs](examples/Demo.hs)
for the complete, compiling implementation.

To use the package from another Cabal project, add this to `cabal.project`:

```cabal
source-repository-package
  type: git
  location: https://github.com/freewillydev/operation-capabilities.git
  tag: 86c5b86078bc6fe9b9130a28d9de600a339f6221
```

Then add `operation-capabilities ==0.1.3.0` to the component's `build-depends`.
The full commit SHA pins the version that includes Flow; `v0.1.1.0` predates it.
The implementation is in `Control.Operation`; the optional generic rule adapter
is in `Control.Operation.Validation`.

## Operations declare their capabilities

```haskell
class ( Typeable op
      , Typeable (Context op)
      , UniqueCapabilities caps
      ) => Operation op (caps :: [Type -> Constraint]) | op -> caps where
  type Context op = (ctx :: Constraint) | ctx -> op
  type Outcome op
  data DSL op
  interpret :: SomeOperation -> DSL op -> Maybe (Outcome op)

data SomeOperation where
  SomeOperation
    :: (Operation op caps, Capabilities caps op)
    => op -> SomeOperation
```

`op -> caps` fixes one capability list for each payload type. Lists cannot contain
duplicates, but different payload types may share the same list. The injective
`Context` family also requires a distinct context type for each operation; contexts
such as `Renderable Note` naturally distinguish payloads.

`Capabilities '[Labelled, Editable] Note` means both `Labelled Note` and
`Editable Note`. The existential uses the **same list** as `Operation`, so packing
requires all declared dictionaries, not just the operation dictionary.

Put behavior in focused classes. A DSL GADT constructor carries its specific
constraint; match it and prove equality of the **payload types** before calling
the class method:

```haskell
instance Operation Note '[Labelled, Editable, Renderable] where
  type Context Note = Renderable Note
  type Outcome Note = String
  data DSL Note where
    Rendering :: Context Note => DSL Note
  interpret (SomeOperation (value :: actual)) Rendering =
    case eqT @actual @Note of
      Just Refl -> Just (render value)
      Nothing -> Nothing
```

This excerpt uses the definitions and language extensions in `examples/Demo.hs`.
Do not compare constraint types or use unchecked casts. `Nothing` denotes a
payload mismatch; represent domain validation failures in `Outcome` instead.

## Complex behavior after Refl

`Just Refl` is not limited to a single method call. Once the payload types are
equal, combine methods from the constructor's specific classes, branch on their
results, and return a domain outcome. Keep reusable orchestration in a function
constrained by only the capabilities it needs:

```haskell
planPayment :: (FeeModel op, SpendPolicy op) => op -> Either String UnsignedTx
planPayment value
  | amount <= 0 = Left "Payment must be positive"
  | fee < 0 = Left "Invalid fee estimate"
  | amount + fee > availableFunds value = Left "Insufficient funds"
  | otherwise = buildUnsigned value fee
  where
    amount = paymentAmount value
    fee = estimateFee value

instance Operation Payment '[FeeModel, SpendPolicy] where
  type Context Payment = (FeeModel Payment, SpendPolicy Payment)
  type Outcome Payment = Either String UnsignedTx
  data DSL Payment where
    PlanPayment :: Context Payment => DSL Payment
  interpret (SomeOperation (value :: actual)) PlanPayment =
    case eqT @actual @Payment of
      Just Refl -> Just (planPayment value)
      Nothing -> Nothing
```

The complete, compiled example is [examples/Planning.hs](examples/Planning.hs).
Its classes supply fee estimation, funds/amount access, and unsigned construction;
concrete instances supply the implementation. The helper needs neither `Operation`
nor `Typeable`. Other payloads can reuse it through their own class instances.

`Nothing` means a payload mismatch; `Just (Left message)` means the type matched
but domain checks failed; `Just (Right tx)` means planning succeeded. This example
neither signs nor broadcasts. Preserve validation order and short-circuit behavior
when extracting helpers, especially before parsing, effects, or partial operations.
For effects, make them explicit in `Outcome` (for example `IO (Either Error Tx)`);
matching `Refl` itself does not execute an IO action. Never return borrowed FFI
data or deferred actions beyond their valid lifetime.

Do not add every concrete behavior to `Operation`, compare capability lists with
`eqT`, or expand the generic `Validation` class into a domain-specific API.
The operation handles dispatch; capability functions compose behavior; instances
implement it. Pure rules that only need `validate` should keep the simpler adapter.

## Pipelines have explicit capability views

`SomeOperationWith declared visible` hides the concrete payload and retains its
canonical dictionaries privately. `prepare value` starts with all declared
capabilities visible. Its constructor is not exported; both type parameters have
nominal roles, preventing `coerce` from widening visibility.

`Pipeline declared before after` records the change in visible capabilities:

| Constructor | Meaning |
| --- | --- |
| `Identity` | Keep the payload and capabilities unchanged |
| `Preserve stage` | Prepare the payload without changing visible capabilities |
| `Restrict proxy` | Expose a subset of the current capabilities |
| `Expand proxy` | Restore a superset, entirely within the declared capabilities |
| `first :>>> next` | Compose matching endpoints, left-to-right |

Every view is duplicate-free and contained in `declared`. Restrict/Expand may
also name the same set, or reorder it; capability membership is set-like, not
positional. Expansion never introduces an undeclared class, even if a concrete
payload happens to have an instance of it.

```haskell
type NoteCaps = '[Labelled, Editable, Renderable]

notePipeline :: Pipeline NoteCaps NoteCaps '[Renderable]
notePipeline =
  Restrict (Proxy @'[Labelled, Editable]) :>>>
  Preserve clean :>>>
  Preserve (Stage (Right . edit (map toUpper))) :>>>
  Expand (Proxy @NoteCaps) :>>>
  Restrict (Proxy @'[Renderable])
```

A rank-2 `Stage visible` receives only that view's dictionaries. It can prepare
and reject requests, but must return the same hidden payload type. It does not
receive the full canonical capability constraint. Dictionary projection uses
typed evidence, not `unsafeCoerce`.

`pipeline` stops on the first `Left` and never automatically calls `interpret`.
Only dispatch when ready:

```haskell
pending <- pipeline notePipeline (prepare (Note text))
pure (interpret (forgetCapabilities pending) Rendering)
```

`withCapabilities` can observe a prepared request using only visible capabilities.
The historically named `forgetCapabilities` erases the visibility index for
terminal dispatch: it **retains canonical dictionaries** and does not interpret.
It is not permanent privilege revocation. This is a typed API discipline, not a
security sandbox against arbitrary Haskell code, explicit effects, or bottoms.
Capability methods can themselves execute effects; the library does not implicitly
execute them. `execute` is a typed packing/dispatch helper; it raises an error if
an incorrectly implemented interpreter returns `Nothing` for its own payload.

## Reuse validation instances

```haskell
newtype Positive = Positive Integer
instance Validation Positive where
  type ValidationResult Positive = Bool
  validate (Positive n) = n > 0

-- The library supplies Operation (Check Positive) '[Validation].
result = execute (Check (Positive 7)) Validate
```

The `Validation` class is optional. Use other focused classes for other behaviors;
do not turn it or `Operation` into a catch-all collection of concrete actions.

## Verify changes

```sh
cabal check
cabal build all --ghc-options=-Werror
cabal test all --test-show-details=direct
bash test/check-capabilities.sh
cabal haddock all
cabal sdist
```

Runtime tests run ten QuickCheck properties, 10,000 cases each, using seed
20261009. They cover the example, generic validation, all sample dispatch pairs,
lazy mismatch rejection, deferred effects, restriction/restoration, composition,
identity, and rejection short-circuiting.

The compile test accepts a valid inference/repacking example and rejects ten
invalid programs: missing dictionaries, duplicate declared/visible lists,
conflicting functional dependencies, undeclared expansion, hidden class use,
Restrict adding capabilities, Expand removing them, `coerce` widening a view, and
use of the private envelope constructor. Set `GHC` to select another compiler.

An inactive CI template is included in [ci/github-actions.yml](ci/github-actions.yml)
for Linux, macOS, and Windows with GHC 9.6.7. The publication credential lacks
GitHub's workflow permission, so it could not install an active Actions workflow.
An authorized maintainer can place the template at `.github/workflows/ci.yml` to
enable it. Local macOS tests pass; hosted Linux/Windows CI has not run. Consult
actual workflow results before claiming those platforms have passed.

See [docs/HANDOFF.md](docs/HANDOFF.md) for a concise adoption message for another
chat, and [NOTICE](NOTICE) for provenance. No Elements node, wallet, network,
credentials, or FFI runtime are required.

## Indexed capability requests after Refl

`Control.Operation.Indexed` adds a kind-polymorphic `IndexedCapability index`
class without changing `Operation`, `interpret`, or the existing pipelines.
Its associated `IndexCaps index` selects a list of capability classes;
`Capabilities (IndexCaps index) op` is the resulting constraint on the payload.
`IndexInput` and `IndexOutput` give each index its own input and result types.

An `IndexedRequest declared result` carries a `TypeRep index`, its typed input,
the indexed capability instance, and proofs that its selected capabilities are
unique and a subset of `declared`. It cannot add an unrelated class to an
operation's declared capabilities, even if an instance happens to exist.

Call the helper only after matching the operation payload:

```haskell
interpret (SomeOperation (value :: actual)) (ObserveIndexed expected request) =
  case eqT @actual @Counter of
    Nothing -> Nothing
    Just Refl -> interpretIndexed expected value request
```

The helper matches the request GADT and compares independently kinded index
representations with `eqTypeRep`. After `HRefl`, it explicitly restricts the
capability view to `IndexCaps index` and invokes `runIndexed` with that view.
A mismatch returns `Nothing` without evaluating request input or running its
effects. An `IO` result remains deferred until the caller executes it. Domain
errors belong in `IndexOutput`, not in dispatch's `Nothing`.

When the DSL deliberately accepts any declared request with the given result,
use `interpretRequest value request` after payload `Refl`. Matching the request
GADT supplies the previously hidden `IndexedCapability index` dictionary and
subset evidence. This avoids a meaningless comparison of an index with itself.
Use `interpretIndexed` instead when an independently selected schema must match.

The runnable test in `test/Main.hs` uses index `24 :: Nat` to select
`'[Adjustable, Observed]`, adjust a counter, then observe it. Index
`"read" :: Symbol` selects only `'[Observed]`. The same interpreter handles both;
cross-kind mismatches are rejected before touching an undefined input. Type
tests reject undeclared and duplicate indexed capabilities.

The request checks identity and dictionary availability, not data validity or
authorization. Hide validated-data constructors where runtime validation is
required. Injectivity is not imposed: several indices may legitimately select
the same capabilities or result type. Capability visibility retains the core
library's API-discipline guarantees, not a security-sandbox guarantee.

## Safe and critical dispatch

`Control.Operation.Severity` supplies `Severity = Safe | Critical` and the opaque
`SomeOperationAt program caller severity result` existential. Use it directly as
a handler carrier, such as `SomeOperationAt Program Signer Critical`; no local
request wrapper is required. Its four parameters are nominal, so `coerce` cannot
change caller, severity, program or result.

```haskell
prepareOperation
  :: (forall op. (Operation op declared, Capabilities visible op)
      => op -> OperationDSL (program caller severity result) op)
  -> SomeOperationWith declared visible
  -> SomeOperationAt program caller severity result

resolveOperation
  :: SomeOperationAt program caller severity result
  -> Maybe (program caller severity result)
```

The selector returns `OperationDSL dsl`, proving that `Outcome op` equals the
indexed program. It sees only the current visible capabilities. Existing pipelines
may prepare/restrict a payload before packing. Packing selects the DSL; only
`resolveOperation` calls the operation's existing `interpret`. Keep its payload
`eqT` check. Resolution returns the program without executing IO stored within it.

Define a closed application GADT for `program`, then route its `Safe` and `Critical`
values to separate evaluators. Severity is a type contract supplied by your
instances, not a security sandbox: authentication, financial checks, serialization
and key access still belong to the application. See [test/SeverityTypes.hs](test/SeverityTypes.hs)
for a complete compiling example and rejection tests.

## Value-dependent workflows

**Important design rule:** when an operation represents a complete workflow,
construct that workflow's `F.do` inside its `interpret`, after successful payload
`eqT`/`Refl`. Return the deferred program as `Outcome`; let the application's
evaluator execute it. Keep this boundary explicit when designing or refactoring
an integration. Interpreting individual steps is useful, but does not replace
interpreting the operation that selects their complete sequence and branches.

`Control.Operation.Flow` is an optional interpreter layer, separate from the
existing capability preparation `Pipeline`. It does not replace `Operation` or
change `interpret`. Its type is `Flow instruction before after result`, where
`before` and `after` are lists of actual heterogeneous state types and `result`
is a separate runtime value returned to a continuation.

- `Pure` returns a value without changing state.
- `Step` stores an application instruction GADT, including its constraints.
- `Bind` builds the next program from the preceding runtime result.
- `Branch` chooses a program using the current heterogeneous state.

`Values xs` holds the indexed state through `VNil` and `(:&)`. Unlike a list of
labels, these indices describe values that the interpreter actually threads.
Both branches must agree on their resulting state list and returned value type.

With `QualifiedDo`, only the named block uses the flow operators. In the complete
example, the operation's DSL requests a payment plan rather than accepting an
arbitrary caller-built sequence:

```haskell
{-# LANGUAGE QualifiedDo #-}
import qualified Control.Operation.Flow as F

instance Operation Account '[Verify, Settle] where
  type Context Account = (Verify Account, Settle Account)
  type Outcome Account = F.Flow (Action Account) '[Integer] '[] Integer
  data DSL Account where
    PlanPayment :: Context Account => DSL Account
  interpret (SomeOperation (_value :: actual)) request =
    case eqT @actual @Account of
      Nothing -> Nothing
      Just Refl -> case request of
        PlanPayment -> Just $ F.do
          amount <- F.step VerifyAmount
          let fee = if amount > 100 then 2 else 1
          F.step (SettleAmount fee)
```

The fee is computed after `VerifyAmount` returns, not while assembling the
program. This uses ordinary Haskell `if` on the returned value. Instructions
and dictionaries come from the application; Flow does not discover or grant
additional capabilities. See [examples/FlowExample.hs](examples/FlowExample.hs)
for the full action GADT, capability instances and `Operation` integration.
Its `payment` helper only dispatches to `interpret`; the separate `runPayment`
evaluator calls `runFlow` and matches instructions to obtain method dictionaries.
This example evaluates in pure `Either`. For effectful applications, return a
Flow or a closed safe/critical program containing it and evaluate IO only at the
application's controlled boundary. Building or resolving a workflow must not
read a database, sign, send, or perform other effects. Runtime-dependent decisions
remain in `Bind` continuations or `Branch`; they run when their inputs are
available, not during initial construction. A separate interpreter for leaf
instructions may compile them into deferred actions at that boundary.

Payload equality proves type identity, not authorization or valid payment data.
Keep authentication, locks, financial checks, journaling and replay protection
in the evaluator and its concrete operations. This is an application design
discipline: the generic library does not enforce a particular evaluator or make
arbitrary capability instances safe.
For runtime schema selection, retain `IndexedRequest` and its declared-capability
checks before executing the selected workflow.

`runFlow` accepts a polymorphic handler:

```haskell
forall xs ys a. instruction xs ys a -> Values xs -> m (a, Values ys)
```

It preserves the indices through each step and returns `m (result, Values after)`.
The chosen monad defines failure/effect semantics: `Either` stops on `Left`, while
`IO` performs effects only when the returned action is executed. Unselected
branches and continuations following a monadic failure are not evaluated.

For dedicated workflow modules, enable `RebindableSyntax` and import
`Control.Operation.Flow.Rebindable` instead of Prelude. Unqualified `do` then
builds Flow, and `if predicate then yes else no` builds `Branch` with
`predicate :: Values before -> Bool`. A bound runtime value can be captured by
either branch. See [test/FlowRebindable.hs](test/FlowRebindable.hs). This is a
different condition type from ordinary Boolean `if`; use a predicate such as
`const condition` for an already computed Boolean, or use ordinary `case`.

Prefer QualifiedDo when mixing workflows with ordinary IO/Either code. The
optional prelude deliberately supplies no `fail`: use explicit `case` and domain
instructions for refutable-pattern/error handling, rather than introducing an
implicit failure policy. No ApplicativeDo or recursive-do support is supplied.

Flow does not promise rollback, linear consumption, a serializable syntax tree
(Bind contains Haskell functions), authorization, or stack-safe unbounded bind
chains. Construction stores instructions and functions without interpreting
them; arbitrary bottoms in caller expressions still follow Haskell evaluation
rules. Re-running an effectful Flow re-runs its effects.

Validation: `cabal test` exercises both syntax styles, whole-workflow Operation
dispatch, mismatch laziness and separate evaluation;
`bash test/check-flow.sh` checks valid programs and rejects bad state transitions,
branch outputs, returned values and missing instruction capabilities.
