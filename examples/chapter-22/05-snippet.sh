# Execute on the approved lab controller host, not production.
sudo systemctl stop jenkins-container
# Restore the service only after the persistent mount is verified.
findmnt /srv/jenkins
sudo systemctl start jenkins-container
