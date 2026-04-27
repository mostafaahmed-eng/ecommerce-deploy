pipeline {
    agent any
    
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
                        sh "docker build -t ghcr.io/mostafaahmed-eng/ecommerce-deploy/${svc}:latest ./services/${svc}"
                    }
                }
            }
        }

        stage('Login to GHCR') {
            steps {
                sh 'echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_ACTOR --password-stdin'
            }
        }

        stage('Push to GHCR') {
            steps {
                sh '''
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/frontend:latest
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/backend:latest
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/payment:latest
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/search:latest
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/cart:latest
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/product:latest
                    docker push ghcr.io/mostafaahmed-eng/ecommerce-deploy/api:latest
                '''
            }
        }
    }
    
    post {
        success { echo 'SUCCESS! All images pushed to GHCR!' }
    }
}