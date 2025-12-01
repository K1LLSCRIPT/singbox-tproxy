#!/bin/bash

prog_control() {
  local \
    program="$1" \
    command="$2";

  (( $counter )) || { counter=0; }
  [[ "$(service $program status)" =~ running  ]] && [[ "$command" == "start" ]] && counter=0 && return 0;
  [[ "$(service $program status)" =~ inactive ]] && [[ "$command" == "stop"  ]] && counter=0 && return 0;
  (( $counter > 10)) && echo  "$command $program failed" && return 1;
  echo "attempt $((++counter)) $command $program";
  "/etc/init.d/$program" "$command";
  sleep 1;
  prog_control "$program" "$command";
}

restart() {
  service dnsmasq restart;
  service firewall restart;
}

control() {
  local \
    command="$1" \
    sing_dns='127.0.0.1#5353' \
    direct_dns='77.88.8.8' \
    nft_file="/etc/nftables.d/30-tproxy.nft" \
    work_dir="/root/singbox-tproxy";

  sing_dns="server=${sing_dns}";
  direct_dns="server=${direct_dns}";

  [[ "$command" =~ disable ]] && {
    [[ "$(head -1 /etc/dnsmasq.servers)" =~ $sing_dns ]] && {
      logger -t sing-box-checker "Change mode to DISABLED";
      sed -i -E "s/$sing_dns/$direct_dns/" "/etc/dnsmasq.servers";
      [[ -f "$nft_file" ]] && mv "$nft_file" "$work_dir";
      restart; exit 0;
    }
  }

  [[ "$command" =~ enable ]] && {
    [[ "$(head -1 /etc/dnsmasq.servers)" =~ $direct_dns ]] && {
      logger -t sing-box-checker "Change mode to ENABLED";
      sed -i -E "s/$direct_dns/$sing_dns/" "/etc/dnsmasq.servers";
      [[ -f "${work_dir}/${nft_file##*/}" ]] && cp "${work_dir}/${nft_file##*/}" "$nft_file";
      restart; exit 0;
    }
  }
}

check() {
  local \
    enabled=$(uci -q get sing-box.main.enabled) \
    config=$(uci -q get sing-box.main.conffile);

  local \
    secret=$(jq -r '.experimental.clash_api.secret' < "$config") \
    port=$(jq -r '.experimental.clash_api.external_controller' < "$config");
    port="${port##*:}";

  local mode=$(
    curl -s -X GET "http://127.0.0.1:${port}/configs" \
         -H "Authorization: Bearer $secret" | \
         jq -r '.mode'
  );

  ((${#mode})) && {
    [[ "$mode" == "disabled" ]] && { control disable; }
    [[ "$mode" != "disabled" ]] && { control enable;  }
  }
}

prog_control "sing-box" start;
check;
