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

    # make -C spk/"$1" arch-armv7-1.2
    # make -C spk/"$1" publish arch-armv7-1.2
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
    # CUR_PWD="$PWD"
    # SPK="$(basename "$PWD")"
    # cd ../cross/"$SPK" || exit 1
    # make clean
    # make digests
    # cd "$CUR_PWD"
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
    help)
        printf "$0 [COMMAND]\n\tdocker\t\trun docker container\n\tbuild [SPK]\tbuild packages for devlopment (x64)\n\tpublish [SPK]\tbuild and publish for all architectures\n\tdigest [SPK]\tupdate digest\n\n"
        ;;
esac
