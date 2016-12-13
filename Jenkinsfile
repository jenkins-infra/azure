#!/usr/bin/env groovy

stage('Plan') {
    node('docker') {
        checkout scm

        withEnv([
            'PATH+TF=./scripts',
            'TF_VAR_PREFIX=jenkins',
        ]) {
            /* Create an empty terraform variables file so that everything can
             * be overridden in the environment
             */
            sh 'echo "{}" > .azure-terraform.json'
            sh 'terraform version'
        }
    }
}

stage('Review') {
}

stage('Apply') {
}
