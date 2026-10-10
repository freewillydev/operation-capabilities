## 0.2.0.0

- Breaking: Pipeline indexes error/input/output; Stage takes an error type.
- Add Transform and typed Interpret/Selection; preserve capability projection.
- Test endpoint/error/outcome mismatches and deferred interpretation effects.

# Changelog

## 0.1.0.0

- Extract the reusable Operation/capability design into a base-only library.
- Enforce one duplicate-free capability list per operation via `op -> caps`.
- Preserve class-constrained existential dispatch and typed `interpret` results.
- Add explicit capability-preserving, restricting, and expanding pipelines.
- Include the generic Validation/Check interpreter, a runnable example,
  QuickCheck properties, compile-time rejection tests, and an inactive CI template.
