export PYTHON_BASE='python:REVIEWED_TAG@sha256:REVIEWED_DIGEST'
docker compose config --quiet
docker compose build --pull
docker compose up -d
curl --fail http://127.0.0.1:8080/readyz
docker compose logs --no-color api
