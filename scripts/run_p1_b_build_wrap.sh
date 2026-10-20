#!/usr/bin/env bash
# Controlled build wrapper for G01. It runs the real command first; if the
# requested tag is selected it returns 3 after the executable has been built.
set -u
"$@"
rc=$?
if [ "${P1_B_FORCE_BUILD_FAIL:-}" = "${P1_B_BUILD_TAG:-}" ]; then
  printf 'P1-B_BUILD_WRAPPER_FORCED_FAIL tag=%s real_rc=%s\n' \
    "$P1_B_BUILD_TAG" "$rc" >&2
  exit 3
fi
exit "$rc"
