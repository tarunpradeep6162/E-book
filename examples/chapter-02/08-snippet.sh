terraform init

# Record package checksums for the team's actual execution platforms.
terraform providers lock   -platform=linux_amd64   -platform=darwin_arm64

terraform fmt -check -recursive
terraform validate
terraform plan -out=reviewed.tfplan
terraform show reviewed.tfplan
