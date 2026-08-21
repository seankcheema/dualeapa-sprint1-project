pipeline {
    agent any
    
    tools {
        maven 'Maven3'
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build') {
            steps {
                sh 'mvn -B clean package'
            }
        }
        stage('Test') {
            steps {
                sh 'mvn -B test || true'
            }
            post {
                always {
                    junit testResults: 'target/surefire-reports/*.xml', 
                          allowEmptyResults: true
                }
            }
        }
        stage('Archive') {
            steps {
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }
    }
    
    post {
        always {
            echo "Pipeline Status: ${currentBuild.result}"
            junit testResults: 'target/surefire-reports/*.xml', 
                  allowEmptyResults: true
        }
        success {
            echo '✓ Build SUCCESS - Ready for deployment'
        }
        failure {
            echo '✗ Build FAILED - Check logs for details'
        }
    }
}
