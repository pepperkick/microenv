function initialize() {
  if which gomplate; then
    gomplate --help > /dev/null
  else
    curl -o ./gomplate -sSL https://github.com/hairyhenderson/gomplate/releases/download/v3.11.5/gomplate_linux-amd64-slim
    chmod +x ./gomplate
    mv ./gomplate /usr/bin/gomplate
  fi

  if [[ -f "$MICRO_ENV_CONFIG_FILE" ]]; then
    # Use gomplate to render config yaml
    if echo "$MICRO_ENV_CONFIG_FILE" | grep ".tmpl"; then
      echo "Found template config file '$MICRO_ENV_CONFIG_FILE', rendering it..."
      OUTPUT=$(cat "$MICRO_ENV_CONFIG_FILE" | gomplate)
      echo "$OUTPUT" > "./config.final.yaml"
      export MICRO_ENV_CONFIG_FILE="./config.final.yaml"
    fi
  fi

  if [[ -z "$CLUSTER_NAME" ]]; then
    export CLUSTER_NAME=$(readConfig ".cluster.name" "test-cluster")
  fi

  if [[ -z "$IP_SUBNET" ]]; then
    export IP_SUBNET=$(readConfig ".cluster.networking.ip_subnet" "172.20.0")
  fi

  export LISTEN_IP=$(readConfig ".machine.listen_ip" "0.0.0.0")

  mkdir -p "./configs"

  export KUBECONFIG=./kubeconfig

  # For some reason kind kube proxy does not work if network name is not "kind"
  # TODO: Have to investigate why does this happen
  export DOCKER_NETWORK="kind"
}

event on initStartup initialize