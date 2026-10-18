# Changelog

## 0.2.0.0

- Remove the shared index-matching continuation helper. Runtime existential
  dispatch uses explicit equality evidence; capability applications carry `~~`
  in GADT constructors until their final constraint dictionary is available.
- Add kind-polymorphic, variadic capability descriptors with payload insertion
  at any argument position. Retain unary lists for simple operations.
- Keep declared-capability restriction, expansion and uniqueness checks for both
  forms. `IndexedCapability index caps` now declares its list directly through a
  functional dependency, replacing the separate `IndexCaps` associated family.
- Exercise zero-, one-, two- and four-argument applications, independently kinded
  arguments, restricted output methods and compile-time rejection boundaries.

## 0.1.5.0

- Share lazy payload equality through withOperation without changing interpret,
  capability visibility, associated request GADTs, or domain outcomes.
- Remove repeated equality dispatch from the validation adapter and examples.
- Reuse registered-index matching and the pull-stream constructor; retain
  existential output schemas, variable arity, and failure/short-circuit behavior.
- Add matching-laziness and empty/failed-source stream regressions.

## 0.1.4.0

- Add runtime-variable heterogeneous outputs with a retained type-level spine.
- Resolve registered output dictionaries through OutputSchema and its associated
  OutputCapability; provide optional OutputRendering with an associated result.
- Check the complete schema before inspecting values, then fold effects in order.
- Add equality-constrained append/composition and a capability-restricted example.
- Add runtime properties and compile-time rejection tests for output schemas.
- Add existential CapabilityOutput values using the existing capability views;
  transport poly-kinded index dictionaries through heterogeneous equality.
- Add registered IndexMatch/discoverRequest helpers and deferred pull streams.
- Keep homogeneous output-list equality simple and preserve Operation.interpret.

## 0.1.3.0

- Add deferred heterogeneous-state Flow with Pure, Step, Bind and Branch.
- Add a rank-n interpreter and QualifiedDo operators for runtime-dependent
  continuations; add an optional RebindableSyntax prelude for state-based if.
- Keep Operation, capability preparation and indexed dispatch APIs unchanged.
- Add compiling Operation examples, runtime properties and type rejection tests.

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
