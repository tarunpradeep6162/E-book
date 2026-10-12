pipeline {
  agent { label 'ebook-builder' }
  options { disableConcurrentBuilds(); timestamps(); timeout(time: 15, unit: 'MINUTES') }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Build and check') { steps { sh 'bash scripts/build.sh' } }
    stage('Archive draft') {
      steps { archiveArtifacts artifacts: 'dist/*.pdf,dist/*.epub', fingerprint: true }
    }
  }
}
