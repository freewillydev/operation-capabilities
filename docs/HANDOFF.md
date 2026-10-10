# Adoption handoff

Use https://github.com/freewillydev/operation-capabilities at tag `v0.1.0.0`
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
