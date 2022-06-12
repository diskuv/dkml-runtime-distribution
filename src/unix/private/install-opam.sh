#!/bin/bash
# ----------------------------
# install-opam.sh DKMLDIR GIT_TAG INSTALLDIR

set -euf

DKMLDIR=$1
shift
if [ ! -e "$DKMLDIR/.dkmlroot" ]; then echo "Expected a DKMLDIR at $DKMLDIR but no .dkmlroot found" >&2; fi

GIT_TAG=$1
shift

INSTALLDIR=$1
shift

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

# Because Cygwin has a max 260 character limit of absolute file names, we place the working directories in /tmp. We do not need it
# relative to TOPDIR since we are not using sandboxes.
if [ -z "${DKML_TMP_PARENTDIR:-}" ]; then
    DKML_TMP_PARENTDIR=$(mktemp -d /tmp/dkmlp.XXXXX)
fi

# Keep the create_workdir() provided temporary directory, even when we switch
# into the reproducible directory so the reproducible directory does not leak
# anything
export DKML_TMP_PARENTDIR

# Change the EXIT trap to clean our shorter tmp dir
trap 'rm -rf "$DKML_TMP_PARENTDIR"' EXIT

# To be portable whether we build scripts in the container or not, we
# change the directory to always be in the DKMLDIR (just like the container
# sets the directory to be /work)
cd "$DKMLDIR"

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# Set BUILDHOST_ARCH
autodetect_buildhost_arch

# Install the source code
log_trace "$DKMLDIR"/vendor/drd/src/unix/private/r-c-opam-1-setup.sh \
    -d "$DKMLDIR" \
    -t "$INSTALLDIR" \
    -a "$BUILDHOST_ARCH" \
    -c "$INSTALLDIR" \
    -u https://github.com/jonahbeckford/opam \
    -v "$GIT_TAG"

# Use reproducible directory created by setup
cd "$INSTALLDIR"

# Build and install Opam
log_trace "$SHARE_REPRODUCIBLE_BUILD_RELPATH"/110co/vendor/drd/src/unix/private/r-c-opam-2-build-noargs.sh

# Remove intermediate files including build files and .git folders
log_trace "$SHARE_REPRODUCIBLE_BUILD_RELPATH"/110co/vendor/drd/src/unix/private/r-c-opam-9-trim-noargs.sh
