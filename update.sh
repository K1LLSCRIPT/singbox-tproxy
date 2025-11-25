#!/bin/bash

#set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")";
SCRIPT_NAME="$(basename $0)";

source <(cat "${SCRIPT_DIR}/config.sh");

download_inbounds_config() {
  log "Downloading inbounds config from $INBOUNDS_CONFIG_URL...";
  curl -fsSL "$INBOUNDS_CONFIG_URL" -o "$LOCAL_INBOUNDS_CONFIG" || {
    error "Failed to download inbounds config from $INBOUNDS_CONFIG_URL.";
    exit 1;
  }
  log "Inbounds config downloaded successfully.";
}

download_extended_config() {
  log "Downloading extended config from $INBOUNDS_CONFIG_URL...";
  curl -fsSL "$INBOUNDS_CONFIG_URL" -o "$LOCAL_INBOUNDS_CONFIG" || {
    error "Failed to download extended config from $INBOUNDS_CONFIG_URL.";
    exit 1;
  }
  log "Extended config downloaded successfully.";
}

build_new_config() {
  local base_config="$1";
  local final_config="$2";
  local temp_config="$TMP_DIR/temp.json";
  log "Building new config...";
  jq --slurpfile local_inbounds "$LOCAL_INBOUNDS_CONFIG" '.inbounds = $local_inbounds[0].inbounds' "$base_config" > "$temp_config" || { error "Failed to merge local inbounds."; return 1; }
  jq --arg uiurl "$EXTERNAL_UI_DOWNLOAD_URL" --arg secret "$EXTERNAL_UI_SECRET" \
    '(if $uiurl != "" and (.experimental.clash_api.external_ui_download_url != null) then .experimental.clash_api.external_ui_download_url = $uiurl else . end) |
     (if $secret != "" and (.experimental.clash_api.secret != null) then .experimental.clash_api.secret = $secret else . end)' \
    "$temp_config" > "$final_config" || { error "Failed to inject UI settings."; return 1; }
  log "New config built successfully.";
}

validate_and_apply() {
  local new_config="$1";
  log "Validating new config...";
  if ! sing-box check -c "$new_config"; then
    log "ERROR: New config validation failed. Keeping old config.";
    rm "$new_config";
    return 1;
  fi
  log "Config check passed. Applying config...";

  local backup_config="$TMP_DIR/config.bak.json";

  # Only backup if a config file already exists
  [[ -f "$FINAL_CONFIG_FILE" ]] && {
    log "Backing up current config to $backup_config...";
    cp "$FINAL_CONFIG_FILE" "$backup_config";
  }

  mv "$new_config" "$FINAL_CONFIG_FILE";
  log "Config applied successfully.";

  (( $RESTART_AFTER_UPDATE )) && {
    log "Reloading sing-box with new config...";
    service sing-box restart;

    log "Waiting 5 seconds for reload and performing health check...";
    sleep 5;

    if curl -sfL --connect-timeout 5 -o /dev/null http://www.gstatic.com/generate_204; then
      log "Health check PASSED. New config is live.";
      # Clean up backup file if it was created. -f suppresses errors if it doesn't exist.
      rm -f "$backup_config";
    else
      log "ERROR: Health check FAILED with the new config. Rolling back...";
      [[ -f "$backup_config" ]] && {
        mv "$backup_config" "$FINAL_CONFIG_FILE";
        service sing-box restart;
        log "Rollback successful. sing-box is running with the last known good config.";
      } || {
        log "FATAL: Initial config is bad and there is no backup to restore. Removing bad config and exiting.";
        rm "$FINAL_CONFIG_FILE";
        exit 1;
      }
      return 1;
    fi
  }
  return 0;
}

run_update() {
  log "Starting update cycle.";
  local downloaded_config="$TMP_DIR/downloaded-config.json";
  local new_config="$TMP_DIR/new-config.json";

  log "Downloading config from subscription URL...";
  local base_url="${SUBSCRIPTION_URL%/}";
  local full_sub_url="$base_url$SUBSCRIPTION_URL_PATH";
  if ! curl -sfL --connect-timeout 10 --retry 3 -o "$downloaded_config" "$full_sub_url"; then
    log "ERROR: Failed to download config from $full_sub_url. Keeping old config.";
    return 1;
  fi
  log "Subscription config downloaded successfully.";

  build_new_config "$downloaded_config" "$new_config" || return 1;

  [[ -f "$FINAL_CONFIG_FILE" ]] && {
    local current_canon_json="$TMP_DIR/current.canon.json";
    local new_canon_json="$TMP_DIR/new.canon.json";

    local CANON_FILTER='del(.outbounds[].tls.reality.short_id?)';
    jq -S "$CANON_FILTER" "$FINAL_CONFIG_FILE" > "$current_canon_json";
    jq -S "$CANON_FILTER" "$new_config" > "$new_canon_json";

    if cmp -s "$current_canon_json" "$new_canon_json"; then
      log "Config has not changed. Skipping apply and reload.";
      return 0;
    fi

    log "Config has changed. Canonical files saved for debugging in $TMP_DIR";
    log "Proceeding with validation and apply.";
  }
  validate_and_apply "$new_config" || return 1;
  log "Update cycle finished successfully.";
}

log "Update starting...";

[[ -z "$SUBSCRIPTION_URL" ]] && { error "SUBSCRIPTION_URL is not set. Exiting."; exit 1; }
[[ -n "$INBOUNDS_CONFIG_URL" ]] || { error "INBOUNDS_CONFIG_URL is not set. Exiting."; exit 1; }

command -v jq >/dev/null || { error "jq is not installed. Exiting."; exit 1; }
command -v sing-box >/dev/null || { error "sing-box is not installed. Exiting."; exit 1; }

mkdir -p "$CONFIG_DIR" "$TMP_DIR";
rm -f "$TMP_DIR"/*;
#log "Setting DNS to 8.8.8.8..."
#echo "nameserver 8.8.8.8" > /etc/resolv.conf

download_inbounds_config;
(( $SINGBOX_EXTENDED )) &&
download_extended_config;

[[ ! -f "$FINAL_CONFIG_FILE" ]] && {
  log "Main config not found. Running initial update...";
  run_update;
}

run_update || log "Update cycle failed.";