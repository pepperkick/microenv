#!/bin/bash

# Helper functions
function setTestPath() {
    export test_path="./assets/test-$1"
}

function buildTest() {
  builder="$(pwd)/../build.sh"
  cur="$(pwd)"
  cd "$(pwd)/$test_path"
  if [[ "$DEBUG_ENABLED" == "true" ]]; then
    "$builder" -c "./build.yaml"
  else
    "$builder" -c "./build.yaml" 2>/dev/null 1>/dev/null
  fi
  cd "$cur"
}

# Should be able to do basic build
test_should_build_basic() {
  setTestPath "build-basic"
  buildTest
  assert "[[ -f "${test_path}/menv.zip" ]]" "${test_path}/menv.zip file not found."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "menv.sh"" "menv.sh file not found in the build."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "script.yaml"" "script.yaml file not found in the build."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "scripts/create.sh"" "scripts/create.sh file not found in the build."
}

# Should be able to build with local module
test_should_build_local_module() {
  setTestPath "build-local-module"
  buildTest
  assert "[[ -f "${test_path}/menv.zip" ]]" "${test_path}/menv.zip file not found."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "menv.sh"" "menv.sh file not found in the build."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "script.yaml"" "script.yaml file not found in the build."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "scripts/test.sh"" "scripts/create.sh file not found in the build."
}

# Should be able to build with git module
test_should_build_git_module() {
  setTestPath "build-git-module"
  buildTest
  assert "[[ -f "${test_path}/menv.zip" ]]" "${test_path}/menv.zip file not found."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "menv.sh"" "menv.sh file not found in the build."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "script.yaml"" "script.yaml file not found in the build."
  assert "unzip -l "${test_path}/menv.zip" | grep -q "scripts/features/core-machine-linux.sh"" "scripts/create.sh file not found in the build."
}
