#!/bin/bash

function deleteOldCluster() {
  echo ""
  echo "================= CREATING CLUSTER ================="

  if [[ "$DELETE_CLUSTER" == "true" ]]; then
    length=$(readArrayLength ".cluster.kinst.machines")
    for index in `seq 0 $length`; do
      docker=$(readConfig ".cluster.kinst.machines[$index].docker")
      DOCKER_HOST="$docker" kind delete cluster --name $CLUSTER_NAME
    done
  fi
}

function createKinstCluster() {
  length=$(readArrayLength ".cluster.kinst.machines")

  if [[ "$length" -lt "0" ]]; then
    echo "ERROR: At least one machine must be defined for kinst cluster"
    exit 1
  fi

  defaultNodeImage=$(readConfig ".cluster.kinst.image" "kindest/node:v1.25.11@sha256:227fa11ce74ea76a0474eeefb84cb75d8dad1b08638371ecf0e86259b35be0c8")

  declare -a taintNodes=()
  for machineIndex in `seq 0 $length`; do
    name=$(readConfig ".cluster.kinst.machines[$machineIndex].name")
    docker=$(readConfig ".cluster.kinst.machines[$machineIndex].docker")

    if [[ "$machineIndex" == "0" ]]; then
      # Setup the machine as the manager
      setupSwarmManager "$docker" "$name"
      export KINST_DOCKER_MANAGER="$docker"
    else
      setupSwarmWorker "$docker" "$name"
    fi
  done

  for machineIndex in `seq 0 $length`; do
    name=$(readConfig ".cluster.kinst.machines[$machineIndex].name")
    docker=$(readConfig ".cluster.kinst.machines[$machineIndex].docker")

    if [[ "$machineIndex" == "0" ]]; then
      # Setup the control plane
      setupKindControlPlane "$docker" "$defaultNodeImage"
      export KINST_CONTROL_PLANE="${CLUSTER_NAME}-control-plane"
      setupNodeContainer "$docker" "$KINST_CONTROL_PLANE"
    fi

    nodes=$(readArrayLength ".cluster.kinst.machines[$machineIndex].nodes")
    for nodeIndex in `seq 0 $nodes`; do
      nodeName=$(readConfig ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].name")
      nodeLabels=$(readConfig ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].labels")
      nodeLabelsFormatted=$(echo "$nodeLabels" | yq -op | sed "s/ = /=/g" | tr "\n" ",")
      nodeTaints=$(readArrayLength ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].taints")
      nodeImage=$(readConfig ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].image")

      if [[ -z "$nodeImage" ]]; then
        nodeImage="$defaultNodeImage"
      fi

      for nodeTaintsIndex in `seq 0 $nodeTaints`; do
        taintKey=$(readConfig ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].taints[$nodeTaintsIndex].key")
        taintValue=$(readConfig ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].taints[$nodeTaintsIndex].value")
        taintEffect=$(readConfig ".cluster.kinst.machines[$machineIndex].nodes[$nodeIndex].taints[$nodeTaintsIndex].effect")
        taintNodes+=("${CLUSTER_NAME}-$nodeName $taintKey=$taintValue:$taintEffect")
      done

      setupKindWorker "$docker" "$nodeImage" "$nodeName" "${nodeLabelsFormatted%?}"
      setupNodeContainer "$docker" "$nodeName"
    done
  done

  # Recreate API server certificates with updated subjects
  controlPlaneIpAddress=$(DOCKER_HOST="$KINST_DOCKER_MANAGER" docker inspect $KINST_CONTROL_PLANE | jq -r ".[].NetworkSettings.Networks.$DOCKER_NETWORK.IPAddress")
  DOMAINS="localhost,0.0.0.0,127.0.0.1,internal"

  if [[ ! -z "$controlPlaneIpAddress" ]]; then
    DOMAINS="$DOMAINS,$controlPlaneIpAddress"
  fi
  if [[ ! -z "$KINST_CONTROL_PLANE" ]]; then
    DOMAINS="$DOMAINS,$KINST_CONTROL_PLANE"
  fi
  if [[ ! -z "$DEPLOYMENT_ZONE" ]]; then
    DOMAINS="$DOMAINS,$DEPLOYMENT_ZONE,kube.$DEPLOYMENT_ZONE"
  fi

  echo "Generating API certs for domains: $DOMAINS"

  DOCKER_HOST="$KINST_DOCKER_MANAGER" docker exec "$KINST_CONTROL_PLANE" rm /etc/kubernetes/pki/apiserver.key || true
  DOCKER_HOST="$KINST_DOCKER_MANAGER" docker exec "$KINST_CONTROL_PLANE" rm /etc/kubernetes/pki/apiserver.crt || true
  DOCKER_HOST="$KINST_DOCKER_MANAGER" docker exec "$KINST_CONTROL_PLANE" kubeadm init phase certs apiserver --apiserver-cert-extra-sans=$DOMAINS
  DOCKER_HOST="$KINST_DOCKER_MANAGER" docker exec "$KINST_CONTROL_PLANE" cat /etc/kubernetes/admin.conf > ./kubeconfig

  mode=$(readConfig ".ingress.certs.mode" "manual")
  if [[ "$mode" == "selfSigned" ]]; then
    sed -i "s,    certificate-authority-data:.*,    insecure-skip-tls-verify: true,g" kubeconfig
  fi

  sed -i "s,    server: https://${CLUSTER_NAME}-control-plane:6443,    server: https://127.0.0.1:55555,g" kubeconfig
  cp ./kubeconfig ~/.kube/config || true
  cp ./kubeconfig ~/.kube/config-kind-$CLUSTER_NAME || true
  export KUBECONFIG=./kubeconfig

  rm -f ./kubeconfig.external || true
  cp ./kubeconfig ./kubeconfig.external

  CONTEXT_NAME=$(echo $DEPLOYMENT_ZONE | cut -d"." -f1 | cut -d"-" -f1-)
  if [[ ! -z "$CONTEXT_NAME" ]]; then
    sed -i "s,    server: https://127.0.0.1:55555,    server: https://kube.$DEPLOYMENT_ZONE:55555,g" kubeconfig.external
    sed -i "s,  name: kind-${CLUSTER_NAME},  name: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,    cluster: kind-${CLUSTER_NAME},    cluster: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,    user: kind-${CLUSTER_NAME},    user: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,- name: kind-${CLUSTER_NAME},- name: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,current-context: kind-${CLUSTER_NAME},current-context: kind-${CONTEXT_NAME},g" kubeconfig.external
  fi

  # Check connection
  sleep 5

  # If connection fails, try with external kubeconfig
  if ! kubectl get nodes; then
    echo "Trying with external kubeconfig..."
    export KUBECONFIG=./kubeconfig.external
    cp ./kubeconfig.external ~/.kube/config || true
  fi

  # If connection still fails, then fail
  if ! kubectl get nodes; then
    echo "ERROR: Unable to communicate with k8s cluster, exiting..."
    exit 1
  fi

  # Taint nodes
  for i in "${taintNodes[@]}"
  do
    echo "Tainting node: $i..."
    kubectl taint nodes --overwrite=true $i
  done
}

