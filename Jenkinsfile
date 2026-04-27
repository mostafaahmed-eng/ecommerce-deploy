pipeline {
    agent any
    
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/mostafaahmed-eng/ecommerce-deploy.git'
            }
        }

        stage('Build') {
            steps {
                sh 'docker build -t mostafaanwar862004/ecommerce-deploy/frontend:latest ./services/frontend'
            }
        }

        stage('Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'U', passwordVariable: 'P')]) {
                    sh 'docker login -u $U -p $P && docker push mostafaanwar862004/ecommerce-deploy/frontend:latest'
                }
            }
        }
    }
    
    post {
        success { echo 'SUCCESS!' }
    }
}