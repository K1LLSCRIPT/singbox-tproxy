#!/bin/bash

WORK_DIR="/root";
CONFIG_FILE="config.sh";
SCRIPT_NAME="$(basename $0)";
SCRIPT_DIR="$(dirname "$(realpath "$0")")";
WORK_DIR="${WORK_DIR}/${SCRIPT_DIR##*/}";

source <(cat "${SCRIPT_DIR}/${CONFIG_FILE}");
source <(cat "${SCRIPT_DIR}/log.sh");

log "SCRIPT_DIR: ${SCRIPT_DIR##*/}";
log "WORK_DIR: ${WORK_DIR}";

[[ "$SCRIPT_DIR" != "$WORK_DIR" ]] && {
  mkdir -p "$WORK_DIR";
  for f in $(find "$SCRIPT_DIR" -type f -name "*.sh"); do
    [[ "${f##*/}" == "config.sh" ]] && [[ -f "${WORK_DIR}/${CONFIG_FILE}" ]] ||
    cp "$f" "$WORK_DIR";
#    cp "$f" "$WORK_DIR" ||
#    cp "$f" "$WORK_DIR";
#    echo "file: ${f##*/}";
  done
  log "work dir files:";
  ls -la "$WORK_DIR";
}