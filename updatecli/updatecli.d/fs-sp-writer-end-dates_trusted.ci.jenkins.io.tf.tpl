{{ range $key, $val := .end_dates.trusted_ci_jenkins_io }}
---
# yamllint disable rule:line-length
name: "Generate new end date for {{ $val.service }} File Share service principal writer on trusted.ci.jenkins.io"

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
      file: trusted.ci.jenkins.io.tf
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
    name: 'New end date for `{{ $val.service }}` File Share service principal writer on `trusted.ci.jenkins.io` (current: {{ source "currentEndDate" }})'
    kind: hcl
    sourceid: nextEndDate
    spec:
      file: trusted.ci.jenkins.io.tf
      path: module.{{ $key }}.service_principal_end_date
    scmid: default

actions:
  default:
    kind: github/pullrequest
    scmid: default
    spec:
      title: 'Azure File Share Principal `{{ $val.service }}` on `trusted.ci.jenkins.io` expires on `{{ source "currentEndDate" }}`'
      description: |
        This PR updates the end date of {{ $val.service }} File Share service principal writer used in trusted.ci.jenkins.io.

        The current end date is set to `{{ source "currentEndDate" }}`.

{{ $val.doc_how_to_get_credential | indent 8 }}

      labels:
        - terraform
        - "{{ $val.service }}"
        - end-dates
        - trusted.ci.jenkins.io
{{ end }}
