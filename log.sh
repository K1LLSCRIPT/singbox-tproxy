log() { (( $LOG )) && echo "$(date +'%d-%b-%Y %H:%M:%S') :: [${SCRIPT_DIR##*/}: ${SCRIPT_NAME%%.*}] $*"; }
error() { log "ERROR: $*" >&2; }