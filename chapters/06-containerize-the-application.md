# Chapter 6: Build Once, Run Consistently: Containerize the Application

## Friday's Different Runtime

The release worked on the developer's laptop. Production fails during startup because the deployment server resolves a newer dependency, uses a different interpreter, and lacks a shared library. Someone installs packages directly on the host while customers retry their orders.

The next deployment fails differently. Yesterday's emergency packages remain, but nobody recorded them. The server is now an undocumented build environment and runtime simultaneously.

Containers address packaging consistency; they do not eliminate architecture, kernel, networking, or configuration differences. **Build a reviewed artifact once, then deploy that artifact by immutable digest.** Do not build production from whichever source happens to be on the server.

## Define the Application Contract

This chapter uses a small Python HTTP API with the standard library, keeping the example executable without fabricating dependency hashes. The API demonstrates readiness, health, environment configuration, and termination. It is a teaching service, not the full order API: database transactions and authentication arrive in a real application implementation.

A production dependency set must be locked and verified separately. For Python packages, use an approved lock workflow and hashed requirements for the selected platform. Native dependencies can differ by architecture; testing on an ARM laptop does not validate an AMD64 release.

The process listens on port 8080, exposes `/healthz` and `/readyz`, writes no persistent data locally, and reads configuration at startup. The real order service must make readiness represent its ability to serve requests without turning every transient database slowdown into mass restart behavior.

### app.py

```python
import json
import os
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ready = True

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ('/healthz', '/readyz', '/'):
            self.send_error(404)
            return
        code = 200 if self.path != '/readyz' or ready else 503
        body = json.dumps({'status': 'ok', 'service': 'orders-api'}).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = ThreadingHTTPServer(('0.0.0.0', int(os.getenv('PORT', '8080'))), Handler)

def stop(signum, frame):
    global ready
    ready = False
    # shutdown must run outside serve_forever's thread to avoid deadlock.
    threading.Thread(target=server.shutdown, daemon=True).start()

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    server.serve_forever()
finally:
    server.server_close()
```

This fixture is intentionally small. Replace the server with your reviewed application framework and production serving stack when introducing real traffic. Set bounded request timeouts, authentication, input limits, and dependency pools; packaging does not supply those controls automatically.

## Separate Build Tools from Runtime

Multi-stage builds separate tools needed to construct software from tools needed to execute it. Compilers, source-control clients, and development dependencies should not automatically enter the runtime image.

The example compiles Python sources in the build stage and copies only the application into runtime. Both stages use the same approved base reference to avoid an interpreter mismatch. Since this application has no external packages, a dependency lock file is unnecessary here; adding packages changes that obligation.

### Dockerfile

```dockerfile
# Supply a verified digest, e.g. python:<reviewed-tag>@sha256:<digest>.
ARG PYTHON_BASE
FROM ${PYTHON_BASE} AS build
WORKDIR /src
COPY app.py ./app.py
RUN python -m compileall -q /src

FROM ${PYTHON_BASE} AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080
WORKDIR /app
# Numeric identity works without relying on host user names.
RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid 10001 --no-create-home app
COPY --from=build --chown=10001:10001 /src/ /app/
USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGTERM
# Exec form makes Python receive the container's termination signal.
CMD ["python", "/app/app.py"]
```

Select a Debian-based official Python image with the `groupadd` and `useradd` tools; do not substitute an Alpine base without changing those commands. The required build argument avoids silently using a floating default. Store the approved digest in reviewed build configuration.

### .dockerignore

```text
.git
.env
.env.*
!.env.example
*.pem
*.key
__pycache__
.venv
backups
terraform.tfstate*
*.tfplan
```

A small build context reduces accidental inclusion and improves caching. Ignore rules are not a secret scanner. A credential copied into an earlier layer can remain recoverable after deletion in a later layer. Use BuildKit secret mounts for build-time authentication, and ensure build tools never echo or persist those values.

## Local Development Without Public Databases

Compose provides a reproducible local topology. It does not provide production high availability, cloud identity, or a disaster-recovery plan. Separate local convenience from deployment expectations.

### docker-compose.yml

```yaml
services:
  api:
    build:
      context: .
      args:
        PYTHON_BASE: ${PYTHON_BASE:?Set an approved Python digest}
    ports:
      - "127.0.0.1:8080:8080" # Restrict the development listener.
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=16m
    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    stop_grace_period: 30s
    environment:
      PORT: "8080"
    healthcheck:
      test:
        - CMD
        - python
        - -c
        - "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"
      interval: 10s
      timeout: 3s
      retries: 3
```

