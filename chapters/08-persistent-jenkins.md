# Chapter 8: Jenkins That Survives Monday: Docker Volume Persistence on EC2

## The Spot Termination That Erased CI

A Spot interruption terminates the EC2 instance hosting Jenkins. The replacement image contains Docker and Jenkins, but no jobs, plugins, credentials, or build history. Every deployment pipeline depended on files inside the terminated instance's root disk.

The root EBS volume was configured to delete on termination. The team had a container restart policy and believed it had persistence. That policy restarts a process on a surviving host; it does not recover a deleted disk.

**Ephemeral compute requires separately owned storage and independently recoverable backups.** A retained EBS volume addresses one failure boundary. An AZ outage, encryption-key loss, or compromised administrator still demands a different recovery path.

## Own the Controller's Data

Jenkins stores its configuration under `/var/jenkins_home` in the official container image. Jobs, plugin binaries, build metadata, credentials, and encryption material live beneath that home. The exact contents matter: restoring encrypted credentials without the corresponding key material does not restore usable credentials.

Use encrypted EBS for the controller's persistent home, retained independently of the root disk. Prefer predictable On-Demand controller capacity unless the interruption and restore procedure is genuinely acceptable. Spot can be valuable for disposable agents, where interrupted work is retried safely.

Place the controller in a private subnet. Use SSM for administration and an authenticated TLS entry point for users. Do not expose port 8080 to the internet. The command below binds only to host loopback; a separate trusted reverse proxy must provide the external authenticated route.

Set built-in executors to zero in Chapter 9. Controller persistence does not justify executing arbitrary builds there. Docker-daemon access is highly privileged and belongs only on deliberately isolated build infrastructure.

## Select the Disk Before Formatting

On Nitro instances, EBS devices appear as NVMe devices, and Linux names may change. Never assume `/dev/nvme1n1` is the new empty disk because a blog used that path.

Identify the provisioned volume using the EC2 attachment, NVMe serial information, and expected size. Verify it has no mounted filesystem or existing data. The following commands use a variable to force explicit device selection.

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,SERIAL
sudo nvme list
# Replace only after matching the approved EBS volume ID and size.
export JENKINS_DEVICE=/dev/nvmeREPLACE
sudo wipefs --no-act "$JENKINS_DEVICE"
sudo blkid "$JENKINS_DEVICE" || true
```

`wipefs --no-act` inspects signatures without erasing them. If a filesystem exists, stop and investigate. A restored EBS volume should be mounted, not formatted. Formatting is a destructive one-time action on a confirmed blank lab disk.

```bash
# DESTRUCTIVE: only for a verified new empty EBS volume.
sudo mkfs.ext4 "$JENKINS_DEVICE"
sudo mkdir -p /srv/jenkins
sudo mount "$JENKINS_DEVICE" /srv/jenkins
sudo blkid -s UUID -o value "$JENKINS_DEVICE"
```

Capture the returned UUID. It identifies the filesystem across device-name changes. Check cloud volume encryption separately; an ext4 UUID says nothing about KMS access or EBS encryption.

## Mount Reliably and Fail Closed

Add one reviewed entry to `/etc/fstab`. Back up the existing file and avoid adding duplicate entries during repeated provisioning.

```bash
sudo cp /etc/fstab /etc/fstab.before-jenkins
# Replace UUID_FROM_BLKID with the actual value.
printf '%s\n' \
  'UUID=UUID_FROM_BLKID /srv/jenkins ext4 defaults 0 2' \
  | sudo tee -a /etc/fstab
sudo findmnt --verify
sudo mount -a
findmnt /srv/jenkins
```

The omission of `nofail` is intentional: silently starting Jenkins on an unmounted directory can create a second home on the root disk. Boot behavior should match your operational preference, but the service must always fail closed when the intended filesystem is unavailable.

For automated startup, use a service dependency that requires the mount. A plain Docker restart policy can race storage mounting after reboot. Use systemd to control the container lifecycle and omit Docker's automatic restart policy when systemd owns retries.

```ini
# /etc/systemd/system/jenkins-container.service
[Unit]
Description=Persistent Jenkins controller
Requires=docker.service
After=docker.service
RequiresMountsFor=/srv/jenkins

