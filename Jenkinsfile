#!/usr/bin/env groovy

/* Load the latest version of our Shared Library defined here:
 *  https://github.com/jenkins-infra/pipeline-library.git
 */
@Library('pipeline-library@master') _


if (env.CHANGE_ID) {
    properties([
        buildDiscarder(logRotator(numToKeepStr: '10')),
    ])
}
else {
    properties([
        buildDiscarder(logRotator(numToKeepStr: '96')),
        pipelineTriggers([[$class:"SCMTrigger", scmpoll_spec:"H/10 * * * *"]]),
    ])
}


String tfVarFile = '.azure-terraform.json'
String tfPrefix

/* Depending on our environment, adjust the prefix for all Terraform resources */
if (infra.isTrusted()) {
    tfPrefix = 'prod'
}
else if (env.CHANGE_ID) {
    /* When handling pull requests, ensure everything is denoted by the pull
     * request
     */
    tfPrefix = "pr${env.CHANGE_ID}${env.BUILD_NUMBER}"
}
else {
    /* Any branches or anything else that might execute this Pipeline should
     * still have a unique prefix
     */
    tfPrefix = 'infraci'
}

try {
    stage('Prepare') {
        /* When planning and applying changes for a pull request, the Pipeline
         * should first use the master branch which will create a remote state
         * that can be continued from later, more accurately simulating an
         * execution of terraform plans on an existing production
         * infrastructure
         */
        if (env.CHANGE_ID) {
            node('docker') {
                deleteDir()
                git 'https://github.com/jenkins-infra/azure.git'
                /* Create an empty terraform variables file so that everything can
                 * be overridden in the environment
                 */
                sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"

                /*
                 * Three following actions must be remove once terraform is greater than 0.8
                 * Cfr INFRA-1288
                 */

                sh 'rm plans/k8s.tf'
                sh 'rm plans/logs.tf'
                sh 'rm plans/dockerregistry.tf'

                /*
                 *INFRA-1288 end
                 */

                tfsh {
                    sh 'make deploy'
                }
            }
        }
    }

    /*
     * In order to migrate to the new backend mechanism, we need to pull
     * the remote state with a terraform version < 0.9 then run terraform init with terraform 0.9.
     * Terraform will detect that a legacy tfstate exist and will migrate it automatically.
     * stage('Pull remote') can be deleted once  tfstate is migrated.
     * It seems that the jenkinsfile git method do not  work with commit_id (instead of branch).
     */

    stage('Pull remote') {
        node('docker') {
            deleteDir()
            git url: 'https://github.com/olblak/azure.git', branch: '0.8.8'
            sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"
            tfsh {
                sh 'make init'
            }
            stash includes: '.terraform/*', name: 'legacy-tfstate'
        }
    }
    /*
     * END
     */

    stage('Plan') {
        node('docker') {
            deleteDir()
            checkout scm
            sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"

            /* unstash 'legacy-tfstate' can be deleted once remote state is migrate
             * to the new backend mechanism
             */
            unstash 'legacy-tfstate'

            tfsh {
                sh 'make terraform'
            }
        }
    }

    stage('Review') {
        /* Inside of a pull request or if executing a Multibranch Pipeline it
         * is acceptable to proceed without any review of the planned
         * infrastructure. Inside our trusted.ci infrastructure the production
         * Pipeline will be using a non-Multibranch Pipeline
         */
        if (infra.isTrusted()) {
            timeout(30) {
                input message: "Apply the planned updates to ${tfPrefix}?", ok: 'Apply'
            }
        }
    }

    stage('Apply') {
        node('docker') {
            deleteDir()
            checkout scm
            sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"
            tfsh {
                sh 'make deploy'
            }
        }
    }
}
finally {
    /* If Pipeline is executing with a pull request, the infrastructure should
     * be destroyed at the end
     */
    if (env.CHANGE_ID) {
        stage('Destroy') {
            node('docker') {
                deleteDir()
                checkout scm
                sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"

                tfsh {
                    /* `make init` ensures we have synced state from the remote
                     * state before doing anything
                     */
                    sh 'make init'
                    /*
                     * Remove backend configuration in order to use the default local backend
                     * instead of azure
                     */
                    sh "sed -i 's/azure/local/g' backend.tf plans/backend.tf"
                    sh "./scripts/terraform init -force-copy"
                    sh "./scripts/terraform destroy -force -var-file=${tfVarFile} plans"
                }
            }
        }
    }
}


/**
 * tfsh is a simple function which will wrap whatever block is passed in with
 * the appropriate credentials loaded into the environment for invoking Terraform
 */
Object tfsh(Closure body) {
    body.resolveStrategy = Closure.DELEGATE_FIRST

    withCredentials([
        string(credentialsId: 'azure-client-id', variable: 'TF_VAR_client_id'),
        string(credentialsId: 'azure-client-secret', variable: 'TF_VAR_client_secret'),
        string(credentialsId: 'azure-subscription-id', variable: 'TF_VAR_subscription_id'),
        string(credentialsId: 'azure-tenant-id', variable: 'TF_VAR_tenant_id'),
        file(credentialsId: 'azure-k8s-management-pubkey', variable: 'TF_VAR_ssh_pubkey_path'),
        ]) {
        ansiColor('xterm') {
            body.call()
        }
    }
}
