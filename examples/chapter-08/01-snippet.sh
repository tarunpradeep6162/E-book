lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
sudo nvme list
# Replace only after matching the approved EBS volume ID and size.
export JENKINS_DEVICE=/dev/nvmeREPLACE
sudo wipefs --no-act "$JENKINS_DEVICE"
sudo blkid "$JENKINS_DEVICE" || true
