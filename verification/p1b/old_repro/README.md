# P1-B-R1 old-version reproduction fixtures

These fixtures reproduce the three review blockers against implementation commit
`278f6f7e13eb423952c1119a28d1900f3ac57356`; they are not part of the current
RTL or normal checker.

- `tb_jal_old.cpp`: drives `0x000010ef` and `0x000012ef` into the old decoder.
- `tb_f02_old.cpp`: drives the old integrated frontend. It checks a held decoded
  result with redirect+accept in the same cycle, then a last-generation request
  cancelled before an injected wrong-ID/gen response.
- `scripts/repro_p1_b_r1.sh` checks out the old commit in a detached worktree.
  For F03 it copies the old `tb_frontend.cpp` and removes only the immediate
  `+mismatch` return, leaving the old per-seed `tb.errors=0` clearing intact;
  the patched source and diff are saved in the evidence directory.

The old worktree is temporary under `/tmp/opencode`; all logs and patches are
written under `verification/evidence/P1-B-R1/old-repro/`.
