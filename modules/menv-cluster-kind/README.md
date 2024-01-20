# MicroEnv Cluster KIND (Deprecated)

Use KIND to create a new K8s cluster.

## Requirements

- docker
- kind

## Scripts

### add-node

Add a new KIND node to the existing cluster.

```shell
./menv.sh add-node <node name>
./menv.sh add-node test1
```

### remove-node

Remove an existing KIND node from the existing cluster.

```shell
./menv.sh remove-node <node name>
./menv.sh remove-node test1
```

## Config

```yaml
cluster:
  kind:
    networking:
      apiServerPort: 55555
      apiServerAddress: "0.0.0.0"
      disableDefaultCNI: true
      podSubnet: 192.168.0.0/16

    nodes:
      image: kindest/node:v1.25.9@sha256:c08d6c52820aa42e533b70bce0c2901183326d86dcdcbedecc9343681db45161

      # List of worker nodes
      # dedicated is used as label
      # image is used for overriding node image
      # Currently only 1 label per node is supported
      workers:
        - dedicated: test
        - dedicated: test
        - dedicated: test
          image: kindest/node:v1.25.9@sha256:c08d6c52820aa42e533b70bce0c2901183326d86dcdcbedecc9343681db45161

```
