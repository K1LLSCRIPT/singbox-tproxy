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
  bc
);

check_deps() {
  local nopkg=();
  for pkg in "${deps[@]}"; do
    opkg list-installed | grep -Eqo "^${pkg}" || nopkg+=("${pkg}");
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
  local tag url arh;
  local name="${1}";
  arh=$(uname -m );
  url="https://github.com/shtorm-7/sing-box-extended";
  [[ "$arh" =~ aarch64 ]] && arh="arm64";
  tag=$(git ls-remote --tags "${url}.git" | awk -F/ '{print $3}' | grep -E '^v[0-9]+' | sort -V | tail -n1);
  url="${url}/releases/download/${tag}/${tag/v/${name}-}-linux-${arh}.tar.gz";
  log "Found URL: ${url}";
  echo "$url";
}

unpack_file() {
  local \
    file="${1}" \
    name="${2}";
  [[ -f "$file" ]] && {
    local dir=$(find "$WORK_DIR" -type d -name "${name}*");
    [[ -z "$dir" ]] && [[ -d "$dir" ]] && rm -rf "$dir";
    tar -xzf "$file" -C "${WORK_DIR}";
    echo $(find "$WORK_DIR" -type f -name "${name}" -exec test -x {} \; -print);
  }
}

copy_file() {
  local \
    file="${1}" \
    name="${2}" \
    dest=$(which "$name");
  [[ -f "$file" ]] && {
    log "Copy file: ${file} to: ${dest}";
    cp "$file" "$dest";
  } || { log "Copy file: ${name} FAILED"; exit 1; }
}

download_yy() {
  local  url  file \
    name="sing-box";
  url=$(get_url);
  [[ ! -f "${WORK_DIR}/${url##*/}" ]] && {
    log "Downloading ${name}...";
    curl -LJOs --output-dir "$WORK_DIR" "$url";
  }
  file=$(find "$WORK_DIR" -type f -name "${name}*");
  file=$(unpack_file "$file" "$name");
  log "Downloading ${name} done.";
  log "File path: ${file}";
  copy_file "$file" "$name";
}

check_file () {
  local file="${1}";

  [[ ! -s "$file" ]] && { log "FILE ${file##*/} error"; return 1; }
  [[ "$file" == *.gz ]] && {
    gzip -t "$file" 2>/dev/null ||
    { log "FILE ${file##*/} is fucked .gz"; return 1; }
  }
  return 0;
}

download() {
  local \
    file="${1}" \
    url="${2}" \
    retries=10 \
    count=0;
url="https://github.com/shtorm-7/sing-box-extended/releases/download/v1.12.12-extended-1.4.2/sing-box-1.12.12-extended-1.4.2-linux-arm64.tar.gz";
  while (( count < retries )); do
    [[ ! -f "${WORK_DIR}/${file}" ]] &&
      log "Downloading: ${file}" && {
        local pp;
        curl "$url" -L -o "${WORK_DIR}/${file}" --progress-bar 2>&1 |
        while IFS= read -d $'\r' -r p; do
          p=$(sed -E 's/(.* )([0-9]+.[0-9]+)(.*%)/\2/g' <<< $p);
          (( ${#p} )) && (( ${#p} < 6 )) && [[ "$p" =~ ^[0-9.]+$ ]] && {
            p=$(bc <<< "($p+0.5)/1");
            (( p != pp )) && {
              pp=$p;
              echo -ne "[ $p% ] [ $(eval 'printf =%.0s {1..'${p}'}')> ]\r";
              (( p == 100 )) && echo;
            }
          }
        done;
      }

    check_file "${WORK_DIR}/${file}" && {
      log "File: ${file} downloaded and passed checks.";
      return 0;
    } || {
      log "File: ${file} failed check, retrying...";
      rm -f "$WORK_DIR/${file}";
      ((count++));
      sleep 5;
    }
  done;
  log "Failed to download ${file} after ${retries} attempts";
  return 1;
}

get_file() {
  local \
    name="${1}" \
    url file;
  url=$(get_url "$name");
  download "${url##*/}" "$url" && {
    file=$(find "$WORK_DIR" -type f -name "${name}*");
    file=$(unpack_file "$file" "$name");
    log "Downloading ${name} done.";
    log "File path: ${file}";
    copy_file "$file" "$name";
  } || { log "Get file: ${name} FAILED. Exiting."; exit 1; }
}

# https://github.com/shtorm-7/sing-box-extended/releases/download/v1.12.12-extended-1.4.2/sing-box-1.12.12-extended-1.4.2-linux-arm64.tar.gz
# url="https://github.com/shtorm-7/sing-box-extended/releases/download/v1.12.12-extended-1.4.2/sing-box-1.12.12-extended-1.4.2-linux-arm64.tar.gz"; file="${url##*/}"; echo "$file"        
# sing-box-1.12.12-extended-1.4.2-linux-arm64.tar.gz
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
    out="${2}" \
    fvc="${3}";
  [[ -f "${inp}" ]] && {
    local reg="(.*)(\{\{)([a-zA-Z]+)(.*)(\}\})";
    { while IFS= read -r line; do
      [[ "${line}" =~ $reg ]] && {
        local \
          beg="${BASH_REMATCH[1]}" \
          str="${BASH_REMATCH[3]}" \
          end="${BASH_REMATCH[4]}";
        typeset -f "$str" >/dev/null 2>&1 &&
        "$str" "$fvc" "${beg}" "${end}";
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

    echo; log "Creating nftables config."; echo;
    file_nft_out="30-${file_nft%%.*}.nft";
    config_path="/etc/nftables.d/${file_nft_out}";

    rm -rf "${GIT_DIR}/${repo_voice##*/}";
    mkdir -p "${GIT_DIR}/${repo_voice##*/}";
    git clone "$repo_voice" "${GIT_DIR}/${repo_voice##*/}";
    file_voice="$(find ${GIT_DIR}/${repo_voice##*/} -name *.list)";
    log "FILE VOICE: $file_voice";
    echo -n > "${WORK_DIR}/${file_nft_out}";
    make_nft_file "${WORK_DIR}/${file_nft}" "${WORK_DIR}/${file_nft_out}" "$file_voice";
    cp "${WORK_DIR}/${file_nft_out}" "$config_path";
}

main() {
  prepare;
  check_deps || { error "Failed to install packages"; exit 1; }
  check_user_args;
  (( $SINGBOX_EXTENDED )) && get_file "sing-box";
#  configure_sing_box_service;
#  configure_dhcp;
#  configure_network;
  configure_nftables;
}

main;