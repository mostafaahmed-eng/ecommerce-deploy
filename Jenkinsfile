pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/mostafaahmed-eng/ecommerce-deploy.git'
            }
        }

        stage('Build frontend') {
            steps {
                sh 'docker build -t mostafaanwar862004/ecommerce-deploy/frontend:latest ./services/frontend'
            }
        }

        stage('Push frontend') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'U', passwordVariable: 'P')]) {
                    sh 'echo $P | docker login -u $U --password-stdin'
                    sh 'docker push mostafaanwar862004/ecommerce-deploy/frontend:latest'
                }
            }
        }
    }
    
    post {
        success { echo 'SUCCESS!' }
        failure { echo 'FAILED!' }
    }
}