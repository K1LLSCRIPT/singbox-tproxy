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

check_url_format() {
  local \
    url="${1}" \
    reg='^(https?)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]$';
    [[ "$url" =~ $reg ]] &&
    return 0;
    return 1;
}

check_user_args(){
  for a in "${USER_ARGS[@]}"; do
    local s=$(cat "${WORK_DIR}/${CONFIG_FILE}" | grep "$a" | head -n 1 | sed -E "s/(${a})(.*)/\2/" | sed -E 's/["'\''=;]//g');

    (( ${#s} )) && [[ "$a" =~ URL ]] && { check_url_format "$s" || s=""; }
    (( ${#s} )) && [[ ! "$a" =~ URL ]] || {
      until check_url_format "$s"; do
      s=$(printf '%s' "Please provide ${a}: " >&2; read x && printf '%s' "$x")
      done
#      while read -r line && [ "$1" != 1 ]
#      while read -p "Please provide ${a}: " v && check_url_format "$v";
#      read -p "Please provide ${a}: " $v;
#      sed -i -E "s/(${a})(.*)/\1=\'${v}\'/" "${WORK_DIR}/${CONFIG_FILE}";
    }
  done
#  [[ ! -z "$v" ]] && source <(cat "${SCRIPT_DIR}/${CONFIG_FILE}") || log "all args are set.";
}

check_user_args;
# v="SUBSCRIPTION_URL"; s=$(cat /root/singbox-tproxy/config.sh | grep "$v" | head -n 1 | sed -E "s/(${v})(.*)/\2/" | sed -E 's/["'\''=;]//g'); echo "$s"
