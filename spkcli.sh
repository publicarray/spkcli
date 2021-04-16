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
    for SPK in "$SCRIPT_DIR"/spk/*; do
        make -C "$SPK" clean
    done
        for SPK in "$SCRIPT_DIR"/cross/*; do
        make -C "$SPK" clean
    done
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
