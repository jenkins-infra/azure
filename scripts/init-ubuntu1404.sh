#!/bin/sh

### USAGE
# curl -O https://raw.githubusercontent.com/jenkins-infra/azure/master/scripts/init-ubuntu1404.sh && sudo bash ./init-ubuntu1404.sh && newgrp docker
###

# This script is designed to be used via the "Init Script" facility in the Azure cloud plugin for Jenkins.
# It assumes that the user executing this script is with sudo!
#
# It sets up the Ubuntu 14.04 LTS VM for running Jenkins project workloads which are typically going to be
# Docker-based

### Prepare to install Docker
# Grab  the necessary dependencies to add our Docker apt repository
apt-get update -qy --fix-missing && apt-get install -qy apt-transport-https ca-certificates

# Create the docker.list file
echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list

# Grab the Docker project's key for apt package signing
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

# Update our local caches with our new repository
apt-get update -qy
###


apt-get install -qy default-jdk git docker-engine linux-image-extra-$(uname -r)
usermod --groups docker --append ${SUDO_USER}
