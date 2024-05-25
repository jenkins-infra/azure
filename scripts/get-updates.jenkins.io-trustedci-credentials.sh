#!/bin/bash

set -eu -o pipefail

# We do not want any credential persisted in the repository!
temp_dir="$(mktemp -d)"
zip_elements=()

for service in content redirections
do
  env_file=.env-"${service}"
  # The -raw flag ensures there are not heredoc markers in the output - https://developer.hashicorp.com/terraform/cli/commands/output#raw
  terraform output -raw -no-color update_center_fileshare_env-"${service}" > "${temp_dir}"/"${env_file}"
  zip_elements+=("${env_file}")
done
# terraform output update_center_fileshare_env-redirections > "${temp_dir}/.env-redirections"

pushd "${temp_dir}"
zip update-center-fileshares-env-zip-credentials.zip "${zip_elements[@]}"
rm -f "${zip_elements[@]}"
popd

echo "ZIP file with credentials available in: ${temp_dir}/update-center-fileshares-env-zip-credentials.zip"
