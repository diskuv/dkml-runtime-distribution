#!/bin/sh
# -------------------------------------------------------
# init-opam-root.sh DKMLABI
#
# Purpose:
# 1. Install an OPAMROOT (`opam init`) in $env:LOCALAPPDATA/opam or
#    the DKMLABI's opam-root/ folder.
#
# When invoked?
# On Windows as part of `setup-userprofile.ps1`
# which is itself invoked by `install-world.ps1`. Also in CMake (DKSDK) for a
# CMake specific root.
#
# Should be idempotent. Can be used for upgrades.
#
# -------------------------------------------------------
set -euf

# ------------------
# BEGIN Command line processing

usage() {
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    init-opam-root.sh -h                         Display this help message" >&2
    printf "%s\n" "    init-opam-root.sh [-r OPAMROOT] -p DKMLABI   Initialize the Opam root" >&2
    printf "%s\n" "      Without '-r' or '-d' the Opam root will be the Opam 2.2 default" >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p DKMLABI: The DKML ABI (not 'dev')" >&2
    printf "%s\n" "    -r OPAMROOT: Use <OPAMROOT> as the Opam root. Unlike [-d] no modifications are made to its system variables" >&2
    printf "%s\n" "    -d STATEDIR: If specified, use <STATEDIR>/opam as the Opam root and modify its sys-ocaml-* variables." >&2
    printf "%s\n" "       It is an error for both [-r] and [-d] to be specified" >&2
    printf "%s\n" "    -o OPAMEXE_OR_HOME: Optional. If a directory, it is the home for Opam containing bin/opam-real or bin/opam." >&2
    printf "%s\n" "       If an executable, it is the opam to use (and when there is an opam shim the opam-real can be used)" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home (containing usr/bin/ocaml or bin/ocaml)" >&2
    printf "%s\n" "       to use." >&2
    printf "%s\n" "       The bin/ subdir of the OCaml home is added to the PATH; currently, passing an OCaml version does nothing" >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "    -a Use local repository rather than git repository for diskuv-opam-repository. Requires rsync" >&2
    printf "%s\n" "    -e DISKUV_REPO: Use DISKUV_REPO rather than the default diskuv-opam-repository. Valid opam" >&2
    printf "%s\n" "       urls must be used like https:// or git+https:// or git+file:// urls." >&2
    printf "%s\n" "    -c CENTRAL_REPO: Use CENTRAL_REPO rather than the default git+https://github.com/ocaml/opam-repository.git" >&2
    printf "%s\n" "       repository. Valid opam urls must be used like https:// or git+https:// or git+file:// urls." >&2
    printf "%s\n" "    -x Disable sandboxing in all platforms. By default, sandboxing is disabled in Windows, WSL2 and in dockcross" >&2
    printf "%s\n" "       Linux containers" >&2
    printf "%s\n" "    -i Re-init the Opam root. Useful to force disabling of the sandboxing" >&2
    printf "%s\n" "    -g GIT_EXECUTABLE: Optional. Location of a git executable. On Windows it must not be in the same directory" >&2
    printf "%s\n" "       as a bash.exe or any other executables that have conflicting names with MSYS2 binaries." >&2
}

DKMLABI=
DKML_OPAM_ROOT=
STATEDIR=
OPAMEXE_OR_HOME=
OCAMLVERSION_OR_HOME=
DISKUVOPAMREPO=REMOTE
CENTRAL_REPO=git+https://github.com/ocaml/opam-repository.git
DISABLE_SANDBOX=OFF
REINIT=OFF
GIT_EXECUTABLE=
while getopts ":hp:r:d:o:v:ac:xie:g:" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        p )
            DKMLABI=$OPTARG
            if [ "$DKMLABI" = dev ]; then
                usage
                exit 1
            fi
        ;;
        d ) STATEDIR=$OPTARG ;;
        r ) DKML_OPAM_ROOT=$OPTARG ;;
        o ) OPAMEXE_OR_HOME=$OPTARG ;;
        v ) OCAMLVERSION_OR_HOME=$OPTARG ;;
        a ) DISKUVOPAMREPO=LOCAL ;;
        e ) DISKUVOPAMREPO=$OPTARG ;;
        c ) CENTRAL_REPO=$OPTARG ;;
        x ) DISABLE_SANDBOX=ON ;;
        i ) REINIT=ON ;;
        g ) GIT_EXECUTABLE=$OPTARG ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$DKMLABI" ]; then
    printf "%s\n" "Missing -p DKMLABI option" >&2
    usage
    exit 1
