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
                    sh 'echo $PASS | docker login ghcr.io -u $USER --password-stdin'
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

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/base/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/frontend/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/backend/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/payment/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/search/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/cart/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/product/
                        kubectl --kubeconfig=$KUBECONFIG apply -f infrastructure/k8s/api/
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/frontend -n ecommerce --timeout=120s
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/backend -n ecommerce --timeout=120s
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/payment -n ecommerce --timeout=120s
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/search -n ecommerce --timeout=120s
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/cart -n ecommerce --timeout=120s
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/product -n ecommerce --timeout=120s
                        kubectl --kubeconfig=$KUBECONFIG rollout status deployment/api -n ecommerce --timeout=120s
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'GAMMED YA GAMMED SUCCESS! All images built, pushed and deployed to K8s!'
        }
        failure {
            echo '7OMS YA 7OMS FAILED! Check logs.'
        }
    }
}
