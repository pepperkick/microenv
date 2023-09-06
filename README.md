# MicroEnv

Handles all operations related to MicroEnvs (menv).

## Concepts

### Modules

The functionality of menv is divided into modules. Each module can contain its own scripts and asset files.
The scripts will be loaded by `core` module dynamically and assets will be placed with the scripts to access.

Each script name must be unique across all modules.

### Distributions

Distribution is the final zip file built with combination of modules defined in the `build.yaml` file.

## Building

### Predefined Distributions

Build from predefined distributions available under "./distributions" folder.

```shell
./build.sh -d "<name without menv->"
./build.sh -d "kind-helmfile"
```

### Custom Distribution

Build custom distribution with custom config. Create a config file using `build.yaml` as an example.

```shell
./build.sh -c "<name>"
./build.sh -c "./build.example.yaml"
```