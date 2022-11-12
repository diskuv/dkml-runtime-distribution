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
# r-f-oorepo-9-trim.sh -d DKMLDIR -t TARGETDIR
#
# Remove unneeded package versions

set -euf

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    r-f-oorepo-9-trim.sh" >&2
    printf "%s\n" "        -h                                      Display this help message." >&2
    printf "%s\n" "        -d DIR -t DIR -a ARCH -b OCAMLVERSION   Create target repository without unneeded package versions." >&2
    printf "%s\n" "Options" >&2
    printf "%s\n" "   -d DIR:     DKML directory containing a .dkmlroot file" >&2
    printf "%s\n" "   -t DIR:     Target directory" >&2
    printf "%s\n" "   -n:         Dry run" >&2
    printf "%s\n" "   -p PACKAGE: Consider only the named package" >&2
    printf "%s\n" "   -a ARCH: Docker architecture that was downloaded. Ex. amd64" >&2
    printf "%s\n" "   -b OCAMLVERSION: OCaml language version. Ex. 4.12.1" >&2
    printf "%s\n" "   -c OCAML_BC_HOME: Optional. The home directory for OCaml containing bin/ocamlrun and the bytecode standard" >&2
    printf "%s\n" "      library." >&2
    printf "%s\n" "      Must be OCaml 4.12.1 or higher should work, and only the Unix and Str modules are needed" >&2
    printf "%s\n" "   -e OOREPO_TRIM_BYTECODE: The OCaml bytecode (.bc) to trim the ocaml-opam-repo" >&2
}

DKMLDIR=
TARGETDIR=
DOCKER_ARCH=
SINGLEPACKAGE=
OCAML_LANG_VERSION=
OCAML_BC_HOME=
OOREPO_TRIM_BYTECODE=
export DRYRUN=OFF
while getopts ":d:t:np:a:b:c:e:h" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        n )
            DRYRUN=ON
        ;;
        d )
            DKMLDIR="$OPTARG"
            if [ ! -e "$DKMLDIR/.dkmlroot" ]; then
                printf "%s\n" "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2;
                usage
                exit 1
            fi
        ;;
        t )
            TARGETDIR="$OPTARG"
        ;;
        p )
            SINGLEPACKAGE="$OPTARG"
        ;;
        a )
            DOCKER_ARCH="$OPTARG"
        ;;
        b )
            OCAML_LANG_VERSION="$OPTARG"
        ;;
        c )
            OCAML_BC_HOME="$OPTARG"
        ;;
        e )
            OOREPO_TRIM_BYTECODE="$OPTARG"
        ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$DKMLDIR" ] || [ -z "$TARGETDIR" ] || [ -z "$DOCKER_ARCH" ] || [ -z "$OCAML_LANG_VERSION" ] || [ -z "$OCAML_BC_HOME" ] || [ -z "$OOREPO_TRIM_BYTECODE" ]; then
    printf "%s\n" "Missing required options" >&2
    usage
    exit 1
fi

# END Command line processing
# ------------------

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

disambiguate_filesystem_paths

# Bootstrapping vars
TARGETDIR_UNIX=$(install -d "$TARGETDIR" && cd "$TARGETDIR" && pwd) # better than cygpath: handles TARGETDIR=. without trailing slash, and works on Unix/Windows
if [ -x /usr/bin/cygpath ]; then
    OOREPO_UNIX=$(/usr/bin/cygpath -au "$TARGETDIR_UNIX/$SHARE_OCAML_OPAM_REPO_RELPATH/$OCAML_LANG_VERSION")
    TARGETDIR_BUILDHOST=$(/usr/bin/cygpath -aw "$TARGETDIR_UNIX")
else
    OOREPO_UNIX="$TARGETDIR_UNIX/$SHARE_OCAML_OPAM_REPO_RELPATH/$OCAML_LANG_VERSION"
    TARGETDIR_BUILDHOST="$TARGETDIR_UNIX"
