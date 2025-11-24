#!/bin/sh

(cat /etc/os-release | grep -i wrt >/dev/null 2>&1) || { echo "Only WRT supported"; exit 1; }

GIT_DIR="/root/git";
REPO="https://github.com/K1LLSCRIPT/singbox-tproxy";

set -- "bash" "coreutils-realpath" "git-http";

for p in "$@"; do
  k=$(opkg list-installed | grep "$p" | cut -d " " -f 1);
  [[ "$k" == "$p" ]] && shift;
done

[[ "$#" -ne 0 ]] && { opkg update || { echo "Command \"opkg update\" failed. Exiting."; exit 1; } }
[[ "$#" -ne 0 ]] && {
  for pkg in "$@"; do
    opkg install "$pkg" || { echo "Command \"opkg install ${pkg}\" failed. Exiting."; exit 1; }
  done
}

mkdir -p "$GIT_DIR";
rm -rf "${GIT_DIR}/${REPO##*/}";
mkdir -p "${GIT_DIR}/${REPO##*/}";

git clone "$REPO" "${GIT_DIR}/${REPO##*/}";
exec "${GIT_DIR}/${REPO##*/}/init.sh" "$@";