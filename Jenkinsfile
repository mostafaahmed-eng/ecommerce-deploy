pipeline {
    agent any
    
    environment {
        DOCKER_REGISTRY = 'ghcr.io'
        IMAGE_NAME = 'mostafaahmed-eng/ecommerce-deploy'
    }

    stages {
        stage('Checkout') {
            steps {
                git 'https://github.com/mostafaahmed-eng/ecommerce-deploy.git'
            }
        }

        stage('Build Images') {
            parallel {
                stage('Frontend') {
                    sh 'docker build -t ${IMAGE_NAME}/frontend:latest ./services/frontend'
                }
                stage('Backend') {
                    sh 'docker build -t ${IMAGE_NAME}/backend:latest ./services/backend'
                }
                stage('Payment') {
                    sh 'docker build -t ${IMAGE_NAME}/payment:latest ./services/payment'
                }
                stage('Search') {
                    sh 'docker build -t ${IMAGE_NAME}/search:latest ./services/search'
                }
                stage('Cart') {
                    sh 'docker build -t ${IMAGE_NAME}/cart:latest ./services/cart'
                }
                stage('Product') {
                    sh 'docker build -t ${IMAGE_NAME}/product:latest ./services/product'
                }
                stage('API') {
                    sh 'docker build -t ${IMAGE_NAME}/api:latest ./services/api'
                }
            }
        }

        stage('Push Images') {
            steps {
                sh '''
                    echo $DOCKER_TOKEN | docker login ghcr.io -u $GITHUB_ACTOR --password-stdin
                    docker push ${IMAGE_NAME}/frontend:latest
                    docker push ${IMAGE_NAME}/backend:latest
                    docker push ${IMAGE_NAME}/payment:latest
                    docker push ${IMAGE_NAME}/search:latest
                    docker push ${IMAGE_NAME}/cart:latest
                    docker push ${IMAGE_NAME}/product:latest
                    docker push ${IMAGE_NAME}/api:latest
                '''
                env:
                    DOCKER_TOKEN: credentials('github-token')
            }
        }
    }
}