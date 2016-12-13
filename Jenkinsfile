#!/usr/bin/env groovy

stage('Plan') {
    node('docker') {
        checkout scm
        docker.image('hashicorp/terraform').inside('--rm') {
            sh 'which terraform'
            sh 'terraform --version'
        }
    }
}

stage('Review') {
}

stage('Apply') {
}