function setupSwarmManager() {
  dockerHost="$1"
  name="$2"

  if isInSwarm "$dockerHost"; then
    machineId=$(getSwarmId "$dockerHost")

    if ! isSwarmLeader "$dockerHost" "$machineId"; then
      echo "ERROR: Machine $name ($dockerHost) is already in docker swarm but not as manager"
      exit 1
    fi

    echo "Manager Machine $name ($dockerHost) is already manager of the docker swarm."
    checkDockerNetwork "$dockerHost"
    return
  fi

  echo ""
  echo "Creating docker swarm with manager machine $name ($dockerHost)..."
  DOCKER_HOST="$dockerHost" docker swarm init
  checkDockerNetwork "$dockerHost"
  echo "Created docker swarm with manager machine $name ($dockerHost)"
}

function setupSwarmWorker() {
  dockerHost="$1"
  name="$2"

  if isInSwarm "$dockerHost"; then
    echo "Worker Machine $name ($dockerHost) is already in a docker swarm."
    return
  fi

  echo ""
  echo "Connecting worker machine $name ($dockerHost) to docker swarm..."
  token=$(DOCKER_HOST="$KINST_DOCKER_MANAGER" docker swarm join-token worker | tail -n 2 | head -n 1 | cut -d" " -f9)
  endpoint=$(DOCKER_HOST="$KINST_DOCKER_MANAGER" docker swarm join-token worker | tail -n 2 | head -n 1 | cut -d" " -f10)
  DOCKER_HOST="$dockerHost" docker swarm join --token "$token" "$endpoint"
  echo "Connected worker machine $name ($dockerHost) to docker swarm"
}

