log() { (( $LOG )) && echo "$(date) :: [${SCRIPT_DIR##*/}: ${SCRIPT_NAME%%.*}] $*"; }
error() { log "ERROR: $*" >&2; }