sudo cp /etc/fstab /etc/fstab.before-jenkins
# Replace UUID_FROM_BLKID with the actual value.
printf '%s\n' \
  'UUID=UUID_FROM_BLKID /srv/jenkins ext4 defaults 0 2' \
  | sudo tee -a /etc/fstab
sudo findmnt --verify
sudo mount -a
findmnt /srv/jenkins