fi
if [ -n "$STATEDIR" ] && [ -n "$DKML_OPAM_ROOT" ]; then
    printf "%s\n" "Both -d and -r cannot be specified at the same time" >&2
    usage
    exit 1
fi

# END Command line processing
# ------------------

if [ -z "${DKMLDIR:-}" ]; then
    DKMLDIR=$(dirname "$0")
    DKMLDIR=$(cd "$DKMLDIR/../../../../.." && pwd)
fi

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/_common_tool.sh

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# ------------------
# BEGIN Feature flags
DKML_FEATURE_FLAG_POST_OPAM_2_2_BETA2=${DKML_FEATURE_FLAG_POST_OPAM_2_2_BETA2:-ON}

if [ "$DKML_FEATURE_FLAG_POST_OPAM_2_2_BETA2" = ON ]; then
    echo "Using feature flag: DKML_FEATURE_FLAG_POST_OPAM_2_2_BETA2"
fi

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# BEGIN         ON-DEMAND VERSIONED GLOBAL INSTALLS
#
# Anything that is in DiskuvOCamlHome is really just for platforms like Windows
# that must have pre-installed software (for Windows that is MSYS2 or we couldn't
# even run this script).
#
# So ... try to do as much as possible in this section (or "ON-DEMAND OPAM ROOT INSTALLATIONS" below).
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Set DKMLPARENTHOME_BUILDHOST
set_dkmlparenthomedir

# Set GIT_LOCATION_MIXED
autodetect_system_path_with_git_before_usr_bin
if [ -z "$GIT_EXECUTABLE" ]; then
    GIT_EXECUTABLE=$(PATH="$DKML_SYSTEM_PATH" command -v git)
fi
GIT_LOCATION_MIXED=$(dirname "$GIT_EXECUTABLE")
if [ -x /usr/bin/cygpath ]; then
    GIT_LOCATION_MIXED=$(/usr/bin/cygpath -am "$GIT_LOCATION_MIXED")
else
    GIT_LOCATION_MIXED=$(cd "$GIT_LOCATION_MIXED" && pwd)
fi

# Set DKMLSYS_AWK and other things
autodetect_system_binaries

# -----------------------
# BEGIN install opam repositories

# 2023-06-25:
#   The versioning of diskuv-opam-repository is done using git tags with
#   DkML's release.sh (which is changing to a CMake packaging/ target).
#   The LOCAL form of diskuv-opam-repository is no longer needed, although
#   the option still exists. Not only that, the LOCAL form requires that
#   there is the correct version of the repository available; if someone
#   used the DkML installer, it is quite possible that the versions will
#   not match. So ... avoid the LOCAL form.
#
# Original notes:
#   Make versioned repos
#
#   Q: Why is repos here rather than in DiskuvOCamlHome?
#   The repos are required for Unix, not just Windows.
#
#   Q: Why aren't we using an HTTP(S) site?
#   Yep, we could have done `opam admin index`
#   and followed the https://opam.ocaml.org/doc/Manual.html#Repositories instructions.
#   It is not hard _but_ we want a) versioning of the repository to coincide with
#   the version of Diskuv OCaml and b) ability to
#   edit the repository for `AdvancedToolchain.rst` patching. We could have done
#   both with HTTP(S) but simpler is usually better.

if [ "$DISKUVOPAMREPO" = LOCAL ]; then
    if [ -x /usr/bin/cygpath ]; then
        # shellcheck disable=SC2154
        OPAMREPOS_MIXED=$(/usr/bin/cygpath -am "$DKMLPARENTHOME_BUILDHOST\\repos\\$dkml_root_version")
        OPAMREPOS_UNIX=$(/usr/bin/cygpath -au "$DKMLPARENTHOME_BUILDHOST\\repos\\$dkml_root_version")
    else
        OPAMREPOS_MIXED="$DKMLPARENTHOME_BUILDHOST/repos/$dkml_root_version"
        OPAMREPOS_UNIX="$OPAMREPOS_MIXED"
    fi
    if [ ! -e "$OPAMREPOS_UNIX".complete ]; then
        install -d "$OPAMREPOS_UNIX"
        if has_rsync; then
            if [ "$DISKUVOPAMREPO" = LOCAL ]; then
                log_trace spawn_rsync -ap "$DKMLDIR"/vendor/diskuv-opam-repository/ "$OPAMREPOS_UNIX/diskuv-opam-repository"
            fi
        else
            log_trace install -d "$OPAMREPOS_UNIX"
            if [ "$DISKUVOPAMREPO" = LOCAL ]; then
                log_trace install -d "$OPAMREPOS_UNIX"/diskuv-opam-repository
                log_trace sh -x -c "cp -r '$DKMLDIR/vendor/diskuv-opam-repository'/* '$OPAMREPOS_UNIX/diskuv-opam-repository/'"
            fi
        fi
        touch "$OPAMREPOS_UNIX".complete
    fi
