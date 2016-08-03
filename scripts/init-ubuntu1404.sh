#!/bin/sh

# This script is designed to be used via the "Init Script" facility in the Azure cloud plugin for Jenkins.
# It assumes that the user executing this script is *not* root but has password-less sudoer access.
#
# It sets up the Ubuntu 14.04 LTS VM for running Jenkins project workloads which are typically going to be
# Docker-based

### Prepare to install Docker
# Grab  the necessary dependencies to add our Docker apt repository
sudo apt-get update -qy --fix-missing && sudo apt-get install -qy apt-transport-https ca-certificates

# Create the docker.list file
sudo sh -c 'echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list'

# Grab the Docker project's key for apt package signing
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

# Update our local caches with our new repository
sudo apt-get update -qy
###


sudo apt-get install -qy default-jdk git docker-engine linux-image-extra-$(uname -r)
sudo usermod --groups docker --append ${USER}
