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

prog_control "sing-box" start;
