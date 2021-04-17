#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

docker_run() {
    docker run -it --rm --name spksrc -v "$SCRIPT_DIR":/spksrc synocommunity/spksrc
}

docker_git_pull() {
    git pull upstream master
    docker pull synocommunity/spksrc
}

auto_publish() {
    make -C spk/"$1" clean
    make -C spk/"$1" -j"$(nproc)" all-supported
    make -C spk/"$1" -j"$(nproc)" arch-x64-7.0 arch-armv7-7.0 arch-aarch64-7.0 arch-evansport-7.0
    make -C spk/"$1" publish-all-supported
    make -C spk/"$1" publish-arch-x64-7.0 publish-arch-armv7-7.0 publish-arch-aarch64-7.0 publish-arch-evansport-7.0
}

auto_publish_SRM() {
    make -C spk/"$1" -j"$(nproc)" arch-armv7-1.2
    make -C spk/"$1" publish arch-armv7-1.2
}

build_x64() {
    make -C spk/"$1" spkclean
    make -C spk/"$1" -j"$(nproc)" arch-x64-7.0
    # make -C spk/"$1" -j"$(nproc)" arch-x64-6.1
}

auto_digests() {
    make -C cross/"$1" clean
    make -C cross/"$1" digests
    make -C cross/"$1" clean
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


github_update_spk() {
    PKG_NAME=$1
    PKG_VERS="$(grep ^PKG_VERS cross/$1/Makefile | awk -F = '{print $2}' | xargs)"
    URL="$(grep ^PKG_DIST_SITE cross/$1/Makefile | awk -F = '{print $2}' | xargs)"
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
        sed -i "s/^PKG_VERS.*/PKG_VERS = $LATEST/" spk/"$1"/Makefile
        SPK_REV="$(grep ^SPK_REV spk/$1/Makefile | awk -F = '{print $2}' | xargs)"
        SPK_REV=$((SPK_REV + 1))
        sed -i "s/^SPK_REV.*/SPK_REV = $SPK_REV/" spk/"$1"/Makefile
        sed -i "s/^CHANGELOG.*/CHANGELOG = \"Update $PKG_NAME to $LATEST\"/" spk/"$1"/Makefile
    fi
    auto_digests "$1"
}

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

case $1 in
    docker|run)
        docker_run
        ;;
    pull)
        docker_git_pull
        ;;
    publish)
        shift
        auto_publish "$1"
        ;;
    publish-srm)
        shift
        auto_publish_SRM "$1"
        ;;
    build)
        shift
        build_x64 "$1"
        ;;
    clean-all)
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
    help)
        printf "$0 [COMMAND]\n\tdocker\t\trun docker container\n\tbuild [SPK]\tbuild packages for devlopment (x64)\n\tpublish [SPK]\tbuild and publish for all architectures\n\tdigest [SPK]\tupdate digest\n\n"
        ;;
esac
