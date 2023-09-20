declare -a VALUE_RESOLVERS

function resolveValue() {
  export OUTPUT_RESOLVED_VALUE=""
  resolvers=(${VALUE_RESOLVERS[@]} "envValueResolver" "fileValueResolver" "passthroughValueResolver")
  for i in "${resolvers[@]}"; do
    if $i "$1" && [[ ! -z "$OUTPUT_RESOLVED_VALUE" ]]; then
     echo "$OUTPUT_RESOLVED_VALUE"
     return 0
    fi
  done

  echo "ERROR: No value resolvers successfully resolved the value '$1'" >&2
  return 1
}

function registerValueResolver() {
  VALUE_RESOLVERS+=($1)
  echo "Registered value resolver $1"
  echo "Value Resolvers: ${VALUE_RESOLVERS[@]}"
}

function passthroughValueResolver() {
  if [[ ! -z "$1" ]]; then
    export OUTPUT_RESOLVED_VALUE="$1"
    return 0
  fi

  return 1
}

function envValueResolver() {
  if [[ "$1" != "env://"* ]]; then
    return
  fi

  env=$(echo "$1" | cut -d "/" -f3)

  if [[ -z "$env" ]]; then
    export OUTPUT_RESOLVED_VALUE=""
    return 1
  fi

  value=$(echo "${!env}")
  if [[ -z "$value" ]]; then
    export OUTPUT_RESOLVED_VALUE=""
    return 1
  fi

  export OUTPUT_RESOLVED_VALUE="$value"
  return 0
}


function fileValueResolver() {
  if [[ "$1" != "file://"* ]]; then
    return
  fi

  file=$(echo "$1" | cut -d "/" -f3-)

  if [[ ! -f "$file" ]]; then
    export OUTPUT_RESOLVED_VALUE=""
    return 1
  fi

  value=$(cat "${file}")
  if [[ -z "$value" ]]; then
    export OUTPUT_RESOLVED_VALUE=""
    return 1
  fi

  export OUTPUT_RESOLVED_VALUE="$value"
  return 0
}

function startValueResolverRegistration() {
  eventStage "RegisterValueResolvers"
}

event on preStartup startValueResolverRegistration