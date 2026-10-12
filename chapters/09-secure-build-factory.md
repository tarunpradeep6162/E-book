# Chapter 9: Secure the Build Factory: Separate Controllers, Agents, and Credentials

## A Dependency Script Finds the Deployment Keys

A package's installation script runs during a Jenkins build. It reads the controller's home directory and retrieves an AWS credential with administrative permissions. The attacker creates a new cloud identity, disables selected logging, and copies database snapshots.

The job ran on the built-in node because it was convenient. That node combined orchestration, credential storage, source execution, and cloud administration. A package installation became a control-plane compromise.

**Treat build code as untrusted execution, even when it came from your own repository.** Review can reduce risk, but dependency scripts, build tools, and contributed pull requests still need constrained authority.

## Controller and Agent Are Different Trust Domains

The controller schedules work, stores configuration, and coordinates plugins. Agents execute job steps. Set built-in executors to zero so jobs cannot casually run beside controller secrets.

Agent isolation is not achieved merely by adding a label. A build that can mount the controller's home, access its Docker daemon, or reach an unrestricted administrative endpoint can still cross the boundary. Give agents separate hosts or appropriately hardened ephemeral execution environments.

Separate untrusted verification from trusted release. Pull-request jobs test code without production credentials or publishing rights. Release jobs execute only approved revisions with narrowly scoped identities. Do not let an arbitrary repository Jenkinsfile request a privileged label and receive a deployment role.

Use folder authorization, node-use restrictions supported by reviewed plugins, and trusted pipeline definitions to enforce those decisions. Labels express scheduling intent; authorization determines who may use the capacity.

## Configuration as Code Must Be Versioned

JCasC makes controller configuration reproducible. It is not a substitute for plugin version management, credential storage, or authorization review. Pin plugin versions through the supported image-building workflow and test configuration compatibility before controller upgrades.

The following example requires JCasC, the matrix-authorization strategy plugin, and core inbound-agent support. It creates a permanently defined logical agent; the actual process must run on separate infrastructure. An ephemeral provisioning plugin can replace this approach when lifecycle ownership is established.

### jenkins.yaml

```yaml
jenkins:
  systemMessage: "Orders CI - approved revisions only"
  numExecutors: 0 # The controller never executes builds.
  mode: EXCLUSIVE
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "bootstrap-admin"
          password: "${BOOTSTRAP_ADMIN_PASSWORD}"
  authorizationStrategy:
    globalMatrix:
      entries:
        - user:
            name: "bootstrap-admin"
            permissions:
              - "Overall/Administer"
  nodes:
    - permanent:
        name: "isolated-verification"
        remoteFS: "/home/jenkins/agent"
        numExecutors: 1
        mode: EXCLUSIVE
        labelString: "untrusted-verification"
        launcher:
          inbound:
            workDirSettings:
              disabled: false
              internalDir: "remoting"
              failIfWorkDirIsMissing: true
  remotingSecurity:
    enabled: true
```

This is a bootstrap configuration, not the final enterprise access model. Supply the administrator password through a protected secret source, never a committed `.env` file. Replace local authentication with your reviewed identity-provider integration, MFA policy, and group-to-role mapping before normal use.

JCasC environment substitution does not make secrets invisible to administrators or process inspection. Avoid export endpoints and logs that disclose interpolated configuration. Test recovery with the secret source available independently of the controller.

Run the inbound agent with the approved agent image and a node-specific connection secret. Use WebSocket over the controller's TLS endpoint where appropriate. Keep the secret out of command history, rotate it after suspected exposure, and avoid sharing one agent identity across unrelated machines.

The controller-to-agent connection carries work but does not grant a secure sandbox automatically. Restrict access to controller ports and monitor anomalous remoting behavior. The agent's workspace is untrusted data; never copy it into controller configuration as an administrative action.

## Short-Lived Credentials Still Need Separation

An EC2 agent can receive an instance-profile role. Every build on that agent may be able to reach its metadata credentials, so the instance role must reflect the least-trusted workload using that host. IMDSv2 improves metadata access controls but is not a magical barrier against code executing on the instance.

Use an untrusted agent role without deployment rights. Place trusted releases on separately authorized capacity. A release-agent base role may assume a narrowly scoped deployment role; ordinary verification agents must not have that permission.

### agent-roles.tf

