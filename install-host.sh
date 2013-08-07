#!/bin/bash
# to start the installation do this:
# wget -O - https://raw.github.com/niieani/lxc-shared/master/install-host.sh | bash

read -p "Are you sure? " -n 1
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

CURDIR="$( cd `dirname "${BASH_SOURCE[0]}` && pwd )"
source $CURDIR/functions.sh

# start
apt-get update
apt-get -y install software-properties-common byobu zsh git htop mc ufw

# LXC
add-apt-repository ppa:ubuntu-lxc/daily
apt-get -y install lxc

mkdir -p $DIR

# dotfiles & others
git clone https://github.com/niieani/lxc-shared.git ${DIR}
(cd $DIR; git submodule init && git submodule update && git submodule status)

source $CURDIR/create-host-links.sh

chsh -s /bin/zsh
