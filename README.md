# Scaling Multi-Cloud

**The Engineer's Guide to Docker, Jenkins, and Infrastructure as Code**

Author: Tarun Pradeep B. Illustrated edition: 22 chapters, 1,500-2,000 words each (whitespace count including code and tables).

## Read

- [PDF](releases/scaling-multi-cloud.pdf) and [EPUB](releases/scaling-multi-cloud.epub)
- Chapters: [chapters/](chapters/)
- Companion examples: [examples/](examples/)
- Review evidence and limitations: [VERIFICATION.md](VERIFICATION.md)
- Companion manifest: [examples/manifest.json](examples/manifest.json)

Examples are scoped teaching material, not an automatically deployable production platform. Read each chapter's prerequisites. Replace reviewed identifiers/digests; never fabricate provider lock hashes or use production data in fault exercises.

## Build

Tested environment: Pandoc 3.1.3, XeLaTeX, Python 3, bundled Inter/JetBrains Mono fonts, titlesec, tcolorbox, fvextra and xurl. No cloud credentials are needed to build the manuscript.

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

## Visual learning edition

Seven editable SVG architecture diagrams plus vector PDF counterparts are in images/. Figures appear in Chapters 1, 4, 8, 12, 15, 16, 20 and 21. The book now has red WARNING, green PRO TIP, and dark Key Takeaways callouts. Longer configuration examples are shown as sequential panels; complete companion files remain available under examples/.

The self-contained [recovery explorer](interactive/failover.html) is a teaching simulation. Download the HTML and open it locally; GitHub's source viewer does not execute it. It performs no cloud operations and requires fencing plus recovery-point confirmation before displaying promotion.

The failover model is self-managed PostgreSQL with asynchronous standby replication. It does not claim native synchronous RDS-to-Azure managed-database replication. Its RPO/RTO values are the book's targets, not demonstrated measurements.

Builds require Pandoc 3.x and TeX Live's extra LaTeX packages. The bundled fonts include their licenses. generate_diagrams.py requires ReportLab only when regenerating figures; the normal build uses checked-in SVG/PDF assets. add_visual_learning.py is a one-time authoring migration and skips already wrapped chapters.
