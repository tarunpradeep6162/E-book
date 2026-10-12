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
