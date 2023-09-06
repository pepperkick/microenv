#!/bin/bash

set -e

EVENT_STAGES=(
  SystemSetup
  Setup
  ClusterCreation
  ClusterDependencies
  Config
  Installation
)
ARGS="$@"

source "./scripts/libs/events.sh"

# Read arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --only-*)
      parseEventArg $1
      ONLY_EVENT_STAGES=("${ONLY_EVENT_STAGES[@]}" "$EVENT_ARG")
      PROCESSED_EVENT_STAGES=("${ONLY_EVENT_STAGES[@]}")
      shift
      ;;
    --after-*)
      parseEventArg $1
      for index in "${!PROCESSED_EVENT_STAGES[@]}" ; do
        [[ " ${PROCESSED_EVENT_STAGES[*]} " =~ " $EVENT_ARG " ]] && unset -v 'PROCESSED_EVENT_STAGES[$index]' ;
      done
      shift
      ;;
    --from-*)
      parseEventArg $1
      for index in "${!PROCESSED_EVENT_STAGES[@]}" ; do
        [[ " ${PROCESSED_EVENT_STAGES[*]} " =~ " $EVENT_ARG " ]] && unset -v 'PROCESSED_EVENT_STAGES[$index]' ;
      done
      PROCESSED_EVENT_STAGES=("$EVENT_ARG" "${PROCESSED_EVENT_STAGES[@]}")
      shift
      ;;
    --before-*)
      parseEventArg $1
      PROCESSED_EVENT_STAGES=($(echo "${PROCESSED_EVENT_STAGES[@]}" | rev))
      for index in "${!PROCESSED_EVENT_STAGES[@]}" ; do
        [[ " ${PROCESSED_EVENT_STAGES[*]} " =~ " $(echo $EVENT_ARG | rev) " ]] && unset -v 'PROCESSED_EVENT_STAGES[$index]' ;
      done
      PROCESSED_EVENT_STAGES=($(echo "${PROCESSED_EVENT_STAGES[@]}" | rev))
      shift
      ;;
    --skip-*|--disable-*)
      parseEventArg $1
      for index in "${!PROCESSED_EVENT_STAGES[@]}" ; do
        [[ " ${PROCESSED_EVENT_STAGES[$index]} " =~ " $EVENT_ARG " ]] && unset -v 'PROCESSED_EVENT_STAGES[$index]' ;
      done
      shift
      ;;
    --add-*)
      parseEventArg $1
      PROCESSED_EVENT_STAGES+=($1)
      shift
      ;;
    *)
      shift 1
      ;;
  esac
done

set -- ${ARGS[@]}
echo "Stages to perform: ${PROCESSED_EVENT_STAGES[*]}"

eventStage "Startup"
for i in "${PROCESSED_EVENT_STAGES[@]}"
do
   eventStage "$i"
done
