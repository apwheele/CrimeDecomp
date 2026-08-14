#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-4}"
mkdir -p src/data/model
run_log="${RUN_LOG:-src/data/model/sequential-linux-run.log}"
failure_log="${FAILURE_LOG:-src/data/model/sequential-linux-failure.log}"
crimes=(murder rape robbery assault burglary theft motor)

exec 9>src/data/model/sequential-run.lock
if ! flock -n 9; then
  printf '%s Another sequential model workflow is already running; refusing to start a duplicate.\n' \
    "$(date --iso-8601=seconds)" | tee -a "$failure_log"
  exit 75
fi

log_message() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$1" | tee -a "$run_log"
}

record_failure() {
  local crime="$1"
  local status="$2"
  {
    printf '%s %s\n' "$(date --iso-8601=seconds)" \
      "${crime} R process failed with exit status ${status}."
    echo "--- memory ---"
    free -h || true
    echo "--- swap ---"
    swapon --show || true
    echo "--- processes ---"
    ps -eo pid,ppid,etimes,time,pcpu,pmem,rss,vsz,stat,cmd || true
    echo "--- recent kernel diagnostics ---"
    dmesg -T 2>/dev/null | tail -n 100 || true
  } >> "$failure_log" 2>&1
  sync
}

hold_wsl_for_diagnostics() {
  # Keep the distro alive long enough to inspect dmesg and the failure logs from
  # another shell without delaying this runner's exit status.
  nohup sleep 600 </dev/null >src/data/model/wsl-diagnostic-hold.log 2>&1 &
  printf '%s WSL diagnostic hold started (PID %s, 10 minutes).\n' \
    "$(date --iso-8601=seconds)" "$!" >> "$failure_log"
}

log_message "Sequential Linux run started. Crimes will never overlap."
for crime in "${crimes[@]}"; do
  log_message "Starting or resuming ${crime}."
  set +e
  /usr/bin/time -v Rscript src/run_model.R \
    "--crime=${crime}" --fit-only=true --resume=true \
    --render-report=false --nthreads=1 2>&1 | tee -a "$run_log"
  r_status=${PIPESTATUS[0]}
  set -e
  if [[ "$r_status" -ne 0 ]]; then
    log_message "${crime} failed with R exit status ${r_status}; diagnostics saved to ${failure_log}."
    record_failure "$crime" "$r_status"
    hold_wsl_for_diagnostics
    exit "$r_status"
  fi
  log_message "${crime} completed."
done

log_message "All crime fits are saved; merging data outputs."
set +e
/usr/bin/time -v Rscript src/run_model.R --resume=true --render-report=false --nthreads=1 \
  2>&1 | tee -a "$run_log"
merge_status=${PIPESTATUS[0]}
set -e
if [[ "$merge_status" -ne 0 ]]; then
  log_message "Final merge failed with R exit status ${merge_status}; diagnostics saved to ${failure_log}."
  record_failure "final-merge" "$merge_status"
  hold_wsl_for_diagnostics
  exit "$merge_status"
fi
log_message "Sequential models and merged outputs completed."
log_message "Validating saved models and merged outputs."
Rscript src/validate_outputs.R 2>&1 | tee -a "$run_log"
log_message "Validation completed successfully."
