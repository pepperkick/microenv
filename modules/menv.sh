#!/bin/bash

set -e

ARGS="$@"

while [[ $# -gt 0 ]]; do
  case $1 in
    --config)
      MICRO_ENV_CONFIG_FILE="$2"
      shift
      shift
      ;;
    --debug)
      set -x
      shift
      ;;
    *)
      shift 1
      ;;
  esac
done

if [[ -z "$MICRO_ENV_CONFIG_FILE" ]]; then
  if [[ -f "./config.yaml" ]]; then
    MICRO_ENV_CONFIG_FILE="./config.yaml"
  fi
fi

if [[ -z "$MICRO_ENV_CONFIG_FILE" ]]; then
  echo "No config file present, will use default values."
else
  echo "Using config file '$MICRO_ENV_CONFIG_FILE'"
fi

# Ensure yq is present
if which yq; then
  yq --version
else
  curl -Lo ./yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64
  chmod +x ./yq
  if ! mv ./yq /usr/bin/yq; then
    echo "Cannot move yq to common location, updating PATH variable instead."
    PATH="$PATH:$PWD"
  fi
fi

SCRIPT_METADATA_FILE="./script.yaml"
if [[ ! -f "$SCRIPT_METADATA_FILE" ]]; then
  echo "ERROR: $SCRIPT_METADATA_FILE not found"
  exit 1
fi

set -- ${ARGS[@]}

# Loop through commands and register them
cmdResult=$(command="$1" yq '.commands[] | select(.name==env(command))' "$SCRIPT_METADATA_FILE")

if [[ -z "$cmdResult" ]]; then
  # No command was found, print help instead
  echo "Unknown command $1"
  echo ""

  typeMainHelp=$(yq '.commands | filter(.type=="main")' "$SCRIPT_METADATA_FILE")
  length=$(echo -e "commands:\n$(echo "$typeMainHelp" | awk '{print "  " $0}')" | yq -oy ".commands | length - 1")
  if [[ "$length" -ge "0" ]]; then
    echo "Main Commands"
    for index in `seq 0 $length`;do
      help=$(echo -e "commands:\n$(echo "$typeMainHelp" | awk '{print "  " $0}')" | yq -oy ".commands[$index].help")
      echo "$help" | awk '{print "  " $0}'
    done
  fi

  typeAutomationsHelp=$(yq '.commands | filter(.type=="automation")' "$SCRIPT_METADATA_FILE")
  length=$(echo -e "commands:\n$(echo "$typeAutomationsHelp" | awk '{print "  " $0}')" | yq -oy ".commands | length - 1")
  if [[ "$length" -ge "0" ]]; then
    echo ""
    echo "Automation Commands"
    for index in `seq 0 $length`;do
      help=$(echo -e "commands:\n$(echo "$typeAutomationsHelp" | awk '{print "  " $0}')" | yq -oy ".commands[$index].help")
      echo "$help" | awk '{print "  " $0}'
    done
  fi

  typeUtilityHelp=$(yq '.commands | filter(.type=="utility")' "$SCRIPT_METADATA_FILE")
  length=$(echo -e "commands:\n$(echo "$typeUtilityHelp" | awk '{print "  " $0}')" | yq -oy ".commands | length - 1")
  if [[ "$length" -ge "0" ]]; then
    echo ""
    echo "Utility Commands"
    for index in `seq 0 $length`;do
      help=$(echo -e "commands:\n$(echo "$typeUtilityHelp" | awk '{print "  " $0}')" | yq -oy ".commands[$index].help")
      echo "$help" | awk '{print "  " $0}'
    done
  fi
else
  for f in ./scripts/libs/*.sh; do source $f; done
  for f in ./scripts/features/*.sh; do source $f; done

  script=$(echo "$cmdResult" | yq ".script")
  source "$script"
fi
