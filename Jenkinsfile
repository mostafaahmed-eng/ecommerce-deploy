pipeline {
    agent any

    environment {
        REGISTRY = "ghcr.io"
        IMAGE_NAME = "mostafaahmed-eng/ecommerce-deploy"
    }

    stages {

        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/mostafaahmed-eng/ecommerce-deploy.git'
            }
        }

        stage('Build all services') {
            steps {
                script {
                    def services = ['frontend', 'backend', 'payment', 'search', 'cart', 'product', 'api']
                    services.each { svc ->
                        sh "docker build -t ${REGISTRY}/${IMAGE_NAME}/${svc}:latest ./services/${svc}"
                    }
                }
            }
        }

        stage('Login to GHCR') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'ghcr-creds', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
                    sh '''
                        echo $PASS | docker login ghcr.io -u $USER --password-stdin
                    '''
                }
            }
        }

        stage('Push to GHCR') {
            steps {
                script {
                    def services = ['frontend', 'backend', 'payment', 'search', 'cart', 'product', 'api']
                    services.each { svc ->
                        sh "docker push ${REGISTRY}/${IMAGE_NAME}/${svc}:latest"
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'GAMMED YA GAMMED SUCCESS! All images pushed to GHCR!'
        }
        failure {
            echo ' FAILED! Check logs.'
        }
    }
}