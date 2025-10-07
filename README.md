## Odyssey CLI Installation

To install the Odyssey CLI, open a terminal and run

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/cleancoders/odyssey-cli-install/refs/heads/master/install.sh)"
```

## Development

Running all tests in `test` directory: 

```bash 
make test
```

## Deployment 

Build the distributable installer file: 

```bash
make build-install
```

Build installer and run all tests: 

```bash
make all
```