fi

# END install opam repositories
# -----------------------

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# END           ON-DEMAND VERSIONED GLOBAL INSTALLS
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# -----------------------
# BEGIN opam init

# Windows does not have a non-deprecated working Opam solution, so we choose
# to have $LOCALAPPDATA/opam be the Opam root for the dev platform. That is
# aligned with ~/.opam for Opam before Opam 2.2. For Windows we also don't have a
# package manager that comes with `opam` pre-compiled, so we bootstrap an
# Opam installation from our Moby Docker downloaded of ocaml/opam image
# (see install-world.ps1).

# Set OPAMROOTDIR_BUILDHOST and OPAMROOTDIR_EXPAND
set_opamrootdir

run_opam() {
    log_trace "$DKMLDIR"/vendor/drd/src/unix/private/platform-opam-exec.sh \
        -p "$DKMLABI" -d "$STATEDIR" -r "$DKML_OPAM_ROOT" \
        -o "$OPAMEXE_OR_HOME" -v "$OCAMLVERSION_OR_HOME" "$@"
}
run_opam_return_error() {
    log_trace --return-error-code "$DKMLDIR"/vendor/drd/src/unix/private/platform-opam-exec.sh \
        -p "$DKMLABI" -d "$STATEDIR" -r "$DKML_OPAM_ROOT" \
        -o "$OPAMEXE_OR_HOME" -v "$OCAMLVERSION_OR_HOME" "$@"
}
run_opam_with_retries() {
    if ! run_opam_return_error "$@"; then
        sleep 2
        if ! run_opam_return_error "$@"; then
            sleep 8
            run_opam "$@"
        fi
    fi
}

# `opam init`.
already_added_default_repository=0
if ! is_minimal_opam_root_present "$OPAMROOTDIR_BUILDHOST" || [ "$REINIT" = ON ]; then
    # Common options.
    # --no-setup: Don't modify user shell configuration (ex. ~/.profile). For containers,
    #             the home directory inside the Docker container is not persistent anyways.
    # --bare: so we can configure its settings before adding the OCaml system compiler.
    #
    # Problem:
    #   [build] <><> Fetching repository information ><><><><><><><><><><><><><><><><><><><><><>
    #   [build] [ERROR] Could not update repository "default": Y:\source\dkml\build\pkg\bump\.ci\sd4\bs\bin\opam.exe: "rename" failed on Y:\source\dkml\build\pkg\bump\.ci\o\repo\default.new: Permission denied
    #   [build] [ERROR] Initial download of repository failed.
    # Context (conversation with Jonah and David):
    #   > So far it seems very much timing influenced. If I turn on logging it (my own, not opam's) between steps it (so far) works ... but if I turn off logging it doesn't consistently. And if I do them manually from the command line I can never get the symptom to appear. (I have turned off antivirus)
    #
    #   > The behavior is sounding like https://devblogs.microsoft.com/oldnewthing/20120907-00/?p=6663
    #
    #   > One thing I do know is that I have to kill git occasionally in VS Code because the stupid thing (git) holds references to sub directories.
    #
    # Solution: Do `opam init` with retries and backoff.
    if [ "$REINIT" = ON ]; then
        run_opam_init() {
            if ! run_opam_return_error init --yes --no-setup --bare --reinit "$@"; then
                sleep 10
                run_opam init --yes --no-setup --bare --reinit "$@"
            fi
        }
    else
        run_opam_init() {
            # Start without any [--reinit] ...
            if ! run_opam_return_error init --yes --no-setup --bare "$@"; then
                sleep 10
                run_opam init --yes --no-setup --bare --reinit "$@"
            fi
        }
    fi
    if [ -x /usr/bin/cygpath ]; then
        # --disable-sandboxing: Sandboxing does not work on native Windows.
        if [ "$DKML_FEATURE_FLAG_POST_OPAM_2_2_BETA2" = ON ]; then
            # --cygwin-location=DIR: Cygwin (actually MSYS2) root location
            # --git-location: git binary directory
            run_opam_init --disable-sandboxing \
                "--cygwin-location=$(/usr/bin/cygpath -am /)" \
                "--git-location=$GIT_LOCATION_MIXED" \
                default "$CENTRAL_REPO"
        else
            run_opam_init --disable-sandboxing default "$CENTRAL_REPO"
        fi
    elif [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ]; then
        # In WSL2 the bwrap sandboxing does not work.
        # See https://giters.com/realworldocaml/book/issues/3331 for one issue; jonahbeckford@ tested as well
        # with Ubuntu 20.04 LTS in WSL2 and got (paths are slightly changed):
        #   [ERROR] Sandboxing is not working on your platform ubuntu:
        #           "~/build/opam/opam-init/hooks/sandbox.sh build sh -c echo SUCCESS >$TMPDIR/opam-sandbox-check-out && cat $TMPDIR/opam-sandbox-check-out; rm -f $TMPDIR/opam-sandbox-check-out" exited with code 1 "bwrap: Can't bind mount /oldroot/mnt/z/source on /newroot/home/jonah/source: No such file or directory"
        run_opam_init --disable-sandboxing default "$CENTRAL_REPO"
    elif [ -n "${DEFAULT_DOCKCROSS_IMAGE:-}" ] || [ -e /dockcross ]; then
        # Inside dockcross is already sandboxed. And often Docker containers can't
        # be nested, so bwrap probably won't work. Regardless, Opam will
        # preemptively give an error:
        #   [ERROR] Missing dependencies -- the following commands are required for opam to operate:
        #       - bwrap: Sandboxing tool bwrap was not found. You should install 'bubblewrap'. See https://opam.ocaml.org/doc/FAQ.html#Why-does-opam-require-bwrap.
        # which we shouldn't do anything about.
        run_opam_init --disable-sandboxing default "$CENTRAL_REPO"
    elif [ "$DISABLE_SANDBOX" = ON ]; then
        run_opam_init --disable-sandboxing default "$CENTRAL_REPO"
    else
        run_opam_init default "$CENTRAL_REPO"
    fi
    already_added_default_repository=1
