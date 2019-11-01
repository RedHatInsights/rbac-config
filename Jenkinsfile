pipeline {
    agent any

    stages {
        stage('Login as deployer account') {
            steps {
                withCredentials([string(credentialsId: 'HccmRbacDevDeployerToken', variable: 'TOKEN')]) {
                    sh "oc login https://api.insights-dev.openshift.com --token=${TOKEN}"
                }

                script {
                    if (GIT_BRANCH == 'origin/master') {
                        sh "oc project rbac-ci"
                    }
                    if (GIT_BRANCH == 'origin/stable') {
                        sh "oc project rbac-qa"
                    }
                }
            }
        }   

        stage('Create ConfigMap') {
            steps {
                sh "oc create configmap rbac-config --from-file=configs --dry-run -o json | oc apply -f -"
            }
        }

        stage('Redeploy service') {
            steps {
                sh "oc rollout latest dc/rbac"
            }
        }   
    }
}