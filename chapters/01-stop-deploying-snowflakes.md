# Chapter 1: Stop Deploying Snowflakes: Design the Platform Before the Pipeline

::: {.callout .failure}
## 03:07: The Server Nobody Can Rebuild

The order API stops responding at 03:07. Your EC2 instance has failed, and the replacement starts with an empty application directory. The engineer who configured the original machine left six months ago.

Git contains the application, but nobody knows which commit was running. PostgreSQL lived on the same server. A cron job supposedly copied backups somewhere; its credentials and destination were configured interactively.
:::

You are rebuilding an undocumented system under pressure. Improvised fixes create undocumented dependencies.

**A server is replaceable only when its configuration, artifacts, access requirements, and recovery procedures exist outside it.**


## Architecture at a Glance

![Separate cloud ownership, workload releases, and durable data.](images/01-before-after.svg){width=100%}



The public companion repository contains the exact code examples.

```bash
git clone https://github.com/tarunpradeep6162/E-book.git
cd E-book/examples
```

## Four Lifecycles, Four Owners

Our reference workload contains an HTTP order API, a background worker, and PostgreSQL. The API commits orders and work records; idempotent workers process pending work. 

Separate the platform into four lifecycles:

| Lifecycle | Contents | Change mechanism | Recovery mechanism |
| --- | --- | --- | --- |
| Application | API, worker, dependencies, migrations | Tested commit becomes an immutable image | Redeploy a known image digest |
| Infrastructure | Networks, compute, IAM, storage resources | Reviewed Terraform plan and apply | Reconcile definitions with protected state |
| Runtime configuration | Endpoints, feature flags, limits, secret references | Validated environment configuration | Restore approved configuration; recover secrets separately |
| Persistent data | Orders, work records, database files | Application transactions and controlled migrations | Restore backups and replay retained database logs |

### Application Code: Promote an Artifact

Build an image once and promote the same digest through environments. Rebuilding for production introduces another dependency-resolution event and weakens the relationship between tested and deployed software.

Keep database migration code with the application, but give migration execution its own release step. An application rollback does not reverse a schema change safely. Prefer additive changes first, migrate consumers, and remove obsolete structures in a later release.

**Application version, configuration version, and schema version must be traceable together.**

### Infrastructure: Define Ownership Before Automation

Terraform owns resource configuration and its association with remote resource identities. Its state is an operational record, not a database backup and not a complete substitute for configuration.

Separate state by meaningful operational boundaries: bootstrap services, shared networking, and workload infrastructure. Give each root configuration a named owner and authorized apply path. Do not let two roots manage the same resource.

### Runtime Configuration: Change Behavior Without Rebuilding

Inject validated configuration at startup. Keep environment endpoints and database passwords outside the image.

Version non-secret configuration. Store only secret references in Git, with secret values held in a dedicated secret manager. Document who creates, rotates, retrieves, and recovers those secrets.

### Persistent Data: Protect It from Replacement

Container filesystems, VM boot disks, persistent volumes, and backups have different failure boundaries. A Docker volume can survive container replacement while remaining vulnerable to host failure or deletion.

Define data retention and destruction rules explicitly. Production database deletion should require a separate authorized workflow, and backups must remain recoverable if the primary environment becomes inaccessible.

**Replacing compute must not imply deleting business data.**

## Set Targets Before Choosing Services

Availability and recovery objectives describe different requirements. Availability concerns how often users receive usable service; disaster recovery concerns how much interruption and data loss the business accepts after a defined failure.

For this book, use provisional targets that must later be demonstrated:

| Objective | Proposed target | Measurement |
| --- | --- | --- |
| Order API availability | 99.9% over a rolling 30 days | Successful eligible requests / total eligible requests |
| API latency | 95th percentile below 300 ms at 100 requests/s | Load test with a documented request mix |
| Production disaster RTO | 60 minutes | Interruption to validated order creation and processing |
| Production disaster RPO | 5 minutes | Gap between failure time and newest recoverable committed data |
| Jenkins recovery | RTO 4 hours; RPO 24 hours | Restore controller configuration and resume a test pipeline |