function getSwarmId() {
  DOCKER_HOST="$1" docker info -fjson | jq -r ".Swarm.NodeID"
}

function isInSwarm() {
  state=$(DOCKER_HOST="$1" docker info -fjson | jq -r ".Swarm.LocalNodeState")
  if [[ "$state" == "active" ]]; then
    return 0
  fi
  return 1
}

function isSwarmLeader() {
  state=$(DOCKER_HOST="$1" docker node inspect "$2" | jq -r ".[].ManagerStatus.Leader")
  if [[ "$state" == "true" ]]; then
    return 0
  fi
  return 1
}

function checkDockerNetwork() {
  # Create the network if it does not exist
  DOCKER_HOST="$1" docker network list | grep "$DOCKER_NETWORK" || \
  DOCKER_HOST="$1" docker network create --driver overlay --subnet "$IP_SUBNET.0/16" --attachable "$DOCKER_NETWORK"
}

function setupKindControlPlane() {
  dockerHost="$1"
  image="$2"
  nodeName="${CLUSTER_NAME}-control-plane"

  if DOCKER_HOST="$dockerHost" docker ps -a | grep "$nodeName"; then
    echo "Control plane with name $nodeName already exists"
    return
  fi

  additionalArgs=""
  enableCgroups=false
  if DOCKER_HOST="$dockerHost" docker info | grep "cgroupns"; then
    enableCgroups=true
    additionalArgs="$additionalArgs --cgroupns=private"
  fi

  DOCKER_HOST="$dockerHost" docker run --name $nodeName --hostname $nodeName \
      --label io.x-k8s.kind.role=control-plane \
      --label io.x-k8s.kind.cluster=${CLUSTER_NAME} \
      --label io.x-k8s.kind.dynamic="yes" \
      --label io.x-k8s.kind.distributed="yes" \
      --privileged \
      --security-opt seccomp=unconfined \
      --security-opt apparmor=unconfined \
      --tmpfs /tmp \
      --tmpfs /run \
      --volume /var \
      --volume /lib/modules:/lib/modules:ro \
      -e KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER \
      --detach --tty \
      --net $DOCKER_NETWORK \
      --restart=on-failure:1 \
      --init=false \
      -p 55555:6443 \
      $additionalArgs \
      $image

  if [[ "$enableCgroups" == "true" ]]; then
    waitForCgroups "$dockerHost" "$nodeName"
  fi
  setupKubeadmConfig "$dockerHost" "$nodeName" "$nodeName" ""

  # Create the control plane node
  DOCKER_HOST="$dockerHost" docker exec "$nodeName" kubeadm init --config /kind/kubeadm.conf --skip-phases=preflight --v=6
}

