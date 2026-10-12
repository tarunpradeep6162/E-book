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
