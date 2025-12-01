log() { (( $LOG )) && echo "$(date +%d-%b-%Y) :: [${SCRIPT_DIR##*/}: ${SCRIPT_NAME%%.*}] $*"; }
error() { log "ERROR: $*" >&2; }