function setupKindWorker() {
  dockerHost="$1"
  image="$2"
  nodeName="${CLUSTER_NAME}-$3"
  nodeLabels="$4"

  # Check if node exists
  if DOCKER_HOST="$dockerHost" docker ps -a | grep "$nodeName"; then
    echo "A node with name $nodeName already exists"
    return
  fi

  additionalArgs=""
  enableCgroups=false
  if DOCKER_HOST="$dockerHost" docker info | grep "cgroupns"; then
    enableCgroups=true
    additionalArgs="$additionalArgs --cgroupns=private"
  fi

  DOCKER_HOST="$dockerHost" docker run --name $nodeName --hostname $nodeName \
      --label io.x-k8s.kind.role=worker \
      --label io.x-k8s.kind.cluster=${CLUSTER_NAME} \
      --label io.x-k8s.kind.dynamic="yes" \
      --label io.x-k8s.kind.distributed="yes" \
      --privileged \
      --security-opt seccomp=unconfined \
      --security-opt apparmor=unconfined \
      --tmpfs /tmp \
      --tmpfs /run \
      --volume /var \
      --volume /lib/modules:/lib/modules:ro \
      -e KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER \
      --detach --tty \
      --net $DOCKER_NETWORK \
      --restart=on-failure:1 \
      --init=false \
      $additionalArgs \
      $image

  if [[ "$enableCgroups" == "true" ]]; then
    waitForCgroups "$dockerHost" "$nodeName"
  fi
  setupKubeadmConfig "$dockerHost" "$nodeName" "$KINST_CONTROL_PLANE" "$nodeLabels"

  # Join the worker node
  DOCKER_HOST="$dockerHost" docker exec "$nodeName" kubeadm join --config /kind/kubeadm.conf --skip-phases=preflight --v=6
}

