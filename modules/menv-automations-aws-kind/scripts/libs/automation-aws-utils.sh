export AWS_PAGER=""

ARGS="$@"

# Read arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance-name)
      INSTANCE_NAME="$2"
      shift
      shift
      ;;
    --spot-instance)
      USE_SPOT_INSTANCE="true"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

set -- ${ARGS[@]}