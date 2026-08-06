#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Damián Búho <damian.buho@proton.me>
#
# SPDX-License-Identifier: MIT

    set -o pipefail  # Note: Removed `-e` to ensure all suites run, even if one fails

    # shellcheck source=.container/foundation/tools.d/b19-i18n
    . b19-i18n

    # Skip benchmarks if disabled
    if [ "${B19_BENCHMARK_ENABLED:-}" = "false" ]; then
      b19-log warn "BENCH.D" "$(_ "Benchmarks disabled") (B19_BENCHMARK_ENABLED=false)"
      exit 0
    fi

    BENCHMARK_PATH="${B19_BENCHMARK_PATH:-/benchmark.d}"
    RESULTS_PATH="${B19_BENCHMARK_RESULTS_PATH:-/tmp/benchmark.d}"

    # Ensure results directory exists
    b19-run "BENCH.D" "$(_ "Make results directory") " -- \
      mkdir -p "${RESULTS_PATH}"

    # Run a single benchmark suite
    run_suite() {
      local SUITE="$1"
      local SUITE_DIR="${BENCHMARK_PATH}/${SUITE}"
      local EXIT_CODE=0
      local SETUP_FAILED=0

      # Verify the suite exists and has benchmark.sh
      if [ ! -f "${SUITE_DIR}/benchmark.sh" ]; then
        b19-log bad "BENCH.D" "$(_p "Benchmark suite not found: %s" "${SUITE}")"
        return 1
      fi

      # Setup (sourced — variables persist to benchmark)
      if [ -f "${SUITE_DIR}/setup.sh" ]; then
        b19-log info "BENCH.D" "$(_p "Setup: %s" "${SUITE}")"
        # shellcheck disable=SC1090,SC1091
        if ! . "${SUITE_DIR}/setup.sh"; then
          b19-log warn "BENCH.D" "$(_p "Setup failed for %s — skipping" "${SUITE}")"
          SETUP_FAILED=1
        fi
      fi

      # Execute benchmark (skip if setup failed, e.g. offgrid apt-get)
      if [ "${SETUP_FAILED}" -eq 0 ]; then
        b19-log info "BENCH.D" "$(_p "Benchmarking: %s" "${SUITE}")"
        "${SUITE_DIR}/benchmark.sh" 2>&1 | tee "${RESULTS_PATH}/${SUITE}.log"
        EXIT_CODE=${PIPESTATUS[0]}
      fi

      # Teardown (sourced — always runs, even if setup or benchmark failed)
      if [ -f "${SUITE_DIR}/teardown.sh" ]; then
        b19-log info "BENCH.D" "$(_p "Teardown: %s" "${SUITE}")"
        # shellcheck disable=SC1090,SC1091
        . "${SUITE_DIR}/teardown.sh"
      fi

      # If setup failed, don't propagate benchmark exit code
      [ "${SETUP_FAILED}" -eq 1 ] && return 0

      return "${EXIT_CODE}"
    }

    FINAL_EXIT_CODE=0
    FAILED_COUNT=0

    # Single suite mode: benchmark.d <suite-name>
    if [ -n "${1:-}" ]; then
      run_suite "$1"
      exit $?
    fi

    # All suites mode: benchmark.d (no args)
    b19-log info "BENCH.D" "$(_p "Reading from: %s" "${BENCHMARK_PATH}")"
    b19-log info "BENCH.D" "$(_ "Writing to:") ${RESULTS_PATH}"

    if [ -d "${BENCHMARK_PATH}" ]; then
      SUITES_COUNT=0
      while IFS= read -r -d '' SUITE_DIR; do
        SUITE_NAME="$(basename "${SUITE_DIR}")"
        SUITES_COUNT=$((SUITES_COUNT + 1))

        if ! run_suite "${SUITE_NAME}"; then
          FINAL_EXIT_CODE=1
          FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
      done < <(fd --print0 --hidden --type directory --exact-depth 1 . "${BENCHMARK_PATH}" | sort --zero-terminated --numeric-sort)

      if [ "${SUITES_COUNT}" -eq 0 ]; then
        b19-log note "BENCH.D" "$(_p "No benchmark suites found in %s" "${BENCHMARK_PATH}")"
      fi
    else
      b19-log note "BENCH.D" "$(_p "Benchmark directory not found: %s" "${BENCHMARK_PATH}")"
    fi

    # Final result
    if [ "${FINAL_EXIT_CODE}" -ne 0 ]; then
      b19-log bad "BENCH.D" "$(_p "%d of %d benchmark suites failed." "${FAILED_COUNT}" "${SUITES_COUNT}")"
    else
      b19-log good "BENCH.D" "$(_p "All %d benchmark suites completed." "${SUITES_COUNT}")"
    fi

exit "${FINAL_EXIT_CODE}"