```hcl
variable "account_id" { type = string }
resource "aws_iam_role" "release_agent" {
  name = "orders-release-agent"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_instance_profile" "release_agent" {
  role = aws_iam_role.release_agent.name
}
resource "aws_iam_role" "deployment" {
  name                 = "orders-production-deployment"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = aws_iam_role.release_agent.arn }
      Action = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "assume_deployment" {
  role = aws_iam_role.release_agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.deployment.arn
    }]
  })
}
```

These declarations define trust, not useful deployment permissions. Attach a separate reviewed permission policy to `deployment` for the intended ECR, EKS, or Terraform operations. Do not attach `AdministratorAccess` to complete the example quickly.

Also restrict who can pass the instance role and attach the instance profile. An attacker who can launch an instance with the release-agent role may inherit its deployment path. `iam:PassRole` is part of the trust model, not an incidental provisioning permission.

A CI OIDC workflow requires an actual trusted issuer and constrained subject/audience claims. Jenkins does not automatically issue an AWS-trusted OIDC token merely because a Jenkinsfile requests one. Use an established federation implementation or EC2 role sessions; do not invent a token exchange.

## Credentials Belong to Stages and Identities

Request credentials only in the stage that needs them. Use short session durations and identifiable role-session names. Avoid `set -x`, environment dumps, and shared workspaces containing credential files.

A pipeline's secret masking is a display feature, not a prevention boundary. Malicious code can encode a credential, send it over the network, or use it without printing it. Prevent exposure by keeping secrets away from untrusted execution.

Separate registry publishing, infrastructure apply, and application deployment where their permissions differ. A builder needs permission to push an image, not to delete production data. An application deployer may need a constrained Kubernetes identity, not Terraform backend access.

## State and Recovery Controls

Back up controller configuration and required credential-encryption material under separate access control. Version pipeline definitions and JCasC, preserve the reviewed plugin inventory, and test restoration into an isolated controller.

Do not restore a compromised controller and immediately resume production jobs. Revoke suspicious sessions, rotate affected secrets, inspect identity changes, and establish a clean trusted configuration source. Recovery must address attacker persistence as well as uptime.

Ephemeral agents should discard workspaces between trust domains. Clear caches deliberately: dependency and build caches can contain modified artifacts or secret material. Use trusted cache ownership and verification instead of sharing an unrestricted writable cache across all jobs.

Record agent image digest, plugin versions, job revision, identity role, and session timestamps as build evidence. Audit who changes labels, node definitions, credential bindings, and pipeline source references.

## Prove the Boundary

Create a synthetic pull-request job that attempts to discover credentials and contact protected services. It must fail without retrieving real secrets. Confirm built-in executors remain zero and the job cannot select release capacity through a modified Jenkinsfile.

On a trusted test agent, obtain a short-lived role session and verify only the intended operation succeeds. Test a denied production action in a sandbox with explicit authorization. Review CloudTrail for the expected role-session identity.

Stop the controller and confirm existing applications continue running. Destroy a disposable agent and verify retry behavior does not duplicate releases. Disconnect the secret source during a recovery rehearsal and confirm the runbook reports the dependency clearly rather than substituting static keys.

A secure build factory has explainable trust transitions. If a reviewer cannot identify which identity executes each stage and what it can change, the pipeline is not ready for production.

## Limit Agent Network Authority

An isolated agent should reach only the source, dependency, artifact, and control services its job needs. Unrestricted outbound access makes exfiltration easy even when logs mask credentials. Use approved proxies, destination policies, or private endpoints where the environment supports them.

Avoid sharing one host between trusted and untrusted jobs merely because they execute at different times. Container cleanup may leave daemon state, writable caches, or host modifications. Recreate agents from a reviewed image when crossing trust domains.

Test whether the verification role can read Terraform state or assume the release role. Both should fail. Then verify the trusted release role can perform only its documented publishing or deployment action. Record effective policies, including inherited grants; a narrowly written policy does not cancel another broad allow.

This turns agent isolation into an observed property of filesystem, network, and identity access rather than a label attached to a Jenkins node.

Review inherited credential bindings whenever a job moves folders; organizational convenience must not silently expand the new job’s effective authority.

## Key Takeaways

- **Keep build execution off the controller.**
- **Labels schedule work; authorization enforces trust boundaries.**
- **Separate untrusted verification from credential-bearing releases.**
- **Short-lived credentials reduce exposure, not excessive privilege.**
- **Version JCasC and plugins, and protect recovery secrets.**
- **Test agent isolation and role assumption explicitly.**

## References

- Jenkins controller isolation: [Documentation](https://www.jenkins.io/doc/book/security/controller-isolation/)
- JCasC: [Documentation](https://github.com/jenkinsci/configuration-as-code-plugin)
