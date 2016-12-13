#!/usr/bin/env groovy

stage('Plan') {
    node('docker') {
        checkout scm

        withEnv(['PATH+TF=./scripts']) {
            sh 'terraform version'
        }
    }
}

stage('Review') {
}

stage('Apply') {
}
