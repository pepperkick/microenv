# MicroEnv Core Ingress

Set up ingress and dns server for microenv

## Config

```yaml
# This section configures the ingress server
ingress:
  enabled: true

  # Base domain to use for the cluster.
  domain: "abc.xyz"

  # Configure the following domains
  domains:
    - example.com

  # Configure the certs location
  certs:
    # Automatically generate or fetch certificate based on the mode
    # Following modes are supported
    # - manual: Place the certs manually at the specified location.
    mode: manual

    # For Manual mode, the paths must point to corresponding cert files
    paths:
      key: ./certs/key.pem
      bundle: ./certs/cert-bundle.pem

# This section configures the dnsmasq server
dns:
  enabled: true

  # Point the following domains to the cluster ingress
  # .ingress.domain is automatically added
  domains:
    - example.com

  # Automatically create route53 entries for the .ingress.domain
  # Following values are supported
  # - manual: Entry has to be done manually
  record: manual
```