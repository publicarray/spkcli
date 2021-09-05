#!/bin/bash

###
# Opinionated Script to make managing https://github.com/SynoCommunity/spksrc/ easier.
# This script is meant to be run from the root of the spksrc repository.
#
# Copyright (C) 2021  Sebastian Schmidt
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
###

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONTAINER_IMAGE="ghcr.io/synocommunity/spksrc"
DEPENDENCIES=("curl" "git" "sed" "jq" "rm" "grep")

RUNNING_IN_CONTAINER="false"
# ToDo: improve container detection by setting an environment variable
if [ -n "$container" ] || ( [ "$PWD" == "/spksrc" ] && grep -q "ID=debian" /etc/*release ); then
    RUNNING_IN_CONTAINER="true"
fi

print_help() {
    printf "%s [COMMAND]\n" "$0"
    printf "    run\t\t\trun container for development\n"
    printf "    pull\t\tgit pull & docker image pull\n"
    printf "    publish [SPK]\tbuild and publish for all DSM architectures\n"
    printf "    publish-ci [SPK] true\tbuild and publish for all supported DSM versions/architectures using GitHub Actions\n"
    printf "    publish-srm [SPK]\tbuild and publish for all SRM architectures\n"
    printf "    build [SPK]\t\tbuild packages for development (x64)\n"
    printf "    clean [SPK]\t\tclean package\n"
    printf "    clean-all\t\tclean all builds and cached files in /distrib\n"
    printf "    digest [SPK]\tupdate digests\n"
    printf "    update [SPK]\tcheck for git releases for an update\n"
}

# Run SPK development docker container from SynoCommunity
docker_run() {
    check_any_dependency "docker" "podman"
    if type -p podman > /dev/null 2>&1; then
        ##setup rootless: udo touch /etc/subuid /etc/subgid && sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
        podman run -it --rm --name spksrc --userns keep-id -v "$SCRIPT_DIR":/spksrc "$CONTAINER_IMAGE"
    else
        docker run -it --rm --name spksrc --user "$(id -u):$(id -g)" -v "$SCRIPT_DIR":/spksrc "$CONTAINER_IMAGE"
    fi
}

# Run commands in the docker container
run_in_container() {
    if [ $RUNNING_IN_CONTAINER == "true" ]; then
        "$@"
    else
        check_any_dependency "docker" "podman"
        if type -p podman > /dev/null 2>&1; then
            podman run -it --rm --name spksrc --userns keep-id -v "$SCRIPT_DIR":/spksrc "$CONTAINER_IMAGE" /bin/bash -c "$*"
        else
            docker run -it --rm --name spksrc --user "$(id -u):$(id -g)" -v "$SCRIPT_DIR":/spksrc "$CONTAINER_IMAGE" /bin/bash -c "$*"
        fi
    fi
}

# Sync git repository and docker image
docker_git_pull() {
    check_any_dependency "docker" "podman"

    # git branch --set-upstream-to=origin/master
    git pull upstream master

    if type -p podman > /dev/null 2>&1; then
        podman pull "$CONTAINER_IMAGE"
    else
        docker pull "$CONTAINER_IMAGE"
    fi
}

# publish an SPK for NASs
auto_publish() {
    # make -C "$SCRIPT_DIR"/spk/"$1" clean
    # make -C "$SCRIPT_DIR"/spk/"$1" -j"$(nproc)" all-supported
    run_in_container make -C /spksrc/spk/"$1" publish-all-supported
    # make -C "$SCRIPT_DIR"/spk/"$1" -j"$(nproc)" arch-x64-7.0 arch-armv7-7.0 arch-aarch64-7.0 arch-evansport-7.0
    # make -C "$SCRIPT_DIR"/spk/"$1" publish-arch-x64-7.0 publish-arch-armv7-7.0 publish-arch-aarch64-7.0 publish-arch-evansport-7.0
}

# publish an SPK for Routers
auto_publish_SRM() {
    mrun_in_container make -C /spksrc/spk/"$1" -j"$(nproc)" arch-armv7-1.2
    run_in_container make -C /spksrc/spk/"$1" publish-arch-armv7-1.2
}

# Create a github release
release_action() {
    # check_dependency "gh"
    if [ -z "$1" ]; then
        echo "Error: Missing package name"
        print_help
        exit 1
    fi
    git checkout master
    # we only want to publish something that is on master
    git pull upstream master
    # git checkout upstream/master
    # git checkout master

    SPK_NAME="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    SPK_VERS="$(grep '^SPK_VERS' spk/$SPK_NAME/Makefile | awk -F = '{print $2}' | xargs)"
    TAG="$SPK_NAME-$SPK_VERS"

    echo "TAG: $TAG"
    echo "Pushing Tag...in 4 seconds!"
    sleep 4s

    git tag -a -s -m "$TAG" "$TAG"
    git push --tags origin "$TAG"
    git tag -d "$TAG"

    GITHUB_USERNAME=$(get_github_username)

    gh run -R "${GITHUB_USERNAME}/spksrc" watch && notify-send -i "github" -a "GitHub" \
        "GiHub Release is done! 🎉" "https://github.com/${GITHUB_USERNAME}/spksrc/releases"
}

# This will publish a SPK of a given name from the master branch to SynoCommunity
publish_action() {
    if [ -z "$1" ]; then
        echo "Error: Missing package name"
        print_help
        exit 1
    fi

    if [ -z "$1" ] || [ "$2" != "true" ]; then
        echo "==> Warning not publishing!"
        echo "Last argument must be 'true'"
    fi
    GITHUB_USERNAME=$(get_github_username)
    SPK_NAME="$(echo "$1" | tr '[:upper:]' '[:lower:]')"

    # we only want to publish something that is on master
    git checkout master
    git pull upstream master
    # make sure master is up to date
    git push origin master

    echo "Running Publish Workflow...in 4 seconds!"
    sleep 4s
    gh workflow -R "${GITHUB_USERNAME}/spksrc" run build.yml -f "package=$SPK_NAME" -f "publish=$2"
    gh run -R "${GITHUB_USERNAME}/spksrc" watch && notify-send -i "github" -a "GitHub" \
        "🛠 Build is done! 🎉" "To view the build visit https://synocommunity.com/admin/build"
}

# Build an SPK inside the docker container
# [all] = all-supported
# [x64-7.0] = arch-x64-7.0 | specific arch and firmware version
# [] defaults to arch-x64-7.0
build() {
    run_in_container make -C /spksrc/spk/"$1" spkclean
    if [ "$2" == "all" ]; then
        run_in_container make -C /spksrc/spk/"$1" all-supported
    elif [ -n "$2" ]; then
        run_in_container make -C /spksrc/spk/"$1" arch-"$2"
    else
        run_in_container make -C /spksrc/spk/"$1" arch-x64-7.0
    fi
}

# Remove generated build files for a specific SPK
clean() {
    make -C "$SCRIPT_DIR"/spk/"$1" clean
}

# Update hashes in 'cross/[Name]'
auto_digests() {
    make -C "$SCRIPT_DIR"/cross/"$1" clean
    make -C "$SCRIPT_DIR"/cross/"$1" digests
    make -C "$SCRIPT_DIR"/cross/"$1" clean
}

# https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
get_latest_release_by_upload() {
    # latest by upload date
    curl -L --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' |                                            # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

get_latest_release() {
    # no draft versions
    curl -L --silent "https://api.github.com/repos/$1/releases" |
        jq 'map(if .draft == true then "" else .tag_name end)[0]'
}

get_latest_tag() {
    # latest by upload date (not all repos make releases but create tags)
    curl -L --silent "https://api.github.com/repos/$1/tags" | jq 'map(.name)[0]'
}


# Check for an update by querying GitHub releases
github_update_spk() {
    PKG_NAME=$1
    PKG_VERS="$(grep '^PKG_VERS' cross/$1/Makefile | awk -F = '{print $2}' | xargs)"
    URL="$(grep '^PKG_DIST_SITE' cross/$1/Makefile | awk -F = '{print $2}' | xargs)"
    REPO=$(sed -rn 's/^https:\/\/github.com\/([^\/]+)\/([^\/]+).+$/\1\/\2/p' <<< "$URL")
    REPO=${REPO//\$(PKG_NAME)/$PKG_NAME}
    if [ -z "$REPO" ]; then
        echo "No github repository detected"
        exit 1
    fi
    echo "Found Repository: https://github.com/$REPO"
    # todo: use best method to determine new version (git release/tag)
    LATEST=$(get_latest_release "$REPO")
    # cleanup version string
    LATEST=${LATEST//[vVrR\"]/}
    LATEST=${LATEST//\_/\.}
    # shellcheck disable=SC2001
    LATEST=$(sed 's/^\.//' <<< "$LATEST")
    echo "Package Version: $PKG_VERS - Latest Version: $LATEST"
    # shellcheck disable=SC2001
    LATEST=$(sed 's/-.*//' <<< "$LATEST")

    # compare version if
    if printf '%s\n' "$LATEST" "$PKG_VERS" | sort -VC ; then
        echo "===> You have the latest version!"
        exit 0
    fi
    echo "===> Warning updating files to latest version"
    sed -i "s/^PKG_VERS.*/PKG_VERS = $LATEST/" cross/"$1"/Makefile
    if [ -f spk/"$1"/Makefile ]; then
        sed -i "s/^SPK_VERS.*/SPK_VERS = $LATEST/" spk/"$1"/Makefile
        SPK_REV="$(grep '^SPK_REV' spk/$1/Makefile | awk -F = '{print $2}' | xargs)"
        SPK_REV=$((SPK_REV + 1))
        sed -i "s/^SPK_REV.*/SPK_REV = $SPK_REV/" spk/"$1"/Makefile
        sed -i "s/^CHANGELOG.*/CHANGELOG = \"Update $PKG_NAME to $LATEST\"/" spk/"$1"/Makefile
    fi
    auto_digests "$1"
}

