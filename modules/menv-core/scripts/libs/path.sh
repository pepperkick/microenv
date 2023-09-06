declare -a PATH_RESOLVERS

function resolvePath() {
  export OUTPUT_RESOLVED_PATH=""
  for i in "${PATH_RESOLVERS[@]}"; do
    echo "Resolving path $1 using $i"
    if $i "$1" && [[ ! -z "$OUTPUT_RESOLVED_PATH" ]]; then
     return 0
    fi
  done

  echo "ERROR: No path resolvers successfully resolved the path $1"
  return 1
}

function registerPathResolver() {
  PATH_RESOLVERS+=($1)
  echo "Registered path resolver $1"
  echo "Resolvers: ${PATH_RESOLVERS[@]}"
}

function localPathResolver() {
  if [[ -f "$1" ]]; then
    export OUTPUT_RESOLVED_PATH="$1"
    return 0
  fi

  return 1
}

function registerLocalPathResolver() {
  registerPathResolver "localPathResolver"
}

function startPathResolverRegistration() {
  eventStage "RegisterPathResolvers"
}

event on preStartup startPathResolverRegistration
event on postRegisterPathResolvers registerLocalPathResolver