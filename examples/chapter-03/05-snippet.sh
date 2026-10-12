umask 077
export STATE_BUCKET="orders-prod-state-123456789012"
export STATE_KEY="prod/aws/orders/terraform.tfstate"

aws s3api list-object-versions   --bucket "$STATE_BUCKET" --prefix "$STATE_KEY"

# Replace VERSION_ID; candidate.json contains sensitive state.
aws s3api get-object   --bucket "$STATE_BUCKET" --key "$STATE_KEY"   --version-id VERSION_ID candidate.json

terraform state pull > current.json

# Stops on incompatible lineage or an older serial.
terraform state push candidate.json
