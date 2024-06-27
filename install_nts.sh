#!/bin/bash
# install.sh
#
# This is a guided installer script for installing several key network monitoring
# and troubleshooting services.

# Script Variables

# Pretty Colors
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

#--------------------------------------------------------------------
# Check if the script is being run as root or as sudo
if [ "$EUID" -ne 0 ]; then
  echo
  echo -e "${RED}This script must be run as root or with sudo. Exiting." >&2
  echo
  exit 1
fi

#--------------------------------------------------------------------
# Bash functions for terminal

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


#--------------------------------------------------------------------
# Build NTS Installer Function

nts_installer () {
  #--------------------------------------------------------------------
  # Intializing script

  # API Token for Oxidized
  API_TOKEN=""
  NTS_PASSWORD="ntsRibbon1893"

  # Local IP and Hostname Info
  HOST_IP=$(hostname -I | awk '{print $1}')
  HOSTNAME=$(hostname)
  FQDN=$(hostname -f)

  # Create source directory for nts
  mkdir /opt/nts
  chown -R 1000:1000 /opt/nts


  #--------------------------------------------------------------------
  # Prompting for Credentials

  # Prompt the user for NTS password
  echo -e "${BLUE}---------------------------------------------------------------------${NC}"
  echo
  read -sp "Enter NTS Password: " NTS_PASSWORD
  echo

  # Check if the password is null (empty)
  if [ -z "$NTS_PASSWORD" ]; then
      echo -e "${YELLOW}Using default password - ntsRibbon1893 ${NC}"
      NTS_PASSWORD="ntsRibbon1893" > /dev/null
  fi

  # Adding NTS_PASSWORD variable to system variables
  # Check if the variable NTS_PASSWORD already exists in /etc/environment to update
  if grep -q "^NTS_PASSWORD=" /etc/environment; then
      # Update the existing variable
      sed -i "s|^NTS_PASSWORD=.*|NTS_PASSWORD=${NTS_PASSWORD}|" /etc/environment
  else
      # Add the variable to the file
      echo "NTS_PASSWORD=${NTS_PASSWORD}" | tee -a /etc/environment > /dev/null
  fi

  # Ensure envinronment variable is loaded to current user
  source /etc/environment


  #--------------------------------------------------------------------
  # Creating functions

  # Create function for user creation
  create_users() {
    local username=$1
    local uid=$2
    local nts_password=$3
    groupadd $username -g $uid
    useradd -u $uid -p $nts_password -g $username $username
    usermod -aG $username $(getent passwd 1000 | cut -d: -f1)
  }

  wait_timer() {
      local timer_length=$1
      local message=$2

      sp="|/-\\"
      end=$((SECONDS + timer_length))

      echo -n "$message "
      while [ $SECONDS -lt $end ]; do
          for (( i=0; i<${#sp}; i++ )); do
              printf "\r%s %c" "$message" "${sp:i:1}"
              sleep 0.1
          done
      done
      echo -ne "\r$message Done!          \n"
  }

  # Function to generate bcrypt password
  generate_bcrypt_password() {
      local password="$1"
      local bcrypt_hash
      bcrypt_hash=$(htpasswd -bnBC 10 "" "$password" | tr -d ':\n')
      echo "{CRYPT}$bcrypt_hash"
  }

  #--------------------------------------------------------------------
  # Installing Dependencies and CLI Tools
  echo_primary "Installing dependencies and CLI tools..."

  # Configured Wireshark group
  groupadd -r wireshark
  usermod -aG wireshark $(getent passwd 1000 | cut -d: -f1)

  # Prepping tshark (wireshark-common) for silent install
  echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
  apt update && apt install apache2-utils hping3 tshark iperf3 iftop nmap net-tools sqlite3 -y

  echo -e "

${YELLOW}Installing the following packages:

${YELLOW}• CN (FQDN): ${WHITE}$FQDN
${YELLOW}• SAN (IP Address): ${WHITE}$HOST_IP
${YELLOW}• SAN (Hostname): ${WHITE}$HOSTNAME
${YELLOW}• SAN (Netdisco SNI): ${WHITE}netdisco-$FQDN
${YELLOW}• SAN (LibreSpeed SNI): ${WHITE}librespeed-$FQDN
${YELLOW}• SAN (LibreNMS SNI): ${WHITE}librenms-$FQDN

"


  #--------------------------------------------------------------------
  # Installing Netdisco
  echo_primary "Installing Netdisco"
  
  # Install Netdisco service account
  create_users netdisco 901 $NTS_PASSWORD

  # Create Netdisco directories change ownership to netdisco
  mkdir -p /opt/nts/netdisco/nd-site-local /opt/nts/netdisco/config /opt/nts/netdisco/logs
  chown -R netdisco:netdisco /opt/nts/netdisco

  # Deploy Netdisco
  docker compose -f docker-netdisco.yml up -d

  echo
  wait_timer 10 "Giving Netdisco 10 seconds to finish setup..."
  echo
  echo "Checking and verifying Netdisco is running..."

  NETDISCO_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://127.0.0.1:5000)

  # Check if the status code is 200
  if [ $NETDISCO_STATUS -eq 200 ]; then
    echo -e "${GREEN}SUCCESS${NC} - Netdisco is reachable and returned a 200 OK response."
    echo

    ## Prompt for Netdisco Authentication
    echo -e "
${CYAN}-----------------------------------------------------------------
${YELLOW}Netdisco Authentication 
${CYAN}-----------------------------------------------------------------
${YELLOW}If you wish to enable Netdisco authentication enter Y/N below.

If yes, installation will pause while user is created so that
authentication is configured after user is created.
${CYAN}-----------------------------------------------------------------${NC}
"

    read -p "Enable Netdisco Authentication? (y/N): " answer
    echo

    # If the user just presses Enter, default to 'n'
    answer=${answer:-n}

    # Convert input to lowercase
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

    # Check the user's response
    if [[ "$answer" == "n" || "$answer" == "no" ]]; then
        echo
        echo -e "${YELLOW}Netdisco defaults configured (no authentication)"
        echo
    elif [[ "$answer" == "y" || "$answer" == "yes" ]]; then
            echo -e "
${CYAN}-----------------------------------------------------------------
${YELLOW}Netdisco Needs Admin User Configured
${CYAN}-----------------------------------------------------------------
${YELLOW}Go to http://$HOST_IP:5000 > Admin > User Management.

Configure your admin user and be sure to enable it as 'Administrator'.

Also a good time to disable guest as administrator.

Script will pause and wait for further input before proceeding.
${CYAN}-----------------------------------------------------------------${NC}
"
    echo
    read -p "Press any key to proceed with the rest of the NTS installation..."
    echo
    sed -i -e "s/no_auth: true/no_auth: false/g" /opt/nts/netdisco/config/deployment.yml
    fi
  else
    echo -e "${RED}FAILED!!!
    
    Netdisco returned a $NETDISCO_STATUS response, indicating a possible issue.

    Please check and verify the Netdisco container is running.${NC}
    "
  fi
  

  #--------------------------------------------------------------------
  # Installaing LibreSpeed
  echo_primary "Installing LibreSpeed"
  
  # Create LibreSpeed directories change ownership to netdisco
  mkdir -p /opt/nts/librespeed/config
  chown -R 1000:1000 /opt/nts/librespeed
  
  # Creating ENV as workaround for NTS_PASSWORD being unavailable during initial install
  echo "NTS_PASSWORD=$NTS_PASSWORD" >> ./librespeed.env

  # Deploy LibreSpeed
  docker compose -f docker-librespeed.yml --env-file ./librespeed.env up -d

  echo
  wait_timer 10 "Giving LibreSpeed 10 seconds to finish setup..."
  echo
  echo "Checking and verifying LibreSpeed is running..."

  LIBRESPEED_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://127.0.0.1:8080)

  # Check if the status code is 200
  if [ $LIBRESPEED_STATUS -eq 200 ]; then
    echo -e "${GREEN}SUCCESS${NC} - LibreSpeed is reachable and returned a 200 OK response."
  else
    echo -e "${RED}FAILED!!!
    
    LibreSpeed returned a $LIBRESPEED_STATUS response, indicating a possible issue.

    Please check and verify the LibreSpeed container is running.${NC}
    "
  fi

  # Remove ENV file due to storing password
  rm ./librespeed.env


  #--------------------------------------------------------------------
  # Installing LibreNMS
  echo_primary "Installing LibreNMS"

  # Create LibreNMS directories change ownership to netdisco
  mkdir -p /opt/nts/librenms/db
  chown -R 1000:1000 /opt/nts/librenms

  # Deploy LibreNMS
  docker compose -f docker-librenms.yml --env-file librenms.env up -d 

  echo
  wait_timer 20 "Giving LibreNMS 20 seconds to finish setup..."
  echo
  echo "Checking and verifying LibreNMS is running..."

  LIBRENMS_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://127.0.0.1:8000/install/user)

  # Check if the status code is 200
  if [ $LIBRENMS_STATUS -eq 200 ]; then
    echo -e "${GREEN}SUCCESS${NC} - LibreNMS is reachable and returned a 200 OK response."
    
    # Finish LibreNMS Configuration
    docker exec -it librenms ./lnms user:add nts-admin -p $NTS_PASSWORD -r admin #add nts-admin
    docker exec -it librenms ./lnms  config:set enable_syslog true #enable syslog
    docker exec -it librenms ./lnms  config:set oxidized.enabled true #enabling oxidized
    docker exec -it librenms ./lnms  config:set oxidized.url http://127.0.0.1:8888 #pointing to oxidize
    docker exec -it librenms ./lnms  config:set oxidized.features.versioning true #enabling oxidize versioning

    echo -e "
${CYAN}-----------------------------------------------------------------
${YELLOW}LibreNMS Needs Setup Finished
${CYAN}-----------------------------------------------------------------
${YELLOW}Go to http://$HOST_IP:8000 to finish setup.

Use 'nts-admin' and the NTS password configured above.
${CYAN}-----------------------------------------------------------------${NC}
"
    sleep 5
  else
    echo -e "${RED}FAILED!!!
    
    LibreNMS returned a $LIBRENMS_STATUS response, indicating a possible issue.

    Please check and verify the LibreNMS container is running.${NC}
    "
  fi


  #--------------------------------------------------------------------
  # Installing Oxidized
  echo_primary "Installing Oxidized"

  # Create LibreNMS directories change ownership to netdisco
  mkdir -p /opt/nts/oxidized/config
  chown -R 1000:1000 /opt/nts/oxidized

  ## Prompt for API key to update Oxidized
  echo -e "
${CYAN}-----------------------------------------------------------------
${YELLOW}API Key Needs Updating for Oxidized to Work Properly!
${CYAN}-----------------------------------------------------------------
${YELLOW}Please go to LibreNMS > Settings (Gear Icon) > API > API Settings

Create a new API key and paste it below.
${CYAN}-----------------------------------------------------------------${NC}
"

  while [[ -z "$API_TOKEN" ]]; do
      read -sp "Enter API Key: " API_TOKEN
      echo
  done
  echo

  # Update Oxidized
  sed \
      -e "s/\${NTS_PASSWORD}/$NTS_PASSWORD/g" \
      -e "s/\${HOST_IP}/$HOST_IP/g" \
      -e "s/\${API_TOKEN}/$API_TOKEN/g" \
      oxidized.conf > /opt/nts/oxidized/config/config

  # Deploy Oxidized
  docker compose -f docker-oxidized.yml up -d 

  echo
  wait_timer 10 "Giving Oxidized 10 seconds to finish setup..."
  echo


  #--------------------------------------------------------------------
  # Installing NGINX
  echo_primary "Installing NGINX"

  # Create LibreNMS directories change ownership to netdisco
  mkdir -p /opt/nts/nginx/certs /opt/nts/nginx/conf /opt/nts/nginx/auth /opt/nts/nginx/html /opt/nts/nginx/logs
  chown -R 1000:1000 /opt/nts/nginx

  # Generate self-signed certificate
  echo -e "
${YELLOW}Generating self-signed certificate that has the following entries:

${YELLOW}• CN (FQDN): ${WHITE}$FQDN
${YELLOW}• SAN (IP Address): ${WHITE}$HOST_IP
${YELLOW}• SAN (Hostname): ${WHITE}$HOSTNAME
${YELLOW}• SAN (Netdisco SNI): ${WHITE}netdisco-$FQDN
${YELLOW}• SAN (LibreSpeed SNI): ${WHITE}librespeed-$FQDN
${YELLOW}• SAN (LibreNMS SNI): ${WHITE}librenms-$FQDN

"

  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=$FQDN" \
    -addext "subjectAltName=IP:$HOST_IP,DNS:$HOSTNAME,DNS:librenms-$HOSTNAME,DNS:librenms-$FQDN,DNS:librespeed-$HOSTNAME,DNS:librespeed-$FQDN,DNS:netdisco-$HOSTNAME,DNS:netdisco-$FQDN" \
    -keyout /opt/nts/nginx/certs/nginx.key \
    -out /opt/nts/nginx/certs/nginx.crt
  echo

  # Create htpasswd file for basic auth
  htpasswd -bc /opt/nts/nginx/auth/.htpasswd nts-admin $NTS_PASSWORD
  echo

  sed \
    -e "s/\${HOSTNAME}/$HOSTNAME/g" \
    -e "s/\${FQDN}/$FQDN/g" \
    -e "s/\${HOST_IP}/$HOST_IP/g" \
    nginx.conf > /opt/nts/nginx/conf/nginx.conf

  sed \
  -e "s/\${HOST_IP}/$HOST_IP/g" \
  -e "s/\${FQDN}/$FQDN/g" \
  index.html > /opt/nts/nginx/html/index.html

  cp -r images /opt/nts/nginx/html/
  chown -R 1000:1000 /opt/nts/nginx
  chown -R www-data:www-data /opt/nts/nginx/html

  # Deploy NGINX
  docker compose -f docker-nginx.yml up -d

  echo
  wait_timer 10 "Giving NGINX 20 seconds to finish setup..."
  echo
  echo "Checking and verifying NGINX is running..."

  NGINX_STATUS=$(curl -k -o /dev/null -s -w "%{http_code}" "https://$HOST_IP")

  # Check if the status code is 200
  if [ $NGINX_STATUS -eq 401 ]; then
    echo -e "${GREEN}SUCCESS${NC} - NGINX is online and returned a 401 needing authentication. This is a good thing!"
    echo
  else
    echo -e "${RED}FAILED!!!
    
    NGINX returned a $NGINX_STATUS response, indicating a possible issue.

    Please check and verify the NGINX container is running.${NC}
    "
  fi


  #--------------------------------------------------------------------
  # Setting up host firewall
  echo_primary "Configuring Server Firewall Rules"

  # Allow traffic to specific TCP ports
  ufw allow 80/tcp > /dev/null 2>&1
  ufw allow 443/tcp > /dev/null 2>&1
  ufw allow 514/tcp > /dev/null 2>&1
  ufw allow 514/udp > /dev/null 2>&1
  ufw allow 5000/tcp > /dev/null 2>&1
  ufw allow 8000/tcp > /dev/null 2>&1
  ufw allow 8080/tcp > /dev/null 2>&1
  ufw allow 8888/tcp > /dev/null 2>&1
  ufw allow from $HOST_IP to any port 8888 proto tcp > /dev/null 2>&1
  ufw allow in on lo to any port 8888 proto tcp > /dev/null 2>&1

  # Allow SSH (port 22) if needed for remote access
  ufw allow 22/tcp > /dev/null 2>&1

  # Deny all other incoming traffic
  ufw default deny incoming > /dev/null 2>&1

  # Allow all outgoing traffic
  ufw default allow outgoing > /dev/null 2>&1

  # Allow internal Docker container communication
  ufw allow in on docker0 > /dev/null 2>&1
  ufw allow out on docker0 > /dev/null 2>&1

  # Enable UFW
  echo "y" | ufw enable > /dev/null 2>&1

}

#--------------------------------------------------------------------
# Beginning Script

# Print the installation message
echo
echo
echo -e "${BLUE}| "
echo -e "${BLUE}| "
echo -e "${BLUE}| ${YELLOW}NTS Installer"
echo -e "${BLUE}| "
echo -e "${BLUE}| "
echo -e "${BLUE}| ${YELLOW}Please be sure to have a password ready for input for the installer."
echo -e "${BLUE}| ${YELLOW}If you do not enter a password, the default password will be used."
echo -e "${BLUE}| "
echo -e "${BLUE}| ${YELLOW}During the installation, you will be prompted to create an API key in LibreNMS for the Oxidized installation."
echo -e "${BLUE}| "
echo -e "${BLUE}| ${NC}"
echo
read -p "Are you ready to proceed? (Y/n): " answer
echo

# If the user just presses Enter, default to 'y'
answer=${answer:-y}

# Convert input to lowercase
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

# Check the user's response
if [[ "$answer" == "y" | "$answer" == "yes" ]]; then
    echo "Proceeding with installation..."
    echo
    nts_installer
elif [[ "$answer" == "n" || "$answer" == "no" ]]; then
    echo "Exiting script."
    exit 0
else
    echo "Invalid input. Exiting script."
    exit 1
fi


#--------------------------------------------------------------------
# Exit script
echo
echo
echo -e "${BLUE}---------------------------------------------------------------------${NC}

${YELLOW}NTS installer is finished. Here's the main page with the links below:

${WHITE}https://${HOST_IP}

${YELLOW}Services:

${WHITE}• Netdisco - https://${HOST_IP}:5000
${WHITE}• LibreSpeed - https://${HOST_IP}:8080
${WHITE}• LibreNMS - https://${HOST_IP}:8000

${YELLOW}Press Enter to exit...${NC}
"
read
