terraform output -raw instance_id
aws ssm describe-instance-information
# Replace the ID with this root's output.
aws ssm start-session --target i-REPLACE
