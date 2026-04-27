pipeline {
    agent any
    
    environment {
        IMAGE_NAME = 'mostafaahmed/ecommerce-deploy'
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
                withCredentials([usernamePassword(credentialsId: 'docker-hub', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh '''
                        echo $DOCKER_PASS | docker login -u $DOCKER_USER --password-stdin
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

        stage('List Images') {
            steps {
                sh 'docker images | grep mostafaahmed'
            }
        }
    }

    post {
        success {
            echo 'Pipeline succeeded! All images built and pushed!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}