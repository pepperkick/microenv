#!/bin/bash

CLUSTER_CONFIG_FILE="./configs/cluster.yaml"

function initKindCluster() {
  export DEPLOYMENT_ZONE=$(readConfig ".ingress.domain" "abc.xyz")
}

function deleteOldKindCluster() {
  echo ""
  echo "================= CREATING CLUSTER ================="

  if [[ "$DELETE_CLUSTER" == "true" ]]; then
    # Delete existing cluster if running
    # TODO: Add retry for this in case it fails temporarily
    kind delete cluster --name $CLUSTER_NAME
  fi
}

function createKindCluster() {
  if cat $CLUSTER_CONFIG_FILE | grep "0.0.0.0"; then
    export LISTEN_IP="0.0.0.0"
  fi

  generateClusterConfig

  # Create cluster
  kind create cluster --config $CLUSTER_CONFIG_FILE --kubeconfig ./kubeconfig --retain || [[ "$DELETE_CLUSTER" != "true" ]]
  mkdir -p ~/.kube || true
  cp ./kubeconfig ~/.kube/config
  cp ./kubeconfig ~/.kube/config-kind-$CLUSTER_NAME
  export KUBECONFIG=~/.kube/config-kind-$CLUSTER_NAME

  if cat $CLUSTER_CONFIG_FILE | grep "0.0.0.0"; then
    DOMAINS="localhost,0.0.0.0,127.0.0.1,internal,$DEPLOYMENT_ZONE,kube.$DEPLOYMENT_ZONE"

    # Check if EC2 public DNS is available
    PUBLIC_DNS=$(curl -s http://169.254.169.254/latest/meta-data/public-hostname)
    COUNT=$(echo $PUBLIC_DNS | wc -l)
    if (( $COUNT == 1 )) && [[ ! -z "$PUBLIC_DNS" ]]; then
      DOMAINS="$DOMAINS,$PUBLIC_DNS"
    fi

    # Recreate API server certificates with updated subjects
    docker exec ${CLUSTER_NAME}-control-plane rm /etc/kubernetes/pki/apiserver.key
    docker exec ${CLUSTER_NAME}-control-plane rm /etc/kubernetes/pki/apiserver.crt
    docker exec ${CLUSTER_NAME}-control-plane kubeadm init phase certs apiserver --apiserver-cert-extra-sans=$DOMAINS
    export NO_PROXY="$NO_PROXY,0.0.0.0,internal"

    CONTEXT_NAME=$(echo $DEPLOYMENT_ZONE | cut -d"." -f1 | cut -d"-" -f1-)

    rm -f ./kubeconfig.external || true
    cp ./kubeconfig ./kubeconfig.external
    sed -i "s,    server: https://0.0.0.0:55555,    server: https://kube.$DEPLOYMENT_ZONE:55555,g" kubeconfig.external
    sed -i "s,  name: kind-${CLUSTER_NAME},  name: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,    cluster: kind-${CLUSTER_NAME},    cluster: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,    user: kind-${CLUSTER_NAME},    user: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,- name: kind-${CLUSTER_NAME},- name: kind-${CONTEXT_NAME},g" kubeconfig.external
    sed -i "s,current-context: kind-${CLUSTER_NAME},current-context: kind-${CONTEXT_NAME},g" kubeconfig.external
  fi

  COUNT=$(kubectl get nodes --no-headers | wc -l)
  if (( $COUNT == 1 )); then
    kubectl label nodes $CLUSTER_NAME-control-plane node-role.kubernetes.io/master="true" --overwrite
    SINGLE_NODE_ONLY=true
  fi

  # Check connection
  kubectl get nodes

  if [[ $(readConfig ".machine.docker.local_registry.enabled" "false") != "true" ]]; then
      if [[ $(readConfig ".machine.proxy.enabled" "true") == "true" ]]; then
          for NODE in $(kind get nodes --name "$CLUSTER_NAME"); do
              docker exec "$NODE" sh -c "mkdir -p /etc/systemd/system/containerd.service.d/ && cat <<-EOF >/etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment='HTTP_PROXY=$(readConfig ".machine.proxy.http_endpoint" "http://proxy:3128/")'
Environment='HTTPS_PROXY=$(readConfig ".machine.proxy.https_endpoint" "http://proxy:3128/")'
Environment='NO_PROXY=$(readConfig ".machine.proxy.exclusions" "169.254.169.254"),${IP_SUBNET}.0/16,10.96.0.0/16,192.168.0.0/16'
EOF
"
              docker exec "$NODE" sh -c 'systemctl daemon-reload'
              docker exec "$NODE" sh -c 'systemctl restart containerd'
          done
      fi
  fi
}

function deployDependenciesKindCluster() {
  echo ""
  echo "================= INSTALLING DEPENDENCIES ================="

  if cat $CLUSTER_CONFIG_FILE | grep "disableDefaultCNI: true"; then
    # Install Calico if default Kindnet CNI is disabled
    echo "Default CNI is disabled for the cluster. Installing calico CNI..."
    kubectl apply -f ./scripts/assets/calico.yaml
    sleep 5
    kubectl wait pods -n kube-system -l k8s-app=calico-kube-controllers --for condition=Ready --timeout=300s
  fi
}

function checkDockerNetwork() {
  # Create the network if it does not exist
  docker network list | grep "kind" || \
  docker network create --driver bridge --subnet "$IP_SUBNET.0/16" "kind"
}

event on onStartup initKindCluster
event on preSetup checkDockerNetwork
event on preClusterCreation deleteOldKindCluster
event on onClusterCreation createKindCluster
event on onClusterDependencies deployDependenciesKindCluster

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