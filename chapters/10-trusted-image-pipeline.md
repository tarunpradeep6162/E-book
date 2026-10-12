# Chapter 10: From Commit to Trusted Image: Write the Jenkinsfile

::: {.callout .failure}
## Latest Was Not the Release

A pipeline pushes an untested image as `orders-api:latest`. Production restarts a pod and pulls that tag. Some replicas run yesterday's image, others run the new one. The deployment record still says `latest`, so nobody can identify the actual code consistently.

The team rolls back the deployment YAML. It still points at `latest`. The new image is fetched again, and the incident continues.
:::

A tag is a name that can change. A registry digest identifies content. **Build evidence must name the exact image that passed the checks and the exact image deployed.** Git-commit tags help humans navigate, but immutable registry policy and digest promotion establish stronger identity.


## Define the Pipeline's Contract

This pipeline executes on a trusted isolated release agent, not the controller. Untrusted pull requests use a separate verification pipeline without registry publishing credentials. Jenkins authorization must prevent arbitrary code from choosing this privileged execution path.

The agent needs a reviewed Docker builder, Python, AWS CLI, Trivy, and the Jenkins Pipeline plugins used below. Pin the toolchain in the agent image. Docker-daemon access is privileged; use dedicated agents and keep their trust boundary away from other tenants.

The repository includes an application test suite and the Chapter 6 Dockerfile. The test suite must contain meaningful tests, not just successful discovery of zero tests. The pipeline checks syntax and executes unit tests before image construction, then performs a runtime health test.

ECR must have an immutable-tag policy for this repository. Its lifecycle policy must retain images referenced by production and recovery records. The assumed agent role may authenticate to ECR and publish only to the approved repository; it must not delete production state.

## A Complete Declarative Pipeline

The following values are examples to replace in reviewed pipeline configuration. `PYTHON_BASE` must contain a verified digest. It is not a user-supplied parameter that an untrusted job can alter.

### First, Read the Smallest Contract

```groovy
stage('Test') {
  steps {
    sh 'python3 -m unittest discover -s tests'
  }
}
```

Start with test execution. This excerpt is not the release gate: the complete pipeline additionally rejects zero tests, tests the image, scans it, and records the ECR digest.

### Jenkinsfile

Read these panels in sequence. They continue the same file; use the complete companion source when executing.

### Pipeline envelope and source identity

```groovy
pipeline {
  agent { label 'trusted-image-builder' }
  options {
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
  }
  environment {
    AWS_REGION = 'ap-south-1'
    AWS_ACCOUNT_ID = '123456789012'
    ECR_REPOSITORY = 'orders-api'
    PYTHON_BASE = 'python:REVIEWED_TAG@sha256:REVIEWED_DIGEST'
  }
  stages {
    stage('Checkout') {
      steps {
        deleteDir() // Do not inherit an unrelated workspace.
        checkout scm
        script {
          env.REVISION = sh(
            script: 'git rev-parse HEAD',
            returnStdout: true
          ).trim()
          if (!(env.REVISION ==~ /[0-9a-f]{40}/)) {
            error('Unexpected Git revision')
          }
          env.REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.IMAGE = "${env.REGISTRY}/${env.ECR_REPOSITORY}:${env.REVISION}"
        }
      }
    }
```

### Tests and runtime verification

```groovy
    stage('Test source') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
python3 -m compileall -q app.py tests
python3 - <<'PY'
import unittest
suite = unittest.defaultTestLoader.discover('tests')
if suite.countTestCases() == 0:
    raise SystemExit('Refusing a zero-test release')
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(not result.wasSuccessful())
PY
'''
      }
    }
    stage('Build and runtime test') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
docker build --pull --build-arg PYTHON_BASE="$PYTHON_BASE" -t "$IMAGE" .
cid=$(docker run -d --read-only --cap-drop ALL --security-opt no-new-privileges:true "$IMAGE")
trap 'docker rm -f "$cid" >/dev/null' EXIT
# Test inside the container without exposing an ephemeral host listener.
for attempt in {1..20}; do
  if docker exec "$cid" python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/readyz', timeout=2)"; then
    exit 0
  fi
  sleep 1
done
docker logs "$cid"
exit 1
```

### Security evidence and registry publication

```groovy
'''
      }
    }
    stage('Scan and SBOM') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
mkdir -p evidence
# Scanner failure and policy failure both fail the build.
trivy image --exit-code 1 --severity HIGH,CRITICAL \
  --format json --output evidence/vulnerabilities.json "$IMAGE"
trivy image --format cyclonedx \
  --output evidence/sbom.json "$IMAGE"
'''
      }
    }
    stage('Publish approved artifact') {
      steps {
        sh '''#!/usr/bin/env bash
set -euo pipefail
actual=$(aws sts get-caller-identity --query Account --output text)
[ "$actual" = "$AWS_ACCOUNT_ID" ]
# Keep registry tokens out of the agent's shared home directory.
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"
docker push "$IMAGE"
# Resolve registry identity, rather than treating the tag as the release.
aws ecr describe-images --region "$AWS_REGION" \
  --repository-name "$ECR_REPOSITORY" \
```

