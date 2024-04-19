#!/bin/bash
# This script calculate next date for certificates
##
set -eux -o pipefail
DATE_BIN='date'

## non GNU operating system
if command -v gdate >/dev/null 2>&1
then
    DATE_BIN='gdate'
fi
command -v "${DATE_BIN}" >/dev/null 2>&1 || { echo "ERROR: ${DATE_BIN} command not found. Exiting."; exit 1; }

# "${DATE_BIN}" --utc +"%Y-%m-%dT00:00:00Z" -d '+1 month' #keep for later use with allinone not alpine based
"${DATE_BIN}" -d@"$(( $(date +%s)+60*60*24*30*3))" --utc '+%Y-%m-%dT00:00:00Z' # next date in around 3 month
