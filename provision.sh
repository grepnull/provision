#!/bin/bash

set -e

# This script supports OS X 10.10 (Yosemite) and possibly higher though
# as of this writing there is nothing higher and so it is not tested.
MIN_OSX_VERSION=10

OSX_VERSION=$(sw_vers -productVersion | awk -F "." '{print $2}')

NF='\033[0m' # no formatting
BOLD='\033[1m'
GREEN='\033[32m'
RED='\033[31m'
BOLD_RED='\033[01;31m'
BLUE='\033[01;34m'
YELLOW='\033[33m'

LEVELS="ok info notice warn error"

ok=$GREEN
info=$BOLD
notice=$BLUE
warn=$YELLOW
error=$BOLD_RED

for level in ${LEVELS}; do
    eval "function ${level} {
            echo -en '${!level}'
            echo -en \$@
            echo -e '${NF}'
         }"
done

function newline {
    count=$1
    if [ -z $count ]; then
        count=1
    fi
    for i in $(seq 1 $count); do
        echo ""
    done
}

function install_xcode_cli_tools {
    if xcode-select -p &> /dev/null; then
        ok "You already have the XCode CLI tools installed."
        return
    fi

    ###
    ### Get and install Xcode CLI tools
    ### https://github.com/timsutton/osx-vm-templates/blob/master/scripts/xcode-cli-tools.sh
    ###

    newline 2
    notice "Installing/upgrading XCode CLI tools. This does not install XCode itself."
    warn "If you need a full install of XCode, install it after this script is done"
    warn "from the Mac App Store."

    # create the placeholder file that's checked by CLI updates' .dist code
    # in Apple's SUS catalog
    # otherwise softwareupdate won't offer the CLI tools as an option
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    # find the right package id to install
    PROD=$(softwareupdate -l 2> /dev/null | grep "Command Line Tools" | head -n 1 | awk -F"*" '{print $2}' | sed -e 's/^ *//')
    info "Will install '${PROD}'"
    # install it
    # amazingly, it won't find the update if we put the update ID in double-quotes
    if [ "${PROD}" ]; then
        softwareupdate -i "${PROD}" -v
    else
        echo "Looks like you already have the XCode CLI tools installed. Continuing."
    fi
}

function install_ansible {
    echo $LOCAL_PW | sudo -S easy_install pip
    echo $LOCAL_PW | sudo -S pip install ansible --upgrade
}

function check_osx_version {
    if [ "$OSX_VERSION" -ge $MIN_OSX_VERSION ]; then
        ok "You're running OS X 10.${OSX_VERSION}. Let's get started!"
    else
        error "You're running OS X 10.${OSX_VERSION} which is unsupported. Upgrade to 10.${MIN_OSX_VERSION} or higher"
        exit 1
    fi
}

function cache_sudo_password {
    if [ -z $LOCAL_PW ]; then
        while [ -z "$LOCAL_PW" ]; do read -s -p "Local $USER@$HOSTNAME's sudo password: " -r LOCAL_PW; done
    fi
    echo $LOCAL_PW | sudo -S ls &> /dev/null
}

function install_homebrew {
    notice Installing homebrew
    # cache sudo password so not prompted during homebrew install
    cache_sudo_password

    # echo into the ruby install script so that it doesn't prompt for user consent
    # there's an "if STDIN.tty?" conditional in the script
    echo "" | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" || true

    notice Installing homebrew bundle
    brew tap homebrew/bundle
}

function install_homebrew_packages {
    notice Installing all homebrew packages
    brew bundle
}

function install_python_packages {
    notice Installing various python packages
    cd ansible
    ansible-playbook -i inventory pip.yml
    cd ..
}

function install_ruby_packages {
    notice Installing various ruby gems
    cd ansible
    ansible-playbook -i inventory gem.yml
    cd ..
}

function install_launch_agents {
    notice Installing launch agents
    cd ansible
    ansible-playbook -i inventory launchagents.yml
    cd ..
}

function install_prelude {
    notice Installing Emacs Prelude
    cd ansible
    ansible-playbook -i inventory emacs-prelude.yml
    cd ..
}

function get_configs_from_git {
    notice Fetching and installing configs from git
    cd ansible
    ansible-playbook -i inventory config.yml
    cd ..
}

function create_alternatives {
    notice Creating GNU tools alternatives
    cd ansible
    # requires sudo
    ansible-playbook -K -i inventory alternatives.yml
    cd ..
}

function setup_mackup {
    notice Setting mackup up
    cd ansible
    ansible-playbook -i inventory mackup.yml
    cd ..
}

function run_mackup {
    notice Restoring preferences via mackup
    mackup -f restore
    while [ ! -f ~/.ssh/id_rsa ]; do
	echo -n "."
	sleep 1
    done
    info Detected that ssh key is restored. Continuing.
    notice Uninstalling mackup so that all configs are real files/directories.
    mackup -f uninstall
}

unset HISTFILE

check_osx_version
newline

install_xcode_cli_tools
newline

install_homebrew
newline

install_homebrew_packages
newline

create_alternatives
newline

install_python_packages
newline

install_ruby_packages
newline

install_prelude
newline

setup_mackup
newline

run_mackup
newline

get_configs_from_git
newline

install_launch_agents
newline


ok Done! You should probably reboot.
