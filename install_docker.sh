#!/bin/bash
# install_docker.sh
#
# This script clones the official Docker installer shell script and
# installs Docker Community edition, along with configuring the main
# user (UID 1000) to be a member of the Docker group.

# Pretty Colors
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Echo function for printing primary demarcation lines on screen
echo_primary () {
  message=$1
  echo
  echo -e "${BLUE}---------------------------------------------------------------------${NC}"
  echo
  echo $message
  echo
}

# Check if git is installed
echo_primary "Checking if Git is installed..."
if ! command -v git &> /dev/null
then
    echo_secondary "Git is not installed. Installing Git..."
    apt update
    apt install -y git
fi

echo_primary "Installing Docker..."
# Clone Docker Installer Repository
git clone https://github.com/docker/docker-install.git

# Moving to docker-installer directory
cd docker-install

# Creating Docker group and adding user in advance
groupadd docker
usermod -aG docker $(getent passwd 1000 | cut -d: -f1)

# Making install script an executable
chmod +x install.sh

# Install Docker
sh ./install.sh

while true; do
    echo -e "${YELLOW}"
    read -p "Install needs to reboot. Reboot computer? (Y/n): " answer
    echo -e "${NC}"

    # If the user just presses Enter, default to 'y'
    answer=${answer:-y}

    # Convert input to lowercase
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

    # Check the user's response
    if [[ "$answer" == "y" || "$answer" == "yes" ]]; then
        reboot now
        break
    elif [[ "$answer" == "n" || "$answer" == "no" ]]; then
        echo "Exiting script."
        exit 0
    fi
done