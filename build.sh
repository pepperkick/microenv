#!/bin/bash

set -e

function handleBuild() {
  config="$1"
  extra_contents="$2"
  echo "Handling build for config '$config' ($extra_contents)"

  if [[ -z "$config" ]]; then
    echo "Config file '$config' not found."
    exit 1
  else
    echo "Using config file '$config'"
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
  length=$(yq -oy ".modules | length - 1" "$config")
  if [[ "$length" -ge "0" ]]; then
    for index in `seq 0 $length`; do
      # Check if it has git url
      git=$(yq -oy ".modules[$index].git" "$config")
      if [[ -z "$git" ]]; then
        module=$(yq -oy ".modules[$index]" "$config")
        copyLocalModule "$module"
      else
        branch=$(yq -oy ".modules[$index].branch" "$config")
        proxy=$(yq -oy ".modules[$index].proxy" "$config")

        if [[ "$branch" == "null" ]]; then
          branch="main"
        fi

        if [[ "$proxy" != "null" ]]; then
          export VAR_GIT_PROXY="$proxy"
        fi

        pathsLength=$(yq -oy ".modules[$index].paths | length - 1" "$config")
        declare -a modulePaths=()
        for pathIndex in `seq 0 $pathsLength`; do
          module=$(yq -oy ".modules[$index].paths[$pathIndex]" "$config")
          modulePaths+=($module)
        done

        copyGitModule "$git" "$branch" "${modulePaths[@]}"
        unset VAR_GIT_PROXY
      fi
    done
  fi

  if [[ -f "./modules/menv.sh" ]]; then
    cp "./modules/menv.sh" "./.tmp"
  else
    curl -Lo "./.tmp/menv.sh" "https://raw.githubusercontent.com/pepperkick/microenv/main/modules/menv.sh"
  fi

  if [[ ! -z "$extra_contents" ]]; then
    cp -r "$extra_contents"* "./.tmp"
    rm "./.tmp/build.yaml" || true
  fi

  name=$(yq -oy ".output" "$config")
  if [[ -z "$name" ]] || [[ "$name" == "null" ]]; then
    name="menv"
  fi

  cd .tmp && zip "$name.zip" -r * && mv "$name.zip" ../ && cd ../
}

function copyModule() {
  module="$1"
  path="$2"

  echo "Copying module $1..."

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

  if [[ ! -z "$VAR_GIT_PROXY" ]]; then
    export HTTP_PROXY="$VAR_GIT_PROXY"
    export HTTPS_PROXY="$VAR_GIT_PROXY"
  fi

  pwd=$PWD
  git clone --depth=1 --no-checkout --branch "$branch" "$repo" ".tmp/git"
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
  unset HTTP_PROXY
  unset HTTPS_PROXY
}

# Ensure yq is present
if which yq; then
  yq --version > /dev/null
else
  curl -Lo ./yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64
  chmod +x ./yq
  if ! mv ./yq /usr/bin/yq; then
    echo "Cannot move yq to common location, updating PATH variable instead."
    PATH="$PATH:$PWD"
  fi
fi

if which zip; then
  zip --version > /dev/null
else
  yum install -y zip
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
    -A|--all-distributions)
      ALL_DISTRIBUTIONS=true
      shift
      ;;
    *)
      shift 1
      ;;
  esac
done

if [[ "$ALL_DISTRIBUTIONS" == "true" ]]; then
  for d in "./distributions/"*; do
   handleBuild "$d/build.yaml" "$d"
  done
else
  handleBuild "$MICRO_ENV_BUILD_FILE" "$DISTRIBUTION_PATH"
fi
