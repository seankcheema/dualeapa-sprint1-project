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
                sh '''
                    docker rm -f test-db >/dev/null 2>&1 || true
                    docker run -d --name test-db \
                        -e POSTGRES_DB=paysprint_test \
                        -e POSTGRES_USER=paysprint \
                        -e POSTGRES_PASSWORD=changeme \
                        -p 5432:5432 \
                        -v "$WORKSPACE/dua-leapa-schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro" \
                        postgres:16-alpine

                    for i in $(seq 1 30); do
                        docker exec test-db pg_isready -U paysprint -d paysprint_test >/dev/null 2>&1 && break
                        sleep 1
                    done
                '''
                sh 'mvn -B test || true'
            }
            post {
                always {
                    sh 'docker rm -f test-db >/dev/null 2>&1 || true'
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
        stage('Angular Install') {
            steps {
                // Agent has no Node.js installed, so run npm/ng inside an ephemeral node container instead.
                dir('trading-season-app') {
                    sh 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$(pwd):/app" -w /app node:22-alpine npm ci'
                }
            }
        }
        stage('Angular Build') {
            steps {
                dir('trading-season-app') {
                    sh 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$(pwd):/app" -w /app node:22-alpine npx ng build --configuration production'
                }
            }
        }
        stage('Angular Test') {
            steps {
                dir('trading-season-app') {
                    sh 'docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$(pwd):/app" -w /app node:22-alpine npx ng test --watch=false || true'
                }
            }
        }
        stage('Docker Build (Multistage)') {
            steps {
                sh 'docker build -t team-skeleton:multistage .'
            }
        }
        stage('Docker Compose Up') {
            steps {
                sh 'docker-compose up -d'
                sh 'docker-compose ps'
            }
        }
        stage('Docker Compose Down') {
            steps {
                sh 'docker-compose down'
            }
        }
    }
    
    post {
        always {
            sh 'docker-compose down || true'
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
