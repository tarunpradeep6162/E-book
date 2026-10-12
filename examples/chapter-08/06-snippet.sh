mountpoint -q /srv/jenkins || exit 1
docker run -d --name jenkins --init \
  --publish 127.0.0.1:8080:8080 \
  --mount type=bind,src=/srv/jenkins/home,dst=/var/jenkins_home \
  "$JENKINS_IMAGE"