function setupNodeContainer() {
  dockerHost="$1"
  nodeName="$2"

  containerConfig=$(DOCKER_HOST="$dockerHost" docker exec "$nodeName" cat /etc/containerd/config.toml | dasel -r toml -w json)

  # Add insecure repositories
  length=$(readArrayLength ".cluster.repositories.insecure")
  if [[ "$length" -le "0" ]]; then
    containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io".endpoint = ["https://ghcr.io"]')
    containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io".endpoint = ["https://registry.k8s.io"]')
    containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.ioo".endpoint = ["https://quay.io"]')

    containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.configs."ghcr.io".tls.insecure_skip_verify = true')
    containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.configs."registry.k8s.io".tls.insecure_skip_verify = true')
    containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.configs."quay.io".tls.insecure_skip_verify = true')
  else
    for index in `seq 0 $length`; do
      endpoint=$(readConfig ".cluster.repositories.insecure[$index]")
      name=$(echo "$endpoint" | cut -d "/" -f3-)
      containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.mirrors."'"$name"'".endpoint = ["'"$endpoint"'"]')
      containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.configs."'"$name"'".tls.insecure_skip_verify = true')
    done
  fi

  # Add docker private repositories
  length=$(readArrayLength ".machine.docker.repositories")
  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`; do
      name=$(readConfig ".machine.docker.repositories[$index].name")
      username=$(readConfig ".machine.docker.repositories[$index].username")
      password=$(readConfig ".machine.docker.repositories[$index].password")

      containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.configs."'"$name"'".auth.username = "'"$username"'"')
      containerConfig=$(echo "$containerConfig" | jq '.plugins."io.containerd.grpc.v1.cri".registry.configs."'"$name"'".auth.password = "'"$password"'"')
    done
  fi

  echo "$containerConfig" | dasel -r json -w toml > .container-config.tmp
  DOCKER_HOST="$dockerHost" docker cp "./.container-config.tmp" "$nodeName:/etc/containerd/config.toml"

  noProxyRegistries=$(readConfig ".cluster.repositories.no_proxy[]")
  if [[ -z "$noProxyRegistries" ]]; then
    noProxyRegistriesFormatted=""
  else
    noProxyRegistriesFormatted=$(echo "$noProxyRegistries" | tr "\n" ",")
    noProxyRegistriesFormatted=$(echo ",${noProxyRegistriesFormatted%?}")
  fi

  if [[ $(readConfig ".machine.docker.local_registry.enabled" "false") != "true" ]]; then
    if [[ $(readConfig ".machine.proxy.enabled" "true") == "true" ]]; then
      DOCKER_HOST="$dockerHost" docker exec "$nodeName" sh -c "mkdir -p /etc/systemd/system/containerd.service.d/ && cat <<-EOF >/etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment='HTTP_PROXY=$(readConfig ".machine.proxy.http_endpoint" "http://proxy:3128/")'
Environment='HTTPS_PROXY=$(readConfig ".machine.proxy.https_endpoint" "http://proxy:3128/")'
Environment='NO_PROXY=$(readConfig ".machine.proxy.exclusions" "169.254.169.254"),${IP_SUBNET}.0/16,10.96.0.0/16,192.168.0.0/16$noProxyRegistriesFormatted'
EOF
"
      DOCKER_HOST="$dockerHost" docker exec "$nodeName" sh -c 'systemctl daemon-reload'
      DOCKER_HOST="$dockerHost" docker exec "$nodeName" sh -c 'systemctl restart containerd'
    fi
  fi
}

function setupKubeadmConfig() {
  dockerHost="$1"
  nodeName="$2"
  controlPlane="$3"
  nodeLabels="$4"

  # Get assigned IP of the node
  nodeIpAddress=$(DOCKER_HOST="$dockerHost" docker inspect $nodeName | jq -r ".[].NetworkSettings.Networks.kind.IPAddress")
  kubernetesVersion=$(readConfig ".cluster.kinst.kubernetesVersion" "v1.25.9")

  # Setup kubeadm.conf
  DOCKER_HOST="$dockerHost" docker exec "$nodeName" sh -c "cat <<-EOF >/kind/kubeadm.conf
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  certSANs:
  - localhost
  - 0.0.0.0
  extraArgs:
    runtime-config: ""
clusterName: ${CLUSTER_NAME}
controlPlaneEndpoint: ${nodeName}:6443
controllerManager:
  extraArgs:
    enable-hostpath-provisioner: \"true\"
kubernetesVersion: ${kubernetesVersion}
networking:
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/16
scheduler:
  extraArgs: null
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
bootstrapTokens:
- token: abcdef.0123456789abcdef
localAPIEndpoint:
  advertiseAddress: ${nodeIpAddress}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: ${nodeIpAddress}
    node-labels: "${nodeLabels}"
    provider-id: kind://docker/${CLUSTER_NAME}/${nodeName}
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: ${controlPlane}:6443
    token: abcdef.0123456789abcdef
    unsafeSkipCAVerification: true
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    node-ip: ${nodeIpAddress}
    node-labels: "${nodeLabels}"
    provider-id: kind://docker/${CLUSTER_NAME}/${nodeName}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
cgroupRoot: /kubelet
evictionHard:
  imagefs.available: 0%
  nodefs.available: 0%
  nodefs.inodesFree: 0%
failSwapOn: false
imageGCHighThresholdPercent: 100
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
conntrack:
  maxPerCore: 0
iptables:
  minSyncPeriod: 1s
mode: iptables
EOF
"
}

function waitForCgroups() {
  dockerHost="$1"
  nodeName="$2"

  retry=0
  while [[ "$retry" < 10 ]]; do
    if DOCKER_HOST="$1" docker logs "$2" | grep -i "cgroup"; then
      sleep 5
      return
    fi

    echo "Waiting for cgroups to be up for $2..."
    sleep 5
  done

  echo "Timeout waiting for cgroups to be up for $2"
}


function deployDependenciesCluster() {
  echo ""
  echo "================= INSTALLING DEPENDENCIES ================="

  kubectl apply -f ./scripts/assets/local-path.yaml
  kubectl apply -f ./scripts/assets/calico.yaml
  sleep 5
  kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=kubernetes-internal-ip
  kubectl wait pods -n kube-system -l k8s-app=calico-kube-controllers --for condition=Ready --timeout=300s
}

event on preClusterCreation deleteOldCluster
event on onClusterCreation createKinstCluster
event on onClusterDependencies deployDependenciesCluster

# Read arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --delete-cluster)
      DELETE_CLUSTER=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

set -- ${ARGS[@]}