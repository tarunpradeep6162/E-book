mkdir -p secrets
chmod 700 secrets
umask 077
# Generate locally; do not print the secret into shared logs.
openssl rand -base64 32 > secrets/postgres-password
