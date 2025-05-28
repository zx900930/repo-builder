# Repo Builder for Offline YUM/DNF Repositories

A Docker-based tool to download RPM packages and their dependencies from configured YUM/DNF repositories and package them into a tarball. This tarball can then be transferred to an air-gapped environment to set up a local, offline repository.

## Features

*   **Offline Repository Creation**: Simplifies creating mirrors of YUM/DNF repositories for offline use.
*   **Dependency Resolution**: Automatically downloads all necessary dependencies (newest versions only by default).
*   **GPG Key Handling**: Attempts to import GPG keys specified in `.repo` files, allowing for `gpgcheck=1` on the client side.
*   **Dockerized**: Ensures a consistent and reproducible build environment using AlmaLinux 8.
*   **Customizable**: Configure repositories via standard `.repo` files.
*   **Organized Output**: Each synced repository is placed in its own subdirectory within the output tarball.
*   **Web Server Ready**: Includes a basic `index.html` for browsing the repositories if served via HTTP.
*   **Standard Tools**: Uses `dnf-utils` (`reposync`) and `createrepo`.

## Prerequisites

*   [Docker](https://docs.docker.com/get-docker/)
*   [Docker Compose](https://docs.docker.com/compose/install/) (Recommended for ease of use)
*   Git (to clone this repository)
*   Internet access on the machine running `repo-builder` (to download packages and GPG keys).

## Project Structure

```
.
├── docker-compose.yml  # Defines the Docker service for easy execution
├── Dockerfile          # Defines the Docker image
├── entrypoint.sh       # Core script: downloads packages, imports GPG keys, creates repo metadata & tarball
├── yum.conf            # Custom YUM/DNF configuration (used by dnf and reposync)
├── yum.repos.d/        # Directory to place your .repo files
│   └── example.repo    # (You should create/add your actual .repo files here)
├── LICENSE             # Your MIT License file
└── out/                # (Created by the script) Output directory for the generated tarball(s)
```

## Getting Started

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/zx900930/repo-builder.git
    cd repo-builder
    ```

2.  **Configure Repositories:**
    *   Place your YUM/DNF repository definition files (`.repo` files) into the `yum.repos.d/` directory. The script will copy these into the container's `/etc/yum.repos.d/`.
    *   **Important for GPG Keys:** If your `.repo` files specify `gpgkey=http://...` or `gpgkey=file:///...`, the `entrypoint.sh` script will attempt to download/access and import these keys using `rpm --import`. This allows you to potentially use `gpgcheck=1` in your offline repository configuration.
        Example `yum.repos.d/almalinux.repo`:
        ```ini
        [baseos]
        name=AlmaLinux $releasever - BaseOS
        mirrorlist=https://mirrors.almalinux.org/mirrorlist/$releasever/baseos
        enabled=1
        gpgcheck=1
        gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux # (This key is part of the base almalinux image)
               # http://example.com/keys/RPM-GPG-KEY-mycustomrepo (This would be downloaded)

        [appstream]
        name=AlmaLinux $releasever - AppStream
        mirrorlist=https://mirrors.almalinux.org/mirrorlist/$releasever/appstream
        enabled=1
        gpgcheck=1
        gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux
        ```
    *   (Optional) Modify `yum.conf` if you need specific global DNF/YUM configurations (e.g., proxy settings). This file will be used by `dnf` and `reposync` inside the container.

3.  **Build and Run:**
    The `docker-compose.yml` is configured to build the image and run the container. The output tarball will be placed in the `./out` directory on your host machine.

    ```bash
    # Ensure you are in the repo-builder project root
    docker-compose up --build
    ```
    This command will:
    *   Build the Docker image (or use `triatk/repo-builder:${REPO_BUILDER_VERSION}` if available, then fall back to build).
    *   Run the `entrypoint.sh` script inside the container.
    *   Mount the local `./out` directory to `/output` inside the container.

    You can also specify a version for the image:
    ```bash
    REPO_BUILDER_VERSION=1.0 docker-compose up --build
    ```

    After the script finishes, the container will stop. You will find a tarball (e.g., `repo-YYYYMMDD-HHMMSS.tar.gz`) in the `./out` directory.

## How it Works

1.  The `Dockerfile` sets up an AlmaLinux 8 environment with `dnf-utils`, `createrepo_c`, `tar`, and `curl`.
2.  Your custom `yum.conf` (from the project root) and all `.repo` files from `yum.repos.d/` are copied into the Docker image.
3.  When the container starts, `entrypoint.sh` executes:
    *   Copies the `.repo` files from `/app/yum.repos.d/` (in-container staging) to `/etc/yum.repos.d/`.
    *   **GPG Key Import**: Parses `gpgkey=` lines from the `.repo` files. For HTTP/FTP URLs, it downloads the key using `curl` and imports it with `rpm --import`. For `file:///` paths, it imports directly.
    *   **Identifies Enabled Repos**: Uses `dnf repolist --enabled` or parses `[repo_id]` sections from the `.repo` files to find which repositories to sync.
    *   **For each enabled repository (`REPO_ID`):**
        *   Uses `reposync` to download packages into `${REPO_BASE_PATH}/${REPO_ID}` (default: `/home/var/www/html/${REPO_ID}`). It downloads only the newest packages, deletes obsolete ones, and fetches `comps.xml` and other metadata.
        *   Determines the directory containing the RPMs. Some repositories place RPMs in a `Packages/` subdirectory (e.g., `${REPO_BASE_PATH}/${REPO_ID}/Packages/`). The script checks for this.
        *   Runs `createrepo_c --update` on the directory containing the RPMs (either `${REPO_BASE_PATH}/${REPO_ID}/` or `${REPO_BASE_PATH}/${REPO_ID}/Packages/`) to generate/update the `repodata` directory.
    *   **Generates HTML files**: Creates `index.html` (listing synced repositories) and a generic `50x.html` in `$REPO_BASE_PATH`.
    *   **Creates Tarball**: Archives the entire contents of `$REPO_BASE_PATH` (which now contains subdirectories for each synced repo, each with its packages and `repodata`, plus the HTML files) into a timestamped `.tar.gz` file (e.g., `repo-YYYYMMDD-HHMMSS.tar.gz`) in the `/output` directory (mapped to your host's `./out`).

## Tarball Structure

The generated tarball (e.g., `repo-20231027-103000.tar.gz`) will have the following structure when extracted:

```
.
├── repo_id_1/
│   ├── (Packages/ or RPMs directly here)
│   │   ├── some-package-1.rpm
│   │   └── ...
│   └── repodata/
├── repo_id_2/
│   ├── (Packages/ or RPMs directly here)
│   │   ├── another-package.rpm
│   │   └── ...
│   └── repodata/
├── ... (other repo_id directories)
├── index.html      # Simple HTML page listing the repo directories
└── 50x.html        # Generic error page
```
*   If `reposync` for a given `repo_id_1` created a `Packages/` subdirectory and RPMs were downloaded there, then `repodata/` will be inside `repo_id_1/Packages/`.
*   Otherwise, RPMs and `repodata/` will be directly under `repo_id_1/`.

## Using the Generated Tarball in an Air-Gapped Environment

1.  **Transfer**: Copy the generated `.tar.gz` file (e.g., `repo-YYYYMMDD-HHMMSS.tar.gz`) from the `./out` directory to your air-gapped machine.

2.  **Extract**: On the air-gapped machine, choose a directory to host your local repository (e.g., `/srv/local-repos`) and extract the tarball:
    ```bash
    sudo mkdir -p /srv/local-repos
    sudo tar -xzf repo-YYYYMMDD-HHMMSS.tar.gz -C /srv/local-repos
    ```
    This will create subdirectories like `/srv/local-repos/repo_id_1/`, `/srv/local-repos/repo_id_2/`, etc.

3.  **Configure Local Repository**: For each repository you want to use from the tarball, create a new `.repo` file on the air-gapped machine (e.g., in `/etc/yum.repos.d/local-offline.repo`).

    **Example `/etc/yum.repos.d/local-offline.repo`:**

    ```ini
    [local-repo_id_1]
    name=Local Offline Repo ID 1
    # Adjust baseurl based on actual structure within the tarball for repo_id_1
    # Option 1: If RPMs and repodata are directly under repo_id_1/
    baseurl=file:///srv/local-repos/repo_id_1/
    # Option 2: If RPMs and repodata are under repo_id_1/Packages/
    # baseurl=file:///srv/local-repos/repo_id_1/Packages/
    enabled=1
    gpgcheck=1  # Recommended if GPG keys were successfully imported during build
                # and you trust them. Otherwise, set to 0.
    # If gpgcheck=1, you might need to ensure the GPG keys are known to the system's RPM DB.
    # The build script attempts to import them into the container's RPM DB,
    # but those keys aren't transferred with the tarball directly for the client system's RPM DB.
    # If you used `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux` and the client
    # also has this key, it will work. For custom keys downloaded via HTTP, you might need to
    # separately transfer and import the .asc/.gpg public key files onto the airgapped clients.
    # For simplicity in an airgapped setup after verifying packages, `gpgcheck=0` is often used.
    gpgkey=file:///srv/local-repos/repo_id_1/your-gpg-key.asc # If you copied a key file into the repo structure
           # Or point to system keys if they match e.g. file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux

    [local-repo_id_2]
    name=Local Offline Repo ID 2
    baseurl=file:///srv/local-repos/repo_id_2/
    enabled=1
    gpgcheck=0 # Or 1, see notes for local-repo_id_1
    ```
    *   **Crucial `baseurl`**: Carefully check the extracted structure inside `/srv/local-repos/YOUR_REPO_ID/`. If it contains a `Packages/` subdirectory which in turn contains the RPMs and `repodata/`, your `baseurl` must point to `.../YOUR_REPO_ID/Packages/`. Otherwise, it points directly to `.../YOUR_REPO_ID/`.
    *   **`gpgcheck`**:
        *   Set to `1` if you are confident the GPG keys were correctly handled by `repo-builder` and are available/trusted on the client.
        *   If using `gpgcheck=1` with keys fetched via HTTP during the build, you'll need to ensure those public GPG key files are also transferred to the air-gapped system and referenced correctly via `gpgkey=` (or imported into the client's RPM database manually). The simplest way is to ensure `gpgkey` points to a `file:///` path within your extracted repository structure if you include the key files there.
        *   Set to `0` to disable GPG signature checking if managing keys is too complex for your scenario.

4.  **Clean Cache and Verify**:
    ```bash
    sudo dnf clean all  # or sudo yum clean all
    sudo dnf repolist   # or sudo yum repolist
    ```
    You should see your `local-*` repositories listed. Now you can install packages:
    ```bash
    sudo dnf install <package-name> # or sudo yum install <package-name>
    ```

## Customization

*   **Repositories**: Add/modify `.repo` files in the `yum.repos.d/` directory. Ensure `gpgkey` lines are correct if you want GPG key handling.
*   **`yum.conf`**: Modify the root `yum.conf` for global DNF/YUM settings (e.g., proxy, specific dnf variables) to be used during the `reposync` process.
*   **`entrypoint.sh`**: For advanced changes (e.g., different `reposync` flags, alternative tarball structure), modify this script.
*   **`REPO_BASE_PATH` (in Dockerfile)**: Defaults to `/home/var/www/html`. This is the internal path in the container where repositories are built before tarring.

## Dockerfile Details

*   `FROM almalinux:8`: Uses AlmaLinux 8 as the base image.
*   `RUN dnf install -y ...`: Installs necessary tools:
    *   `dnf-utils`: Provides `reposync` for downloading repositories.
    *   `createrepo_c`: Creates repository metadata.
    *   `tar`: For creating the tarball.
    *   `findutils`, `coreutils`, `curl`: General utilities.
*   `WORKDIR /app`: Sets the working directory inside the container.
*   `COPY yum.conf /app/yum.conf`: Copies your custom DNF configuration.
*   `COPY ./yum.repos.d/ /app/yum.repos.d/`: Copies all your repository definition files.
*   `COPY entrypoint.sh /app/entrypoint.sh`: Copies the main script.
*   `RUN chmod +x /app/entrypoint.sh`: Makes the script executable.
*   `ENV REPO_BASE_PATH /home/var/www/html`: Sets an environment variable that might be used by `entrypoint.sh`.
*   `ENTRYPOINT ["/app/entrypoint.sh"]`: Specifies the script to run when the container starts.
*   `CMD ["--help"]`: Default command if `entrypoint.sh` is run without arguments (or if the entrypoint is overridden). This suggests your `entrypoint.sh` might support a `--help` flag.

## Docker Compose Details (`docker-compose.yml`)

*   `version: '3.8'`: Specifies the Docker Compose file format version.
*   `services: repo-builder:`: Defines a service named `repo-builder`.
*   `build: context: . dockerfile: Dockerfile`: Tells Docker Compose to build an image from the `Dockerfile` in the current directory.
*   `image: triatk/repo-builder:${REPO_BUILDER_VERSION:-latest}`:
    *   If an image named `triatk/repo-builder` with the specified tag (or `latest`) exists locally or can be pulled, Docker Compose will use it.
    *   If not, and `build:` is specified, it will build the image locally and tag it with this name. This allows you to potentially push your built image to a registry like Docker Hub under `triatk/repo-builder`.
*   `volumes: - ./out:/output`: Mounts the `./out` directory from your host machine to the `/output` directory inside the container. This is how the generated tarball is persisted on your host.
*   `# environment: ...`: Commented out; allows you to pass environment variables to the `entrypoint.sh` script if needed.
*   `# restart: 'no'`: Default behavior; the container will stop after the `entrypoint.sh` script completes.

## Contributing

Contributions are welcome! Please feel free to submit a pull request or open an issue.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

## License

Distributed under the MIT License. 
