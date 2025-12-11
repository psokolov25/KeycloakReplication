#!/usr/bin/env bash
set -euo pipefail

log() {
  local ts
  ts="$(date -Iseconds)"
  echo "${ts} [repl-init] $*" >&2
}

REPL_INIT_MAX_WAIT="${REPL_INIT_MAX_WAIT:-300}"
REPL_INIT_SLEEP_STEP="${REPL_INIT_SLEEP_STEP:-5}"
REPL_INIT_INITIAL_SLEEP="${REPL_INIT_INITIAL_SLEEP:-400}"

CENTER_DB_HOST="${CENTER_DB_HOST:-pg-center}"
CENTER_DB_PORT="${CENTER_DB_PORT:-5432}"
CENTER_DB_NAME="${CENTER_DB_NAME:-keycloak}"
CENTER_DB_USER="${CENTER_DB_USER:-keycloak}"
CENTER_DB_PASSWORD="${CENTER_DB_PASSWORD:-dev_center_pass}"

BRANCH_DB_HOST="${BRANCH_DB_HOST:-pg-branch}"
BRANCH_DB_PORT="${BRANCH_DB_PORT:-5432}"
BRANCH_DB_NAME="${BRANCH_DB_NAME:-keycloak}"
BRANCH_DB_USER="${BRANCH_DB_USER:-keycloak}"
BRANCH_DB_PASSWORD="${BRANCH_DB_PASSWORD:-dev_branch_pass}"

wait_for_table() {
  local host="$1"
  local port="$2"
  local db="$3"
  local user="$4"
  local password="$5"
  local table="$6"

  local waited=0

  log "Waiting for table '${table}' in database '${db}' at ${host}:${port} (timeout=${REPL_INIT_MAX_WAIT}s, step=${REPL_INIT_SLEEP_STEP}s)..."

  while (( waited < REPL_INIT_MAX_WAIT )); do
    if PGPASSWORD="${password}" psql -h "${host}" -p "${port}" -U "${user}" -d "${db}" -Atqc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${table}' LIMIT 1;" >/dev/null 2>&1; then
      log "Table '${table}' is present in database '${db}' at ${host}:${port}"
      return 0
    else
      log "Table '${table}' not found yet in database '${db}' at ${host}:${port}, retrying in ${REPL_INIT_SLEEP_STEP}s..."
      sleep "${REPL_INIT_SLEEP_STEP}"
      waited=$(( waited + REPL_INIT_SLEEP_STEP ))
    fi
  done

  log "ERROR: Timeout waiting for table '${table}' in database '${db}' at ${host}:${port} after ${REPL_INIT_MAX_WAIT}s"
  return 1
}

check_longtime_tables() {
  local host="$1"
  local port="$2"
  local db="$3"
  local user="$4"
  local password="$5"
  shift 5
  local tables=("$@")

  local waited=0

  log "Checking full set of longtime tables in database '${db}' at ${host}:${port} (timeout=${REPL_INIT_MAX_WAIT}s, step=${REPL_INIT_SLEEP_STEP}s)..."

  while (( waited < REPL_INIT_MAX_WAIT )); do
    local missing=()
    for tbl in "${tables[@]}"; do
      if ! PGPASSWORD="${password}" psql -h "${host}" -p "${port}" -U "${user}" -d "${db}" -Atqc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${tbl}' LIMIT 1;" >/dev/null 2>&1; then
        missing+=("${tbl}")
      fi
    done

    if ((${#missing[@]} == 0)); then
      log "All longtime tables are present in database '${db}' at ${host}:${port}"
      return 0
    else
      log "Still missing longtime tables in '${db}' at ${host}:${port}: ${missing[*]} (waiting ${REPL_INIT_SLEEP_STEP}s)..."
      sleep "${REPL_INIT_SLEEP_STEP}"
      waited=$(( waited + REPL_INIT_SLEEP_STEP ))
    fi
  done

  log "ERROR: Timeout waiting for full set of longtime tables in database '${db}' at ${host}:${port} after ${REPL_INIT_MAX_WAIT}s"
  return 1
}

main() {
  log "Starting replication init..."
  log "Initial sleep ${REPL_INIT_INITIAL_SLEEP}s to allow Keycloak migrations to complete..."
  sleep "${REPL_INIT_INITIAL_SLEEP}"

  wait_for_table "${CENTER_DB_HOST}" "${CENTER_DB_PORT}" "${CENTER_DB_NAME}" "${CENTER_DB_USER}" "${CENTER_DB_PASSWORD}" "realm"
  wait_for_table "${CENTER_DB_HOST}" "${CENTER_DB_PORT}" "${CENTER_DB_NAME}" "${CENTER_DB_USER}" "${CENTER_DB_PASSWORD}" "user_entity"
  wait_for_table "${BRANCH_DB_HOST}" "${BRANCH_DB_PORT}" "${BRANCH_DB_NAME}" "${BRANCH_DB_USER}" "${BRANCH_DB_PASSWORD}" "realm"
  wait_for_table "${BRANCH_DB_HOST}" "${BRANCH_DB_PORT}" "${BRANCH_DB_NAME}" "${BRANCH_DB_USER}" "${BRANCH_DB_PASSWORD}" "user_entity"

  local longtime_tables=(
    "realm"
    "user_entity"
    "client"
    "role_"
    "group_"
    "user_group_membership"
    "user_role_mapping"
    "client_role"
    "client_scope"
    "identity_provider"
    "identity_provider_mapper"
  )

  check_longtime_tables "${CENTER_DB_HOST}" "${CENTER_DB_PORT}" "${CENTER_DB_NAME}" "${CENTER_DB_USER}" "${CENTER_DB_PASSWORD}" "${longtime_tables[@]}"
  check_longtime_tables "${BRANCH_DB_HOST}" "${BRANCH_DB_PORT}" "${BRANCH_DB_NAME}" "${BRANCH_DB_USER}" "${BRANCH_DB_PASSWORD}" "${longtime_tables[@]}"

  log "Configuring publication on center..."
  PGPASSWORD="${CENTER_DB_PASSWORD}" psql -v ON_ERROR_STOP=1 -h "${CENTER_DB_HOST}" -p "${CENTER_DB_PORT}" -U "${CENTER_DB_USER}" -d "${CENTER_DB_NAME}" -f /sql/center-publication-longtime.sql

  log "Configuring subscription on branch..."
  PGPASSWORD="${BRANCH_DB_PASSWORD}" psql -v ON_ERROR_STOP=1 -h "${BRANCH_DB_HOST}" -p "${BRANCH_DB_PORT}" -U "${BRANCH_DB_USER}" -d "${BRANCH_DB_NAME}" -f /sql/branch-subscription-longtime.sql

  log "Checking subscriptions on branch (SELECT * FROM pg_stat_subscription)..."
  PGPASSWORD="${BRANCH_DB_PASSWORD}" psql -h "${BRANCH_DB_HOST}" -p "${BRANCH_DB_PORT}" -U "${BRANCH_DB_USER}" -d "${BRANCH_DB_NAME}" -c "SELECT * FROM pg_stat_subscription;"

  log "Replication init completed successfully."
}

main "$@"
