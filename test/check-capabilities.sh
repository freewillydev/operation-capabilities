#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/operation-capabilities.XXXXXX")
trap 'rm -rf "$work"' EXIT
compile() {
    "${GHC:-ghc}" -v0 -fno-code -fforce-recomp -Wall -Werror -no-user-package-db -package-env - \
        -hide-all-packages -package base -i"$root/src" -odir "$work" -hidir "$work" \
        "$root/test/CapabilityTypes.hs" "$@"
}
compile
printf 'PASS inferred capability list, existential dictionaries, unchanged interpret\n'
for variant in MISSING DUPLICATE CONFLICT EXTRA_DUPLICATE ARBITRARY RESTRICTED RESTRICT_EXPANDS EXPAND_RESTRICTS COERCE_VIEW PRIVATE_CONSTRUCTOR INDEX_ARBITRARY INDEX_DUPLICATE; do
    if compile "-D$variant" > "$work/$variant.log" 2>&1; then
        printf 'FAIL %s unexpectedly compiled\n' "$variant" >&2
        exit 1
    fi
    case "$variant" in
        MISSING) expected='No instance for.*Named Request' ;;
        DUPLICATE|EXTRA_DUPLICATE|INDEX_DUPLICATE) expected='Duplicate operation capability' ;;
        CONFLICT) expected='Functional dependencies conflict' ;;
        ARBITRARY|RESTRICT_EXPANDS|EXPAND_RESTRICTS|INDEX_ARBITRARY) expected='No instance for' ;;
        RESTRICTED) expected='Could not deduce.*Named' ;;
        COERCE_VIEW) expected="Couldn't match type" ;;
        PRIVATE_CONSTRUCTOR) expected='Data constructor not in scope' ;;
    esac
    if ! grep -Eq "$expected" "$work/$variant.log"; then
        cat "$work/$variant.log" >&2
        exit 1
    fi
    printf 'PASS %s rejected for the expected type error\n' "$variant"
done

compile_severity() {
    "${GHC:-ghc}" -v0 -fno-code -fforce-recomp -Wall -Werror -no-user-package-db -package-env - \
        -hide-all-packages -package base -i"$root/src" -odir "$work" -hidir "$work" \
        "$root/test/SeverityTypes.hs" "$@"
}
compile_severity
printf 'PASS indexed existential and partially applied carrier\n'
for variant in WRONG_CALLER WRONG_SEVERITY WRONG_RESULT WRONG_PROGRAM COERCE_CALLER COERCE_SEVERITY COERCE_RESULT COERCE_PROGRAM PRIVATE_SCOPED WRONG_DSL HIDDEN_SELECTOR; do
    if compile_severity "-D$variant" > "$work/$variant.log" 2>&1; then
        printf 'FAIL %s unexpectedly compiled\n' "$variant" >&2
        exit 1
    fi
    case "$variant" in
        PRIVATE_SCOPED) expected='Data constructor not in scope' ;;
        HIDDEN_SELECTOR) expected='Could not deduce.*Reading' ;;
        *) expected="Couldn't match" ;;
    esac
    if ! grep -Eq "$expected" "$work/$variant.log"; then
        cat "$work/$variant.log" >&2
        exit 1
    fi
    printf 'PASS %s rejected for the expected type error\n' "$variant"
done

compile_applications() {
    "${GHC:-ghc}" -v0 -fno-code -fforce-recomp -Wall -Werror -no-user-package-db -package-env - \
        -hide-all-packages -package base -i"$root/src" -i"$root/examples" \
        -odir "$work" -hidir "$work" "$root/test/CapabilityApplications.hs" "$@"
}
compile_applications
printf 'PASS curried capability applications and restricted methods\n'
for variant in WRONG_KIND WRONG_RESULT INCOMPLETE FORGED_DICTIONARY HIDDEN_METHOD UNDECLARED DUPLICATE; do
    if compile_applications "-D$variant" > "$work/$variant.log" 2>&1; then
        printf 'FAIL %s unexpectedly compiled\n' "$variant" >&2
        exit 1
    fi
    case "$variant" in
        WRONG_KIND) expected="Couldn't match kind" ;;
        INCOMPLETE) expected="Couldn't match (kind|type)" ;;
        WRONG_RESULT) expected="Couldn't match type" ;;
        FORGED_DICTIONARY) expected='No instance for.*Show Missing' ;;
        HIDDEN_METHOD) expected='Could not deduce.*Quote' ;;
        UNDECLARED) expected='No instance for' ;;
        DUPLICATE) expected='Duplicate operation capability' ;;
    esac
    if ! grep -Eq "$expected" "$work/$variant.log"; then
        cat "$work/$variant.log" >&2
        exit 1
    fi
    printf 'PASS curried %s rejected for the expected type error\n' "$variant"
done
