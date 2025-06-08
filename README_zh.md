# 离线 YUM/DNF 仓库构建器

[English Version](README.md)

一个基于 Docker 的工具，用于从配置的 YUM/DNF 仓库下载 RPM 包及其依赖，并将其打包成一个 tarball（压缩包）。这个 tarball 可以传输到**离线环境**，以设置一个本地离线仓库。

## 功能特性

*   **离线仓库创建**：简化了为离线使用创建 YUM/DNF 仓库镜像的过程。
*   **依赖解析**：自动下载所有必要的依赖（默认仅下载最新版本）。
*   **GPG 密钥处理**：尝试导入 `.repo` 文件中指定的 GPG 密钥，允许客户端使用 `gpgcheck=1`。
*   **Docker 化**：使用 AlmaLinux 8 确保一致且可复现的构建环境。
*   **可定制化**：通过标准 `.repo` 文件配置仓库。
*   **组织化的输出**：每个同步的仓库都位于输出 tarball 内的独立子目录中。
*   **支持 Web 服务器**：包含一个基本的 `index.html`，如果通过 HTTP 提供服务，可用于浏览仓库。
*   **标准工具**：使用 `dnf-utils` (`reposync`) 和 `createrepo`。

## 前提条件

*   [Docker](https://docs.docker.com/get-docker/)
*   [Docker Compose](https://docs.docker.com/compose/install/) (推荐，便于使用)
*   Git (用于克隆此仓库)
*   运行 `repo-builder` 的机器需要有互联网连接 (用于下载软件包和 GPG 密钥)。

## 项目结构

```
.
├── docker-compose.yml  # 定义 Docker 服务，便于执行
├── Dockerfile          # 定义 Docker 镜像
├── entrypoint.sh       # 核心脚本：下载软件包、导入 GPG 密钥、创建仓库元数据并打包成 tarball
├── yum.conf            # 自定义 YUM/DNF 配置 (由 dnf 和 reposync 使用)
├── yum.repos.d/        # 存放您的 .repo 文件的目录
│   └── example.repo    # (您应该在此处创建/添加您的实际 .repo 文件)
├── LICENSE             # 您的 MIT 许可证文件
└── out/                # (由脚本创建) 生成的 tarball 的输出目录
```

## 快速开始

1.  **克隆仓库：**
    ```bash
    git clone https://github.com/zx900930/repo-builder.git
    cd repo-builder
    ```

2.  **配置仓库：**
    *   将您的 YUM/DNF 仓库定义文件（`.repo` 文件）放置到 `yum.repos.d/` 目录中。脚本会将这些文件复制到容器的 `/etc/yum.repos.d/`。
    *   **随附示例说明：** 本仓库提供了一些示例 `.repo` 文件，目前包含以下软件源：
        *   银河麒麟 V10 SP3 2403 X86_64 软件源
        *   docker-ce 软件源
        *   nginx-stable 软件源
        您可以根据这些示例进行修改，或者添加您自己需要同步的 `.repo` 文件。
    *   **GPG 密钥注意事项：** 如果您的 `.repo` 文件指定了 `gpgkey=http://...` 或 `gpgkey=file:///...`，`entrypoint.sh` 脚本将尝试下载/访问并使用 `rpm --import` 导入这些密钥。这允许您在离线仓库配置中可能使用 `gpgcheck=1`。
        `yum.repos.d/almalinux.repo` 示例：
        ```ini
        [baseos]
        name=AlmaLinux $releasever - BaseOS
        mirrorlist=https://mirrors.almalinux.org/mirrorlist/$releasever/baseos
        enabled=1
        gpgcheck=1
        gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux # (此密钥是 AlmaLinux 基础镜像的一部分)
               # http://example.com/keys/RPM-GPG-KEY-mycustomrepo (此密钥将被下载)

        [appstream]
        name=AlmaLinux $releasever - AppStream
        mirrorlist=https://mirrors.almalinux.org/mirrorlist/$releasever/appstream
        enabled=1
        gpgcheck=1
        gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux
        ```
    *   （可选）如果您需要特定的全局 DNF/YUM 配置（例如，代理设置），可以修改 `yum.conf`。此文件将在容器内部由 `dnf` 和 `reposync` 使用。

3.  **构建并运行：**
    `docker-compose.yml` 已配置为构建镜像并运行容器。生成的 tarball 将放置在您主机上的 `./out` 目录中。

    ```bash
    # 请确保您位于 repo-builder 项目的根目录
    docker-compose up --build
    ```
    此命令将：
    *   构建 Docker 镜像（如果可用，则使用 `triatk/repo-builder:${REPO_BUILDER_VERSION}`，否则回退到构建）。
    *   在容器内部运行 `entrypoint.sh` 脚本。
    *   将本地 `./out` 目录挂载到容器内部的 `/output`。

    您还可以为镜像指定版本：
    ```bash
    REPO_BUILDER_VERSION=1.0 docker-compose up --build
    ```

    脚本完成后，容器将停止。您将在 `./out` 目录中找到一个 tarball（例如，`repo-YYYYMMDD-HHMMSS.tar.gz`）。

## 工作原理

1.  `Dockerfile` 设置了一个 AlmaLinux 8 环境，并安装了 `dnf-utils`、`createrepo_c`、`tar` 和 `curl`。
2.  您的自定义 `yum.conf` (来自项目根目录) 和 `yum.repos.d/` 中的所有 `.repo` 文件都被复制到 Docker 镜像中。
3.  容器启动时，`entrypoint.sh` 执行：
    *   将 `.repo` 文件从 `/app/yum.repos.d/` (容器内暂存区) 复制到 `/etc/yum.repos.d/`。
    *   **GPG 密钥导入**：解析 `.repo` 文件中的 `gpgkey=` 行。对于 HTTP/FTP URL，它使用 `curl` 下载密钥并使用 `rpm --import` 导入。对于 `file:///` 路径，它直接导入。
    *   **识别启用的仓库**：使用 `dnf repolist --enabled` 或解析 `.repo` 文件中的 `[repo_id]` 部分来查找要同步的仓库。
    *   **对于每个启用的仓库 (`REPO_ID`)：**
        *   使用 `reposync` 将软件包下载到 `${REPO_BASE_PATH}/${REPO_ID}` (默认: `/home/var/www/html/${REPO_ID}`)。它只下载最新软件包，删除过时的，并获取 `comps.xml` 和其他元数据。
        *   确定包含 RPM 包的目录。一些仓库将 RPM 包放置在 `Packages/` 子目录中（例如，`${REPO_BASE_PATH}/${REPO_ID}/Packages/`）。脚本会检查这一点。
        *   在包含 RPM 包的目录（无论是 `${REPO_BASE_PATH}/${REPO_ID}/` 还是 `${REPO_BASE_PATH}/${REPO_ID}/Packages/`）上运行 `createrepo_c --update` 以生成/更新 `repodata` 目录。
    *   **生成 HTML 文件**：在 `$REPO_BASE_PATH` 中创建 `index.html`（列出同步的仓库）和一个通用的 `50x.html`。
    *   **创建压缩包**：将 `$REPO_BASE_PATH` 的全部内容（现在包含每个同步仓库的子目录，每个子目录都包含其软件包和 `repodata`，以及 HTML 文件）归档到一个带时间戳的 `.tar.gz` 文件（例如，`repo-YYYYMMDD-HHMMSS.tar.gz`），并将其放置在 `/output` 目录（映射到您主机的 `./out` 目录）。

## 压缩包结构

生成的 tarball (例如，`repo-20231027-103000.tar.gz`) 解压后将具有以下结构：

```
.
├── repo_id_1/
│   ├── (Packages/ 或 RPM 包直接在此处)
│   │   ├── some-package-1.rpm
│   │   └── ...
│   └── repodata/
├── repo_id_2/
│   ├── (Packages/ 或 RPM 包直接在此处)
│   │   ├── another-package.rpm
│   │   └── ...
│   └── repodata/
├── ... (其他 repo_id 目录)
├── index.html      # 简单的 HTML 页面，列出仓库目录
└── 50x.html        # 通用错误页面
```
*   如果 `reposync` 为给定的 `repo_id_1` 创建了 `Packages/` 子目录，并且 RPM 包下载到了那里，那么 `repodata/` 将位于 `repo_id_1/Packages/` 内部。
*   否则，RPM 包和 `repodata/` 将直接位于 `repo_id_1/` 下。

## 在离线环境中使用生成的压缩包

1.  **传输**：将生成的 `.tar.gz` 文件（例如，`repo-YYYYMMDD-HHMMSS.tar.gz`）从 `./out` 目录复制到您的**离线机器**。

2.  **解压**：在**离线机器**上，选择一个目录来托管您的本地仓库（例如，`/srv/local-repos`），然后解压 tarball：
    ```bash
    sudo mkdir -p /srv/local-repos
    sudo tar -xzf repo-YYYYMMDD-HHMMSS.tar.gz -C /srv/local-repos
    ```
    这将创建 `/srv/local-repos/repo_id_1/`、`/srv/local-repos/repo_id_2/` 等子目录。

3.  **配置本地仓库**：对于您想从 tarball 中使用的每个仓库，在**离线机器**上创建一个新的 `.repo` 文件（例如，在 `/etc/yum.repos.d/local-offline.repo`）。

    **示例 `/etc/yum.repos.d/local-offline.repo`：**

    ```ini
    [local-repo_id_1]
    name=Local Offline Repo ID 1
    # 根据 repo_id_1 在 tarball 内的实际结构调整 baseurl
    # 选项 1: 如果 RPM 包和 repodata 直接位于 repo_id_1/ 下
    baseurl=file:///srv/local-repos/repo_id_1/
    # 选项 2: 如果 RPM 包和 repodata 位于 repo_id_1/Packages/ 下
    # baseurl=file:///srv/local-repos/repo_id_1/Packages/
    enabled=1
    gpgcheck=1  # 如果在构建期间 GPG 密钥成功导入且您信任它们，则推荐设置为 1。否则，设置为 0。
                # 如果 gpgcheck=1，您可能需要确保 GPG 密钥已被系统的 RPM DB 识别。
                # 构建脚本尝试将它们导入到容器的 RPM DB 中，
                # 但这些密钥不会随 tarball 直接传输到客户端系统的 RPM DB。
                # 如果您使用了 `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux` 并且客户端
                # 也拥有此密钥，它将起作用。对于通过 HTTP 下载的自定义密钥，您可能需要
                # 单独将 .asc/.gpg 公钥文件传输到离线客户端并导入。
                # 为简化离线环境中的设置，在验证软件包后，通常使用 `gpgcheck=0`。
    gpgkey=file:///srv/local-repos/repo_id_1/your-gpg-key.asc # 如果您将密钥文件复制到了仓库结构中
           # 或者指向系统密钥，如果它们匹配，例如 file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux

    [local-repo_id_2]
    name=Local Offline Repo ID 2
    baseurl=file:///srv/local-repos/repo_id_2/
    enabled=1
    gpgcheck=0 # 或 1，参阅 local-repo_id_1 的注意事项
    ```
    *   **关键的 `baseurl`**：仔细检查 `/srv/local-repos/YOUR_REPO_ID/` 内部的解压结构。如果它包含一个 `Packages/` 子目录，而该子目录又包含 RPM 包和 `repodata/`，那么您的 `baseurl` 必须指向 `.../YOUR_REPO_ID/Packages/`。否则，它直接指向 `.../YOUR_REPO_ID/`。
    *   **`gpgcheck`**：
        *   如果您确信 GPG 密钥已由 `repo-builder` 正确处理，并且在客户端上可用/受信任，请设置为 `1`。
        *   如果在构建期间使用了通过 HTTP 获取的密钥并设置 `gpgcheck=1`，您需要确保这些公共 GPG 密钥文件也已传输到**离线系统**，并通过 `gpgkey=` 正确引用（或手动导入到客户端的 RPM 数据库）。最简单的方法是确保 `gpgkey` 指向您提取的仓库结构中的 `file:///` 路径，如果您将密钥文件包含在那里。
        *   如果管理密钥对于您的场景来说过于复杂，请将 `gpgcheck` 设置为 `0` 以禁用 GPG 签名检查。

4.  **清理缓存并验证：**
    ```bash
    sudo dnf clean all  # 或 sudo yum clean all
    sudo dnf repolist   # 或 sudo yum repolist
    ```
    您应该看到您的 `local-*` 仓库已列出。现在您可以安装软件包了：
    ```bash
    sudo dnf install <package-name> # 或 sudo yum install <package-name>
    ```

## 自定义

*   **仓库**：在 `yum.repos.d/` 目录中添加/修改 `.repo` 文件。如果您想处理 GPG 密钥，请确保 `gpgkey` 行是正确的。
*   **`yum.conf`**：修改根目录下的 `yum.conf` 以设置用于 `reposync` 过程的全局 DNF/YUM 设置（例如，代理、特定的 dnf 变量）。
*   **`entrypoint.sh`**：如需进行高级更改（例如，不同的 `reposync` 标志、替代的 tarball 结构），请修改此脚本。
*   **`REPO_BASE_PATH` (在 Dockerfile 中)**：默认为 `/home/var/www/html`。这是容器内部的路径，仓库在此处构建，然后进行打包。

## Dockerfile 详情

*   `FROM almalinux:8`：使用 AlmaLinux 8 作为基础镜像。
*   `RUN dnf install -y ...`：安装必要的工具：
    *   `dnf-utils`：提供 `reposync` 用于下载仓库。
    *   `createrepo_c`：创建仓库元数据。
    *   `tar`：用于创建 tarball。
    *   `findutils`, `coreutils`, `curl`：通用实用工具。
*   `WORKDIR /app`：设置容器内的工作目录。
*   `COPY yum.conf /app/yum.conf`：复制您的自定义 DNF 配置。
*   `COPY ./yum.repos.d/ /app/yum.repos.d/`：复制所有您的仓库定义文件。
*   `COPY entrypoint.sh /app/entrypoint.sh`：复制主脚本。
*   `RUN chmod +x /app/entrypoint.sh`：使脚本可执行。
*   `ENV REPO_BASE_PATH /home/var/www/html`：设置一个可能由 `entrypoint.sh` 使用的环境变量。
*   `ENTRYPOINT ["/app/entrypoint.sh"]`：指定容器启动时要运行的脚本。
*   `CMD ["--help"]`：如果 `entrypoint.sh` 在没有参数的情况下运行（或者如果 entrypoint 被覆盖），这是默认命令。这表明您的 `entrypoint.sh` 可能支持 `--help` 标志。

## Docker Compose 详情 (`docker-compose.yml`)

*   `version: '3.8'`：指定 Docker Compose 文件格式版本。
*   `services: repo-builder:`：定义一个名为 `repo-builder` 的服务。
*   `build: context: . dockerfile: Dockerfile`：告诉 Docker Compose 从当前目录中的 `Dockerfile` 构建镜像。
*   `image: triatk/repo-builder:${REPO_BUILDER_VERSION:-latest}`：
    *   如果本地存在或可以拉取带有指定标签（或 `latest`）的 `triatk/repo-builder` 镜像，Docker Compose 将使用它。
    *   否则，如果指定了 `build:`，它将在本地构建镜像并使用此名称进行标记。这允许您将构建的镜像推送到像 Docker Hub 这样的注册表，名称为 `triatk/repo-builder`。
*   `volumes: - ./out:/output`：将主机上的 `./out` 目录挂载到容器内部的 `/output` 目录。这是生成的 tarball 在主机上持久化的方式。
*   `# environment: ...`：被注释掉；允许您在需要时将环境变量传递给 `entrypoint.sh` 脚本。
*   `# restart: 'no'`：默认行为；容器将在 `entrypoint.sh` 脚本完成后停止。

## 贡献

欢迎贡献！请随意提交拉取请求或提出问题。

1.  派生（Fork）项目
2.  创建您的功能分支 (`git checkout -b feature/AmazingFeature`)
3.  提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4.  推送到分支 (`git push origin feature/AmazingFeature`)
5.  打开一个拉取请求（Pull Request）

## 许可证

本项目采用 MIT 许可证分发。
