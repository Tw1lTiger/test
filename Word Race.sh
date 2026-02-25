#!/bin/sh
printf '\033c\033]0;%s\a' Word Race
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Word Race.x86_64" "$@"