# Remove all generated build files, dependencies, and old downloads
clean_all() {
    echo "===> Cleaning spk"
    for PKG in "$SCRIPT_DIR"/spk/*; do
        make -C "$PKG" clean
    done
    echo "===> Cleaning cross"
    for PKG in "$SCRIPT_DIR"/cross/*; do
        make -C "$PKG" clean
    done
    echo "===> Cleaning diyspk"
    for PKG in "$SCRIPT_DIR"/diyspk/*; do
        make -C "$PKG" clean
    done
    echo "===> Cleaning native"
    make native-clean

    echo "===> Cleaning distrib"
    DIGESTS_FILES=$(find cross -name 'digests' -type f)
    DIGESTS_FILES+=" $(find spk -name 'digests' -type f)"
    for DIGESTS_FILE in $DIGESTS_FILES; do
        DIGESTS+=("$(grep -i sha256 "$DIGESTS_FILE" | awk '{print $3}')")
    done
    echo "==> Calculating hashes..."
    while IFS= read -r -d $'\0' FILE
    do
        MATCH=0
        CURRENT_HASH=$(echo "$FILE" | awk '{print $1}')
        for DIGEST in ${DIGESTS[*]}; do
            if [ "$CURRENT_HASH" = "$DIGEST" ]; then
                MATCH=1
            fi
        done
        if [ "$MATCH" = "0" ]; then
            rm -v "$(echo "$FILE" | awk '{print $2}')"
        fi
    done <   <(sha256sum -z distrib/* 2>/dev/null)

    echo "===> Cleaning distrib/nuget"
    if [ -f /spksrc/native/dotnet-sdk-5.0/work-native/dotnet ]; then
        NUGET_PACKAGES=/spksrc/distrib/nuget/packages /spksrc/native/dotnet-sdk-5.0/work-native/dotnet nuget locals all --clear
    else
        rm -rdf "$SCRIPT_DIR"/distrib/nuget/packages
    fi

    echo "===> Done!"
}

# Helper function to grab the GitHub user
get_github_username() {
    check_dependency "gh"
    if [ ! -f "$HOME/.config/gh/hosts.yml" ]; then
        echo "Error: Please login to GitHub with 'gh auth login'" 1>&2
        echo "file '~/config/gh/hosts.yml' not found!" 1>&2
        exit 1
    fi
    GITHUB_USERNAME=$(sed -n 's/\s*user:\s*\(.*\)/\1/p' "$HOME"/.config/gh/hosts.yml)
    if [ -z "$GITHUB_USERNAME" ]; then
        echo "Error: Please login to GitHub with 'gh auth login'" 1>&2
        echo "Username not found!" 1>&2
        exit 1
    fi
    echo "$GITHUB_USERNAME"
}

# Helper function to check for dependent commands
# returns true if all requested commands are available
check_dependency() {
    missing="false"
    for cmd in "$@"; do
        if ! type -p "$cmd" > /dev/null 2>&1; then
            echo "Missing command '$cmd' please install it to continue." 1>&2
            missing="true"
        fi
    done

    [ "$missing" == "false" ] || exit 1
}
# Helper function to check for any available commands
# returns true if any command is available
check_any_dependency() {
    missing="true"
    for cmd in "$@"; do
        if type -p "$cmd" > /dev/null 2>&1; then
            missing="false"
        fi
    done

    if [ "$missing" == "true" ]; then
        echo "Missing command of either '$1' or '$2' please install one of them to continue." 1>&2
        exit 1
    fi
}
#### Script Start ####
check_dependency ${DEPENDENCIES[*]}

case $1 in
    docker|podman|run)
        docker_run
        ;;
    pull)
        docker_git_pull
        ;;
    publish)
        shift
        auto_publish "$1"
        ;;
    publish-srm|publishsrm)
        shift
        auto_publish_SRM "$1"
        ;;
    publish-action|publishaction|gh-publish|ghpublish|publish-ci|publishci)
        shift
        publish_action "$1" "$2"
        ;;
    pr)
        gh pr create
        ;;
    build)
        shift
        build "$1" "$2"
        ;;
    clean)
        shift
        clean "$1"
        ;;
    build-all|buildall)
        shift
        build "$1" all
        ;;
    clean-all|cleanall)
        clean_all
        ;;
    digest|digests|hash)
        shift
        auto_digests "$1"
        ;;
    update)
        shift
        github_update_spk "$1"
        ;;
    *)
        print_help
        ;;
esac
