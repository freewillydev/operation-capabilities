# Changelog

## 0.1.2.0

- Add kind-polymorphic indexed requests selecting only declared capabilities.
- Dispatch after payload equality through a request GADT, with optional runtime
  index equality for schema-bound callers; mismatches do not evaluate inputs.
- Add multi-capability planning examples and runtime/compile-time regression tests.
- Retain the severity API added in 0.1.1.0.

## 0.1.1.0

- Add optional base-only severity-indexed operation envelopes, binding caller,
  Safe/Critical classification and result to the interpreted program.
- Keep payload equality checks, capability visibility and explicit interpretation;
  no evaluator, IO execution or domain authorization is supplied by the library.
- Test nominal indices, private construction, typed selection and deferred effects.

## 0.1.0.0

- Extract the reusable Operation/capability design into a base-only library.
- Enforce one duplicate-free capability list per operation via `op -> caps`.
- Preserve class-constrained existential dispatch and typed `interpret` results.
- Add explicit capability-preserving, restricting, and expanding pipelines.
- Include the generic Validation/Check interpreter, a runnable example,
  QuickCheck properties, compile-time rejection tests, and an inactive CI template.
