#!/bin/bash

function setupSystem() {
  echo ""
  echo "================= CONFIGURING SYSTEM ================="

  setupDockerRepo

  if [[ $(readConfig ".machine.ssh.enabled" "false") == "true" ]]; then
    createSshTunnelUser
  fi

  # Configure system
  if cat /etc/sysctl.conf | grep "fs.inotify.max_user_watches"; then
    echo ""
  else
    sysctl fs.inotify.max_user_watches=524288
    sysctl fs.inotify.max_user_instances=512
    echo "fs.inotify.max_user_watches = 524288" >> /etc/sysctl.conf
    echo "fs.inotify.max_user_instances = 512"  >> /etc/sysctl.conf
  fi

  if [[ $(readConfig ".machine.swap.enabled" "false") == "true" ]]; then
    createSwapFile
  fi

  mkdir -p /root/.docker/ || true
  mkdir -p /etc/systemd/system/docker.service.d/ || true

  if which kubectl; then
    kubectl version --client
  else
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    mv ./kubectl /usr/bin/kubectl
  fi

  # NOTE: Not upgrading to kind v1.20 due to the following issue
  # https://github.com/kubernetes-sigs/kind/issues/3283
  if which kind; then
    kind version
  else
    curl -Lo ./kind https://github.com/kubernetes-sigs/kind/releases/download/v0.19.0/kind-linux-amd64
    chmod +x ./kind
    mv ./kind /usr/bin/kind
  fi

  if which jq; then
    jq --version
  else
    curl -Lo ./jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    chmod +x ./jq
    mv ./jq /usr/bin/jq
  fi

  if which helm; then
    helm version
  else
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh || true
    mv /usr/local/bin/helm /usr/bin/helm
  fi

  if which mc; then
    mc -v
  else
    curl -Lo ./mc https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x ./mc
    mv ./mc /usr/bin/mc
  fi

  if which dasel; then
    dasel --version
  else
    curl -Lo ./dasel https://github.com/TomWright/dasel/releases/download/v2.3.6/dasel_linux_amd64
    chmod +x ./dasel
    mv ./dasel /usr/bin/dasel
  fi

  if [[ -f "/etc/sysconfig/selinux" ]]; then
    sed -i "s/SELINUX=.*/SELINUX=disabled/g" /etc/sysconfig/selinux
    setenforce 0 || true
  fi

  if which yum; then
    # TODO: Add support to install additional packages via config
    yum install --nogpgcheck -y docker-ce docker-ce-cli containerd.io xfsprogs unzip wget curl \
      https://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/h/htop-2.2.0-3.el7.x86_64.rpm
  elif which apk; then
    apk add xfsprogs unzip wget curl htop
  else
    echo "No supported package manager executable found! Exiting..."
    exit 1
  fi

  RESTART_DOCKER=0
  # Create docker config file if it does not exist
  dest="/root/.docker/config.json"
  if [[ ! -f "$dest" ]] || [[ $(readConfig ".machine.force_update_configs" "false") == "true" ]]; then
    length=$(readArrayLength ".machine.docker.repositories")
    config=$(echo "{}" | jq '.auths={}')

    if [[ "$length" -ge "0" ]]; then
      for index in `seq 0 $length`;do
        name=$(readConfig ".machine.docker.repositories[$index].name")
        username=$(readConfig ".machine.docker.repositories[$index].username")
        password=$(readConfig ".machine.docker.repositories[$index].password")
        config=$(echo "$config" | jq --arg name "$name" --arg value "$(echo -ne "$username:$password" | base64 -w 0)" '.auths[$name].auth=$value')
      done
    fi

    echo "$config" > "$dest"
    RESTART_DOCKER=1
  fi

  # Create docker service file if it does not exist
  dest="/etc/systemd/system/docker.service.d/http-proxy.conf"
  if [[ $(readConfig ".machine.proxy.enabled" "true") == "true" ]]; then
    if [[ ! -f "$dest" ]] || [[ $(readConfig ".machine.force_update_configs" "false") == "true" ]]; then
    cat <<EOF > "$dest"
[Service]
Environment="HTTP_PROXY=$(readConfig ".machine.proxy.http_endpoint" "http://proxy:3128/")"
Environment="HTTPS_PROXY=$(readConfig ".machine.proxy.https_endpoint" "http://proxy:3128/")"
Environment="NO_PROXY=$(readConfig ".machine.proxy.exclusions" "169.254.169.254"),127.0.0.0/8,172.20.0.190,172.20.0.200"
EOF
      RESTART_DOCKER=1
    fi
  fi

  if [[ -f "/usr/lib/systemd/system/docker.service" ]]; then
    sed -i "s,ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock,ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H fd:// --containerd=/run/containerd/containerd.sock,g" "/usr/lib/systemd/system/docker.service"
  fi

  # Setup services
  if which systemctl; then
    systemctl daemon-reload
    if [[ "$RESTART_DOCKER" == 1 ]]; then
      systemctl stop docker || true
      systemctl start docker
    fi
  fi
}

function setupDockerRepo() {
  # Create docker yum repo file if it does not exist
  if which docker; then
    docker version || true
  else
    dest="/etc/yum.repos.d/docker-ce.repo"
    if [[ ! -f "$dest" ]] || [[ $(readConfig ".machine.force_update_configs" "false") == "true" ]]; then
cat <<\EOF > "$dest"
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/centos/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
EOF
    fi
  fi

}

function createSshTunnelUser() {
  # Setup password auth for "tunnel" user
  SSH_CONFIG_LOCATION=/etc/ssh/sshd_config
  if [[ ! -f "$SSH_CONFIG_LOCATION" ]] || [[ $(readConfig ".machine.force_update_configs" "false") == "true" ]]; then
    SSH_CONFIG_LOCATION=/etc/ssh/ssh_config
  fi
  sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" $SSH_CONFIG_LOCATION
  if cat $SSH_CONFIG_LOCATION | grep "Match User tunnel"; then
    echo ""
  else
    echo ""                           >> $SSH_CONFIG_LOCATION
    echo "Match User tunnel"          >> $SSH_CONFIG_LOCATION
    echo "  AllowTcpForwarding yes"   >> $SSH_CONFIG_LOCATION
    echo "  X11Forwarding no"         >> $SSH_CONFIG_LOCATION
    echo "  AllowAgentForwarding no"  >> $SSH_CONFIG_LOCATION
    echo "  ForceCommand /bin/false"  >> $SSH_CONFIG_LOCATION
  fi

  service sshd restart || true
}

function createSwapFile() {
  if [[ -z "$SWAP_SIZE" ]]; then
    SWAP_SIZE=$(readConfig ".machine.swap.size" "65536")
  fi

  # Create swapfile
  if [[ ! -f /swapfile ]]; then
    echo "Creating swap file..."
    dd if=/dev/zero of=/swapfile count=${SWAP_SIZE} bs=1MiB
  fi

  echo "Setting up swap file..."
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab
}

event on onSystemSetup setupSystem