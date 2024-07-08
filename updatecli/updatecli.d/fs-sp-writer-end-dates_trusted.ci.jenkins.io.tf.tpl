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
    kind: yaml
    spec:
      file: updatecli/values.yaml
      key: $.end_dates.trusted_ci_jenkins_io.{{ $key }}.end_date
  nextEndDate:
    name: Prepare next `end_date` date within 3 months
    kind: shell
    spec:
      command: bash ./updatecli/scripts/dateadd.sh
      environments:
        - name: PATH
  shortNextEndDate:
    name: Short next `end_date` date within 3 months
    kind: shell
    spec:
      command: bash ./updatecli/scripts/dateadd.sh | cut -c -10
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
    kind: yaml
    sourceid: nextEndDate
    spec:
      file: updatecli/values.yaml
      key: $.end_dates.trusted_ci_jenkins_io.{{ $key }}.end_date
    scmid: default

actions:
  default:
    kind: github/pullrequest
    scmid: default
    spec:
      title: 'New end date for `{{ $val.service }}` File Share service principal writer on `trusted.ci.jenkins.io` (current: {{ source "currentEndDate" }})'
      description: |
        This PR updates the end date of {{ $val.service }} File Share service principal writer used in trusted.ci.jenkins.io.

        The current end date is set to `{{ $val.end_date }}`.

        After merging this PR, a new password will be generated.

        > [!IMPORTANT]
        > You'll have to ensure that the trusted.ci.jenkins.io top-level credential `{{ $val.secret }}` is updated with this new password!

        If you don't, {{ $val.service }} File Share won't be updated by trusted.ci.jenkins.io jobs anymore.
      labels:
        - terraform
        - "{{ $val.service }}"
        - end-dates
        - trusted.ci.jenkins.io
{{ end }}
