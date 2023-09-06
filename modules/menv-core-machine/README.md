# MicroEnv Core Machine

Set up the machine with prerequisites to use for microenv.

## Config

```yaml
# This section configures the machine
machine:
  ssh:
    enabled: false

  swap:
    enabled: false
    ## Size of the swapfile to create
    ## $size * 1MB
    size: "2048"

  proxy:
    # Enable this if the machine is running behind corp proxy
    enabled: false
    http_endpoint: http://proxy:3128/
    https_endpoint: http://proxy:3128/
    exclusions: "169.254.169.254"

  docker:
    # Authentication for private docker repositories
    repositories:
      - name: registry.com
        username: test
        password: test
```