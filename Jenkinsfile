#!/usr/bin/env groovy

/* Load the latest version of our Shared Library defined here:
 *  https://github.com/jenkins-infra/pipeline-library.git
 */
@Library('pipeline-library@master') _

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
    tfPrefix = "pr${env.CHANGE_ID}"
}
else {
    /* Any branches or anything else that might execute this Pipeline should
     * still have a unique prefix
     */
    tfPrefix = 'jenkinsinfra'
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
                sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"
                tfsh {
                    sh 'make deploy'
                }
            }
        }
    }

    stage('Plan') {
        node('docker') {
            deleteDir()
            checkout scm

            /* Create an empty terraform variables file so that everything can
             * be overridden in the environment
             */
            sh "echo '{\"prefix\":\"${tfPrefix}\"}' > ${tfVarFile}"
            tfsh {
                sh 'make'
            }

            stash includes: '**', name: 'tf'
        }
    }

    stage('Review') {
        /* Inside of a pull request or if executing a Multibranch Pipeline it
         * is acceptable to proceed without any review of the planned
         * infrastructure. Inside our trusted.ci infrastructure the production
         * Pipeline will be using a non-Multibranch Pipeline
         */
        if ((!env.CHANGE_ID) && (!env.BRANCH_NAME)) {
            timeout(30) {
                input message: "Apply the planned updates to ${tfPrefix}?", ok: 'Apply'
            }
        }
    }

    stage('Apply') {
        node('docker') {
            deleteDir()
            unstash 'tf'

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
                unstash 'tf'

                tfsh {
                    /* `make init` ensures we have synced state from the remote
                     * state before doing anything
                     */
                    sh 'make init'
                    echo 'Turning off remote state before destroying'
                    sh './scripts/terraform remote config --disable'
                    sh "./scripts/terraform destroy --force --var-file=${tfVarFile} plans"
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
        string(credentialsId: 'azure-tenant-id', variable: 'TF_VAR_tenant_id')]) {

        ansiColor('xterm') {
            body.call()
        }
    }
}