[Service]
EnvironmentFile=/etc/jenkins-container.env
ExecStartPre=/usr/bin/mountpoint -q /srv/jenkins
ExecStartPre=-/usr/bin/docker rm jenkins
ExecStart=/usr/bin/docker run --name jenkins --init --publish 127.0.0.1:8080:8080 --mount type=bind,src=/srv/jenkins/home,dst=/var/jenkins_home --env JAVA_OPTS=-Djenkins.install.runSetupWizard=true ${JENKINS_IMAGE}
ExecStop=/usr/bin/docker stop --time 60 jenkins
Restart=on-failure
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
```

Set `JENKINS_IMAGE` in the environment file to an approved official Jenkins LTS image digest. This file contains image configuration, not cloud keys. Match the Docker binary path to the distribution before enabling the unit.

## Match Ownership to the Image

The official Jenkins image normally uses UID/GID 1000. Verify the actual selected image rather than trusting a universal number.

```bash
export JENKINS_IMAGE='jenkins/jenkins:REVIEWED_LTS@sha256:REVIEWED_DIGEST'
docker run --rm --entrypoint id "$JENKINS_IMAGE"
sudo mkdir -p /srv/jenkins/home
# Use 1000:1000 only after confirming the selected image's identity.
sudo chown 1000:1000 /srv/jenkins/home
sudo chmod 750 /srv/jenkins/home
```

For a manual first start, use the following command instead of starting the systemd service simultaneously:

```bash
mountpoint -q /srv/jenkins || exit 1
docker run -d --name jenkins --init \
  --publish 127.0.0.1:8080:8080 \
  --mount type=bind,src=/srv/jenkins/home,dst=/var/jenkins_home \
  "$JENKINS_IMAGE"
```

The `--mount` form rejects a nonexistent bind source rather than conveniently creating an unexpected directory. The mountpoint check prevents writing into the root filesystem when EBS is absent. Do not mount the host Docker socket into the controller to make a pipeline work.

Retrieve the initial administrator secret through the protected administrative session. Do not paste it into CI logs or the repository. Complete setup through the approved private access route, then configure authentication, authorization, TLS, and controller executors before onboarding users.

## Demonstrate Replacement Survival

Create a disposable test job, stop Jenkins cleanly, remove only the container, and start the exact same image with the same mount. Verify the job and configuration remain.

```bash
docker stop --time 60 jenkins
docker rm jenkins
# Repeat the manual docker run command using the same mount and image.
```

Reboot the instance after configuring the systemd unit. Confirm the EBS filesystem mounts before Jenkins starts. Deliberately test a missing-volume scenario in a lab: Jenkins must fail to start, not create a new empty home.

Moving a retained EBS volume requires a replacement instance in the same AZ. Stop the old writer and detach cleanly before attaching elsewhere. Never start two controllers against the same home. EBS volume attachment does not implement an active-active Jenkins architecture.

## Backup and Recovery Are Separate

For this single-controller lab, stop Jenkins to take a consistent home backup, or use an explicitly supported consistency procedure. EBS snapshots alone do not guarantee application-consistent content unless quiescing and filesystem behavior are addressed.

Protect the entire required home, including credential encryption material, while restricting who can read backups. Prefer configuration-as-code and versioned job definitions to reduce the amount of irreplaceable manual configuration. Plugins need a reviewed version inventory; restoring a home with incompatible runtime or plugins can fail even when files exist.

Rehearse restoring an encrypted snapshot to a new EBS volume, attaching it to a replacement host, mounting its existing filesystem, and starting the approved Jenkins image. Confirm authentication, one test job, artifact access, and credential retrieval without executing production deployments.

Cross-AZ recovery uses a snapshot restored into the destination AZ, not direct cross-AZ attachment of the original volume. Cross-region copies and KMS policies introduce additional dependencies. Document which recovery identity can decrypt the destination volume and obtain image artifacts when the primary environment is unavailable.

Measure RTO from interruption to a validated pipeline. Measure RPO from the newest recoverable controller changes, not the snapshot creation request timestamp alone. Preserve the bootstrap procedure outside Jenkins; restoring Jenkins must never require Jenkins to run first.

## Retention Is a Cloud Resource Setting

Verify the EBS attachment's deletion-on-termination setting through the infrastructure definition and actual EC2 attachment. Naming a disk persistent does not change that flag. Separate the volume resource's lifecycle from the disposable instance and record its AZ, encryption key, size, and backup policy.

Plan what happens if the instance disappears during a filesystem write. Retained storage may need filesystem recovery and Jenkins consistency checks; do not confuse retention with guaranteed clean shutdown. Review disk utilization and inode exhaustion because a full home can break jobs, plugin updates, and backup operations.

Monitor snapshot completion and restoration capability. A snapshot request that never completes does not meet the controller's RPO. Keep enough versions to recover from delayed discovery of corruption, and restrict snapshot-sharing permissions.

For disk expansion, increase the cloud volume and extend the filesystem through a tested distribution-specific procedure. Confirm the mounted device and current size first. Expansion should not require replacing Jenkins home or recursively changing ownership on unrelated directories.

Finally, record the image digest and plugin inventory used with each recovery point. Data persistence without runtime compatibility can leave the team with intact files and an unusable controller.

A restore drill should also verify filesystem ownership after attachment; matching the volume ID does not guarantee Jenkins can read its home.

## Key Takeaways

- **A restart policy is not persistence or disaster recovery.**
- **Retain encrypted controller storage separately from disposable compute.**
- **Identify a blank disk before formatting; never format restored data.**
- **Require the real mount before starting Jenkins.**
- **Keep controller access private and build execution isolated.**
- **Test container, host, and AZ recovery as different failure scenarios.**

## References

- Jenkins Docker installation: [Documentation](https://www.jenkins.io/doc/book/installing/docker/)
- EBS volume attachment: [Documentation](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-attaching-volume.html)