Request-based availability and downtime calculations differ. A separate time-based 99.9% target over 30 days permits approximately 43 minutes of unavailability.

**RTO includes detection, decision-making, provisioning, restoration, and validation.** A restore command completing in fifteen minutes does not prove a fifteen-minute RTO.

RPO describes acceptable loss measured in time. If the latest recoverable database point is 03:02 and the failure occurs at 03:07, the recovery gap is five minutes. A successful nightly backup cannot establish a five-minute RPO without another recovery mechanism.

Recovery objectives should be defined per workload and used to select recovery strategies.[1] Our initial single-cloud labs will not claim these production targets; they establish components that later recovery exercises will test.

## Draw Trust Boundaries Around Identities

A private subnet is a network placement decision, not an authorization policy. Model what each identity can do after compromise.

Separate production and non-production accounts. Isolate build agents from the controller, and never expose production credentials to untrusted pull requests.

Define these boundaries:

| Boundary | Allowed interaction | Required control |
| --- | --- | --- |
| Internet → API entry point | Authenticated order requests over HTTPS | TLS, authentication, input validation, rate limits |
| Entry point → API | Forward application traffic | Restricted origin access |
| API/worker → PostgreSQL | Required database operations | Private connectivity, TLS, separate least-privilege roles |
| Build agent → registry | Publish approved build artifacts | Scoped temporary credentials where supported |
| Release agent → production | Apply approved release or infrastructure change | Separate roles, review gate, audit trail |
| Operator → administration | Approved administrative sessions | MFA, restricted access, logged emergency procedure |

Network policies and firewalls reinforce these boundaries; they do not replace application authorization. A FortiGate inspection path must have documented routes and return paths. A firewall deployed outside the actual traffic path provides no protection to that flow.

## Hands-On: Create the Platform Repository

Run the following from a directory where a new platform repository should be created:

```bash
mkdir -p platform
cd platform
git init

# Separate lifecycles so releases cannot silently absorb infrastructure changes.
mkdir -p apps/{api,worker} infra/{bootstrap,modules}
mkdir -p infra/environments/{dev,staging,prod}/{aws,azure}

# Commit configuration contracts, never recovered data or secret values.
mkdir -p config/environments deploy/{compose,kubernetes}
mkdir -p ci docs/{architecture,runbooks} tests/architecture

touch README.md docs/architecture/{environment-matrix,dependency-map,threat-model,acceptance-criteria}.md
touch docs/runbooks/{restore-database,restore-jenkins,emergency-access}.md
```

The resulting ownership structure is:

```text
platform/
├── apps/                 # Application code and schema migration code
├── infra/
│   ├── bootstrap/        # State storage and foundational access
│   ├── modules/          # Reusable resource definitions
│   └── environments/     # Independent cloud/environment roots
├── config/environments/  # Non-secret values and secret references
├── deploy/               # Compose and Kubernetes workload definitions
├── ci/                   # Jenkinsfiles and agent configuration
├── docs/
│   ├── architecture/     # Contracts, dependencies, threats, acceptance gates
│   └── runbooks/         # Procedures executable by another engineer
└── tests/architecture/   # Boundary and recovery verification
```

Add a starting `.gitignore`:

```gitignore
# Terraform caches, plans, and state can expose infrastructure and secrets.
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
crash.log

# Preserve examples while excluding local secret-bearing configuration.
.env
.env.*
!.env.example

# Recovery artifacts belong in protected storage, never source control.
backups/
*.sql
*.dump
*.pem
*.key
```

### Define the Environment Matrix

Copy this table into `docs/architecture/environment-matrix.md`. These are planned contracts, not deployed capabilities.

| Property | Development | Staging | Production |
| --- | --- | --- | --- |
| Cloud scope | AWS sandbox | Separate AWS account | AWS primary; Azure recovery later |
| Data | Synthetic | Synthetic representative dataset | Customer orders |
| Deploy authority | Developer pipeline | Release pipeline | Approved release pipeline |
| Terraform state | Dedicated dev roots | Dedicated staging roots | Separate AWS/Azure production roots |
| Identity | Dev-scoped roles | Staging-scoped roles | Production-scoped roles; MFA administration |
| Capacity | Minimal, scheduled shutdown | Production-like during tests | Sized from measured demand |
| Recovery target | Rebuild; disposable data | Restore drill ≤ 2 hours | RTO 60 min; RPO 5 min |
| Deletion | Automated cleanup allowed | Owner-approved reset | Separate authorized destruction workflow |

