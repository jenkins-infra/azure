#!/bin/bash
# This script calculate diff between dates for letsencrypt expiration
set -eux -o pipefail

currentexpirydate="${1}"
DATE_BIN='date'

## non GNU operating system
if command -v gdate >/dev/null 2>&1
then
    DATE_BIN='gdate'
fi
command -v "${DATE_BIN}" >/dev/null 2>&1 || { echo "ERROR: ${DATE_BIN} command not found. Exiting."; exit 1; }

currentdateepoch=$("${DATE_BIN}" --utc "+%s" 2>/dev/null)
expirydateepoch=$("${DATE_BIN}" "+%s" -d "$currentexpirydate")

datediff=$(((expirydateepoch-currentdateepoch)/(60*60*24))) # diff per days

if [ "$datediff" -lt 21 ] # launch renew 21 days before expiration
then
    echo "time for update"
    exit 0
else
    echo "not yet expired"
    exit 1
fi
