if [[ -z "$CLUSTER_NAME" ]]; then
  CLUSTER_NAME=$(readConfig ".cluster.name" "test-cluster")
fi

if [[ -z "$IP_SUBNET" ]]; then
  IP_SUBNET=$(readConfig ".cluster.networking.ip_subnet" "172.20.0")
fi

DEPLOYMENT_ZONE=$(readConfig ".ingress.domain" "abc.xyz")

LISTEN_IP=$(readConfig ".machine.listen_ip" "127.0.0.1")

REGISTRY_CONTAINER_NAME="$CLUSTER_NAME-docker-registry-proxy"
DNS_CONTAINER_NAME="$CLUSTER_NAME-dnsmasq"
INGRESS_CONTAINER_NAME="$CLUSTER_NAME-ingress"
NFS_CONTAINER_NAME="$CLUSTER_NAME-nfs"

mkdir -p "./configs"

export KUBECONFIG=./kubeconfig