### Record the Dependency Map

Copy this into `docs/architecture/dependency-map.md`:

```markdown
# Dependency Map

Arrows mean "depends on", not packet direction.

## Bootstrap and provisioning
Terraform execution -> cloud authentication
Terraform workload roots -> protected state backend
Workload provisioning -> networking and IAM
State backend recovery -> independently accessible backup and credentials

## Build and release
Jenkins controller -> persistent home, authentication, configuration backup
Build agent -> source repository, dependency sources, image registry
Release agent -> approved image digest, environment config, deployment API

## Runtime
Public entry point -> DNS, certificate, healthy API instances
API -> secret retrieval, PostgreSQL
Worker -> secret retrieval, PostgreSQL
Database recovery -> backup storage, retained logs, decryption authorization

## Failure contracts
- Existing workloads must run when Jenkins is unavailable.
- Rebuilding Jenkins must not require a successful Jenkins pipeline.
- Restoring state storage must not require the unavailable state backend.
- Restoring PostgreSQL must not require the failed primary database.
```

Bootstrap dependencies deserve special attention. Record an independently authenticated procedure for recreating backend access and restoring state. Otherwise your recovery system depends on the component it must recover.

### Copy the Threat-Model Template

Create `docs/architecture/threat-model.md`:

```markdown
# Architecture Threat Model

## Scope
Workload: Order API, worker, PostgreSQL, Jenkins, Terraform
Owner: <named team>
Reviewed: <date and architecture revision>
Assumptions: <identity provider, cloud scope, data classification>
Out of scope: <explicit exclusions and responsible owners>

## Protected assets
| Asset | Consequence of compromise | Owner |
|---|---|---|
| Customer orders | Disclosure, deletion, unauthorized modification | Application team |
| Terraform state | Sensitive-value exposure, ownership manipulation | Platform team |
| Deployment identity | Unauthorized production changes | Platform team |
| Database backups | Data exposure or loss of recovery capability | Database owner |

## Trust boundaries
For each flow record:
source identity -> destination -> protocol -> authorization -> audit evidence

## Threat register
| Threat | Control | Verification | Residual risk / owner |
|---|---|---|---|
| Malicious PR steals production credentials | Untrusted builds isolated from release roles | PR job cannot obtain production session | Agent compromise / platform |
| Runtime identity deletes backups | Backup administration separate from runtime | Authorization-policy test in sandbox | Backup admin compromise / database owner |
| Secret committed to Git | Secret references, scanning, rotation procedure | Seeded test secret blocked before merge | Scanner gaps / application |
| Order retried after timeout | Idempotency key and transactional uniqueness | Repeat request creates one order | External side effects / application |

## Recovery and review
Backup location and access owner: <reference>
Emergency access procedure: <runbook>
Recovery evidence: <test date and results>
Open risks: <owner, decision, deadline>
Review triggers: identity change, new public endpoint, storage change
```

## Acceptance Gates: Make the Architecture Falsifiable

Finish `acceptance-criteria.md` with concrete gates:

1. **Rebuild:** another engineer can identify every required input without accessing the original host.
2. **Traceability:** each deployment records image digest, configuration revision, schema version, and infrastructure revision.
3. **Isolation:** a development identity cannot read production secrets or state.
4. **Persistence:** replacing application compute preserves committed orders.
5. **Recovery:** database and Jenkins restores are tested with timestamps and functional checks.
6. **Independence:** existing workloads continue serving when Jenkins is unavailable.

At this stage, review repository completeness and assign owners. Mark operational gates **unverified** until later labs produce evidence. An empty runbook is unfinished work, and a successful Terraform apply is not proof of recoverability.

## References

[1] AWS Well-Architected Framework, “Define recovery objectives for downtime and data loss”: [Documentation](https://docs.aws.amazon.com/wellarchitected/latest/framework/rel_planning_for_recovery_objective_defined_recovery.html)

