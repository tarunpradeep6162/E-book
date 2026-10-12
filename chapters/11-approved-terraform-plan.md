# Chapter 11: Terraform Through CI: Approve the Change You Actually Apply

::: {.callout .failure}
## Approval Covered a Different Plan

The engineer reviewed a local plan showing one security-group change. Before CI ran, another administrator modified the database configuration. The pipeline generated a fresh plan and applied it automatically, including a database replacement nobody approved.

The dangerous action came from executing a newly generated plan, not from Terraform magically changing an approved saved plan. A saved plan whose state has become stale can be rejected. External changes outside state still require coordination and reconciliation.
:::

**An approval must identify the exact execution artifact, source revision, environment, and identity.** Infrastructure approval is not a generic permission to run the latest branch.


## Plan Files Are Sensitive Execution Artifacts

`terraform plan -out=tfplan` creates a binary plan that apply can consume. It includes configuration and values required for execution, potentially including sensitive material. Human-readable masking does not turn the binary into a public artifact.

Store the plan under restricted access and retention. Avoid a public pull-request attachment containing plan JSON or state. `terraform show -json` can expose values in machine-readable form; use protected policy checks rather than publishing the entire output.

Pair the plan with the source commit, provider lock file, CLI version, backend key, account identity, timestamp, and a cryptographic hash. Require approval after those details are established. Apply only that plan in the matching execution context.

## Separate Review from Authority

A planning role normally needs read access to resources and state plus permissions for backend lock operations. An applying role needs the exact write operations the root manages. Separate credentials where practical, but test that both roles can initialize the same backend correctly.

A plan approval does not replace IAM. The apply identity should be unable to modify unrelated accounts, read other state keys, or delete protected backups. Terraform can only act within effective cloud permissions, so an overly broad root and role remain dangerous even with a manual button.

Backend locking coordinates state operations. Pipeline serialization coordinates this pipeline. Neither prevents a human console change or a different pipeline using another state key. Establish an environment write policy and a drift-response procedure.

## A Plan, Approve, Apply Pipeline

The example requires a trusted isolated agent with pinned Terraform and a scoped instance role. It plans and applies using one authorized lab identity for simplicity; production can split stages onto distinct protected agents with reviewed credential transitions.

Jenkins authorization must restrict job edits, source references, and the `platform-approvers` group. Adapt the submitter to your configured security realm. A string in a Jenkinsfile does not create that group.

### First, Read the Smallest Contract

```bash
terraform init -lockfile=readonly
terraform validate
terraform plan -out=tfplan
terraform show tfplan
# Review before applying this exact file.
```

These commands establish the plan artifact. The complete Jenkins workflow below adds protected storage, approval, identity checks, and serialization.

### Jenkinsfile

Read these panels in sequence. They continue the same file; use the complete companion source when executing.

### Identity and plan generation

```groovy
pipeline {
  agent { label 'trusted-terraform' }
  options {
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 60, unit: 'MINUTES')
  }
  environment {
    TF_IN_AUTOMATION = 'true'
    TF_INPUT = 'false'
    AWS_ACCOUNT_ID = '123456789012'
    TF_ROOT = 'infra/environments/prod/aws/orders'
  }
  stages {
    stage('Checkout and identify') {
      steps {
        deleteDir()
        checkout scm
        sh '''#!/usr/bin/env bash
set -euo pipefail
[ "$(aws sts get-caller-identity --query Account --output text)" = "$AWS_ACCOUNT_ID" ]
git rev-parse HEAD > revision.txt
terraform version
'''
      }
    }
    stage('Plan') {
      steps {
        dir("${env.TF_ROOT}") {
          sh '''#!/usr/bin/env bash
set -euo pipefail
```

### Protected approval and applying the saved plan

```groovy
umask 077
terraform init -lockfile=readonly
terraform fmt -check -recursive
terraform validate
terraform plan -lock-timeout=120s -out=tfplan
terraform show -no-color tfplan > plan-review.txt
sha256sum tfplan > tfplan.sha256
'''
          // Restrict job/artifact readers; these are sensitive artifacts.
          archiveArtifacts artifacts: 'tfplan,tfplan.sha256,plan-review.txt',
            fingerprint: true
        }
      }
    }
    stage('Approve exact plan') {
      steps {
        timeout(time: 30, unit: 'MINUTES') {
          input message: 'Approve this build\'s protected plan and environment?',
            submitter: 'platform-approvers'
        }
      }
    }
    stage('Apply approved plan') {
      steps {
        dir("${env.TF_ROOT}") {
          sh '''#!/usr/bin/env bash
set -euo pipefail
[ "$(aws sts get-caller-identity --query Account --output text)" = "$AWS_ACCOUNT_ID" ]
sha256sum --check tfplan.sha256
# No fresh planning command and no -auto-approve are needed here.
terraform apply -lock-timeout=120s tfplan
'''
```

### Convergence and cleanup

