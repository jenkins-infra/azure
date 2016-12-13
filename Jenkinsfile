#!/usr/bin/env groovy

def tfVarFile = '.azure-terraform.json'
String tfPrefix

/* Depending on our environment, adjust the prefix for all Terraform resources */
if (env.TF_VAR_PREFIX) {
    /** For production environments, something outside this code will define
     * the prefix
     */
    tfPrefix = env.TF_VAR_PREFIX
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
        /* When inside of a pull request, Terraform is working with ephemeral
         * resources anyways, so automatically apply the planned changes
         */
        if (!env.CHANGE_ID) {
            timeout(30) {
                input message: 'Apply the planned updates?', ok: 'Apply'
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
