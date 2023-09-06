# MicroEnv AWS

Provides utilities to create microenvs in AWS cloud.

## Requirements

- aws cli

## Supported Features

### Fetch ingress domain certs from S3

If `s3` is used as `ingress.certs.mode` then it will fetch certificates from the S3 bucket configured.
The certs must be present as ZIP files with domain as the name
eg: s3://automations/certs/abc.com.zip
The ZIP must follow the following directory structure
- abc.com
  - cert.pem
  - chain.pem
  - fullchain.pem
  - privkey.pem

### Create Route53 entry

If `route53` is used as `dns.record` then it will automatically create a route53 with the current public IP of the machine (EC2).

### S3 Path Resolver

Provides support to resolve S3 paths. This will download from S3 and then return a local path.

## Config

```yaml
ingress:
  certs:
    # Automatically generate or fetch certificate based on the mode
    # Following modes are supported
    # - s3: Download certs from AWS S3.
    mode: s3

    # For S3 mode, the certs must be present as ZIP files with domain as the name
    # eg: s3://automations/certs/abc.com.zip
    # The ZIP must follow the following directory structure
    # - abc.com
    #   - cert.pem
    #   - chain.pem
    #   - fullchain.pem
    #   - privkey.pem
    s3:
      path: s3://automations/certs/

dns:
  enabled: true

  # Point the following domains to the cluster ingress
  # .ingress.domain is automatically added
  domains:
    - example.com

  # Automatically create route53 entries for the .ingress.domain
  # Following values are supported
  # - route53: Create entry in Route53
  record: route53

  # Configure values for Route53
  route53:
    hosted_zone: DUMMY
```
