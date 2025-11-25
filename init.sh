#!/bin/bash

WORK_DIR="/root";
GIT_DIR="${WORK_DIR}/git";
CONFIG_FILE="config.sh";
SCRIPT_NAME="$(basename $0)";
SCRIPT_DIR="$(dirname "$(realpath "$0")")";
WORK_DIR="${WORK_DIR}/${SCRIPT_DIR##*/}";

source <(cat "${SCRIPT_DIR}/${CONFIG_FILE}");
source <(cat "${SCRIPT_DIR}/log.sh");

[[ "$SCRIPT_DIR" != "$WORK_DIR" ]] && {
  mkdir -p "$WORK_DIR";
  for f in $(find "$SCRIPT_DIR" -type f -name "*.sh"); do
    [[ "${f##*/}" == "config.sh" ]] &&
    [[ -f "${WORK_DIR}/${CONFIG_FILE}" ]] ||
    { cp "$f" "$WORK_DIR"; log "Copy file: ${f} to: ${WORK_DIR}"; }
  done
  exec "${WORK_DIR}/init.sh" "$@";
}

prepare() {
  rm -rf "$TMP_DIR";
  mkdir -p "$TMP_DIR";
}

deps=(
  sing-box
  kmod-nft-tproxy
  git-http
  curl
  jq
);

check_deps() {
  local nopkg=();
  for pkg in "${deps[@]}"; do
    opkg list-installed | grep -qo "$pkg" || nopkg+=("${pkg}");
  #  [[ ! -x "$(command -v $pkg)" ]] && nopkg+=("${pkg}");
  done;
  (( "${#nopkg[@]}" )) && {
    log "Updating package list.";
    opkg update >/dev/null || return 1;
    log "Installing packages: ${nopkg[@]}";
    opkg install "${nopkg[@]}" || return 1;
  }
  return 0;
}

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
  echo; log "Checking user settings.";
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

get_url() {
  local \
    tag \
    url="https://github.com/shtorm-7/sing-box-extended";
    arh=$(uname -m );
  [[ "$arh" =~ aarch64 ]] && arh="arm64";
  tag=$(git ls-remote --tags "${url}.git" | awk -F/ '{print $3}' | grep -E '^v[0-9]+' | sort -V | tail -n1);
  url="${url}/releases/download/${tag}/${tag/v/sing-box-}-linux-${arh}.tar.gz";
  log "Found URL: ${url}";
  echo "$url";
}

unpack_file() {
  local \
    file="${1}" \
    name="${2}";
  [[ -f "$file" ]] && {
    tar -xzf "$file" -C "${TMP_DIR}";
    echo $(find $TMP_DIR -type f -name ${name} -exec test -x {} \; -print);
  }
}

copy_file() {
  local \
    file="${1}" \
    name="${2}" \
    dest=$(which "$name");
  log "Copy file: ${file} to: ${dest}";
  cp "$file" "$dest";
}

download() {
  local \
    file \
    name="sing-box" \
    url=$(get_url);
  log "Downloading ${name}...";
  curl -LJOs --output-dir "$TMP_DIR" "$url";
  file=$(find $TMP_DIR -type f -name ${name}*);
  file=$(unpack_file "$file" "$name");
  log "Downloading ${name} done.";
  log "File path: ${file}";
  copy_file "$file" "$name";
}

configure_sing_box_service() {
  local \
    enabled=$(uci -q get sing-box.main.enabled) \
    user=$(uci -q get sing-box.main.user);

  (( "$sing_box_enabled" )) || {
    log "Enabling sing-box service";
    uci -q set sing-box.main.enabled=1;
    uci commit sing-box;
  }

  [[ "$sing_box_user" != "root" ]] && {
    log "Setting sing-box user to root";
    uci -q set sing-box.main.user=root;
    uci commit sing-box;
  }
}

