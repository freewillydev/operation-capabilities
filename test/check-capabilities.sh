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
for variant in MISSING DUPLICATE CONFLICT EXTRA_DUPLICATE ARBITRARY RESTRICTED RESTRICT_EXPANDS EXPAND_RESTRICTS COERCE_VIEW PRIVATE_CONSTRUCTOR BAD_COMPOSITION BAD_OUTCOME BAD_ERROR HIDDEN_SELECTION; do
    if compile "-D$variant" > "$work/$variant.log" 2>&1; then
        printf 'FAIL %s unexpectedly compiled\n' "$variant" >&2
        exit 1
    fi
    case "$variant" in
        MISSING) expected='No instance for.*Named Request' ;;
        DUPLICATE|EXTRA_DUPLICATE) expected='Duplicate operation capability' ;;
        CONFLICT) expected='Functional dependencies conflict' ;;
        ARBITRARY|RESTRICT_EXPANDS|EXPAND_RESTRICTS) expected='No instance for' ;;
        RESTRICTED|HIDDEN_SELECTION) expected='Could not deduce.*Named' ;;
        BAD_COMPOSITION|BAD_OUTCOME|BAD_ERROR|COERCE_VIEW) expected="Couldn't match type" ;;
        PRIVATE_CONSTRUCTOR) expected='Data constructor not in scope' ;;
    esac
    if ! grep -Eq "$expected" "$work/$variant.log"; then
        cat "$work/$variant.log" >&2
        exit 1
    fi
    printf 'PASS %s rejected for the expected type error\n' "$variant"
done