fi

# If we have a state directory then "sys-ocaml-*"
# variables need to be searched from within the state directory
if [ -n "$STATEDIR" ]; then
    case "$OCAMLVERSION_OR_HOME" in
        /* | ?:*) # /a/b/c or C:\Windows
            validate_and_explore_ocamlhome "$OCAMLVERSION_OR_HOME"
            {
                # ex.:
                #   sed 's#"ocamlc"#"/tmp/dckbuild/darwin_x86_64/Debug/dksdk/ocaml/bin/ocamlc"#g'
                # for ...
                # eval-variables: [
                #   [
                #     sys-ocaml-version
                #     ["ocamlc" "-vnum"]
                #     "OCaml version present on your system independently of opam, if any"
                #   ]
                #   ...
                # ]
                #   shellcheck disable=SC2016
                printf '/^eval-variables:/,/^]/s#"ocamlc"#"%s"#g\n' "$DKML_OCAMLHOME_ABSBINDIR_MIXED/ocamlc"
                # ex.:
                #   sed 's#"ocamlc -config#"/tmp/dckbuild/darwin_x86_64/Debug/dksdk/ocaml/bin/ocamlc -config#g'
                # for ...
                # eval-variables: [
                #   [
                #     sys-ocaml-arch
                #    [
                #      "sh"
                #      "-c"
                #      "ocamlc -config 2>/dev/null | tr -d '\\r' | grep '^architecture: ' | sed -e 's/.*: //' -e 's/i386/i686/' -e 's/amd64/x86_64/'"
                #    ]
                #   ]
                #   ...
                # ]
                #   shellcheck disable=SC2016
                printf '/^eval-variables:/,/^]/s#"ocamlc -config#"%s#g\n' "$DKML_OCAMLHOME_ABSBINDIR_MIXED/ocamlc -config"
            } > "$WORK/sys-ocaml.sed"
            "$DKMLSYS_SED" -f "$WORK/sys-ocaml.sed" "$OPAMROOTDIR_BUILDHOST/config" > "$WORK/config.new"
            if ! cmp -s "$WORK/config.new" "$OPAMROOTDIR_BUILDHOST/config"; then
                mv "$WORK/config.new" "$OPAMROOTDIR_BUILDHOST/config"
            fi
            ;;
    esac
fi

# If and only if we have Windows Opam root we have to configure its global options
# to tell it to use `wget` instead of `curl`
if is_unixy_windows_build_machine; then
    WINDOWS_DOWNLOAD_COMMAND=wget

    # MSYS curl does not work with Opam. After debugging with `platform-opam-exec.sh ... reinstall ocaml-variants --debug` found it was calling:
    #   C:\source\...\build\_tools\common\MSYS2\usr\bin\curl.exe --write-out %{http_code}\n --retry 3 --retry-delay 2 --user-agent opam/2.1.0 -L -o C:\Users\...\.opam\4.12\.opam-switch\sources\ocaml-variants\4.12.0.tar.gz.part -- https://github.com/ocaml/ocaml/archive/4.12.0.tar.gz
    # yet erroring with:
    #   [ERROR] Failed to get sources of ocaml-variants.4.12.0+msvc64: curl error code %http_coden
    # Seems like Windows command line processing is stripping braces and backslash (upstream bugfix: wrap --write-out argument with single quotes?).
    # Goes away with wget!! With wget has no funny symbols ... it is like:
    #   C:\source\...\build\_tools\common\MSYS2\usr\bin\wget.exe --content-disposition -t 3 -O C:\Users\...\AppData\Local\Temp\opam-29232-cc6ec1\inline-flexdll.patch.part -U opam/2.1.0 -- https://gist.githubusercontent.com/fdopen/fdc645a61a208552ebac76a67eafd3ee/raw/9f521e91c8f0e9490652651ccdbfae88da701919/inline-flexdll.patch
    if ! grep -q '^download-command: wget' "$OPAMROOTDIR_BUILDHOST/config"; then
        run_opam option --yes --global download-command=$WINDOWS_DOWNLOAD_COMMAND
    fi
fi

# Make a `default` repo that is an overlay of diskuv-opam-repository and finally the offical Opam repository.
# If we don't we get make a repo named "default" in opam 2.1.0 the following will happen:
#     #=== ERROR while compiling ocamlbuild.0.14.0 ==================================#
#     Sys_error("C:\\Users\\user\\.opam\\repo\\default\\packages\\ocamlbuild\\ocamlbuild.0.14.0\\files\\ocamlbuild-0.14.0.patch: No such file or directory")
if [ ! -e "$OPAMROOTDIR_BUILDHOST/repo/diskuv-$dkml_root_version" ] && [ ! -e "$OPAMROOTDIR_BUILDHOST/repo/diskuv-$dkml_root_version.tar.gz" ]; then
    case "$DISKUVOPAMREPO" in
        LOCAL)
            OPAMREPO_DISKUV="$OPAMREPOS_MIXED/diskuv-opam-repository"
            run_opam repository add diskuv-"$dkml_root_version" "$OPAMREPO_DISKUV" --yes --dont-select --rank=1
            ;;
        REMOTE)
            run_opam repository add diskuv-"$dkml_root_version" "git+https://github.com/diskuv/diskuv-opam-repository.git#$dkml_root_version" --yes --dont-select --rank=1
            ;;
        *)
            run_opam repository add diskuv-"$dkml_root_version" "$DISKUVOPAMREPO" --yes --dont-select --rank=1
    esac
else
    # If there is an update for an updateable repository, use it
    case "$DISKUVOPAMREPO" in
        LOCAL|REMOTE) ;;
        *)
            run_opam repository set-url diskuv-"$dkml_root_version" "$DISKUVOPAMREPO" --yes
    esac
fi

# add the [default] repository if a [default] is not there
if [ "$already_added_default_repository" = 0 ]; then
    if [ ! -e "$OPAMROOTDIR_BUILDHOST/repo/default" ] && [ ! -e "$OPAMROOTDIR_BUILDHOST/repo/default.tar.gz" ]; then
        if [ -d "$OPAMROOTDIR_BUILDHOST/repo" ]; then
            ls -l "$OPAMROOTDIR_BUILDHOST/repo"
        fi
        run_opam repository add default "$CENTRAL_REPO" --yes --dont-select --rank=3
    else
        # force the [default] to be up-to-date because unlike [diskuv-opam-repository] the
        # [default] is not versioned (which means we have no way to tell it is up-to-date).
        # using `set-url` is required in case CENTRAL_REPO changes, and since it also
        # updates the repository we don't need an explicit `run_opam update default --yes --all`
        #
        # This is also prone to:
        #   [build] [ERROR] Could not update repository "default": Y:\source\dkml\build\pkg\bump\.ci\sd4\bs\bin\opam.exe: "rename" failed on Y:\source\dkml\build\pkg\bump\.ci\o\repo\default.new: Permission denied
        run_opam_with_retries repository set-url default "$CENTRAL_REPO" --yes --all
    fi
fi

# Set MSYS2
#   Input Environment (example):
#       MSYSTEM=CLANG64
#       MSYSTEM_CARCH=x86_64
#       MSYSTEM_CHOST=x86_64-w64-mingw32
#       MSYSTEM_PREFIX=/clang64
#       MINGW_CHOST=x86_64-w64-mingw32
#       MINGW_PREFIX=/clang64
#       MINGW_PACKAGE_PREFIX=mingw-w64-clang-x86_64
#
#   The `MSYSTEM` comes from https://www.msys2.org/docs/environments/
#
#   The remaining environment variables are mastered in
#   https://github.com/msys2/MSYS2-packages/blob/1ff9c79a6b6b71492c4824f9888a15314b85f5fa/filesystem/msystem:
#       MSYSTEM_PREFIX MSYSTEM_CARCH MSYSTEM_CHOST MINGW_CHOST MINGW_PREFIX MINGW_PACKAGE_PREFIX
#
#   Opam Global Variables (part 1 ... these will end up as compiler flags or a conf package):
#       msystem=CLANG64
#       msystem-prefix=/clang64
#       msystem-carch=x86_64
#       msystem-chost=x86_64-w64-mingw32
#       mingw-chost=x86_64-w64-mingw32
#       mingw-prefix=/clang64
#       mingw-package-prefix=mingw-w64-clang-x86_64
#
#   Opam Global Variables (part 2):
#       msys2-nativedir=C:\msys64
#       os-distribution=msys2
#
#   Note: Here is where opam may upgrade the repository layout:
#       This [development] version of opam requires an update to the layout of C:\build\pkg\bump\.ci\o
#       from version 2.1 to version 2.2~alpha, which can't be reverted.
#       So use --yes for any subsequent [opam var]
if [ -n "${MSYSTEM:-}" ] && [ -x /usr/bin/cygpath ]; then
    msys2nativedir=$(/usr/bin/cygpath -aw "/")
    run_opam var --global "os-distribution=msys2" --yes
    run_opam var --global "msystem=$MSYSTEM" --yes
    run_opam var --global "msystem-prefix=${MSYSTEM_PREFIX:-}" --yes
    run_opam var --global "msystem-carch=${MSYSTEM_CARCH:-}" --yes
    run_opam var --global "msystem-chost=${MSYSTEM_CHOST:-}" --yes
    run_opam var --global "mingw-chost=${MINGW_CHOST:-}" --yes
    run_opam var --global "mingw-prefix=${MINGW_PREFIX:-}" --yes
    run_opam var --global "mingw-package-prefix=${MINGW_PACKAGE_PREFIX:-}" --yes
    run_opam var --global "msys2-nativedir=$msys2nativedir" --yes
    # Tell opam to not use MSYS2's pacman for depexts
    run_opam option --global "depext=false" --yes
    if ! [ "$DKML_FEATURE_FLAG_POST_OPAM_2_2_BETA2" = ON ]; then
        syspkgmgrpath=$(/usr/bin/cygpath -aw "/usr/bin/pacman.exe")
        syspkgmgrpath_ESCAPED=$(printf "%s" "$syspkgmgrpath" | "$DKMLSYS_SED" 's#\\#\\\\#g')
        # * We can use sys-pkg-manager-cmd+= is idempotent, even if msys2 has a
        #   different existing value.
        # * Only some later prereleases of opam 2.2 support that option, so we'll
        #   use essentially a try/catch to fallback to the older option.
        #   That can disappear sometime after
        #   https://github.com/ocaml/opam/pull/5436 propagates
        #   to DkML. Then only **sys-pkg-manager-cmd** should be kept.
        if ! run_opam_return_error option --global "sys-pkg-manager-cmd+=[\"msys2\" \"$syspkgmgrpath_ESCAPED\"]" --yes; then
            run_opam var --global "sys-pkg-manager-cmd-msys2=$syspkgmgrpath" --yes
        fi

    fi
fi

# Diagnostics
log_trace echo '=== opam repository list --all ==='
run_opam repository list --all --yes
log_trace echo '=== opam var --global ==='
run_opam var --global --yes

# END opam init
# -----------------------
