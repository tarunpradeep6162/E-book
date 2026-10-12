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
