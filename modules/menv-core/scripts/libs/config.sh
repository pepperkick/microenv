function readConfig() {
  result=""

  if [[ -f "$MICRO_ENV_CONFIG_FILE" ]]; then
    result=$(yq -oy -r "$1" "$MICRO_ENV_CONFIG_FILE")
  fi

  if [[ "$result" == "null" ]] || [[ -z "$result" ]]; then
    if [[ -n "$2" ]]; then
      echo "$2"
    else
      echo ""
    fi
    return
  fi

  if ! resolveValue "$result"; then
    echo "ERROR: Failed to resolve value '$result'" >&2
    exit 1
  fi
}

function readArrayLength() {
  result=""

  if [[ -f "$MICRO_ENV_CONFIG_FILE" ]]; then
    result=$(yq -oy "$1 | length" "$MICRO_ENV_CONFIG_FILE")
  fi

  if [[ "$result" == "null" ]] || [[ -z "$result" ]]; then
    echo "0"
    return
  fi

  echo "$((result - 1))"
}

function abspath {
    if [[ -d "$1" ]]
    then
        pushd "$1" >/dev/null
        pwd
        popd >/dev/null
    elif [[ -e "$1" ]]
    then
        pushd "$(dirname "$1")" >/dev/null
        echo "$(pwd)/$(basename "$1")"
        popd >/dev/null
    else
        echo "$1" does not exist! >&2
        return 127
    fi
}