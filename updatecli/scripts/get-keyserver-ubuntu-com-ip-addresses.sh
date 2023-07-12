#!/bin/bash
# This script returns the IP addresses of keyserver.ubuntu.com as a string representing an array like ["<ip-1>", "<ip-2>"]

set -eu -o pipefail

# Open the "array"
output="["
# Loop over (sorted) IPs of keyserver.ubuntu.com
for ip_address in $(dig keyserver.ubuntu.com +short | sort)
do
  output+="\"${ip_address}\", "
done
# Remove last 2 characters and close the "array"
output="${output%??}]"
# Returns IPs as string representing an array
echo $output