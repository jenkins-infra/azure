{{ range $key, $val := .updatecli_end_dates }}
{{ $hclFile := printf "%s%s" $key ".tf" }}
{{ $hclKey := "module.controller_service_principal_end_date" }}
{{ if (and $val $val.custom_hcl_key) }}
  {{ $hclKey = $val.custom_hcl_key }}
{{ end }}
---
# yamllint disable rule:line-length
name: "Generate new end date for the {{ $key }} Azure AD Application password"

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
      title: 'Azure AD Application password for updatecli in `{{ $key }}` expires on `{{ source "currentEndDate" }}`'
      description: |
        This PR updates the Azure AD application password used in `{{ $key }}` for updatecli.

        The current end date is set to `{{ source "currentEndDate" }}`.

{{ $val.doc_how_to_get_credential | indent 8 }}

      labels:
        - azure-ad-application
        - end-dates
        - {{ $key }}
{{ end }}
