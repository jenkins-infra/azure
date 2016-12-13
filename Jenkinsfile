#!/usr/bin/env groovy

def tfPrefix = "jenkins${env.CHANGE_ID ?: ''}"
def tfVarFile = '.azure-terraform.json'

try {
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
                    sh "make init && ./scripts/terraform destroy --force --var-file=${tfVarFile} plans || true"
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
