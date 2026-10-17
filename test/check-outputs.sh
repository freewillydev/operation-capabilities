#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/operation-outputs.XXXXXX")
trap 'rm -rf "$work"' EXIT
compile() {
    "${GHC:-ghc}" -v0 -XHaskell2010 -fno-code -fforce-recomp -Wall -Werror -no-user-package-db -package-env - \
        -hide-all-packages -package base -i"$root/src" -i"$root/examples" \
        -odir "$work" -hidir "$work" "$root/test/OutputTypes.hs" "$@"
}
compile
printf 'PASS typed output concatenation and restricted production\n'
for variant in WRONG_SEQUENCE WRONG_APPEND FORGED_METHODS HIDDEN_CAPABILITY OUTPUT_ARBITRARY REGISTRY_ARBITRARY WRONG_REQUEST_RESULT; do
    if compile "-D$variant" > "$work/$variant.log" 2>&1; then
        printf 'FAIL %s unexpectedly compiled\n' "$variant" >&2
        exit 1
    fi
    case "$variant" in
        FORGED_METHODS) expected='Could not deduce.*RenderOutput' ;;
        HIDDEN_CAPABILITY) expected='Could not deduce.*Inspect' ;;
        REGISTRY_ARBITRARY) expected='No instance for' ;;
        *) expected="Couldn't match" ;;
    esac
    if ! grep -Eq "$expected" "$work/$variant.log"; then
        cat "$work/$variant.log" >&2
        exit 1
    fi
    printf 'PASS %s rejected for the expected type error\n' "$variant"
done
