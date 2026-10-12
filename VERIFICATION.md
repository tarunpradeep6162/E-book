# Verification - illustrated edition

## Passed

- Exactly 22 chapters, each within 1,500-2,000 whitespace-counted words including tables/code.
- Markdown fences, chapter ordering, and Chapter 2 companion consistency.
- 79 extracted examples passed applicable YAML parsing, Python parsing, Bash syntax, or Terraform HCL parsing/format processing. Results: static-check-results.json.
- Python fixture: readiness JSON, unknown-path rejection, and SIGTERM completion through two runtime tests.
- Full PDF and EPUB built with Pandoc 3.1.3 and XeLaTeX.
- PDF reviewed as page contact sheets; long reference/code overflows repaired. Automated text bounds check found zero words outside pages in the final build.
- EPUB container and XML structure checks.
- EPUBCheck 5.3.0 completed with zero fatal errors, errors, warnings, or informational messages.

## Blocked

Terraform provider-backed validate and mock-provider tests remain blocked by an installed AWS 6.66.0 package checksum mismatch. Reinstalling through ordinary signed-registry initialization did not resolve the subsequent cache verification failure. No checksum check was disabled; no AWS plan/apply occurred. Do not treat HCL parsing as provider-schema or cloud verification. Review provider lock selections and investigate this in a clean trusted environment.

## Pending operational gates

- Jenkins declarative/JCasC compatibility against a pinned real controller/plugin set.
- Docker image build/scan using real reviewed base digests; no placeholder digest is executable.
- Kubernetes server-side admission, CNI enforcement, CSI behavior, and real cluster tests.
- AWS/Azure/GCP provider schema validation, quotas, identities, network routes, and live applies.
- FortiGate licensing, routing, throughput, and HA testing.
- Database replication, fencing, promotion, DNS failover, and measured RPO/RTO game days.
- Kindle Previewer and final publication-cover review.

## Scope

The complete manuscript and companion snippets are finished as an educational review edition. They do not constitute a verified production deployment. Partial templates and integration prerequisites are labeled in the chapter and companion manifest. No paid cloud resources or publishing accounts were created.

## Illustrated-edition checks

- Seven diagrams generated as editable SVG and vector PDF, used in eight chapter locations.
- Diagram source distinguishes Terraform provisioning from workload deployment, zonal volume attachment from recovery, and asynchronous self-managed standby replication from managed-service assumptions.
- Inter and JetBrains Mono embedded/bundled with font licenses; red warning, green pro-tip, and dark takeaway panels applied.
- All 22 chapter word-count bounds still pass after additions.
- Recovery explorer gate tests pass using a DOM stub: either missing prerequisite blocks promotion, and revoking a prerequisite returns to the fencing stage. This is logic verification, not a real-cloud or browser-device certification.
- Illustrated EPUB passed EPUBCheck 5.3.0 after external SVG DOCTYPE declarations were removed.
- Final PDF text-bound check and rendered-page review were repeated. Prior live-infrastructure limitations remain unchanged.
