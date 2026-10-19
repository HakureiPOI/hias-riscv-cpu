# P0-01 unified entry points. Build products go to build/ and are ignored.
# Expected-failure probes are identified explicitly by scripts/run_*_smoke.sh;
# the top-level target fails on any missing tool or unexpected failure.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help env-check lint-smoke rtl-smoke ref-smoke check-p0-01 clean

help:
	@printf '%s\n' \
	  'P0-01 targets:' \
	  '  make env-check     check OS, tools, versions, RV32I/ILP32 compile' \
	  '  make lint-smoke    Verilator lint for the smoke fixture and probe' \
	  '  make rtl-smoke     build/run fixture, assertion, checker, timeout probes' \
	  '  make ref-smoke     build RV32I ELF variants and run them under Spike' \
	  '  make check-p0-01   run env-check, lint-smoke, rtl-smoke, ref-smoke' \
	  '  make clean         remove build/ (not evidence)'

env-check:
	./scripts/env_check.sh

lint-smoke:
	./scripts/run_rtl_smoke.sh --lint-only

rtl-smoke:
	./scripts/run_rtl_smoke.sh

ref-smoke:
	./scripts/run_ref_smoke.sh

check-p0-01:
	@set -o pipefail; \
	./scripts/check_p0_01.sh

clean:
	rm -rf build
