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
                string(credentialsId: 'azure-client-id', variable: 'TF_VAR_CLIENT_ID'),
                string(credentialsId: 'azure-client-secret', variable: 'TF_VAR_CLIENT_SECRET'),
                string(credentialsId: 'azure-subscription-id', variable: 'TF_VAR_SUBSCRIPTION_ID'),
                string(credentialsId: 'azure-tenant-id', variable: 'TF_VAR_TENANT_ID')]) {

                sh 'make'
            }
        }
    }
}

stage('Review') {
}

stage('Apply') {
}
