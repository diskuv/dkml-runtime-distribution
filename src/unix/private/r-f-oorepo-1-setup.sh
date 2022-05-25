#!/usr/bin/env bash
# ----------------------------
# Copyright 2021 Diskuv, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------
#
# @jonahbeckford: 2021-09-07
# - This file is licensed differently than the rest of the Diskuv OCaml distribution.
#   Keep the Apache License in this file since this file is part of the reproducible
#   build files.
#
######################################
# r-f-oorepo-1-setup.sh -d DKMLDIR -t TARGETDIR -g DOCKER_IMAGE [-a HOST] [-b GIT_EXE]
#
# Sets up the source code for a reproducible build

set -euf

# ------------------
# BEGIN Command line processing

SETUP_ARGS=()
BUILD_ARGS=()
TRIM_ARGS=()

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    r-f-oorepo-1-setup.sh" >&2
    printf "%s\n" "        -h                                              Display this help message." >&2
    printf "%s\n" "        -d DIR -t DIR -v IMAGE -a ARCH -b OCAMLVERSION  Setup fetching of ocaml/opam repository." >&2
    printf "%s\n" "Options" >&2
    printf "%s\n" "   -d DIR: DKML directory containing a .dkmlroot file" >&2
    printf "%s\n" "   -t DIR: Target directory" >&2
    printf "%s\n" "   -v IMAGE: Docker image" >&2
    printf "%s\n" "   -a ARCH: Docker architecture. Ex. amd64" >&2
    printf "%s\n" "   -b OCAMLVERSION: OCaml language version to setup. Ex. 4.12.1" >&2
    printf "%s\n" "   -c OCAMLHOME: Optional. The home directory for OCaml containing usr/bin/ocamlc or bin/ocamlc," >&2
    printf "%s\n" "      and other OCaml binaries and libraries. If not specified expects ocaml to be in the system PATH." >&2
    printf "%s\n" "      OCaml 4.08 and higher should work, and only the OCaml interpreter and Unix and Str modules are needed" >&2
}

DKMLDIR=
DOCKER_IMAGE=
DOCKER_ARCH=
TARGETDIR=
OCAML_LANG_VERSION=
while getopts ":d:v:t:a:b:c:h" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        d )
            DKMLDIR="$OPTARG"
            if [ ! -e "$DKMLDIR/.dkmlroot" ]; then
                printf "%s\n" "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2;
                usage
                exit 1
            fi
            # Make into absolute path
            DKMLDIR_1=$(dirname "$DKMLDIR")
            DKMLDIR_1=$(cd "$DKMLDIR_1" && pwd)
            DKMLDIR_2=$(basename "$DKMLDIR")
            DKMLDIR="$DKMLDIR_1/$DKMLDIR_2"
        ;;
        v )
            DOCKER_IMAGE="$OPTARG"
            SETUP_ARGS+=( -v "$DOCKER_IMAGE" )
            BUILD_ARGS+=( -v "$DOCKER_IMAGE" )
        ;;
        t )
            TARGETDIR="$OPTARG"
            SETUP_ARGS+=( -t . )
            BUILD_ARGS+=( -t . )
            TRIM_ARGS+=( -t . )
        ;;
        a )
            DOCKER_ARCH="$OPTARG"
            SETUP_ARGS+=( -a "$DOCKER_ARCH" )
            BUILD_ARGS+=( -a "$DOCKER_ARCH" )
            TRIM_ARGS+=( -a "$DOCKER_ARCH" )
        ;;
        b )
            OCAML_LANG_VERSION="$OPTARG"
            SETUP_ARGS+=( -b "$OCAML_LANG_VERSION" )
            TRIM_ARGS+=( -b "$OCAML_LANG_VERSION" )
        ;;
        c )
            SETUP_ARGS+=( -c "$OPTARG" )
            TRIM_ARGS+=( -c "$OPTARG" )
        ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$DKMLDIR" ] || [ -z "$DOCKER_IMAGE" ] || [ -z "$TARGETDIR" ] || [ -z "$DOCKER_ARCH" ] || [ -z "$OCAML_LANG_VERSION" ]; then
    printf "%s\n" "Missing required options" >&2
    usage
    exit 1
fi

# END Command line processing
# ------------------

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

# Make a WORK dir
create_workdir

disambiguate_filesystem_paths

# Bootstrapping vars
TARGETDIR_UNIX=$(install -d "$TARGETDIR" && cd "$TARGETDIR" && pwd) # better than cygpath: handles TARGETDIR=. without trailing slash, and works on Unix/Windows

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

vendor/drd/src/unix/private/download-moby-downloader.sh "$WORK"

# Copy self into share/dkml/repro/200-fetch-oorepo-4.12.1
export BOOTSTRAPNAME=200-fetch-oorepo-$OCAML_LANG_VERSION
export DEPLOYDIR_UNIX="$TARGETDIR_UNIX"
DESTDIR=$TARGETDIR_UNIX/$SHARE_REPRODUCIBLE_BUILD_RELPATH/$BOOTSTRAPNAME
THISDIR=$(pwd)
if [ "$DESTDIR" = "$THISDIR" ]; then
    printf "Already deployed the reproducible scripts. Replacing them as needed\n"
    DKMLDIR=.
fi
# shellcheck disable=SC2016
COMMON_ARGS=(-d "$SHARE_REPRODUCIBLE_BUILD_RELPATH/$BOOTSTRAPNAME")
install_reproducible_common
install_reproducible_readme           vendor/drd/src/unix/private/r-f-oorepo-README.md
install_reproducible_system_packages  vendor/drd/src/unix/private/r-f-oorepo-0-system.sh
install_reproducible_script_with_args vendor/drd/src/unix/private/r-f-oorepo-1-setup.sh "${COMMON_ARGS[@]}" "${SETUP_ARGS[@]}"
install_reproducible_script_with_args vendor/drd/src/unix/private/r-f-oorepo-2-build.sh "${COMMON_ARGS[@]}" "${BUILD_ARGS[@]}"
install_reproducible_script_with_args vendor/drd/src/unix/private/r-f-oorepo-9-trim.sh  "${COMMON_ARGS[@]}" "${TRIM_ARGS[@]}"
install_reproducible_file             vendor/drd/src/unix/private/ml/ocaml_opam_repo_trim.ml
install_reproducible_file             vendor/drd/src/unix/private/download-moby-downloader.sh
install_reproducible_file             vendor/drd/src/unix/private/moby-download-docker-image.sh
install_reproducible_file             vendor/drd/src/unix/private/moby-extract-opam-root.sh
if is_cygwin_build_machine; then
    install_reproducible_file         vendor/drd/src/cygwin/idempotent-fix-symlink.sh
fi
install_reproducible_generated_file   "$WORK"/download-frozen-image-v2.sh vendor/drd/src/unix/private/download-frozen-image-v2.sh
