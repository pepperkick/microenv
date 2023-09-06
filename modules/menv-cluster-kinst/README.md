# MicroEnv Cluster KINST

Use KINST to create a new K8s cluster.

## KINST

KINST is a collection of bash scripts that utilizes docker swarm to create KIND clusters with nodes that span across multiple machines. 

Intended to test heavier workload where resource usage are high and horizontal scaling is required.

## Requirements

- docker
- kind

## Config

```yaml
cluster:
  kinst:
    # Configure the kubernetes nodes for KINST
    nodes:
      image: kindest/node:v1.25.9@sha256:c08d6c52820aa42e533b70bce0c2901183326d86dcdcbedecc9343681db45161

    # Configure the machines to use for KINST.
    # Each machine must be accessible from where the scripts are running from to create docker swarm.
    # Each machine must be initialized with core-machine module to ensure all dependencies are present.
    # The first machine is always the manager machine.
    # It is required to run KINST only from manager machine.
    # The manager machine will contain the control-plane node
    machines:
      - name: manager
        docker: 10.10.10.10:2375
        nodes:
          - name: set1-test1
            labels:
              dedicated: components
              test: components
      - name: worker1
        docker: 10.10.10.11:2375
        nodes:
          - name: set2-test1
```
