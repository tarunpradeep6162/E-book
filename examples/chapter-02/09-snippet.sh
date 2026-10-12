# Apply the reviewed saved plan rather than generating a different plan.
terraform apply reviewed.tfplan

# Confirm convergence; inspect any unexpected remaining actions.
terraform plan -detailed-exitcode