There is no bind mount over `/app` in this release-like topology. A developer may add an explicit override with source mounting and reload behavior, but must understand that it bypasses the built artifact. Never test a bind-mounted tree and assume the separately built image contains identical files.

## Build, Test, and Record the Artifact

Use an actual approved digest, not the placeholder text below. A digest establishes identity, not trust: review the publisher, provenance, architecture, and vulnerability findings.

```bash
export PYTHON_BASE='python:REVIEWED_TAG@sha256:REVIEWED_DIGEST'
docker compose config --quiet
docker compose build --pull
docker compose up -d
curl --fail http://127.0.0.1:8080/readyz
docker compose logs --no-color api
```

Verify the container executes as UID 10001 and writing to `/app` fails. Confirm `/tmp` is the only writable temporary location you intended. Test termination with an in-flight request and check the process exits before the grace period expires.

```bash
docker compose exec api id
docker compose stop -t 30 api
docker compose up -d
```

A production API must stop accepting new work, drain active requests, and release connections. Workers must stop claiming new jobs, complete or safely abandon current work, and acknowledge only after durable side effects. SIGTERM handling and idempotency are linked: a forced shutdown must not silently lose an acknowledged order.

## Promote, Do Not Rebuild

CI builds the image, tests it, scans it, and pushes it to a registry. Record the registry digest and deploy `repository@sha256:...`. A Git commit tag is useful traceability but can still be overwritten unless registry policy prevents it.

Maintain an evidence record containing source commit, base digest, build platform, dependency lock revision, test results, scan policy, and final image digest. A release approval covers that record and its configuration, not just a human-readable tag.

Multi-platform releases require testing each supported platform or a documented test strategy. Emulated tests may be slower and do not prove all native performance behavior. Build-cache reuse also must not introduce secret material or untrusted artifacts into a trusted release.

Keep runtime secrets outside images. Inject short-lived credentials or secret references through the deployment platform. Environment variables may be inspectable by administrators; mounted secret files still need access controls and rotation handling. Choose based on the actual threat model.

Persistent data belongs outside the writable layer. Application logs go to standard output or a configured collection path, with retention owned by the logging system. Avoid writing database files, uploaded customer documents, or release identity into a disposable container filesystem.

Cleanup with `docker compose down`; this example has no persistent volumes. Once a database is added, never casually add `--volumes`. The next chapter explains why that option belongs in a deliberate data-destruction procedure.

## A Dependency Change Is a New Release

When the application gains external packages, introduce a reviewed dependency lock and build from that lock. A file listing only broad version ranges allows package resolution to change independently of the application commit. That weakens the claim that the same source produces the same artifact.

For packages fetched from a private index, supply authentication through a build secret mount and confirm the installer does not write credentials into configuration copied to runtime. Inspect the resulting image filesystem and history using a synthetic credential during a controlled test. Do not experiment with a real production token.

Native extensions require compatible runtime libraries. A builder may compile successfully against a library absent from the final image. Run the actual final image's import and startup tests instead of concluding success from the build stage.

Track rebuild triggers separately from application changes. A base-image security update creates a new artifact and needs verification even if business code is unchanged. Retain the old approved digest until rollback and recovery policies permit deletion.

Image size is an operational input: larger images increase cold-start transfer time and registry dependence during recovery. Measure compressed pull size and startup duration on the intended node environment. Do not optimize size by removing certificate authorities or diagnostic capability without understanding the consequences.

The release fixture deliberately avoids pretending that a fabricated lock file proves dependency integrity. Once dependencies are real, their ownership, updates, and verification become part of the repository's acceptance gates.

## Key Takeaways

- **Containers package an execution contract; they do not prove production readiness.**
- **Pin the base image and promote the tested final digest.**
- **Keep build tools, secrets, and durable data outside runtime layers.**
- **Run non-root with explicit writable locations and minimal capabilities.**
- **Test signal handling, readiness, and the actual built image.**
- **Treat dependency and architecture selection as reviewed inputs.**

## References

- Docker multi-stage builds: [Documentation](https://docs.docker.com/build/building/multi-stage/)
- Build secrets: [Documentation](https://docs.docker.com/build/building/secrets/)
