# operation-capabilities

A small Haskell library for preparing existential operations without interpreting
them prematurely. Each operation declares its capability classes once. Pipelines
make changes to the visible subset explicit and statically checked.

The library depends only on `base`. QuickCheck is a test-only dependency.
Tested with GHC 9.6.7. MIT licensed. This package is not yet published to Hackage.

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
  tag: v0.1.0.0
```

Then add `operation-capabilities ==0.1.0.0` to the component's `build-depends`.
For an immutable dependency, replace the tag with its resolved full commit SHA.
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

Runtime tests run seven QuickCheck properties, 10,000 cases each, using seed
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
