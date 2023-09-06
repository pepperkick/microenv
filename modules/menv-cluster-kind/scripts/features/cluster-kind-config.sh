#!/bin/bash

CLUSTER_CONFIG_FILE="./configs/cluster.yaml"

# TODO: Simplify this
function generateClusterConfig() {
  echo "Generating kind cluster config"

cat <<EOF > "$CLUSTER_CONFIG_FILE"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
EOF

  if [[ -z "$MICRO_ENV_CONFIG_FILE" ]]; then
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
networking:
  apiServerPort: 55555
  apiServerAddress: "0.0.0.0"
EOF
  else
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
networking:
$(yq ".cluster.kind.networking" $MICRO_ENV_CONFIG_FILE | awk '{print "  " $0}')
EOF
  fi

cat <<EOF >> "$CLUSTER_CONFIG_FILE"
containerdConfigPatches:
EOF

generateClusterCriConfig
generateClusterNodeConfig
}

function generateClusterNodeConfig() {
  defaultImage=$(readConfig ".cluster.kind.nodes.image" "kindest/node:v1.25.9@sha256:c08d6c52820aa42e533b70bce0c2901183326d86dcdcbedecc9343681db45161")

cat <<EOF >> "$CLUSTER_CONFIG_FILE"
nodes:
  - role: control-plane
    image: $defaultImage
EOF
  # Add worker nodes
  length=$(readArrayLength ".cluster.kind.nodes.workers")
  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`;do
      nodeLabels=$(readConfig ".cluster.kind.nodes.workers[$index].labels")
      nodeLabelsFormatted=$(echo "$nodeLabels" | yq -op | sed "s/ = /=/g" | tr "\n" ",")
      image=$(readConfig ".cluster.kind.nodes.workers[$index].image" "$defaultImage")

cat <<EOF >> "$CLUSTER_CONFIG_FILE"
  - role: worker
    kubeadmConfigPatches:
      - |
        kind: JoinConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "$nodeLabelsFormatted"
    image: $image
EOF
    done
  fi
}

function generateClusterCriConfig() {
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
  - |-
    [plugins."io.containerd.grpc.v1.cri"]
      [plugins."io.containerd.grpc.v1.cri".registry]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
EOF

  # Add insecure repositories
  length=$(readArrayLength ".cluster.repositories.insecure")

  if [[ "$length" -le "0" ]]; then
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
            endpoint = ["https://ghcr.io"]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
            endpoint = ["https://registry.k8s.io"]
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
            endpoint = ["https://quay.io"]
        [plugins."io.containerd.grpc.v1.cri".registry.configs]
          [plugins."io.containerd.grpc.v1.cri".registry.configs."ghcr.io".tls]
            insecure_skip_verify = true
          [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.k8s.io".tls]
            insecure_skip_verify = true
          [plugins."io.containerd.grpc.v1.cri".registry.configs."quay.io".tls]
            insecure_skip_verify = true
EOF
    return
  fi

  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`;do
      endpoint=$(readConfig ".cluster.repositories.insecure[$index]")
      name=$(echo "$endpoint" | cut -d "/" -f3-)
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
          [plugins."io.containerd.grpc.v1.cri".registry.mirrors."$name"]
            endpoint = ["$endpoint"]
EOF
    done
  fi

cat <<EOF >> "$CLUSTER_CONFIG_FILE"
        [plugins."io.containerd.grpc.v1.cri".registry.configs]
EOF

  # Add insecure repositories
  length=$(readArrayLength ".cluster.repositories.insecure")
  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`;do
      endpoint=$(readConfig ".cluster.repositories.insecure[$index]")
      name=$(echo "$endpoint" | cut -d "/" -f3-)
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
          [plugins."io.containerd.grpc.v1.cri".registry.configs."$name".tls]
            insecure_skip_verify = true
EOF
    done
  fi

  # Add docker private repositories
  length=$(readArrayLength ".machine.docker.repositories")
  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`;do
      name=$(readConfig ".machine.docker.repositories[$index].name")
      username=$(readConfig ".machine.docker.repositories[$index].username")
      password=$(readConfig ".machine.docker.repositories[$index].password")
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
          [plugins."io.containerd.grpc.v1.cri".registry.configs."$name"]
            [plugins."io.containerd.grpc.v1.cri".registry.configs."$name".auth]
              username = "$username"
              password = "$password"
EOF
    done
  fi

  # Add private repositories
  length=$(readArrayLength ".cluster.repositories.private")
  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`;do
      name=$(readConfig ".cluster.repositories.private[$index].name")
      username=$(readConfig ".cluster.repositories.private[$index].username")
      password=$(readConfig ".cluster.repositories.private[$index].password")
cat <<EOF >> "$CLUSTER_CONFIG_FILE"
          [plugins."io.containerd.grpc.v1.cri".registry.configs."$name"]
            [plugins."io.containerd.grpc.v1.cri".registry.configs."$name".auth]
              username = "$username"
              password = "$password"
EOF
    done
  fi
}