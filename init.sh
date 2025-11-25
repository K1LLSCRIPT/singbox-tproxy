#!/bin/bash

WORK_DIR="/root";
CONFIG_FILE="config.sh";
SCRIPT_NAME="$(basename $0)";
SCRIPT_DIR="$(dirname "$(realpath "$0")")";
WORK_DIR="${WORK_DIR}/${SCRIPT_DIR##*/}";

source <(cat "${SCRIPT_DIR}/${CONFIG_FILE}");
source <(cat "${SCRIPT_DIR}/log.sh");

[[ "$SCRIPT_DIR" != "$WORK_DIR" ]] && {
  log "SCRIPT_DIR: ${SCRIPT_DIR}";
  log "WORK_DIR: ${WORK_DIR}";
  log "copy files";
  mkdir -p "$WORK_DIR";
  for f in $(find "$SCRIPT_DIR" -type f -name "*.sh"); do
    [[ "${f##*/}" == "config.sh" ]] &&
    [[ -f "${WORK_DIR}/${CONFIG_FILE}" ]] ||
    cp "$f" "$WORK_DIR";
  done
  exec "${WORK_DIR}/init.sh" "$@";
}

echo;
log "running";
log "SCRIPT_DIR: ${SCRIPT_DIR}";
log "WORK_DIR: ${WORK_DIR}";

USER_ARGS=(
  SUBSCRIPTION_URL
  EXTERNAL_UI_SECRET
  INBOUNDS_CONFIG_URL
);

check_user_args(){
  for a in "${USER_ARGS[@]}"; do
    (( ${#a} )) || {
      read -p "Please provide ${a}: " $v;
      sed -i -E "s/(${a})(.*)/\1=\'${v}\'/" "${WORK_DIR}/${CONFIG_FILE}";
    }
  done
  [[ ! -z "$v" ]] && source <(cat "${SCRIPT_DIR}/${CONFIG_FILE}") || log "all args are set.";
}

check_user_args;
