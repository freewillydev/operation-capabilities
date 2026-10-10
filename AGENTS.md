# Indexed pipeline extension

This isolated checkout is owned by WRAPPED ECX SOL (2). Follow the controller
PROTOCOL.md and OWNERS.md. Keep capability projection private, retain nominal
roles and payload equality checks, and do not claim type indices authorize IO.

## How to run and verify this project

Run `cabal build all -j1`, `cabal test all -j1 --test-show-details=direct`, and
`GHC=ghc bash test/check-capabilities.sh`. The latter must accept its positive
control and reject each variant for its intended diagnostic. DONE.md records
scope; a fresh nonimplementing verifier is required before completion.