configure_dhcp() {
  local \
    init_dns="8.8.8.8" \
    sing_dns="127.0.0.1#5353";

  #echo "server=$sing_dns" > /etc/dnsmasq.servers;

  dhcp_params=(
    "dhcp.@dnsmasq[0].serversfile='/etc/dnsmasq.servers'"
    "dhcp.@dnsmasq[0].domainneeded='1'"
    "dhcp.@dnsmasq[0].localise_queries='1'"
    "dhcp.@dnsmasq[0].rebind_protection='1'"
    "dhcp.@dnsmasq[0].rebind_localhost='1'"
    "dhcp.@dnsmasq[0].local='local'"
    "dhcp.@dnsmasq[0].domain='local'"
    "dhcp.@dnsmasq[0].expandhosts='1'"
    "dhcp.@dnsmasq[0].cachesize='100'"
    "dhcp.@dnsmasq[0].authoritative='1'"
    "dhcp.@dnsmasq[0].readethers='1'"
    "dhcp.@dnsmasq[0].leasefile='/tmp/dhcp.leases'"
    "dhcp.@dnsmasq[0].localservice='1'"
    "dhcp.@dnsmasq[0].ednspacket_max='1232'"
    "dhcp.@dnsmasq[0].filter_aaaa='1'"
    "dhcp.@dnsmasq[0].noresolv='1'"
  );

  local c=$(uci show dhcp | grep "=dnsmasq" | wc -l);

  log "Configuring DHCP. Servers found: ${c}";

  for (( i=0; i<$c; i++ )); do
    for p in "${dhcp_params[@]}"; do
      echo $(echo "$p" | sed -E "s/(.*)(\[.\])(.*)/\1\[${i}\]\3/");
    #  uci -q set $(echo "$p" | sed -E "s/(.*)(\[.\])(.*)/\1\[${i}\]\3/");
    done
  done
  #uci commit dhcp;
}

configure_network() {
  [[ -z "$(uci -q get network.@rule[0])" ]] && {
    log "Creating marking rule.";
    uci batch <<EOI
add network rule
set network.@rule[0].mark='0x1'
set network.@rule[0].priority='100'
set network.@rule[0].lookup='100'
EOI
    uci commit network;
  }

  [[ -z "$(uci -q get network.@route[0])" ]] && {
    log "Creating route rule.";
    uci batch <<EOI
add network route
set network.@route[0].interface='loopback'
set network.@route[0].target='0.0.0.0/0'
set network.@route[0].table='100'
set network.@route[0].type='local'
EOI
    uci commit network;
  }
}

voicelist() {
  local \
    inp="${1}" \
    beg="${2}" \
    end="${3}";
  [[ -f "${inp}" ]] && {
    local \
      ifst=$IFS \
      list=($(cat "$inp"));
    declare -a a;
    for _l in ${!list[@]}; do
      (($_l==((${#list[@]}-1)))) && end="";
      a+=("${beg}${list[$_l]}${end}");
    done
    IFS=$'\n'; echo "${a[*]}"; IFS=$ifst;
  }
}

make_nft_file() {
  local \
    inp="${1}" \
    out="${2}";
  [[ -f "${inp}" ]] && {
    local reg="(.*)(\{\{)([a-zA-Z]+)(.*)(\}\})";
    { while IFS= read -r line; do
      [[ "${line}" =~ $reg ]] && {
        local \
          beg="${BASH_REMATCH[1]}" \
          str="${BASH_REMATCH[3]}" \
          end="${BASH_REMATCH[4]}";
        typeset -f "$str" >/dev/null 2>&1 &&
        "$str" "$FILE_VOICE" "${beg}" "${end}";
      } || echo "${line}";
    done < "${inp}"; } >> "${out}";
  }
}

configure_nftables() {
  local \
    repo_voice="https://github.com/K1LLSCRIPT/rulesets" \
    file_nft="tproxy.sh" \
    file_nft_out \
    config_path \
    file_voice;

    log "Creating nftables config."
    file_nft_out="30-${file_nft%%.*}.nft";
    config_path="/etc/nftables.d/${file_nft_out}";

    rm -rf "${GIT_DIR}/${repo_voice##*/}";
    mkdir -p "${GIT_DIR}/${repo_voice##*/}";
    git clone "$repo_voice" "${GIT_DIR}/${repo_voice##*/}";
    file_voice="$(find ${GIT_DIR}/${repo_voice##*/} -name *.list)";
    log "FILE VOICE: $file_voice";
    echo -n > "${WORK_DIR}/${file_nft_out}";
    make_nft_file "${WORK_DIR}/${file_nft}" "${WORK_DIR}/${file_nft_out}";
    cp "${WORK_DIR}/${file_nft_out}" "$config_path";
}

main() {
  check_deps || { error "Failed to install packages"; exit 1; }
  check_user_args;
  (( $SINGBOX_EXTENDED )) && download;
#  configure_sing_box_service;
#  configure_dhcp;
#  configure_network;
  configure_nftables;
}

main;