#!/usr/bin/env groovy

stage('Plan') {
    node('docker') {
        checkout scm

        /* Create an empty terraform variables file so that everything can
            * be overridden in the environment
            */
        sh "echo '{\"prefix\":\"jenkins\"}' > .azure-terraform.json"
        withCredentials([
            string(credentialsId: 'azure-client-id', variable: 'TF_VAR_client_id'),
            string(credentialsId: 'azure-client-secret', variable: 'TF_VAR_client_secret'),
            string(credentialsId: 'azure-subscription-id', variable: 'TF_VAR_subscription_id'),
            string(credentialsId: 'azure-tenant-id', variable: 'TF_VAR_tenant_id')]) {

            ansiColor('xterm') {
                sh 'make'
            }
        }

        stash includes: '**', name: 'tf'
    }
}

stage('Review') {
    timeout(30) {
        input message: 'Apply the planned updates?', ok: 'Apply'
    }
}

stage('Apply') {
    node('docker') {
        deleteDir()
        unstash 'tf'

        withCredentials([
            string(credentialsId: 'azure-client-id', variable: 'TF_VAR_client_id'),
            string(credentialsId: 'azure-client-secret', variable: 'TF_VAR_client_secret'),
            string(credentialsId: 'azure-subscription-id', variable: 'TF_VAR_subscription_id'),
            string(credentialsId: 'azure-tenant-id', variable: 'TF_VAR_tenant_id')]) {

            ansiColor('xterm') {
                sh 'make deploy'
            }
        }
    }
}