```groovy
        }
      }
    }
    stage('Verify convergence') {
      steps {
        dir("${env.TF_ROOT}") {
          sh '''#!/usr/bin/env bash
set -euo pipefail
# This stage fails if further changes remain; investigate partial convergence.
terraform plan -lock-timeout=120s -detailed-exitcode
'''
        }
      }
    }
  }
  post {
    always { deleteDir() }
  }
}
```

A checksum stored beside the plan detects accidental modification, not an attacker who can replace both files. Protect the workspace and artifact service, and bind approval to an authenticated build record. Stronger signing or immutable artifact storage can extend that trust chain.

Holding one agent during approval is simple but consumes capacity. A production workflow may archive the plan and release the agent, then retrieve it on a separate applying agent. That requires authenticated artifact retrieval, matching source and lock file, compatible CLI, and exact backend configuration. Do not casually reconstruct inputs from a moving branch.

## Handle Staleness Explicitly

Approval expires when its reviewed assumptions no longer hold. Define a maximum plan age and reject an approval after relevant configuration, state, or administrative changes. A fixed thirty-minute approval timeout is only one part of that policy.

If apply reports a stale plan, stop. Generate a new plan and obtain new approval. Do not regenerate and auto-apply because the reviewer “already approved the intent.” Intent and concrete resource effects are different review objects.

An external console change may not alter Terraform state until refreshed. Coordinate writers and use post-apply verification. Saved plans are not a guarantee that remote services remain unchanged between review and execution.

Plan policy should flag deletions, replacements, public access, IAM privilege expansion, encryption changes, and movement across network boundaries. For destructive database changes, require a separate recovery checkpoint and database-owner approval. Do not rely on reviewers visually scanning thousands of unchanged resources.

## Partial Apply Is an Incident Condition

::: {.callout .failure}
Terraform is not a transaction that rolls back every AWS operation when one resource fails. Some resources may be created or updated before another operation errors. The state can record successful operations while the overall apply reports failure.
:::

Preserve logs and inspect the authoritative state. Determine which actions completed, identify the failed dependency, and re-plan after correcting the cause. Do not blindly rerun the original saved plan or restore an older state snapshot to hide partial progress.

Application rollback and infrastructure repair are separate decisions. If a network change broke traffic, a safe corrective plan may restore connectivity. If a database replacement deleted data, a configuration rollback does not reconstruct the missing records; the tested recovery procedure must do that.

## Protect the Approval System

Jenkins job configuration, shared libraries, credentials, and agent images are part of the execution trust chain. A contributor who can edit the production pipeline or replace its trusted toolchain may bypass the approval gate entirely.

Keep untrusted PR planning separate. Public plans can expose resource names, network ranges, and secrets; even read-only planning can execute data sources or interact with external tools. Review providers and external execution paths before granting planning credentials to contributed code.

Retain the approved plan and execution evidence according to a defined policy. Do not keep sensitive artifacts indefinitely just because storage is cheap. Log the approver, build ID, source revision, target account, plan hash, apply result, and functional verification result.

## Test the Process

Use a disposable root to demonstrate a waiting lock, an expired approval, a rejected stale plan, and a failed IAM write. Confirm none causes an automatic transition to a new unapproved apply.

Modify a synthetic plan artifact in a test workspace and verify the checksum gate fails. Test that an unauthorized Jenkins user cannot approve the production stage or edit its source reference. Check that secrets do not appear in archived review text or shared logs.

Finally, verify the workload after infrastructure changes: DNS, connection paths, health, identity, and representative transactions. Terraform convergence is an infrastructure observation. The business service still needs a functional acceptance check.

## Plan Review Must Explain Replacements

Terraform marks some attribute changes as requiring replacement. The reviewer should understand whether that is a provider limitation, an immutable service property, or a resource-address change introduced by configuration. The word replacement is a recovery question, especially for databases and storage.

For each replacement, record the affected service, expected interruption, preserved data, reconnect behavior, and rollback boundary. Check whether create-before-destroy is feasible: uniqueness constraints, address capacity, quotas, or dependent resources can make it impossible.

Do not add lifecycle settings as a generic promise of zero downtime. They change graph behavior but do not establish application compatibility or spare capacity. Verify the replacement sequence in a disposable representative environment.

The approval record should explain why destructive actions are acceptable and which recovery evidence supports that decision. A reviewer who cannot answer those questions should reject the plan rather than approve it because the number of changed resources is small.

Require the approver to identify the protected build record explicitly; approval in a separate chat message is not the execution gate.

::: {.callout .protip}
Apply the saved approved plan; stale assumptions require a new review.
:::

::: {.callout .takeaways}
- **Approve a concrete saved plan, not a moving branch or general intent.**
- **Protect plans as sensitive artifacts.**
- **Re-plan and re-approve when assumptions become stale.**
- **Serialize execution and coordinate every other writer.**
- **Partial apply requires investigation, not assumed rollback.**
- **Verify application behavior after infrastructure convergence.**
:::

## References

- Terraform plan: [Documentation](https://developer.hashicorp.com/terraform/cli/commands/plan)
- Terraform apply: [Documentation](https://developer.hashicorp.com/terraform/cli/commands/apply)
