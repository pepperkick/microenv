#!/bin/bash

function s3PathResolver() {
    if [[ $1 != "s3://"* ]]; then
      return
    fi

    echo "Fetching $1 from s3..."

    file=$(basename $1)
    path="$file"
    if aws s3 cp "$1" "$path"; then
      export OUTPUT_RESOLVED_PATH="$path"
      return 0
    else
      export OUTPUT_RESOLVED_PATH=""
      return 1
    fi
}

function registerS3PathResolver() {
  registerPathResolver "s3PathResolver"
}

event on onRegisterPathResolvers registerS3PathResolver