# P0-01 unified entry points. Build products go to build/ and are ignored.
# Expected-failure probes are identified explicitly by scripts/run_*_smoke.sh;
# the top-level target fails on any missing tool or unexpected failure.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help env-check lint-smoke rtl-smoke ref-smoke check-p0-01 r1-probes check-p0-02 check-p1-a check-p1-b check-p1-c check-p1-d platform-generate platform-check clean

help:
	@printf '%s\n' \
	  'P0-01 targets:' \
	  '  make env-check     check OS, tools, versions, RV32I/ILP32 compile' \
	  '  make lint-smoke    Verilator lint for the smoke fixture and probe' \
	  '  make rtl-smoke     build/run fixture, assertion, checker, timeout probes' \
	  '  make ref-smoke     build RV32I ELF variants and run them under Spike' \
	  '  make check-p0-01   run env-check, lint-smoke, rtl-smoke, ref-smoke' \
	  '  make r1-probes     run controlled fault-injection probes (P0-01-R1)' \
	  '  make platform-generate  regenerate files from config/platform.json' \
	  '  make platform-check     validate platform config and generated files' \
	  '  make check-p0-02   platform/types/retire checks + P0-01 regression' \
	  '  make check-p1-a    P1-A skeleton, RAM/bridge, token joint and regression' \
	  '  make check-p1-b    P1-B fetch/decode, real RAM integration and P1-A regression' \
	  '  make check-p1-c    P1-C integer execute, sequential commit, Spike diff and P1-B regression' \
	  '  make check-p1-d    P1-D Load/Store, arbitrated RAM, data faults and P1-C regression' \
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

r1-probes:
	@set -o pipefail; \
	./scripts/run_r1_probes.sh

platform-generate:
	python3 ./scripts/gen_platform.py

platform-check:
	python3 ./scripts/gen_platform.py --check
	python3 ./scripts/check_platform.py

check-p0-02:
	@set -o pipefail; \
	./scripts/check_p0_02.sh

check-p1-a:
	@set -o pipefail; \
	./scripts/check_p1_a.sh

check-p1-b:
	@set -o pipefail; \
	./scripts/check_p1_b.sh

check-p1-c:
	@set -o pipefail; \
	./scripts/check_p1_c.sh

check-p1-d:
	@set -o pipefail; \
	./scripts/check_p1_d.sh

clean:
	rm -rf build
