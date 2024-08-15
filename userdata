#!/bin/bash
apt-get update
apt upgrade -y
apt install docker.io -y 
systemctl start docker
groupadd docker
usermod -aG docker ubuntu
