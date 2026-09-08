pipeline {
    agent any

    tools {
        maven 'maven'
    }

    environment {
        NEXUS_REGISTRY  = 'nexus:8082'
        IMAGE_NAME      = 'petclinic-app'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
        SONAR_PROJECT   = 'sample-app'
        DOCKER_USERNAME = 'iamakshu'
        GITOPS_REPO     = 'https://github.com/your-org/gitops-repo.git'
    }

    stages {
        stage('Checkov — IaC Scan') {
            steps {
                sh '''
                    checkov -d 00_Setup/Infra/terraform/ \
                    --framework terraform \
                    --compact --quiet \
                    --output json --output-file-path ./reports/ \
                    --soft-fail >/dev/null 2>&1
                '''
            }
        }

        // stage('OWASP Dependency Check') {
        //     steps {
        //         dependencyCheck(
        //             odcInstallation: 'Dependency-Check',
        //             nvdCredentialsId: 'nvd-api-key',
        //             additionalArguments: '''
        //                 --scan ./
        //                 --format XML
        //                 --format HTML
        //                 --noupdate
        //             '''
        //         )

        //         dependencyCheckPublisher(
        //             pattern: 'dependency-check-report.xml'
        //         )
        //     }
        // }

        stage('Build') {
            steps {
                sh '''
                    cd Reference_Project/spring-petclinic/
                    mvn clean verify -DskipTests >/dev/null
                '''
            }
        }

        // stage('SonarQube Analysis') {
        //     steps {
        //         withSonarQubeEnv('SonarQube') {
        //             // fully qualified plugin — avoids "No plugin found for prefix 'sonar'" on restricted agents
        //             sh "mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.projectKey=${SONAR_PROJECT}"
        //         }
        //     }
        // }

        // stage('Quality Gate') {
        //     steps {
        //         timeout(time: 5, unit: 'MINUTES') {
        //             waitForQualityGate abortPipeline: true
        //         }
        //     }
        // }

        stage('Docker Build') {
            steps {
                sh '''
                    cd Reference_Project/spring-petclinic/
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Trivy — Image Scan') {
            steps {
                sh """
                    trivy image \
                      --exit-code 0 \
                      --severity HIGH,CRITICAL \
                      --ignore-unfixed \
                      --format table \
                      ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
            post {
                always {
                    sh """
                        trivy image \
                          --exit-code 0 \
                          --format json \
                          --output trivy-report.json \
                          ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                    """
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Image Push to DockerHub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USERNAME',
                        passwordVariable: 'DOCKER_PASSWORD'
                    )
                ]) {
                    sh '''
                    echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
                    docker push ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                '''
                }
            }
        }

        // stage('Push to Nexus') {
        //     steps {
        //         script {
        //             docker.withRegistry("http://${NEXUS_REGISTRY}", 'nexus-credentials') {
        //                 docker.image("${IMAGE_NAME}:${IMAGE_TAG}").push()
        //                 docker.image("${IMAGE_NAME}:${IMAGE_TAG}").push('latest')
        //             }
        //         }
        //     }
        // }

        stage('Cosign — Sign Image') {
            steps {
                withCredentials([
                    file(credentialsId: 'cosign-private-key', variable: 'COSIGN_PVT_KEY'),
                    file(credentialsId: 'cosign-public-key', variable: 'COSIGN_PUB_KEY'),
                    string(credentialsId: 'cosign-key-password', variable: 'COSIGN_PASSWORD')
                ]) {
                    sh '''
                        echo "Getting Digest"
                        IMAGE="docker.io/$DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
                        DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE")

                        if [ -z "$DIGEST" ] || [ "$DIGEST" = "<no value>" ]; then
                            echo "No registry digest found for $IMAGE. The image must be pushed before signing." >&2
                            exit 1
                        fi

                        echo "Signing $DIGEST"
                        COSIGN_PASSWORD="$COSIGN_PASSWORD" \
                        cosign sign --key "$COSIGN_PVT_KEY" --yes "$DIGEST"

                        echo "Verifying $DIGEST"
                        cosign verify --key "$COSIGN_PUB_KEY" "$DIGEST"

                        docker logout
                    '''
                }
            }
        }

        stage('Update Kubernetes Manifest') {
            steps {
                dir('Reference_Project/kubernetes-manifest') {
                    script {
                        withCredentials([
                            gitUsernamePassword(
                                credentialsId: 'github-creds',
                                gitToolName: 'Default'
                            )
                        ]) {
                            sh '''
                                echo "Updating Kubernetes deployment with the pushed image digest..."

                                DIGEST=$(docker inspect \
                                    --format='{{index .RepoDigests 0}}' \
                                    "${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}")
                                DIGEST_HASH="${DIGEST##*:}"

                                if [ -z "$DIGEST_HASH" ] || [ "$DIGEST_HASH" = "<no value>" ]; then
                                    echo "Unable to determine the pushed image digest" >&2
                                    exit 1
                                fi

                                sed -i -E \
                                    "s#image:.*petclinic-app(:|@sha256:).*#image: docker.io/${DOCKER_USERNAME}/${IMAGE_NAME}@sha256:${DIGEST_HASH}#" \
                                    deployment.yml

                                git config user.email "jenkins@ci.local"
                                git config user.name "Jenkins"

                                if ! git diff --quiet -- deployment.yml; then
                                    echo "Changes detected."

                                    git add deployment.yml
                                    git commit -m "ci: pin image to ${DIGEST_HASH} [skip ci]"

                                    echo "Pushing changes to ${BRANCH_NAME}..."
                                    git push origin HEAD:${BRANCH_NAME}
                                else
                                    echo "No changes to commit."
                                fi
                            '''
                        }
                    }
                }
            }
        }

        stage('Update Kubernetes Helm Values') {
            steps {
                dir('Reference_Project/petclinic-app') {
                    script {
                        withCredentials([
                            gitUsernamePassword(
                                credentialsId: 'github-creds',
                                gitToolName: 'Default'
                            )
                        ]) {
                            sh '''
                                echo "Updating Helm values with the pushed image digest..."

                                DIGEST=$(docker inspect \
                                    --format='{{index .RepoDigests 0}}' \
                                    "${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}")
                                DIGEST_HASH="${DIGEST##*:}"

                                if [ -z "$DIGEST_HASH" ] || [ "$DIGEST_HASH" = "<no value>" ]; then
                                    echo "Unable to determine the pushed image digest" >&2
                                    exit 1
                                fi

                                sed -i -E "s|^  imageDigest:.*|  imageDigest: sha256:${DIGEST_HASH}|" values-prod.yaml

                                git config user.email "jenkins@ci.local"
                                git config user.name "Jenkins"

                                if ! git diff --quiet -- values-prod.yaml; then
                                    echo "Changes detected in values-prod.yaml."

                                    git add values-prod.yaml
                                    git commit -m "ci: pin helm image to ${DIGEST_HASH} [skip ci]"

                                    echo "Pushing changes to ${BRANCH_NAME}..."
                                    git push origin HEAD:${BRANCH_NAME}
                                else
                                    echo "No changes to commit in values-prod.yaml."
                                fi
                            '''
                        }
                    }
                }
            }
        }
    }
}
