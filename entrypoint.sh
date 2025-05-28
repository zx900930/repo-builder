#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
# set -x # Uncomment for debugging

REPO_BASE_PATH="${REPO_BASE_PATH:-/home/var/www/html}"
YUM_CONF_PATH="/app/yum.conf"

echo "----> Initializing repository sync process"
echo "----> Using yum.conf: ${YUM_CONF_PATH}"
echo "----> Repository files will be copied from /app/yum.repos.d to /etc/yum.repos.d/"

mkdir -p "${REPO_BASE_PATH}"
rm -f /etc/yum.repos.d/*.repo
cp /app/yum.repos.d/*.repo /etc/yum.repos.d/
echo "----> Copied custom .repo files to /etc/yum.repos.d/:"
ls -l /etc/yum.repos.d/

echo "----> Attempting to import GPG keys..."
for repo_file in /etc/yum.repos.d/*.repo; do
    gpgkeys=$(grep -Po '^gpgkey=\K.*' "$repo_file" | sed 's/ file:\/\//\//g')
    for key_url in $gpgkeys; do
        if [[ "$key_url" == http* ]] || [[ "$key_url" == ftp* ]]; then
            echo "Importing GPG key from URL: $key_url"
            temp_key_file=$(mktemp)
            if curl -sSL "$key_url" -o "$temp_key_file"; then
                if rpm --import "$temp_key_file"; then
                    echo "Successfully imported GPG key $key_url"
                else
                    echo "Warning: Failed to import GPG key from $key_url using rpm --import"
                fi
                rm -f "$temp_key_file"
            else
                echo "Warning: Failed to download GPG key from $key_url"
                rm -f "$temp_key_file"
            fi
        elif [ -f "$key_url" ]; then
            echo "Importing GPG key from file: $key_url"
            if rpm --import "$key_url"; then
                 echo "Successfully imported GPG key $key_url"
            else
                echo "Warning: Failed to import GPG key $key_url"
            fi
        fi
    done
done

echo "----> Identifying enabled repositories..."
REPO_IDS=$(dnf -c "${YUM_CONF_PATH}" repolist --enabled -q | awk '{print $1}' | grep -vE '^(repo id|Repodata|Last|Repo-id|repo)$' || true)

if [ -z "$REPO_IDS" ]; then
    echo "No enabled repositories found by 'dnf repolist'. Trying to parse from .repo files directly."
    REPO_IDS=$(grep -hPro '^\s*\[\K[^\]]+' /etc/yum.repos.d/*.repo | grep -vE '\[|\]' | sort -u)
    if [ -z "$REPO_IDS" ]; then
        echo "Error: No repository IDs could be determined. Please check your .repo files in yum.repos.d/"
        exit 1
    fi
    echo "Found repo IDs by parsing files: $REPO_IDS"
else
    echo "Enabled repository IDs found by dnf: $REPO_IDS"
fi

for REPO_ID in $REPO_IDS; do
    echo ""
    echo "**********************************************"
    echo "**** Processing repository: $REPO_ID"
    echo "**********************************************"

    REPO_SYNC_TARGET_DIR="${REPO_BASE_PATH}/${REPO_ID}" # Base dir for this repo_id

    echo "----> Syncing repository: $REPO_ID to ${REPO_BASE_PATH} (subdir ${REPO_ID})..."
    reposync_cmd="reposync -c ${YUM_CONF_PATH} \
        --repoid=${REPO_ID} \
        --download-path=${REPO_BASE_PATH} \
        --newest-only \
        --delete \
        --downloadcomps \
        --download-metadata"

    echo "Executing: $reposync_cmd"
    if $reposync_cmd; then
        echo "Sync successful for $REPO_ID."
    else
        echo "Warning: reposync for $REPO_ID encountered issues. Continuing..."
    fi

    # Determine the actual directory containing RPMs
    # Default to the REPO_SYNC_TARGET_DIR
    PACKAGE_DIR_FOR_CREATEREPO="${REPO_SYNC_TARGET_DIR}"
    HAS_PACKAGES_SUBDIR=false

    if [ -d "${REPO_SYNC_TARGET_DIR}/Packages" ] && [ "$(ls -A "${REPO_SYNC_TARGET_DIR}/Packages"/*.rpm 2>/dev/null)" ]; then
        PACKAGE_DIR_FOR_CREATEREPO="${REPO_SYNC_TARGET_DIR}/Packages"
        HAS_PACKAGES_SUBDIR=true
        echo "INFO: RPMs found in Packages/ subdirectory for $REPO_ID. Using $PACKAGE_DIR_FOR_CREATEREPO for createrepo."
    fi

    echo "DEBUG: Checking for RPMs. Main sync dir: $REPO_SYNC_TARGET_DIR. Dir for createrepo: $PACKAGE_DIR_FOR_CREATEREPO. Has Packages subdir: $HAS_PACKAGES_SUBDIR"
    if [ -d "$REPO_SYNC_TARGET_DIR" ]; then # Check if the base repo_id directory was created
        echo "DEBUG: Contents of $REPO_SYNC_TARGET_DIR (and subdirs if relevant):"
        ls -lR "$REPO_SYNC_TARGET_DIR" # Retain this for debugging overall structure
    else
        echo "DEBUG: Directory $REPO_SYNC_TARGET_DIR does not exist."
    fi


    # Check for RPMs in the determined PACKAGE_DIR_FOR_CREATEREPO
    if [ -d "$PACKAGE_DIR_FOR_CREATEREPO" ] && [ "$(ls -A "$PACKAGE_DIR_FOR_CREATEREPO"/*.rpm 2>/dev/null)" ]; then
        echo "----> Creating repository metadata for: $PACKAGE_DIR_FOR_CREATEREPO..."
        # createrepo_c should be run on the directory containing the RPMs.
        # It will create a 'repodata' subdirectory within PACKAGE_DIR_FOR_CREATEREPO.
        if createrepo_c --update "$PACKAGE_DIR_FOR_CREATEREPO"; then
            echo "Metadata creation successful for $REPO_ID (in $PACKAGE_DIR_FOR_CREATEREPO)."

            # If RPMs were in a 'Packages' subdir, we need to make sure the top-level
            # repo directory (e.g., /home/var/www/html/ks10-adv-os/) also has a repodata
            # directory that points to or contains the metadata.
            # Most web servers and yum clients expect repodata at the root of the repo URL.
            # createrepo_c creates repodata *inside* the directory it's run on.
            if [ "$HAS_PACKAGES_SUBDIR" = true ]; then
                echo "INFO: RPMs were in Packages/. Ensuring repodata is accessible at top level of $REPO_SYNC_TARGET_DIR..."
                # If createrepo_c created repodata in REPO_SYNC_TARGET_DIR/Packages/repodata
                # we might need to link or move it to REPO_SYNC_TARGET_DIR/repodata
                # For simplicity, let's re-run createrepo on the parent if it had a Packages subdir
                # This might be slightly inefficient but ensures repodata is at the top level.
                # A more robust way would be to symlink or adjust web server config.
                # For now, let's ensure the primary createrepo runs on the RPM location.
                # The user then needs to ensure their web server serves $REPO_SYNC_TARGET_DIR
                # and that $REPO_SYNC_TARGET_DIR/Packages (or wherever RPMs are) is the path
                # in their .repo file's baseurl.
                #
                # Simpler approach: createrepo expects RPMs at the root of the directory it's told to process.
                # So, PACKAGE_DIR_FOR_CREATEREPO is correct. The .repo file on the client
                # will need its baseurl to point to .../ks10-adv-os/Packages/ if that's where RPMs and repodata are.
                #
                # OR, if we want the client's baseurl to be .../ks10-adv-os/,
                # then RPMs AND repodata must be directly under ks10-adv-os/
                # This would mean moving RPMs from Packages/ up one level, then running createrepo.

                # Let's stick to createrepo on the actual RPM location for now.
                # The user will need to adjust client .repo files if necessary.
                # For example, client baseurl: http://my.server/ks10-adv-os/Packages
            fi
        else
            echo "Warning: createrepo_c for $REPO_ID (in $PACKAGE_DIR_FOR_CREATEREPO) encountered issues."
        fi
    elif [ -d "$REPO_SYNC_TARGET_DIR" ]; then # Check if the main repo_id dir exists even if no RPMs found
        echo "Warning: No RPMs found for repository $REPO_ID in expected locations ($PACKAGE_DIR_FOR_CREATEREPO or $REPO_SYNC_TARGET_DIR). Skipping createrepo."
        echo "This could be due to an empty upstream repo, network issues, GPG key problems, or reposync filters."
    else
        echo "Warning: Main directory $REPO_SYNC_TARGET_DIR does not exist after reposync for $REPO_ID. Skipping createrepo."
    fi
done

echo ""
echo "----> All repositories processed."
echo "----> Repository structure in ${REPO_BASE_PATH}:"
ls -lR "${REPO_BASE_PATH}"

# Create index.html and 50x.html
echo "Creating index.html and 50x.html..."
echo "<html><head><title>Local Repository Mirror</title></head><body><h1>Local YUM/DNF Repositories</h1><p>Available repositories:</p><ul>" > "${REPO_BASE_PATH}/index.html"
# Adjust find to account for potential 'Packages' subdirectories if we want to list them.
# For now, it lists top-level repo_id directories.
find "${REPO_BASE_PATH}" -mindepth 1 -maxdepth 1 -type d -printf '<li><a href="%f/">%f/</a></li>\n' | sort >> "${REPO_BASE_PATH}/index.html"
echo "</ul></body></html>" >> "${REPO_BASE_PATH}/index.html"
echo "<html><head><title>50x Server Error</title></head><body><h1>50x Server Error</h1><p>An unexpected error occurred.</p></body></html>" > "${REPO_BASE_PATH}/50x.html"
echo "----> HTML files created."

OUTPUT_TAR_DIR="/output"
mkdir -p "$OUTPUT_TAR_DIR"

TARBALL_NAME="repo-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "Compressing repository contents from ${REPO_BASE_PATH} to ${OUTPUT_TAR_DIR}/${TARBALL_NAME}..."

if tar -czvf "${OUTPUT_TAR_DIR}/${TARBALL_NAME}" -C "${REPO_BASE_PATH}" .; then
    echo "Repository archive created: ${OUTPUT_TAR_DIR}/${TARBALL_NAME}"
    ls -lh "${OUTPUT_TAR_DIR}/${TARBALL_NAME}"
    echo "----> Sync and archive process complete."
else
    echo "ERROR: Failed to create tarball."
    exit 1
fi

exit 0

