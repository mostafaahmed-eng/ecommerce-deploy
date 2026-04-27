
pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'ghcr.io'
        IMAGE_NAME = 'mostafaahmed-eng/ecommerce-deploy'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/mostafaahmed-eng/ecommerce-deploy.git'
            }
        }

        stage('Build Docker Images') {
            steps {
                script {
                    def services = ['frontend', 'backend', 'payment', 'search', 'cart', 'product', 'api']
                    services.each { service ->
                        sh "docker build -t ${IMAGE_NAME}/${service}:latest ./services/${service}"
                    }
                }
            }
        }

        stage('Push Images') {
    steps {
        withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
            sh '''
                echo $GITHUB_TOKEN | docker login ghcr.io -u mostafaahmed-eng --password-stdin
                docker push ${IMAGE_NAME}/frontend:latest
                docker push ${IMAGE_NAME}/backend:latest
                docker push ${IMAGE_NAME}/payment:latest
                docker push ${IMAGE_NAME}/search:latest
                docker push ${IMAGE_NAME}/cart:latest
                docker push ${IMAGE_NAME}/product:latest
                docker push ${IMAGE_NAME}/api:latest
            '''
        }
    }
}

    post {
        failure {
            echo 'Pipeline failed!'
        }
    }
}