fi
export OOREPO_UNIX
REPODIR_UNIX=${TARGETDIR_UNIX}/full-opam-root
BASEDIR_IN_FULL_OPAMROOT=${REPODIR_UNIX}/msvc-"$DOCKER_ARCH"

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

# Set BUILDHOST_ARCH
autodetect_buildhost_arch

# Install files and directories into $OOREPO_UNIX:
# - /packages/
if [[ "$DRYRUN" = OFF ]]; then
    install -d "$OOREPO_UNIX"
    if has_rsync; then
        log_trace spawn_rsync -a --delete --delete-excluded \
            --exclude '.git*' --exclude '.travis*' --exclude 'Dockerfile' --exclude '*.md' --exclude 'COPYING' \
            "$BASEDIR_IN_FULL_OPAMROOT"/cygwin64/home/opam/opam-repository/packages/ "$OOREPO_UNIX"/packages
    else
        log_trace rm -rf "$OOREPO_UNIX"/packages
        log_trace install -d "$OOREPO_UNIX"/packages
        log_trace sh -x -c "cp -r '$BASEDIR_IN_FULL_OPAMROOT/cygwin64/home/opam/opam-repository/packages'/* '$OOREPO_UNIX/packages/'"
        find . \( -name '.git*' -o -name '.travis*' -o -name 'Dockerfile' -o -name '*.md' -o -name 'COPYING' \) -exec rm -rf {} \;
    fi
else
    printf "%s\n" "Would have synchronized the '$BASEDIR_IN_FULL_OPAMROOT'/cygwin64/home/opam/opam-repository/packages/ directory with $OOREPO_UNIX/packages/"
fi

# Mimic dkml-component-staging-ocamlrun.api's spawn_ocamlrun
case "$BUILDHOST_ARCH" in
windows_*)
    spawn_ocamlrun() {
        log_trace env OCAMLRUNPARAM=b \
            "OCAMLLIB=$OCAML_BC_HOME/lib/ocaml" \
            "PATH=$OCAML_BC_HOME/lib/ocaml/stublibs:${PATH:-}" \
            "$OCAML_BC_HOME/bin/ocamlrun" \
            "$@"
    }
    ;;
darwin_*)
    spawn_ocamlrun() {
        log_trace env OCAMLRUNPARAM=b \
            "OCAMLLIB=$OCAML_BC_HOME/lib/ocaml" \
            "DYLD_FALLBACK_LIBRARY_PATH=$OCAML_BC_HOME/lib/ocaml/stublibs:${DYLD_FALLBACK_LIBRARY_PATH:-}" \
            "$OCAML_BC_HOME/bin/ocamlrun" \
            "$@"
    }
    ;;
*)
    spawn_ocamlrun() {
        log_trace env OCAMLRUNPARAM=b \
            "OCAMLLIB=$OCAML_BC_HOME/lib/ocaml" \
            "LD_LIBRARY_PATH=$OCAML_BC_HOME/lib/ocaml/stublibs:${LD_LIBRARY_PATH:-}" \
            "$OCAML_BC_HOME/bin/ocamlrun" \
            "$@"
    }
    ;;
esac

# Do bulk of trimming in OCaml interpreter for speed (much faster than shell script!)
spawn_ocamlrun "$OOREPO_TRIM_BYTECODE" -t "$TARGETDIR_BUILDHOST" -b "$OCAML_LANG_VERSION" -a "$DOCKER_ARCH" -p "$SINGLEPACKAGE"

# Install files and directories into $OOREPO_UNIX:
# - /repo
# - /version
if [[ "$DRYRUN" = OFF ]]; then
    install -d "$OOREPO_UNIX"
    install -v "$BASEDIR_IN_FULL_OPAMROOT"/cygwin64/home/opam/opam-repository/repo "$BASEDIR_IN_FULL_OPAMROOT"/cygwin64/home/opam/opam-repository/version "$OOREPO_UNIX"
fi
