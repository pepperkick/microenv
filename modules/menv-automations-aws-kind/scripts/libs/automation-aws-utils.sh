export AWS_PAGER=""

# Read arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance-name)
      INSTANCE_NAME="$2"
      shift
      shift
      ;;
    *)
      shift
      ;;
  esac
done

set -- ${ARGS[@]}