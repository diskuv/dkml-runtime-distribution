#!/bin/sh
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
# r-f-oorepo-2-build.sh -d DKMLDIR -t TARGETDIR
#
# Download the Opam repository

set -euf

# ------------------
# BEGIN Command line processing

usage() {
    echo "Usage:" >&2
    echo "    r-f-oorepo-2-build.sh" >&2
    echo "        -h                              Display this help message." >&2
    echo "        -d DIR -t DIR -v IMAGE -a ARCH  Do compilation of Opam." >&2
    echo "Options" >&2
    echo "   -d DIR: DKML directory containing a .dkmlroot file" >&2
    echo "   -t DIR: Target directory" >&2
    echo "   -v IMAGE: Docker image" >&2
    echo "   -a ARCH: Docker architecture to download. Ex. amd64" >&2
}

DKMLDIR=
DOCKER_IMAGE=
DOCKER_ARCH=
TARGETDIR=
while getopts ":d:v:t:a:h" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        d )
            DKMLDIR="$OPTARG"
            if [ ! -e "$DKMLDIR/.dkmlroot" ]; then
                echo "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2;
                usage
                exit 1
            fi
            DKMLDIR=$(cd "$DKMLDIR" && pwd) # absolute path
        ;;
        v )
            DOCKER_IMAGE="$OPTARG"
        ;;
        t )
            TARGETDIR="$OPTARG"
        ;;
        a )
            DOCKER_ARCH="$OPTARG"
        ;;
        \? )
            echo "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$DKMLDIR" ] || [ -z "$DOCKER_IMAGE" ] || [ -z "$TARGETDIR" ] || [ -z "$DOCKER_ARCH" ]; then
    echo "Missing required options" >&2
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
REPODIR_UNIX=${TARGETDIR_UNIX}/full-opam-root
BASEDIR_IN_FULL_OPAMROOT=${REPODIR_UNIX}/msvc-"$DOCKER_ARCH"

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

MOBYDIR_UNIX=${DKML_MOBYDIR:-$WORK/moby}
if [ -x /usr/bin/cygpath ]; then
    MOBYDIR_UNIX=$(/usr/bin/cygpath -au "$MOBYDIR_UNIX")
fi

log_trace vendor/drd/src/unix/private/moby-download-docker-image.sh "$MOBYDIR_UNIX" vendor/drd/src/unix/private/download-frozen-image-v2.sh "$DOCKER_IMAGE" "$DOCKER_ARCH"
log_trace vendor/drd/src/unix/private/moby-extract-opam-root.sh "$MOBYDIR_UNIX" "$DOCKER_IMAGE" "$DOCKER_ARCH" msvc "$REPODIR_UNIX"

if is_cygwin_build_machine; then
    echo Fixing symlinks ...
    find "$BASEDIR_IN_FULL_OPAMROOT" -xtype l | while read -r linkpath
    do
        vendor/drd/src/cygwin/idempotent-fix-symlink.sh "$linkpath" "$REPODIR_UNIX" msvc-"$DOCKER_ARCH" /cygdrive/c/
    done
fi
