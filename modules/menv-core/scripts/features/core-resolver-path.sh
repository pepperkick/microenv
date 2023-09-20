declare -a PATH_RESOLVERS

function resolvePath() {
  export OUTPUT_RESOLVED_PATH=""
  resolvers=(${PATH_RESOLVERS[@]} "localPathResolver")
  for i in "${resolvers[@]}"; do
    if $i "$1" && [[ ! -z "$OUTPUT_RESOLVED_PATH" ]]; then
     return 0
    fi
  done

  echo "ERROR: No path resolvers successfully resolved the path $1" >&2
  return 1
}

function registerPathResolver() {
  PATH_RESOLVERS+=($1)
  echo "Registered path resolver $1"
  echo "Path Resolvers: ${PATH_RESOLVERS[@]}"
}

function localPathResolver() {
  if [[ -f "$1" ]]; then
    export OUTPUT_RESOLVED_PATH="$1"
    return 0
  fi

  return 1
}

function startPathResolverRegistration() {
  eventStage "RegisterPathResolvers"
}

event on preStartup startPathResolverRegistration