#!/bin/bash

set -e

function copyModule() {
  module="$1"
  path="$2"
  echo "$2"
  if [[ ! -d "$path" ]]; then
    echo "ERROR: Module ${module} does not exist at ${path}"
    exit 1
  fi

  cp -R "$path/scripts"* "./.tmp"

  if [[ -f "$path/script.yaml" ]]; then
    yq eval-all '. as $item ireduce ({}; . *+ $item)' "./.tmp/script.yaml" "$path/script.yaml" > "./.tmp/script.yaml.tmp"
    mv "./.tmp/script.yaml.tmp" "./.tmp/script.yaml"
  fi
}

function copyLocalModule() {
  module="$1"
  path="./modules/menv-${module}"
  copyModule "$module" "$path"
}

function copyGitModule() {
  repo="$1"
  branch="$2"
  shift
  shift

  paths=("$@")

  if [[ -z "$branch" ]]; then
    branch="main"
  fi

  pwd=$PWD
  git clone --depth=1 --no-checkout "$repo" ".tmp/git"
  cd ".tmp/git"
  git sparse-checkout init
  git sparse-checkout set "${paths[@]}"
  git checkout "$branch"
  cd "$pwd"

  for i in "${paths[@]}"; do
    path="./.tmp/git/$i"
    copyModule "$i" "$path"
  done

  rm -rf ".tmp/git"
}

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

if [[ -d "./modules/menv-core" ]]; then
  copyLocalModule core
else
  copyGitModule "https://github.com/pepperkick/microenv.git" "main" "modules/menv-core"
fi

# Read modules from build.yaml
length=$(yq -oy ".modules | length - 1" "$MICRO_ENV_BUILD_FILE")
if [[ "$length" -ge "0" ]]; then
  for index in `seq 0 $length`; do
    # Check if it has git url
    git=$(yq -oy ".modules[$index].git" "$MICRO_ENV_BUILD_FILE")
    if [[ -z "$git" ]]; then
      module=$(yq -oy ".modules[$index]" "$MICRO_ENV_BUILD_FILE")
      copyLocalModule "$module"
    else
      branch=$(yq -oy ".modules[$index].branch" "$MICRO_ENV_BUILD_FILE")
      if [[ "$branch" == "null" ]]; then
        branch="main"
      fi

      pathsLength=$(yq -oy ".modules[$index].paths | length - 1" "$MICRO_ENV_BUILD_FILE")
      declare -a modulePaths=()
      for pathIndex in `seq 0 $pathsLength`; do
        module=$(yq -oy ".modules[$index].paths[$pathIndex]" "$MICRO_ENV_BUILD_FILE")
        modulePaths+=($module)
      done

      copyGitModule "$git" "$branch" "${modulePaths[@]}"
    fi
  done
fi

if [[ -f "./modules/menv.sh" ]]; then
  cp "./modules/menv.sh" "./.tmp"
else
  curl -Lo "./.tmp/menv.sh" "https://raw.githubusercontent.com/pepperkick/microenv/main/modules/menv.sh"
fi

if [[ ! -z "$DISTRIBUTION_PATH" ]]; then
  cp "$DISTRIBUTION_PATH"* "./.tmp"
  rm "./.tmp/build.yaml" || true
fi

name=$(yq -oy ".output" "$MICRO_ENV_BUILD_FILE")
if [[ -z "$name" ]] || [[ "$name" == "null" ]]; then
  name="menv"
fi
cd .tmp && zip "$name.zip" -r * && mv "$name.zip" ../


