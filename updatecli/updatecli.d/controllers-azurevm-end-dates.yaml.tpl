{{ range $key, $val := .controllers_azurevm_client_end_dates }}
{{ $hclFile := printf "%s%s" $key ".tf" }}
{{ $hclKey := "module.controller_service_principal_end_date" }}
{{ if (and $val $val.custom_hcl_key) }}
  {{ $hclKey = $val.custom_hcl_key }}
{{ end }}
{{ $controlerCredentialId := "azure-jenkins-sponsorship-credentials" }}
{{ if (and $val $val.custom_credential_id) }}
  {{ $controlerCredentialId = $val.custom_credential_id }}
{{ end }}
---
# yamllint disable rule:line-length
name: "Generate new end date for the {{ $key }} controller Azure AD Application password"

scms:
  default:
    kind: github
    spec:
      user: "{{ $.github.user }}"
      email: "{{ $.github.email }}"
      owner: "{{ $.github.owner }}"
      repository: "{{ $.github.repository }}"
      token: "{{ requiredEnv $.github.token }}"
      username: "{{ $.github.username }}"
      branch: "{{ $.github.branch }}"

sources:
  currentEndDate:
    name: Get current `end_date` date
    kind: hcl
    spec:
      file: {{ $hclFile }}
      path: {{ $hclKey }}
  nextEndDate:
    name: Prepare next `end_date` date within 3 months
    kind: shell
    spec:
      command: bash ./updatecli/scripts/dateadd.sh
      environments:
        - name: PATH

conditions:
  checkIfEndDateSoonExpired:
    kind: shell
    sourceid: currentEndDate
    spec:
      # Current end_date date value passed as argument
      command: bash ./updatecli/scripts/datediff.sh
      environments:
        - name: PATH

targets:
  updateNextEndDate:
    name: Update Terraform file `{{ $key }}.tf` with new expiration date
    kind: hcl
    sourceid: nextEndDate
    spec:
      file: {{ $hclFile }}
      path: {{ $hclKey }}
    scmid: default

actions:
  default:
    kind: github/pullrequest
    scmid: default
    spec:
      title: 'Extend Azure AD Application password validity on `{{ $key }}` (current end date: {{ source "currentEndDate" }})'
      description: |
        This PR generates a new Azure AD application password with a new end date for the `{{ $key }}` controller (to allow spawning Azure VM agents).

        Once this PR is merged and deployed with success by Terraform (on infra.ci.jenkins.io),
        you can retrieve the new password value from the Terraform state with `terraform show -json`
        then searching for the new password in `values.value` of the `{{ $hclKey }}` section (do NOT save it anywhere!)
        and (manually) update the {{ $key }} credential named `{{ $controlerCredentialId }}` through the Jenkins UI.

        Finally, verify both Azure Credential and Azure VM clouds by checking that a click on the "Verify <...>" buttons returns a success,
        then restart the controller to ensure that the old credential is not kept in cache.
      labels:
        - azure-ad-application
        - end-dates
        - {{ $key }}
{{ end }}
