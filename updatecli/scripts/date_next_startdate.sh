#!/bin/bash
# This script calculate next start date as of today for expiry azurerm_storage_account_sas
##
set -eux -o pipefail
DATE_BIN='date'

## non GNU operating system
if command -v gdate >/dev/null 2>&1
then
    DATE_BIN='gdate'
fi
command -v "${DATE_BIN}" >/dev/null 2>&1 || { echo "ERROR: ${DATE_BIN} command not found. Exiting."; exit 1; }

"${DATE_BIN}" --utc +"%Y-%m-%dT00:00:00Z"
