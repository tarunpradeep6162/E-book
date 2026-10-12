# Run in the workload root after bootstrap completes.
umask 077
terraform init -migrate-state

# Confirm migration did not introduce ownership changes.
terraform plan -lock-timeout=60s
