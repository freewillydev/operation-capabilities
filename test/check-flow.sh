#!/usr/bin/env bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/operation-flow.XXXXXX")
trap 'rm -rf "$work"' EXIT
compile() {
    "${GHC:-ghc}" -v0 -fno-code -fforce-recomp -Wall -Werror -no-user-package-db -package-env - \
        -hide-all-packages -package base -i"$root/src" -i"$root/examples" \
        -odir "$work" -hidir "$work" "$root/test/FlowTypes.hs" "$@"
}
compile
printf 'PASS indexed flow with value-dependent continuation\n'
for variant in WRONG_INPUT WRONG_SEQUENCE WRONG_BRANCH WRONG_RESULT MISSING_CAPABILITY; do
    if compile "-D$variant" > "$work/$variant.log" 2>&1; then
        printf 'FAIL %s unexpectedly compiled\n' "$variant" >&2
        exit 1
    fi
    case "$variant" in
        MISSING_CAPABILITY) expected='No instance for.*Verify Unregistered' ;;
        *) expected="Couldn't match" ;;
    esac
    if ! grep -Eq "$expected" "$work/$variant.log"; then
        cat "$work/$variant.log" >&2
        exit 1
    fi
    printf 'PASS %s rejected for the expected type error\n' "$variant"
done
