# DESTRUCTIVE: only for a verified new empty EBS volume.
sudo mkfs.ext4 "$JENKINS_DEVICE"
sudo mkdir -p /srv/jenkins
sudo mount "$JENKINS_DEVICE" /srv/jenkins
sudo blkid -s UUID -o value "$JENKINS_DEVICE"
