# Inspect observed drift without proposing configuration-driven repairs.
terraform plan -refresh-only

# Compare configuration with refreshed infrastructure before authorizing writes.
terraform plan -out=reviewed.tfplan
terraform show reviewed.tfplan
