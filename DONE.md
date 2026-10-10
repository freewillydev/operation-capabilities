Done means: indexed preparation and typed interpretation preserve capability boundaries and integrate into the bridge without changing financial execution.

- Library build/properties: `cabal build all -j1` and `cabal test all -j1 --test-show-details=direct` exit0. PASS GHC9.14.1, /tmp/ecx-indexed-library-build.log and /tmp/ecx-indexed-library-test.log (9 properties, 10000 cases each).
- Type checks: `bash test/check-capabilities.sh` accepts positive and rejects all14 variants for intended reasons. PASS with GHC9.6.7; log /tmp/ecx-indexed-library-types.log.
- Bridge: typed preparation compiles and existing caller/severity/result/capability negative checks remain rejected. PASS direct GHC9.14.1 positive plus nine intended negatives; /tmp/ecx-indexed-bridge-*.log.
- Fresh independent verifier: exact library and bridge changes receive explicit scoped PASS. PASS: Fresh verifier01a12711-79cf-7532-b6d1-bdd180b66245 turn01a12714-ba86-7b80-847f-0addf51ae5d5: bounded source/type and supplied execution evidence PASS for librarya9aec9b + bridge0ea4bf7; full components/PG/financial/release unverified.
- Broader bridge Cabal/component/PostgreSQL and release gates remain outside this extension and unverified for its bytes.
