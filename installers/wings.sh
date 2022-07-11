#!/bin/bash

set -e

#############################################################################
#                                                                           #
# Project 'pterodactyl-installer' for panel                                 #
#                                                                           #
# Copyright (C) 2018 - 2022, Vilhelm Prytz, <vilhelm@prytznet.se>           #
#                                                                           #
#   This program is free software: you can redistribute it and/or modify    #
#   it under the terms of the GNU General Public License as published by    #
#   the Free Software Foundation, either version 3 of the License, or       #
#   (at your option) any later version.                                     #
#                                                                           #
#   This program is distributed in the hope that it will be useful,         #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of          #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           #
#   GNU General Public License for more details.                            #
#                                                                           #
#   You should have received a copy of the GNU General Public License       #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.  #
#                                                                           #
# https://github.com/vilhelmprytz/pterodactyl-installer/blob/master/LICENSE #
#                                                                           #
# This script is not associated with the official Pterodactyl Project.      #
# https://github.com/vilhelmprytz/pterodactyl-installer                     #
#                                                                           #
#############################################################################

# TODO: Change to something like
# source /tmp/lib.sh || source <(curl -sL https://raw.githubuserc.com/vilhelmprytz/pterodactyl-installer/master/lib.sh)
# When released
# shellcheck source=lib.sh
source lib/lib.sh

# ------------------ Variables ----------------- #
INSTALL_MARIADB="${INSTALL_MARIADB:-false}"

# firewall
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

# SSL (Let's Encrypt)
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
FQDN="${FQDN:-}"
EMAIL="${EMAIL:-}"

# Database host
CONFIGURE_DBHOST="${CONFIGURE_DBHOST:-false}"
CONFIGURE_DBEXTERNAL="${CONFIGURE_DBEXTERNAL:-false}"
CONFIGURE_DBEXTERNAL_HOST="${CONFIGURE_DBEXTERNAL_HOST:-%}"
CONFIGURE_DB_FIREWALL="${CONFIGURE_DB_FIREWALL:-false}"
MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pterodactyluser}"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

# -------------- OS check funtions ------------- #

# check virtualization
check_virt() {
  echo -e "* Installing virt-what..."

  update_repos true
  install_packages "virt-what" true

  # Export sbin for virt-what
  export PATH="$PATH:/sbin:/usr/sbin"

  virt_serv=$(virt-what)

  case "$virt_serv" in
  *openvz* | *lxc*)
    print_warning "Unsupported type of virtualization detected. Please consult with your hosting provider whether your server can run Docker or not. Proceed at your own risk."
    echo -e -n "* Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      print_error "Installation aborted!"
      exit 1
    fi
    ;;
  *)
    [ "$virt_serv" != "" ] && print_warning "Virtualization: $virt_serv detected."
    ;;
  esac

  if uname -r | grep -q "xxxx"; then
    print_error "Unsupported kernel detected."
    exit 1
  fi
}

enable_services() {
  systemctl start docker
  systemctl enable docker
  [ "$INSTALL_MARIADB" == true ] && systemctl enable mariadb
  [ "$INSTALL_MARIADB" == true ] && systemctl start mariadb
}

dep_install() {
  output "Installing dependencies for $OS $OS_VER..."

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_allow_ports

  case "$OS" in
  ubuntu | debian)
    install_packages "ca-certificates gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    [ "$INSTALL_MARIADB" == true ] && [ "$OS_VER_MAJOR" == "18" ] && curl -sS "$MARIADB_URL" | bash

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  rocky | almalinux | centos)
    case "$OS" in
    centos)
      install_packages "yum-utils"
      yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
      ;;
    almalinux | rocky) 
      install_packages "dnf-utils" 
      dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo 
      ;;
    esac

    [ "$INSTALL_MARIADB" == true ] && [ "$OS_VER_MAJOR" == "7" ] && curl -sS "$MARIADB_URL" | bash

    install_packages "device-mapper-persistent-data lvm2"
  esac

  # Update the new repos
  update_repos

  # Install dependencies
  install_packages "docker-ce docker-ce-cli containerd.io"
  
  # Install mariadb if needed
  [ "$INSTALL_MARIADB" == true ] && install_packages "mariadb-server"

  enable_services
}

ptdl_dl() {
  echo "* Installing Pterodactyl Wings .. "

  mkdir -p /etc/pterodactyl
  curl -L -o /usr/local/bin/wings "$WINGS_DL_BASE_URL$ARCH"

  chmod u+x /usr/local/bin/wings

  echo "* Done."
}

systemd_file() {
  echo "* Installing systemd service.."
  curl -o /etc/systemd/system/wings.service "$GITHUB_BASE_URL"/configs/wings.service
  systemctl daemon-reload
  systemctl enable wings
  echo "* Installed systemd service!"
}

install_mariadb() {
  case "$OS" in
  debian)
    apt install -y mariadb-server
    ;;
  ubuntu)
    
    apt install -y mariadb-server
    ;;
  centos)
    [ "$OS_VER_MAJOR" == "7" ] && curl -sS "$MARIADB_URL" | bash
    [ "$OS_VER_MAJOR" == "7" ] && yum -y install mariadb-server
    [ "$OS_VER_MAJOR" == "8" ] && dnf install -y mariadb mariadb-server
    ;;
  esac
}

firewall_ports() {
  echo "* Opening port 22 (SSH), 8080 (Wings Port), 2022 (Wings SFTP Port)"

  [ "$CONFIGURE_LETSENCRYPT" == true ] && firewall_allow_ports "80 443"
  [ "$CONFIGURE_DB_FIREWALL" == true ] && firewall_allow_ports "3306"

  firewall_allow_ports "22 8080 2022"
}