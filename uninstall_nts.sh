#!/bin/bash
# uninstall_nts.sh
#
# This script is a tool used in testing to reset the server to a base level.
# The script can be run with either the 'full' or 'nts' parameters.
# Example: ./uninstall_nts.sh full # Uninstalls NTS and Docker
# Without parameters, script prompts user for uninstallation type, with 
# default being NTS services.

# Pretty Colors
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if the script is being run as root or as sudo
if [ "$EUID" -ne 0 ]; then
  echo
  echo -e "${RED}This script must be run as root or with sudo. Exiting." >&2
  echo
  exit 1
fi

# Parameter Input
# Check if no parameters were entered
if [ $# -eq 0 ]; then
  cleanup_option="default"
# Check the number of parameters, bail if more than 1
elif [ "$#" -gt 1 ]; then
    echo "Error: More than one parameter provided."
    exit 1
else
  # Parameters entered, use first parameter
  cleanup_option=$1
  # Convert input to lowercase
  cleanup_option=$(echo "$cleanup_option" | tr '[:upper:]' '[:lower:]')
fi

# Echo function for printing primary demarcation lines on screen
echo_primary () {
  message=$1
  echo
  echo -e "${BLUE}---------------------------------------------------------------------${NC}"
  echo
  echo $message
  echo
}

# Echo function for printing secondary demarcation lines on screen
echo_secondary () {
  message=$1
  echo
  echo -e "${GREEN}----------------------------------------------------------${NC}"
  echo
  echo $message
  echo
}

# NTS Cleanup 
nts_cleanup () {

  # Docker Cleanup
  echo_secondary "Cleaning up Docker containers..."
  docker ps -a --filter "name=netdisco" --format "{{.ID}}" | xargs -I {} sh -c 'docker stop {}; docker rm {}'
  docker ps -a --filter "name=librespeed" --format "{{.ID}}" | xargs -I {} sh -c 'docker stop {}; docker rm {}'
  docker ps -a --filter "name=librenms" --format "{{.ID}}" | xargs -I {} sh -c 'docker stop {}; docker rm {}'
  docker ps -a --filter "name=oxidized" --format "{{.ID}}" | xargs -I {} sh -c 'docker stop {}; docker rm {}'
  docker ps -a --filter "name=nginx" --format "{{.ID}}" | xargs -I {} sh -c 'docker stop {}; docker rm {}'

  # Removing system variables
  echo_secondary "Removing any system variables..."
  # Clear NTS_PASSWORD
  sed -i "/NTS_PASSWORD=/d" /etc/environment
  source /etc/environment

  # Server group cleanup
  echo_secondary "Cleaning server groups..."
  # List of groups to delete
  nts_groups=('netdisco','wireshark')
  # Loop through patterns and delete matching groups
  for pattern in "${patterns[@]}"; do
      groupdel $pattern
  done

  # Server service account cleanup
  echo_secondary "Cleaning server service accounts..."
  userdel netdisco

  # Removing NTS directory
  echo_secondary "Removing NTS directory..."
  rm -rf /opt/nts

  # Removing server apps
  echo_secondary "Removing previously installed dependencies and CLI tools..."
  apt autoremove --purge -y apache2-utils hping3 tshark iperf3 iftop nmap net-tools sqlite3
  apt autoclean

  # Removing and disabling firewall rules
  echo_secondary "Disabling and removing NTS firewall rules..."
  HOST_IP=$(hostname -I | awk '{print $1}')
  ufw disable
  ufw delete allow 80/tcp
  ufw delete allow 443/tcp
  ufw delete allow 514/tcp
  ufw delete allow 514/udp
  ufw delete allow 5000/tcp
  ufw delete allow 8000/tcp
  ufw delete allow 8080/tcp
  ufw delete allow 8888/tcp
  ufw delete allow from $HOST_IP to any port 8888 proto tcp
  ufw delete allow in on lo to any port 8888 proto tcp
  
}

# Docker Uninstall
docker_uninstall () {

  echo_secondary "Removing Docker and related files/directories..."
  docker stop $(docker ps -aq)
  docker rm $(docker ps -aq)
  docker rmi $(docker images -q)
  apt-get autoremove -y --purge docker-ce docker-ce-cli
  apt-get autoclean
  rm -rf /var/lib/docker /etc/docker
  rm -rf /var/run/docker.sock
  rm -rf /etc/systemd/system/docker.service.d
  rm -rf /etc/systemd/system/docker.service
  rm -rf /etc/systemd/system/docker.socket
  rm -rf /usr/lib/systemd/system/docker.service
  rm -rf /usr/lib/systemd/system/docker.socket
  rm -rf docker-install

  while true; do
    echo -e "${YELLOW}"
    read -p "Uninstaller needs to reboot. Reboot computer? (Y/n): " answer
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
}

cleanup_options () {
  # Print the cleanup message
  echo
  echo
  echo -e "${BLUE}| "
  echo -e "${BLUE}| "
  echo -e "${BLUE}| ${YELLOW}NTS Cleanup"
  echo -e "${BLUE}| "
  echo -e "${BLUE}| "
  echo -e "${BLUE}| ${YELLOW}Please select a cleanup option"
  echo -e "${BLUE}| "
  echo -e "${BLUE}| ${YELLOW}1. NTS Services and Dependecies Cleanup"
  echo -e "${BLUE}| ${YELLOW}2. Full Service Cleanup (NTS and Docker)"
  echo -e "${BLUE}| "
  echo -e "${BLUE}| ${NC}"
  echo
  read -p "Cleanup Option [Default: 1]: " answer
  echo

  # If the user just presses Enter, default to 'y'
  answer=${answer:-1}

  # Check the user's response
  if [[ "$answer" == 1 ]]; then
    echo_primary "Cleaning up NTS services and depdencies only..."
    nts_cleanup
  elif [[ "$answer" == 2 ]]; then
      echo_primary "Performing FULL Docker and NTS cleanup..."
      nts_cleanup
      docker_uninstall
  else
      echo "Invalid input. Exiting script."
      exit 1
  fi
}

# Check the user's response
if [[ "$cleanup_option" == "nts" ]]; then
    echo_primary "Cleaning up NTS services and depdencies only..."
    nts_cleanup
elif [[ "$cleanup_option" == "full" ]]; then
    echo_primary "Performing FULL Docker and NTS cleanup..."
    nts_cleanup
    docker_uninstall
elif [[ "$cleanup_option" == "default" ]]; then
    cleanup_options
else
    echo "Invalid input. Exiting script."
    exit 1
fi