# Adoption handoff

Use https://github.com/freewillydev/operation-capabilities at tag `v0.1.1.0`
(or pin its full commit SHA) as a Cabal dependency. The package requires GHC 9.6
or newer and depends only on `base`. Read the README and `examples/Demo.hs` first.

Preserve these design requirements:

1. `Operation op caps | op -> caps` assigns one duplicate-free list of capability
   classes to every payload. Do not add the reverse dependency: different payloads
   can share capability lists.
2. Pack existential requests with both `Operation op caps` and
   `Capabilities caps op`, using exactly the same `caps`.
3. Keep `interpret :: SomeOperation -> DSL op -> Maybe (Outcome op)` and the
   injective `Context`, associated `DSL` GADT, and `Outcome` families.
4. DSL constructors carry specific class constraints. Unpack the existential,
   match the constructor, compare payload types using `eqT`, and invoke the
   specific class method directly inside `Just Refl`. No unchecked casts or
   constraint-type comparisons. `Nothing` means a type mismatch, not a domain error.
5. Keep behavior in focused classes and reusable instances. Use the optional
   `Validation`/`Check` adapter where it removes repetition, not as a universal
   action dispatcher.
6. Prepare requests through `SomeOperationWith declared visible` and
   `Pipeline declared before after`. `prepare` starts fully visible; `Preserve`
   keeps capabilities, `Restrict` hides them, and `Expand` restores only declared
   ones. An undeclared class must never become available through expansion.
7. Compose stages with `:>>>`. Preserve the hidden payload type, stop on `Left`,
   and do not automatically interpret. Stage implementations only receive their
   visible dictionaries. Keep the envelope constructor private.
8. Use `forgetCapabilities` only at the terminal dispatch boundary; it erases the
   visibility index but retains canonical dictionaries. This is not a security
   sandbox or irreversible permission revocation.
9. Retain runtime and compile-negative tests. Run `cabal test all` and
   `bash test/check-capabilities.sh`, and add tests for the destination project's
   domain behavior rather than assuming the library tests cover it.

Do not copy Elements-specific business logic, FFI code, configuration, or secrets.
Prefer depending on this package to maintaining divergent copied frameworks.
Adapt to the destination project's existing conventions and preserve unrelated
changes. A passing upstream library build does not qualify a new integration.

The repository includes `ci/github-actions.yml` as an inactive template because
the publishing credential lacked workflow permission. Hosted cross-platform CI
has not run; do not claim it has. An authorized maintainer must activate it.

The optional `Control.Operation.Severity` module provides the opaque, nominal
`SomeOperationAt program caller severity result` carrier. Pack a selected DSL with
`prepareOperation`, which requires its outcome to match those indices. Resolve
explicitly with `resolveOperation`; retain payload equality in the Operation
instance and application-owned safe/critical evaluators and runtime authorization.
No local existential/newtype is needed just to partially apply the carrier.
The original capability pipeline API is unchanged; the separate indexed-pipeline
branch is not incorporated into this release.

For a variable number of heterogeneous results, use `Control.Operation.Outputs`
rather than an untyped list or a fixed tuple. Define an `OutputSchema` with an
associated `OutputCapability`; prove unknown payload equality before returning
its `OutputDict`. Use the optional `OutputRendering` associated result for pure
rendering, or `withOutputs`/`foldOutputsM` for domain-specific effects. Keep request
preparation on the existing Restrict/Preserve/Expand pipeline. The complete schema
is resolved before values are inspected; rejection does not run prefix effects.
Use the equality-constrained append/composition functions rather than casts.
The runnable `VariableOutputs` example and output type/property tests are part of
the package. See README's variable output schemas section for semantics and limits.

For outputs that each carry a hidden payload and their own methods, use
`CapabilityOutput`/`SomeCapabilityOutput`. The carried `SomeOperationWith` view
is selected by `IndexCaps`; capability parameters may have different kinds.
`withMatchingIndex` grants `(actual ~~ selected)` only after `eqTypeRep` succeeds,
transporting the carried index class and its associated constraint families.
`interpretOutput` then invokes `runIndexed` using only visible methods. See
`CapableOutputs` for a class parameterized by both Symbol and a promoted Slot.
Use `OutputStream` to keep batches uninterpreted across demand-driven stages.
Ordinary output-list equality remains homogeneous; do not use `(~~)` just because
a list contains heterogeneous values. Preserve native callback lifetimes.
