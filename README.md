# Scaling Multi-Cloud

**The Engineer's Guide to Docker, Jenkins, and Infrastructure as Code**

Author: Tarun Pradeep B. First complete manuscript: 22 chapters, 1,500-2,000 words each (whitespace count including code and tables).

## Read

- [PDF](releases/scaling-multi-cloud.pdf) and [EPUB](releases/scaling-multi-cloud.epub)
- Chapters: [chapters/](chapters/)
- Companion examples: [examples/](examples/)
- Review evidence and limitations: [VERIFICATION.md](VERIFICATION.md)
- Companion manifest: [examples/manifest.json](examples/manifest.json)

Examples are scoped teaching material, not an automatically deployable production platform. Read each chapter's prerequisites. Replace reviewed identifiers/digests; never fabricate provider lock hashes or use production data in fault exercises.

## Build

Tested environment: Pandoc 3.1.3, XeLaTeX, Python 3, DejaVu fonts, fvextra and microtype. No cloud credentials are needed to build the manuscript.

```bash
bash scripts/build.sh
```

Outputs: dist/scaling-multi-cloud.pdf and dist/scaling-multi-cloud.epub. The build orders chapters numerically, checks source fences, verifies Chapter 2/download consistency, checks all chapter lengths, and inspects EPUB XML/container structure.

Jenkinsfile runs these checks on an agent labeled ebook-builder with the documented toolchain. It archives artifacts and never publishes to a sales platform or deploys cloud infrastructure. Configure agent tools and artifact access before using it.

## Validation scope

Terraform formatting and parse checks are separate from provider-backed validate/plan. Kubernetes YAML parsing is separate from server admission and live behavior. EPUB structure checks are not EPUBCheck certification. See VERIFICATION.md for exact passed, blocked, and pending results.

## Publication gates

Review the full manuscript and examples; rerun EPUBCheck after changes and use Kindle Previewer; confirm all device code rendering; commission/review a final cover; verify author/rights metadata; execute applicable labs under authorized isolated accounts. The portrait marketing cover target is 1600 pixels wide by 2560 high. No final cover or publishing credentials are included.

## Security

No secrets, state files, provider caches, saved plans, customer records, or disk images belong in Git. The examples include explicit placeholders instead of credentials. Commands that format storage, delete resources, or promote databases are restricted to the stated verified lab/recovery scope.
