{{ range $key, $val := .end_dates.publick8s }}
---
# yamllint disable rule:line-length
name: "Generate new end date for {{ $val.service }} File Share service principal writer on publick8s"

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
      file: publick8s.tf
      path: module.{{ $key }}.service_principal_end_date
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
    name: 'New end date for `{{ $val.service }}` File Share service principal writer on `publick8s` (current: {{ source "currentEndDate" }})'
    kind: hcl
    sourceid: nextEndDate
    spec:
      file: publick8s.tf
      path: module.{{ $key }}.service_principal_end_date
    scmid: default

actions:
  default:
    kind: github/pullrequest
    scmid: default
    spec:
      title: 'Azure File Share Principal `{{ $val.service }}` on `publick8s` expires on `{{ source "currentEndDate" }}`'
      description: |
        This PR updates the end date of {{ $val.service }} File Share service principal writer used in publick8s for geoip.

        The current end date is set to `{{ source "currentEndDate" }}`.

{{ $val.doc_how_to_get_credential | indent 8 }}

      labels:
        - terraform
        - "{{ $val.service }}"
        - end-dates
        - publick8s
{{ end }}
