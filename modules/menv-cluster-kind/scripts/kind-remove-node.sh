#!/bin/bash

# ============================================================================
# Goal of this script is to remove nodes from existing KIND cluster
# NOTE: This is not officially supported by KIND
# ============================================================================

TARGET_NODES="${@:2}"
IFS=' ' read -r -a TARGET_NODES <<< "$TARGET_NODES"

# Remove node for each name provided
for element in "${TARGET_NODES[@]}"
do
  if [[ "$element" == "--"* ]]; then
    continue
  fi

  if [[ "$element" == "control-plane" ]]; then
    echo "ERROR: Cannot remove $element node"
    exit 1
  fi

  nodeName="${CLUSTER_NAME}-${element}"

  # Check if node exists
  if ! docker ps -a | grep "$nodeName"; then
    echo "ERROR: No node exists with name $nodeName"
  fi

  echo ""
  echo "Deleting node $nodeName..."

  kubectl delete node "$nodeName"
  docker kill "$nodeName"
  docker rm "$nodeName" || true

  echo "Deleted node $nodeName"
done
