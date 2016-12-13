#!/usr/bin/env groovy

stage('Plan') {
    node('docker') {
        checkout scm

        withEnv([
            'PATH+TF=./scripts',
        ]) {
            /* Create an empty terraform variables file so that everything can
             * be overridden in the environment
             */
            sh "echo '{\"prefix\":\"jenkins\"}' > .azure-terraform.json"
            withCredentials([
                string(credentialsId: 'azure-client-id', variable: 'TF_VAR_client_id'),
                string(credentialsId: 'azure-client-secret', variable: 'TF_VAR_client_secret'),
                string(credentialsId: 'azure-subscription-id', variable: 'TF_VAR_subscription_id'),
                string(credentialsId: 'azure-tenant-id', variable: 'TF_VAR_tenant_id')]) {

                sh 'make'
            }
        }
    }
}

stage('Review') {
}

stage('Apply') {
}
