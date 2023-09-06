# MicroEnv Installation Helmfile

Utilize helmfile to install helm charts in the microenv.

## Requirements

- helmfile (auto installed)
- helm (auto installed)
- helm diff (auto installed)

## Config

```yaml
installation:
  mode: helmfile

  # Configration for Helmfile installer
  helmfile:
    path: "./helmfile.yaml"
    environment: default
    value_files:
      - ./example.yaml
```