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

Running all tests and auto re-run on save (requires `fswatch` on Mac and `inotifywait` on Linux):
```bash
make test-watch
```

All new files created must have executable permissions. To set, use: 
```bash
chmod +x path_to_my_new_file.sh
```

### Creating a new test file
```bash
make test-file FILE=bin/my_file.sh
```

This will create a file `test/test_my_file.sh` based on a template test file that sources the given source file
and ensures that the created test file is executable. The corresponding source file must be created first. 

## Deployment 

1. Merge changes to `production` branch. 
2. Build the distributable installer file:
    ```bash
    make build-install
    ```
3. Push merged code and built installer file to remote:
   ```bash
   git push origin production
   ```

Build installer and run all tests: 

```bash
make all
```