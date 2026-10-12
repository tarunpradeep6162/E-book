export JENKINS_IMAGE='jenkins/jenkins:REVIEWED_LTS@sha256:REVIEWED_DIGEST'
docker run --rm --entrypoint id "$JENKINS_IMAGE"
sudo mkdir -p /srv/jenkins/home
# Use 1000:1000 only after confirming the selected image's identity.
sudo chown 1000:1000 /srv/jenkins/home
sudo chmod 750 /srv/jenkins/home
