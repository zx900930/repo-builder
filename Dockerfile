# Use AlmaLinux 8 as a base, similar to CentOS 8
FROM almalinux:8

# Set DEBIAN_FRONTEND to noninteractive for any tools that might prompt
ARG DEBIAN_FRONTEND=noninteractive

# Install necessary tools
RUN dnf install -y --allowerasing dnf-utils createrepo_c tar findutils coreutils curl && \
    dnf clean all

# Set a working directory inside the container
WORKDIR /app

# Copy the custom yum.conf
COPY yum.conf /app/yum.conf

# Copy repository definition files into a staging area in /app
COPY ./yum.repos.d/ /app/yum.repos.d/

# Copy the entrypoint script and make it executable
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Define the base path for repositories as an environment variable
ENV REPO_BASE_PATH /home/var/www/html

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# CMD is not strictly necessary if ENTRYPOINT does all the work and exits,
# but can be useful for debugging or overriding.
CMD ["--help"]