### Digest evidence and cleanup

```groovy
  --image-ids imageTag="$REVISION" \
  --query 'imageDetails[0].imageDigest' --output text \
  > evidence/image-digest.txt
grep -Eq '^sha256:[0-9a-f]{64}$' evidence/image-digest.txt
printf '%s\n' "$REVISION" > evidence/source-commit.txt
printf '%s\n' "$PYTHON_BASE" > evidence/base-image.txt
'''
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'evidence/*',
        allowEmptyArchive: true, fingerprint: true
      // Agent destruction, not deleteDir alone, ends its trust lifecycle.
      deleteDir()
    }
  }
}
```

The build refuses to publish if testing or scanning fails. `allowEmptyArchive` preserves a failure's available evidence without pretending a missing scan report means success. Configure artifact retention and access independently; reports can expose dependency and infrastructure details.

## Understand the Scanner Gate

Severity is a policy input, not a complete risk model. A critical finding in an unreachable component and a moderate finding in an exposed authentication path need different analysis. Start with a conservative gate and define a reviewed exception mechanism with owner, scope, expiry, and compensating controls.

Do not add `|| true` when scanner infrastructure is unavailable. That transforms an unavailable security check into permission to release. Cache vulnerability databases under trusted ownership and monitor freshness. Record scanner version and database revision alongside results.

An SBOM describes components; it does not prove authenticity. Add provenance and signing through a reviewed signing identity, then verify signatures and policy at deployment. Signing an untested image merely authenticates a bad release.

## Publication Is Not Deployment

The pipeline publishes a candidate artifact. Environment promotion consumes its recorded digest and approval evidence without rebuilding. A release record should include repository, digest, source revision, test results, configuration revision, and schema compatibility.

If an ECR immutable tag already exists for a retried commit, do not delete it automatically. Determine whether the recorded artifact already passed the required checks. A retry can produce a different image from changing external inputs even when source is unchanged.

Prevent registry cleanup from deleting deployed digests. Keep a separate retention policy for recoverable releases, and verify a replacement cluster can still pull the previous approved artifact. Registry availability and authentication are part of recovery, not just build convenience.

Multi-platform images introduce a manifest-list digest plus platform-specific digests. Record the top-level identity and prove each supported architecture meets the test contract. The single-platform pipeline here does not claim multi-platform verification.

## Boundaries and Failure Handling

A failed build must leave production unchanged. A failed push can leave partial registry upload state but must not create an approved deployment record. A scan report from a previous workspace must never be reused as current evidence; clean checkout and isolated agents prevent that confusion.

Cloud credentials should be short-lived and scoped. Publishing requires ECR authorization plus upload operations on the intended repository. Application deploy permissions and Terraform backend access belong to different identities and stages.

Jenkins pipeline definitions are code with administrative consequences. Protect the source revision used by this trusted pipeline, review shared-library updates, and restrict who can edit the job's branch reference. The most secure shell command is irrelevant if a contributor can replace the whole pipeline with credential exfiltration.

Exercise failures deliberately: make a unit test fail, inject a synthetic scanner policy failure, and deny publishing to a sandbox repository. Confirm each prevents publication and preserves diagnostic evidence. Never introduce a real exploitable package into production to test the gate.

Measure build duration, scan freshness, agent queue time, and retry causes. Excessive flakiness drives engineers to bypass controls. Fix unstable dependencies and execution environments instead of weakening the definition of a trusted image.

## Bind the Published Digest to the Tested Image

A registry query after push identifies the stored artifact, but the evidence chain must also show that the tested local image produced that publication. Record the local image identifier and build metadata before testing, keep the agent isolated, and prevent another job from retagging the image during the pipeline.

After publication, pull the recorded digest on a clean verification environment and repeat a bounded smoke test. This detects registry-reference mistakes and missing runtime content without rebuilding. Preserve the distinction between verifying a copied artifact and constructing a new one.

Use an explicit platform when architecture matters. A manifest-list publication can include multiple images, so testing one architecture does not prove the entire list meets the contract. Record supported platforms and their verification evidence.

If signing is added, sign the resolved digest rather than a mutable tag. Restrict the signing identity and require deployment-side verification against the approved issuer or key. Keep the private key or token out of the repository and build context.

These controls close a practical gap: a good test report is useful only if the deployed bytes are the bytes that generated it.

Retain the registry verification result with the build record so recovery operators can retrieve the artifact without relying on mutable branch names.

::: {.callout .protip}
Bind the published digest to the tested image and preserve its evidence record.
:::

::: {.callout .takeaways}
- **Tags are labels; digests identify the promoted artifact.**
- **Testing, runtime checks, scanning, and publication have separate gates.**
- **Zero tests and unavailable scanners must not silently pass.**
- **Keep publishing credentials off untrusted pull-request agents.**
- **Preserve evidence and retain deployed image digests.**
- **Provenance and signing complement testing; neither replaces it.**
:::

## References

- Jenkins declarative pipeline: [Documentation](https://www.jenkins.io/doc/book/pipeline/syntax/)
- ECR tag immutability: [Documentation](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html)
- Trivy: [Documentation](https://trivy.dev/latest/docs/)
