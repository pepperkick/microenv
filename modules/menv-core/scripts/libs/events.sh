#!/bin/bash

PROCESSED_EVENT_STAGES=("${EVENT_STAGES[@]}")
ONLY_EVENT_STAGES=()

function parseEventArg() {
  EVENT_ARG=$(echo "$1" | cut -d"-" -f4- | sed -r 's/(^|-)(\w)/\U\2/g')

  if [[ ! " ${EVENT_STAGES[*]} " =~ " $EVENT_ARG " ]]; then
    echo "Event stage '$EVENT_ARG' not found"
    exit 1
  fi
}

function eventStage() {
  pids=""
  event emit pre$1
  event emit init$1
  event emit on$1
  event emit post$1
  wait $pids
}