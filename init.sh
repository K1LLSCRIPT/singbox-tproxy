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

check_input() {
  local \
    inp="${1}" \
    url="${2}" \
    reg='^(https?)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]$';

    (( $url )) && { [[ "$inp" =~ $reg ]] && return 0; } ||
    { (( ${#inp} )) && return 0; }
    return 1;
}

check_user_args(){
  for a in "${USER_ARGS[@]}"; do
    local s u e;
    s=$(cat "${WORK_DIR}/${CONFIG_FILE}" | grep "$a" | head -n 1 | sed -E "s/(${a})(.*)/\2/" | sed -E 's/["'\''=;]//g');
    [[ "$a" =~ URL ]] && u=1 || u=0;
    (( ${#s} )) && { check_input "$s" "$u" || s=""; }
    (( ${#s} )) || {
      until (check_input "$s" "$u"); do
        s=$(printf '%s' "Please provide ${a}: " >&2; read x && printf '%s' "$x");
        e=${s//\\/\\\\}; e=${e//&/\\&}; e=${e//\//\\/};

        sed -i -E \
          "1,/^###################/ s#^[[:space:]]*(${a})[[:space:]]*=.*#\1='${e}';#" \
          "${WORK_DIR}/${CONFIG_FILE}";
      done
    }
  done
}

check_user_args;

rm -rf "$TMP_DIR";
mkdir -p "$TMP_DIR";

get_url() {
  local url="https://github.com/shtorm-7/sing-box-extended";
  local arh=$(uname -m );
  local tag;
  [[ "$arh" =~ aarch64 ]] && arh="arm64";
  tag=$(git ls-remote --tags "${url}.git" | awk -F/ '{print $3}' | grep -E '^v[0-9]+' | sort -V | tail -n1);
  url="${url}/releases/download/${tag}/${tag/v/sing-box-}-linux-${arh}.tar.gz";
  echo "$url";
}

download() {
  local url=$(get_url);
  log "download: ${url}";
  curl -LJOs --output-dir "$TMP_DIR" "$url";
}

(( $SINGBOX_EXTENDED )) && download

#          tar -xzf

