#!/bin/bash

function copyModule() {
  module="$1"
  path="./modules/menv-${module}"
  if [[ ! -d "$path" ]]; then
    echo "ERROR: Module ${module} does not exist at ${path}"
    exit 1
  fi

  cp -R "./modules/menv-${module}/scripts"* "./.tmp"

  if [[ -f "./modules/menv-${module}/script.yaml" ]]; then
    yq eval-all '. as $item ireduce ({}; . *+ $item)' "./.tmp/script.yaml" "./modules/menv-${module}/script.yaml" > "./.tmp/script.yaml.tmp"
    mv "./.tmp/script.yaml.tmp" "./.tmp/script.yaml"
  fi
}

# Ensure yq is present
if which yq; then
  yq --version
else
  curl -Lo ./yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64
  chmod +x ./yq
  mv ./yq /usr/bin/yq
fi

# Read args
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--config)
      MICRO_ENV_BUILD_FILE="$2"
      shift
      shift
      ;;
    -d|--distribution)
      MICRO_ENV_BUILD_FILE="./distributions/menv-$2/build.yaml"
      DISTRIBUTION_PATH="./distributions/menv-$2/"
      shift
      shift
      ;;
    *)
      shift 1
      ;;
  esac
done

if [[ -z "$MICRO_ENV_BUILD_FILE" ]]; then
  echo "Config file $MICRO_ENV_BUILD_FILE not found."
  exit 1
else
  echo "Using config file '$MICRO_ENV_BUILD_FILE'"
fi

rm -rf .tmp || true

mkdir -p ./.tmp
mkdir -p ./.tmp/scripts

echo "commands:" > ./.tmp/script.yaml

copyModule core

# Read modules from build.yaml
length=$(yq -oy ".modules | length - 1" "$MICRO_ENV_BUILD_FILE")
if [[ "$length" -ge "0" ]]; then
  for index in `seq 0 $length`;do
    module=$(yq -oy ".modules[$index]" "$MICRO_ENV_BUILD_FILE")
    copyModule $module
  done
fi

cp "./modules/menv.sh" "./.tmp"

if [[ ! -z "$DISTRIBUTION_PATH" ]]; then
  cp "$DISTRIBUTION_PATH"* "./.tmp"
  rm "./.tmp/build.yaml" || true
fi

name=$(yq -oy ".output" "$MICRO_ENV_BUILD_FILE")
if [[ -z "$name" ]] || [[ "$name" == "null" ]]; then
  name="menv"
fi
cd .tmp && zip "$name.zip" -r * && mv "$name.zip" ../


