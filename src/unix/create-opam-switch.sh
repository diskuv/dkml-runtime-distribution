#!/bin/sh
set -euf

# ------
# pinned
# ------
#
# The format is `PACKAGE_NAME,PACKAGE_VERSION`. Notice the **comma** inside the quotes!

# These MUST BE IN SYNC with:
# https://github.com/diskuv/dkml-workflows-prerelease/blob/v1/src/logic/model.ml's [global_env_vars]
# https://github.com/diskuv/dkml-workflows-prerelease/blob/v1/src/scripts/setup-dkml.sh's [do_pins]
#
# Summary: DKML provides patches for these
#
# Sections:
# 0. Subset of packages from dune-*-pkgs.txt, in `.txt` order
# 1. Subset of packages from ci-*-pkgs.txt, in `.txt` order
# 2. Subset of packages from full-pkgs.txt, in `.txt` order
# 3. Any packages that don't belong in #1 and #2, in alphabetical order

OCAML_DEFAULT_VERSION=4.14.2

# ------------------
# BEGIN Command line processing

# __escape_args_for_shell ARG1 ARG2 ...
# (Copied from crossplatform-functions.sh)
#
# If `__escape_args_for_shell asd sdfs 'hello there'` then prints `asd sdfs hello\ there`
#
# Prereq: autodetect_system_binaries
__escape_args_for_shell() {
    # Confer %q in https://www.gnu.org/software/bash/manual/bash.html#Shell-Builtin-Commands
    bash -c 'printf "%q " "$@"' -- "$@" | PATH=/usr/bin:/bin sed 's/ $//'
}

usage() {
    printf "%s\n" "Creates a local Opam switch with a working compiler.">&2
    printf "%s\n" "  Will pre-pin package versions based on the installed Diskuv OCaml distribution." >&2
    printf "%s\n" "  Will set switch options pin package versions needed to compile on Windows." >&2
    printf "%s\n" "Usage:" >&2
    printf "%s\n" "    create-opam-switch.sh -h           Display this help message" >&2
    printf "%s\n" "    create-opam-switch.sh -p DKMLABI (-s|-n GLOBALOPAMSWITCH|-t LOCALOPAMSWITCH)" >&2
    printf "%s\n" "                                       Create the Opam switch." >&2
    printf "%s\n" "                                       If an OCaml home is specified with the -v option, then the" >&2
    printf "%s\n" "                                       switch will have a 'system' OCaml compiler that uses OCaml from the" >&2
    printf "%s\n" "                                       PATH. If an OCaml version is specified with the -v option, and the" >&2
    printf "%s\n" "                                       -p option is used, then the switch will build a 'base' OCaml compiler." >&2
    printf "%s\n" "                                       Otherwise (ie. OCaml version specified with the -v option but no -p option, or" >&2
    printf "%s\n" "                                       the -v option not specified) the switch must be created by the DKSDK product;" >&2
    printf "%s\n" "                                       DKSDK will supply environment variables so that the switch can build a" >&2
    printf "%s\n" "                                       'base' OCaml compiler, although this path is rare since DKSDK will typically" >&2
    printf "%s\n" "                                       create and use an OCaml home. DKSDK will also supply variables so that the" >&2
    printf "%s\n" "                                       -b option is not needed; otherwise -b option is required." >&2
    printf "%s\n" "Opam root directory:" >&2
    printf "%s\n" "    If -r OPAMROOT then <OPAMROOT> is the Opam root directory." >&2
    printf "%s\n" "    Or if -d STATEDIR then <STATEDIR>/opam is the Opam root directory." >&2
    printf "%s\n" "    Otherwise the Opam root directory is the user's standard Opam root directory." >&2
    printf "%s\n" "    It is an error for both [-r] and [-d] to be specified" >&2
    printf "%s\n" "Opam [dkml] switch:" >&2
    printf "%s\n" "    The default [dkml] switch is the 'dkml' global switch." >&2
    printf "%s\n" "    In highest precedence order:" >&2
    printf "%s\n" "    1. If the environment variable DKSDK_INVOCATION is set to ON," >&2
    printf "%s\n" "       the [dkml] switch will be the 'dksdk-<DKML_HOST_ABI>' global switch." >&2
    printf "%s\n" "    2. If there is a Diskuv OCaml installation, then the [dkml] switch will be" >&2
    printf "%s\n" "       the local <DiskuvOCamlHome>/dkml switch." >&2
    printf "%s\n" "    These rules allow for the DKML OCaml system compiler to be distinct from" >&2
    printf "%s\n" "    any DKSDK OCaml system compiler." >&2
    printf "%s\n" "Options:" >&2
    printf "%s\n" "    -p DKMLABI: The DKML ABI (not 'dev'). Determines how to make an OCaml home if a version number is specified" >&2
    printf "%s\n" "       (or nothing) using -v option. Also part of the name for the dkml switch if -s option" >&2
    printf "%s\n" "    -s: Create the [dkml] switch" >&2
    printf "%s\n" "    -n GLOBALOPAMSWITCH: The target global Opam switch. If specified adds --switch to opam" >&2
    printf "%s\n" "    -t LOCALOPAMSWITCH: The target Opam switch. If specified adds --switch to opam." >&2
    printf "%s\n" "       Usability enhancement: Opam init shell scripts search the ancestor paths for an" >&2
    printf "%s\n" "       '_opam' directory, so the local switch will be found if you are in <LOCALOPAMSWITCH>" >&2
    printf "%s\n" "    -r OPAMROOT: Use <OPAMROOT> as the Opam root" >&2
    printf "%s\n" "    -d STATEDIR: Use <STATEDIR>/opam as the Opam root directory" >&2
    printf "%s\n" "    -b BUILDTYPE: The build type which is one of:" >&2
    printf "%s\n" "        Debug" >&2
    printf "%s\n" "        Release - Most optimal code. Should be faster than ReleaseCompat* builds" >&2
    printf "%s\n" "        ReleaseCompatPerf - Compatibility with 'perf' monitoring tool." >&2
    printf "%s\n" "        ReleaseCompatFuzz - Compatibility with 'afl' fuzzing tool." >&2
    printf "%s\n" "       Ignored when -v OCAMLHOME is a OCaml home" >&2
    printf "%s\n" "    -u ON|OFF: Deprecated" >&2
    printf "%s\n" "    -a: Do not look for with-dkml. By default with-dkml is added to the PATH and used as the wrap-build-commands," >&2
    printf "%s\n" "        wrap-install-commands and wrap-remove-commands. Use -0 WRAP_COMMAND if you want your own wrap commands" >&2
    printf "%s\n" "    -w: Disable updating of opam repositories. Useful when already updated (ex. by init-opam-root.sh)" >&2
    printf "%s\n" "    -x: Disable creation of switch and setting of pins. All other steps like option creation are done." >&2
    printf "%s\n" "        Useful during local development" >&2
    printf "%s\n" "    -F: Deprecated. Disable adding of the fdopen repository on Windows, which is no longer available" >&2
    printf "%s\n" "    -z: Do not use any default invariants (ocaml-system, dkml-base-compiler). If the -m option is not used," >&2
    printf "%s\n" "       there will be no invariants. When there are no invariants no pins will be created" >&2
    printf "%s\n" "    -v OCAMLVERSION_OR_HOME: Optional. The OCaml version or OCaml home containing bin/ocaml or usr/bin/ocaml" >&2
    printf "%s\n" "       to use. The OCaml home, which prefers bin/ocaml over usr/bin/ocaml determines the native code produced by the switch." >&2
    printf "%s\n" "       Examples: 4.13.1, /usr, /opt/homebrew" >&2
    printf "%s\n" "    -o OPAMEXE_OR_HOME: Optional. If a directory, it is the home for Opam containing bin/opam-real or bin/opam." >&2
    printf "%s\n" "       If an executable, it is the opam to use (and when there is an opam shim the opam-real can be used)" >&2
    printf "%s\n" "    -y Say yes to all questions (can be overridden with DKML_OPAM_FORCE_INTERACTIVE=ON)" >&2
    printf "%s\n" "    -c EXTRAPATH: Optional. Semicolon separated PATH that should be available to all users of and packages" >&2
    printf "%s\n" "       in the switch. Since the PATH is affected the EXTRAPATH must be for the host ABI." >&2
    printf "%s\n" "       Users of with-dkml.exe should also do '-e DKML_3P_PROGRAM_PATH+=<EXTRAPATH>' so that PATH can propagate." >&2
    printf "%s\n" "    -e NAME=VAL or -e NAME+=VAL: Optional; can be repeated. Environment variables that will be available" >&2
    printf "%s\n" "       to all users of and packages in the switch" >&2
    printf "%s\n" "    -f NAME=VAL or -f NAME=: Optional; can be repeated. Opam variables that will be available" >&2
    printf "%s\n" "       to all <package>.opam in the switch. '-f NAME=' will delete the variable if present." >&2
    printf "%s\n" "    -R NAME=EXTRAREPO: Optional; may be repeated. Opam repository to use in the switch. Will be higher priority" >&2
    printf "%s\n" "       than the implicit repositories like the default opam.ocaml.org repository. First repository listed on command" >&2
    printf "%s\n" "       line will be highest priority of the extra repositories." >&2
    printf "%s\n" "    -i HOOK: Optional; may be repeated. Command that will be run after the Opam switch has been created." >&2
    printf "%s\n" "       The hook file must be a /bin/sh script (POSIX compatible script, not Bash!)." >&2
    printf "%s\n" "       Opam commands should be platform-neutral, and will be executed after the switch has been initially" >&2
    printf "%s\n" "       created with a minimal OCaml compiler, and after pins and options are set for the switch." >&2
    printf "%s\n" "       The Opam commands should use \$OPAMEXE as the path to the Opam executable. \$OPAMSWITCH and" >&2
    printf "%s\n" "       \$OPAMROOT will have already been set; \$OPAMCONFIRMLEVEL will be 'unsafe-yes'." >&2
    printf "%s\n" "          Example: \$OPAMEXE pin add --yes opam-lib 'https://github.com/ocaml/opam.git#1.2'" >&2
    printf "%s\n" "       The hook file must use LF (not CRLF) line terminators. In a git project we recommend including" >&2
    printf "%s\n" "         *.sh text eol=lf" >&2
    printf "%s\n" "       or similar in a .gitattributes file so on Windows the file is not autoconverted to CRLF on git checkout." >&2
    printf "%s\n" "    -0 WRAP_COMMAND: Use <WRAP_COMMAND> instead of with-dkml for wrap-build-commands, wrap-install-commands and" >&2
    printf "%s\n" "       wrap-remove-commands" >&2
    printf "%s\n" "    -j PREBUILD: Optional; may be repeated. A pre-build-command that Opam will execute before building any" >&2
    printf "%s\n" "      Opam package. Documentation is at https://opam.ocaml.org/doc/Manual.html#configfield-pre-build-commands" >&2
    printf "%s\n" "      and the format of PREBUILD must be:" >&2
    printf "%s\n" "        <term> { <filter> } ..." >&2
    printf "%s\n" "      The enclosing [ ] array will be added automatically; do not add it yourself." >&2
    printf "%s\n" "    -k POSTINSTALL: Optional; may be repeated. A post-install-command that Opam will execute before building any" >&2
    printf "%s\n" "      Opam package. Documentation is at https://opam.ocaml.org/doc/Manual.html#configfield-post-install-commands" >&2
    printf "%s\n" "      ; see -j PREBUILD for the format." >&2
    printf "%s\n" "    -l PREREMOVE: Optional; may be repeated. A pre-remove-command that Opam will execute before building any" >&2
    printf "%s\n" "      Opam package. Documentation is at https://opam.ocaml.org/doc/Manual.html#configfield-pre-remove-commands" >&2
    printf "%s\n" "      ; see -j PREBUILD for the format." >&2
    printf "%s\n" "    -m EXTRAINVARIANT: Optional; may be repeated. Opam package or package.version that will be added to the switch" >&2
    printf "%s\n" "      invariant" >&2
}
# Two operators: option setenv(OP1)"NAME OP2 VALUE"
#
# OP1
# ---
#   (from opam option --help)
#   `=` will reset
#   `+=` will append
#   `-=` will remove an element
#
# OP2
# ---
#   http://opam.ocaml.org/doc/Manual.html#Environment-updates
#   `=` overrides the environment variable
#   `+=` prepends to the environment variable without adding a path separator (`;` or `:`) at the end if empty
#
# [add_do_setenv_option "NAME OP2 VALUE"] is OP1=`+=` and OP2="NAME OP2 VALUE"
# [add_remove_setenv NAME OP2] is OP1=`-=` for all existing "NAME OP2 *"
DO_SETENV_OPTIONS=
add_do_setenv_option() {
    add_do_setenv_option_CMD=$1
    shift
    add_do_setenv_option_ESCAPED=$(__escape_args_for_shell "$add_do_setenv_option_CMD")
    # newlines are stripped by MSYS2 dash, so use semicolons as separator
    if [ -z "$DO_SETENV_OPTIONS" ]; then
        DO_SETENV_OPTIONS=$(printf "do_setenv_option %s" "$add_do_setenv_option_ESCAPED")
    else
        DO_SETENV_OPTIONS=$(printf "%s ; do_setenv_option %s" "$DO_SETENV_OPTIONS" "$add_do_setenv_option_ESCAPED")
    fi
}
add_remove_setenv() {
    add_remove_setenv_NAME=$1
    shift
    add_remove_setenv_OP2=$1
    shift
    if [ -z "$DO_SETENV_OPTIONS" ]; then
        DO_SETENV_OPTIONS=$(printf "remove_setenv %s %s" "$add_remove_setenv_NAME" "$add_remove_setenv_OP2")
    else
        DO_SETENV_OPTIONS=$(printf "%s ; remove_setenv %s %s" "$DO_SETENV_OPTIONS" "$add_remove_setenv_NAME" "$add_remove_setenv_OP2")
    fi
}

DO_VARS=
add_do_var() {
    add_do_var_CMD=$1
    shift
    add_do_var_ESCAPED=$(__escape_args_for_shell "$add_do_var_CMD")
    # newlines are stripped by MSYS2 dash, so use semicolons as separator
    if [ -z "$DO_VARS" ]; then
        DO_VARS=$(printf "do_var %s" "$add_do_var_ESCAPED")
    else
        DO_VARS=$(printf "%s ; do_var %s" "$DO_VARS" "$add_do_var_ESCAPED")
    fi
}
DO_HOOKS=
add_do_hook() {
    add_do_hook_CMD=$1
    shift
    add_do_hook_ESCAPED=$(__escape_args_for_shell "$add_do_hook_CMD")
    # newlines are stripped by MSYS2 dash, so use semicolons as separator
    if [ -z "$DO_HOOKS" ]; then
        DO_HOOKS=$(printf "do_hook %s" "$add_do_hook_ESCAPED")
    else
        DO_HOOKS=$(printf "%s ; do_hook %s" "$DO_HOOKS" "$add_do_hook_ESCAPED")
    fi
}

BUILDTYPE=
DKML_TOOLS_SWITCH=OFF
DKML_OPAM_ROOT=
STATEDIR=
YES=OFF
OCAMLVERSION_OR_HOME=${OCAML_DEFAULT_VERSION}
OPAMEXE_OR_HOME=
DKMLABI=
EXTRAPATH=
EXTRAREPOCMDS=
PREBUILDS=
POSTINSTALLS=
PREREMOVES=
EXTRAINVARIANTS=
TARGETLOCAL_OPAMSWITCH=
TARGETGLOBAL_OPAMSWITCH=
DISABLE_UPDATE=OFF
DISABLE_SWITCH_CREATE=OFF
DISABLE_DEFAULT_INVARIANTS=OFF
WRAP_COMMAND=
NO_WITHDKML=OFF
while getopts ":hb:p:sd:r:u:o:n:t:v:yc:R:e:f:i:j:k:l:m:wxz0:aF" opt; do
    case ${opt} in
        h )
            usage
            exit 0
        ;;
        p )
            DKMLABI=$OPTARG
            if [ "$DKMLABI" = dev ]; then
                usage
                exit 0
            fi
        ;;
        b )
            BUILDTYPE=$OPTARG
        ;;
        d ) STATEDIR=$OPTARG ;;
        r ) DKML_OPAM_ROOT=$OPTARG ;;
        s ) DKML_TOOLS_SWITCH=ON ;;
        n ) TARGETGLOBAL_OPAMSWITCH=$OPTARG ;;
        t ) TARGETLOCAL_OPAMSWITCH=$OPTARG ;;
        u ) true ;;
        y)
            YES=ON
        ;;
        v )
            if [ -n "$OPTARG" ]; then OCAMLVERSION_OR_HOME=$OPTARG; fi
        ;;
        o ) OPAMEXE_OR_HOME=$OPTARG ;;
        c ) EXTRAPATH=$OPTARG ;;
        e ) add_do_setenv_option "$OPTARG" ;;
        f ) add_do_var "$OPTARG" ;;
        R )
            if [ -n "$EXTRAREPOCMDS" ]; then
                EXTRAREPOCMDS="$EXTRAREPOCMDS; "
            fi
            EXTRAREPOCMDS="${EXTRAREPOCMDS}add_extra_repo '${OPTARG}'"
        ;;
        i ) add_do_hook "$OPTARG" ;;
        0 ) WRAP_COMMAND=$OPTARG ;;
        j ) PREBUILDS="${PREBUILDS} [$OPTARG]" ;;
        k ) POSTINSTALLS="${POSTINSTALLS} [$OPTARG]" ;;
        l ) PREREMOVES="${PREREMOVES} [$OPTARG]" ;;
        m ) EXTRAINVARIANTS="$EXTRAINVARIANTS,$OPTARG" ;;
        w ) DISABLE_UPDATE=ON ;;
        x ) DISABLE_SWITCH_CREATE=ON ;;
        z ) DISABLE_DEFAULT_INVARIANTS=ON ;;
        a ) NO_WITHDKML=ON ;;
        F ) ;;
        \? )
            printf "%s\n" "This is not an option: -$OPTARG" >&2
            usage
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [ -z "${DKMLABI:-}" ]; then
    echo "FATAL: Missing -p DKMLABI option" >&2
    usage
    exit 1
fi
if [ -n "$STATEDIR" ] && [ -n "$DKML_OPAM_ROOT" ]; then
    printf "%s\n" "Both -d and -r cannot be specified at the same time" >&2
    usage
    exit 1
fi

#   At most one of -t LOCALOPAMSWITCH, -s, -n GLOBALOPAMSWITCH
_switch_count=
if [ "$DKML_TOOLS_SWITCH" = ON ]; then _switch_count="x$_switch_count"; fi
if [ -n "$TARGETLOCAL_OPAMSWITCH" ]; then _switch_count="x$_switch_count"; fi
if [ -n "$TARGETGLOBAL_OPAMSWITCH" ]; then _switch_count="x$_switch_count"; fi
if [ -z "$_switch_count" ]; then
    echo "FATAL: One of -t LOCALOPAMSWITCH, -s, -n GLOBALOPAMSWITCH must be specified" >&2
    usage
    exit 1
elif [ ! "$_switch_count" = x ]; then
    echo "FATAL: At most one of -t LOCALOPAMSWITCH, -s, -n GLOBALOPAMSWITCH may be specified" >&2
    usage
    exit 1
fi

# END Command line processing
# ------------------

if [ -z "${DKMLDIR:-}" ]; then
    DKMLDIR=$(dirname "$0")
    DKMLDIR=$(cd "$DKMLDIR/../../../.." && pwd)
fi
if [ ! -e "$DKMLDIR/.dkmlroot" ]; then printf "%s\n" "FATAL: Not launched within a directory tree containing a .dkmlroot file" >&2 ; exit 1; fi

# shellcheck disable=SC1091
. "$DKMLDIR"/vendor/drc/unix/_common_tool.sh

# From here onwards everything should be run using RELATIVE PATHS ...
# >>>>>>>>>

# Set OPAMEXE from OPAMEXE_OR_HOME
set_opamexe

# Set DKML_POSIX_SHELL
autodetect_posix_shell

# Set NUMCPUS if unset from autodetection of CPUs
autodetect_cpus

# Set DKMLPARENTHOME_BUILDHOST
set_dkmlparenthomedir

# Set DKMLSYS_*
autodetect_system_binaries

# The `dkml` switch will have the with-dkml.exe binary which is used by non-`dkml`
# switches. Whether the `dkml` switch is being created or being used, we need
# to know where it is.
#
# Set OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_EXPAND of `dkml` switch
# and set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND
set_opamswitchdir_of_system "$DKMLABI"
TOOLS_OPAMROOTDIR_BUILDHOST="$OPAMROOTDIR_BUILDHOST"
TOOLS_OPAMSWITCHFINALDIR_BUILDHOST="$OPAMSWITCHFINALDIR_BUILDHOST"
TOOLS_OPAMSWITCHNAME_EXPAND="$OPAMSWITCHNAME_EXPAND"
#   Since these 'tools' variables may not correspond to the user's selected
#   switch, we avoid bugs by clearing the variables from the environment.
unset OPAMSWITCHFINALDIR_BUILDHOST OPAMSWITCHNAME_EXPAND
unset OPAMROOTDIR_BUILDHOST OPAMROOTDIR_EXPAND

# --------------------------------
# BEGIN Opam troubleshooting script

cat > "$WORK"/troubleshoot-opam.sh <<EOF
#!/bin/sh
set -euf
OPAMROOT='$TOOLS_OPAMROOTDIR_BUILDHOST'
printf "\n\n========= [START OF TROUBLESHOOTING] ===========\n\n" >&2
if find . -maxdepth 0 -mmin -240 2>/dev/null >/dev/null; then
    FINDARGS="-mmin -240" # is -mmin supported? BSD (incl. macOS), MSYS2, GNU
else
    FINDARGS="-mtime -1" # use 1 day instead. Solaris
fi
find "\$OPAMROOT"/log -mindepth 1 -maxdepth 1 \$FINDARGS -name "*.out" ! -name "log-*.out" ! -name "dkml-base-compiler-*.out" | while read -r dump_on_error_LOG; do
    dump_on_error_BLOG=\$(basename "\$dump_on_error_LOG")
    printf "\n\n========= [TROUBLESHOOTING] %s ===========\n\n" "\$dump_on_error_BLOG" >&2
    awk -v BLOG="\$dump_on_error_BLOG" '{print "[" BLOG "]", \$0}' "\$dump_on_error_LOG" >&2
done
printf "\nScroll up to see the [TROUBLESHOOTING] logs that begin at the [START OF TROUBLESHOOTING] line\n" >&2
EOF
chmod +x "$WORK"/troubleshoot-opam.sh

# END Opam troubleshooting script
# --------------------------------

# --------------------------------
# BEGIN opam switch create

# Get the OCaml version and check whether to build an OCaml base (ocamlc compiler, etc.)
if [ -x /usr/bin/cygpath ]; then
    # If OCAMLVERSION_OR_HOME=C:/x/y/z then match against /c/x/y/z
    OCAMLVERSION_OR_HOME_UNIX=$(/usr/bin/cygpath -u "$OCAMLVERSION_OR_HOME")
else
    OCAMLVERSION_OR_HOME_UNIX="$OCAMLVERSION_OR_HOME"
fi
case "$OCAMLVERSION_OR_HOME_UNIX" in
    /* | ?:*) # /a/b/c or C:\Windows
        validate_and_explore_ocamlhome "$OCAMLVERSION_OR_HOME"
        # the `awk ...` is dos2unix equivalent
        "$DKML_OCAMLHOME_ABSBINDIR_UNIX/ocamlc" -version > "$WORK/ocamlc.version"
        OCAMLVERSION=$(awk '{ sub(/\r$/,""); print }' "$WORK/ocamlc.version")
        BUILD_OCAML_BASE=OFF
        ;;
    *)
        OCAMLVERSION="$OCAMLVERSION_OR_HOME"
        BUILD_OCAML_BASE=ON
        if [ -z "$BUILDTYPE" ]; then
            usage
            printf "FATAL: Missing -b BUILDTYPE. Required except when -v OCAMLHOME is specified and contains bin/ocaml or usr/bin/ocaml\n" >&2
            exit 1
        fi
        ;;
esac

# Set OCAML_OPTIONS if we are building the OCaml base. And if so, set
# TARGET_ variables that can be used to pick the DKMLBASECOMPILERVERSION later.
#
# Also any "EXTRA" compiler flags. Use standard ./configure compiler flags
# (AS/ASFLAGS/CC/etc.) not OCaml ./configure compiler flags (AS/ASPP/etc.)
# any autodetect_compiler() flags will be standard ./configure flags ... and
# in a hook we'll convert them all to OCaml ./configure flags.
#
true > "$WORK"/invariant.formula.txt
if [ "$BUILD_OCAML_BASE" = ON ]; then
    # Frame pointers enabled
    # ----------------------
    # option-fp
    # * OCaml only supports 64-bit Linux thing with either the GCC or the clang compiler.
    # * In particular the Musl GCC compiler is not supported.
    # * On Linux we need it for `perf`.
    # Confer:
    #  https://github.com/ocaml/ocaml/blob/e93f6f8e5f5a98e7dced57a0c81535481297c413/configure#L17455-L17472
    #  https://github.com/ocaml/opam-repository/blob/ed5ed7529d1d3672ed4c0d2b09611a98ec87d690/packages/ocaml-option-fp/ocaml-option-fp.1/opam#L6
    OCAML_OPTIONS=
    case "$BUILDTYPE" in
        Debug*) BUILD_DEBUG=ON; BUILD_RELEASE=OFF ;;
        Release*) BUILD_DEBUG=OFF; BUILD_RELEASE=ON ;;
        *) BUILD_DEBUG=OFF; BUILD_RELEASE=OFF
    esac
    # We'll set compiler options to:
    # * use static builds for Linux platforms running in a (musl-based Alpine) container
    # * use flambda optimization if a `Release*` build type
    #
    # Setting compiler options via environment variables (like CC and LIBS) has been available since 4.8.0 (https://github.com/ocaml/ocaml/pull/1840)
    # but still has problems even as of 4.10.0 (https://github.com/ocaml/ocaml/issues/8648).
    #
    # The following has some of the compiler options we might use for `macos`, `linux` and `windows`:
    #   https://github.com/ocaml/opam-repository/blob/bfc07c20d6846fffa49c3c44735905af18969775/packages/ocaml-variants/ocaml-variants.4.12.0%2Boptions/opam#L17-L47
    #
    # The following is for `macos`, `android` and `ios`:
    #   https://github.com/EduardoRFS/reason-mobile/tree/master/sysroot
    #
    # Notes:
    # * `ocaml-option-musl` has a good defaults for embedded systems. But we don't want to optimize for size on a non-embedded system.
    #   Since we have fine grained information about whether we are on a tiny system (ie. ARM 32-bit) we set the CFLAGS ourselves.
    # * Advanced: You can use OCAMLPARAM through `opam config set ocamlparam` (https://github.com/ocaml/opam-repository/pull/16619) or
    #   just set it in `within-dev.sh`.
    # `is_reproducible_platform && case "$PLATFORM" in linux*) ... ;;` then
    #     # NOTE 2021/08/04: When this block is enabled we get the following error, which means the config is doing something that we don't know how to inspect ...
    #
    #     # === ERROR while compiling capnp.3.4.0 ========================================#
    #     # context     2.0.8 | linux/x86_64 | ocaml-option-static.1 ocaml-variants.4.12.0+options | https://opam.ocaml.org#8b7c0fed
    #     # path        /work/build/linux_x86_64/Debug/_opam/.opam-switch/build/capnp.3.4.0
    #     # command     /work/build/linux_x86_64/Debug/_opam/bin/dune build -p capnp -j 5
    #     # exit-code   1
    #     # env-file    /work/build/_tools/linux_x86_64/opam-root/log/capnp-1-ebe0e0.env
    #     # output-file /work/build/_tools/linux_x86_64/opam-root/log/capnp-1-ebe0e0.out
    #     # ## output ###
    #     # [...]
    #     # /work/build/linux_x86_64/Debug/_opam/.opam-switch/build/stdint.0.7.0/_build/default/lib/uint56_conv.c:172: undefined reference to `get_uint128'
    #     # /usr/lib/gcc/x86_64-alpine-linux-musl/10.3.1/../../../../x86_64-alpine-linux-musl/bin/ld: /work/build/linux_x86_64/Debug/_opam/lib/stdint/libstdint_stubs.a(uint64_conv.o): in function `uint64_of_int128':
    #     # /work/build/linux_x86_64/Debug/_opam/.opam-switch/build/stdint.0.7.0/_build/default/lib/uint64_conv.c:111: undefined reference to `get_int128'
    #
    #     # NOTE 2021/08/03: `ocaml-option-static` seems to do nothing. No difference when running `dune printenv --verbose`
    #     OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-static
    # fi
    case "$DKMLABI" in
        windows_*)    TARGET_LINUXARM32=OFF ;;
        linux_arm32*) TARGET_LINUXARM32=ON ;;
        *)            TARGET_LINUXARM32=OFF
    esac
    case "$DKMLABI" in
        *_x86 | linux_arm32*) TARGET_32BIT=ON ;;
        *) TARGET_32BIT=OFF
    esac
    case "$DKMLABI" in
        linux_x86_64) TARGET_CANENABLEFRAMEPOINTER=ON ;;
        *) TARGET_CANENABLEFRAMEPOINTER=OFF
    esac

    if [ $TARGET_LINUXARM32 = ON ]; then
        # Optimize for size. Useful for CPUs with small cache sizes. Confer https://wiki.gentoo.org/wiki/GCC_optimization
        OCAML_OPTIONS="$OCAML_OPTIONS",dkml-option-minsize
    fi
    if [ $BUILD_DEBUG = ON ]; then
        OCAML_OPTIONS="$OCAML_OPTIONS",dkml-option-debuginfo
    fi
    if [ $BUILD_DEBUG = ON ] && [ $TARGET_CANENABLEFRAMEPOINTER = ON ]; then
        # Frame pointer should be on in Debug mode.
        OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-fp
    fi
    if [ "$BUILDTYPE" = ReleaseCompatPerf ] && [ $TARGET_CANENABLEFRAMEPOINTER = ON ]; then
        # If we need Linux `perf` we need frame pointers enabled
        OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-fp
    fi
    if [ $BUILD_RELEASE = ON ]; then
        # All release builds should get flambda optimization
        OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-flambda
    fi
    if cmake_flag_on "${DKML_COMPILE_CM_HAVE_AFL:-OFF}" || [ "$BUILDTYPE" = ReleaseCompatFuzz ]; then
        # If we need fuzzing we must add AFL. If we have a fuzzing compiler, use AFL in OCaml.
        OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-afl
    fi
fi

# Set DKMLBASECOMPILERVERSION. Ex: 4.12.1~v1.0.2~prerel27
if [ "$BUILD_OCAML_BASE" = ON ]; then
    # Use DKML base compiler, which compiles ocaml from scratch
    if [ "$TARGET_32BIT" = ON ]; then
        OCAML_OPTIONS="$OCAML_OPTIONS",ocaml-option-32bit
    fi
    # shellcheck disable=SC2154
    dkml_opam_version=$(printf "%s" "$dkml_root_version" | $DKMLSYS_SED 's/-/~/g')
    DKMLBASECOMPILERVERSION="$OCAMLVERSION~v$dkml_opam_version"
fi

# Make launchers for opam switch create <...> and for opam <...>
if [ "$DKML_TOOLS_SWITCH" = ON ]; then
    OPAM_EXEC_OPTS="-s -r '$DKML_OPAM_ROOT' -d '$STATEDIR' -p '$DKMLABI' -o '$OPAMEXE_OR_HOME' -v '$OCAMLVERSION_OR_HOME'"

    # Set OPAMROOTDIR_BUILDHOST and OPAMSWITCHFINALDIR_BUILDHOST
    OPAMROOTDIR_BUILDHOST="$TOOLS_OPAMROOTDIR_BUILDHOST"
    OPAMSWITCHFINALDIR_BUILDHOST="$TOOLS_OPAMSWITCHFINALDIR_BUILDHOST"
    OPAMSWITCHNAME_EXPAND="$TOOLS_OPAMSWITCHNAME_EXPAND"
else
    # Set OPAMSWITCHFINALDIR_BUILDHOST, OPAMSWITCHNAME_BUILDHOST, OPAMSWITCHNAME_EXPAND, OPAMSWITCHISGLOBAL
    # and set OPAMROOTDIR_BUILDHOST, OPAMROOTDIR_EXPAND
    set_opamrootandswitchdir "$TARGETLOCAL_OPAMSWITCH" "$TARGETGLOBAL_OPAMSWITCH"

    OPAM_EXEC_OPTS=" -p '$DKMLABI' -r '$DKML_OPAM_ROOT' -d '$STATEDIR' -t '$TARGETLOCAL_OPAMSWITCH' -n '$TARGETGLOBAL_OPAMSWITCH' -o '$OPAMEXE_OR_HOME' -v '$OCAMLVERSION_OR_HOME'"
fi
if [ "$NO_WITHDKML" = ON ]; then
    OPAM_EXEC_OPTS="$OPAM_EXEC_OPTS -a"
fi
printf "%s\n" "exec '$DKMLDIR'/vendor/drd/src/unix/private/platform-opam-exec.sh \\" > "$WORK"/nonswitchexec.sh
printf "%s\n" "  $OPAM_EXEC_OPTS \\" >> "$WORK"/nonswitchexec.sh
printf "%s\n" "'$DKMLDIR/vendor/drd/src/unix/private/platform-opam-exec.sh' \\" > "$WORK"/nonswitchcall.sh
printf "%s\n" "  $OPAM_EXEC_OPTS \\" >> "$WORK"/nonswitchcall.sh

printf "%s\n" "switch create \\" > "$WORK"/switchcreateargs.sh
if [ "$YES" = ON ] && [ "${DKML_OPAM_FORCE_INTERACTIVE:-OFF}" = OFF ]; then printf "%s\n" "  --yes \\" >> "$WORK"/switchcreateargs.sh; fi
printf "%s\n" "  --jobs=$NUMCPUS \\" >> "$WORK"/switchcreateargs.sh

# Only the compiler should be created; no local .opam files will be auto-installed so that
# the `opam option` done later in this script can be set.
printf "%s\n" "  --no-install \\" >> "$WORK"/switchcreateargs.sh

# Add the extra repository, if any
FIRST_REPOS=
EXTRAREPONAMES=
add_extra_repo() {
    add_extra_repo_ARG=$1
    shift
    add_extra_repo_NAME=$(printf "%s" "$add_extra_repo_ARG" | $DKMLSYS_SED 's@=.*@@')
    add_extra_repo_REPO=$(printf "%s" "$add_extra_repo_ARG" | $DKMLSYS_SED 's@^[^=]*=@@')
    EXTRAREPONAMES="$EXTRAREPONAMES $add_extra_repo_NAME"
    FIRST_REPOS="${FIRST_REPOS}$add_extra_repo_NAME,"
    # Add it
    if [ ! -e "$OPAMROOTDIR_BUILDHOST/repo/$add_extra_repo_NAME" ] && [ ! -e "$OPAMROOTDIR_BUILDHOST/repo/$add_extra_repo_NAME.tar.gz" ]; then
        {
            cat "$WORK"/nonswitchexec.sh
            # `--kind local` is so we get file:/// rather than git+file:/// which would waste time with git
            case "$add_extra_repo_REPO" in
                /* | ?:* | file://) # /a/b/c or C:\Windows or file://
                    printf "  repository add %s '%s' --yes --dont-select --kind local" "$add_extra_repo_NAME" "$add_extra_repo_REPO"
                    ;;
                *)
                    printf "  repository add %s '%s' --yes --dont-select" "$add_extra_repo_NAME" "$add_extra_repo_REPO"
                    ;;
            esac
            if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
        } > "$WORK"/repoadd.sh
        log_shell "$WORK"/repoadd.sh
    fi
}
if [ -n "$EXTRAREPOCMDS" ]; then
    eval "$EXTRAREPOCMDS"
fi

do_switch_create() {
    printf "%s\n" "  $EXTRAREPONAMES diskuv-$dkml_root_version default \\" > "$WORK"/repos-choice.lst
    printf "  --repos='%s%s' %s\n" "$FIRST_REPOS" "diskuv-$dkml_root_version,default" "\\" >> "$WORK"/switchcreateargs.sh

    if [ "$DISABLE_DEFAULT_INVARIANTS" = OFF ]; then
        if [ "$BUILD_OCAML_BASE" = ON ]; then
            # ex. '"dkml-base-compiler" {= "4.12.1~v1.0.2~prerel27"}'
            invariants=$(printf "dkml-base-compiler.%s%s\n" \
                "$DKMLBASECOMPILERVERSION$OCAML_OPTIONS" \
                "$EXTRAINVARIANTS"
            )
        else
            # ex. '"ocaml-system" {= "4.12.1"}'
            invariants=$(printf "ocaml-system.%s%s\n" \
                "$OCAMLVERSION" \
                "$EXTRAINVARIANTS"
            )
        fi
        printf "  --packages='%s' %s\n" "$invariants" "\\" >> "$WORK"/switchcreateargs.sh
        printf "'%s'" "$invariants" >> "$WORK"/invariant.formula.txt
    elif [ -n "$EXTRAINVARIANTS" ]; then
        printf "  --packages='%s' %s\n" "$EXTRAINVARIANTS" "\\" >> "$WORK"/switchcreateargs.sh
        printf "'%s'" "$EXTRAINVARIANTS" >> "$WORK"/invariant.formula.txt
    else
        printf "  --empty %s\n" "\\" >> "$WORK"/switchcreateargs.sh
    fi

    if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s\n" "  --debug-level 2 \\" >> "$WORK"/switchcreateargs.sh; fi

    {
        printf "%s\n" "#!$DKML_POSIX_SHELL"
        # Ignore any switch the developer gave. We are creating our own.
        printf "%s\n" "export OPAMROOT="
        printf "%s\n" "export OPAMSWITCH="
        printf "%s\n" "export OPAM_SWITCH_PREFIX="
        printf "exec \"\$@\"\n"
    } > "$WORK"/switch-create-prehook.sh
    chmod +x "$WORK"/switch-create-prehook.sh
    if [ "${DKML_BUILD_TRACE:-OFF}" = ON ] && [ "${DKML_BUILD_TRACE_LEVEL:-0}" -ge 2 ]; then
        printf  "@+ switch-create-prehook.sh\n" >&2
        # print file with prefix ... @+| . Also make sure each line is newline terminated using awk.
        "$DKMLSYS_SED" 's/^/@+| /' "$WORK"/switch-create-prehook.sh | "$DKMLSYS_AWK" '{print}' >&2
    fi

    if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s\n" "+ ! is_minimal_opam_switch_present \"$OPAMSWITCHFINALDIR_BUILDHOST\"" >&2; fi
    if ! is_minimal_opam_switch_present "$OPAMSWITCHFINALDIR_BUILDHOST"; then
        # clean up any partial install
        printf "%s\n" "exec '$DKMLDIR'/vendor/drd/src/unix/private/platform-opam-exec.sh $OPAM_EXEC_OPTS switch remove \\" > "$WORK"/switchremoveargs.sh
        if [ "$YES" = ON ]; then printf "%s\n" "  --yes \\" >> "$WORK"/switchremoveargs.sh; fi
        printf "  '%s'\n" "$OPAMSWITCHNAME_EXPAND" >> "$WORK"/switchremoveargs.sh
        log_shell "$WORK"/switchremoveargs.sh || rm -rf "$OPAMSWITCHFINALDIR_BUILDHOST"

        # do real install
        printf "%s\n" "exec '$DKMLDIR'/vendor/drd/src/unix/private/platform-opam-exec.sh $OPAM_EXEC_OPTS -0 '$WORK/switch-create-prehook.sh' \\" > "$WORK"/switchcreateexec.sh
        cat "$WORK"/switchcreateargs.sh >> "$WORK"/switchcreateexec.sh
        printf "  '%s'\n" "$OPAMSWITCHNAME_EXPAND" >> "$WORK"/switchcreateexec.sh
        #   Do troubleshooting if the initial switch creation fails (it shouldn't fail!)
        if ! log_shell "$WORK"/switchcreateexec.sh; then
            "$WORK"/troubleshoot-opam.sh
            exit 107
        fi

        # the switch create already set the invariant
        NEEDS_INVARIANT=OFF
    else
        # We need to upgrade each Opam switch's selected/ranked Opam repository choices whenever Diskuv OCaml
        # has an upgrade. If we don't the PINNED_PACKAGES_* may fail.
        # We know from `diskuv-$dkml_root_version` what Diskuv OCaml version the Opam switch is using, so
        # we have the logic to detect here when it is time to upgrade!
        {
            cat "$WORK"/nonswitchexec.sh
            printf "%s\n" "  repository list --short"
        } > "$WORK"/list.sh
        log_shell "$WORK"/list.sh > "$WORK"/list
        UPGRADE_REPO=OFF
        if awk -v N="diskuv-$dkml_root_version" '$1==N {exit 1}' "$WORK"/list; then
            UPGRADE_REPO=ON
        elif is_unixy_windows_build_machine && awk -v N="fdopen-mingw-$dkml_root_version-$OCAMLVERSION" '$1==N {exit 1}' "$WORK"/list; then
            UPGRADE_REPO=ON
        elif [ -n "$EXTRAREPONAMES" ]; then
            printf "%s" "$EXTRAREPONAMES" | $DKMLSYS_TR ' ' '\n' > "$WORK"/extrarepos
            while IFS= read -r _reponame; do
                if awk -v N="$_reponame" '$1==N {exit 1}' "$WORK"/list; then
                    UPGRADE_REPO=ON
                fi
            done < "$WORK"/extrarepos
        fi
        if [ "$UPGRADE_REPO" = ON ]; then
            # Time to upgrade. We need to set the repository (almost instantaneous) and then
            # do a `opam update` so the switch has the latest repository definitions.
            {
                cat "$WORK"/nonswitchexec.sh
                printf "%s" "  repository set-repos"
                if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
                cat "$WORK"/repos-choice.lst
            } > "$WORK"/setrepos.sh
            log_shell "$WORK"/setrepos.sh

            #   This part can be time-consuming
            if [ "$DISABLE_UPDATE" = OFF ]; then
                {
                    printf "ec=0\n"
                    cat "$WORK"/nonswitchcall.sh
                    printf "%s" "  update"
                    if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
                    # Bizarrely opam 2.1.0 on macOS can return exit code 40 (Sync error) when there
                    # are no sync changes. So both 0 and 40 are successes.
                    printf " || ec=\$?\n"
                    printf "%s\n" "if [ \$ec -eq 40 ] || [ \$ec -eq 0 ]; then exit 0; fi; exit \$ec"
                } > "$WORK"/update.sh
                log_shell "$WORK"/update.sh
            fi
        fi

        # A DKML upgrade could have changed the invariant; we do not change it here; instead we wait until after
        # the pins and options (especially the wrappers) have changed because changing the invariant can recompile
        # _all_ packages (many of them need wrappers, and many of them need a pin upgrade to support a new OCaml version)
        NEEDS_INVARIANT=ON
    fi
}
if [ "$DISABLE_SWITCH_CREATE" = OFF ]; then
    do_switch_create
else
    # No DKML upgrade happened
    NEEDS_INVARIANT=OFF
fi

# END opam switch create
# --------------------------------

install -d "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR"

# --------------------------------
# BEGIN opam option
#
# Most of these options are tied to the $dkml_root_version, so we use $dkml_root_version
# as a cache key. If an option does not depend on the version we use ".once" as the cache
# key.

SETPATH=

# Add FLEXLINKFLAGS
case "$BUILDTYPE,$DKMLABI" in
    Debug*,windows_*)
        # MSVC needs the linker to create a PDB file.
        # See https://learn.microsoft.com/en-us/cpp/build/reference/debug-generate-debug-info?view=msvc-170
        add_do_setenv_option "FLEXLINKFLAGS+= -link /DEBUG:FULL"
        ;;
    *)
        add_remove_setenv FLEXLINKFLAGS "+="
esac

# Add PATH=<system ocaml>:$EXTRAPATH:$PATH
#   Add PATH=<system ocaml> if system ocaml. (Especially on Windows and for DKSDK, the system ocaml may not necessarily be on the system PATH)
if [ "$BUILD_OCAML_BASE" = OFF ]; then
    SETPATH="$DKML_OCAMLHOME_ABSBINDIR_BUILDHOST;$SETPATH"
fi
#   Add PATH=$EXTRAPATH
if [ -n "$EXTRAPATH" ]; then
    SETPATH="$EXTRAPATH;$SETPATH"
fi
#   Remove leading and trailing and duplicated separators
SETPATH=$(printf "%s" "$SETPATH" | $DKMLSYS_SED 's/^;*//; s/;*$//; s/;;*/;/g')
#   Add the setenv command
if [ -n "$SETPATH" ]; then
    # Use Win32 (;) or Unix (:) path separators
    if is_unixy_windows_build_machine; then
        SETPATH_WU=$SETPATH # already has semicolons
    else
        SETPATH_WU=$(printf "%s" "$SETPATH" | $DKMLSYS_TR ';' ':')
    fi
    add_do_setenv_option "PATH+=$SETPATH_WU"
fi

# Run the `var` commands
if [ -n "$DO_VARS" ]; then
    {
        printf "#!%s\n" "$DKML_POSIX_SHELL"
        printf "#   shellcheck disable=SC1091\n"
        printf ". '%s'\n" "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

        printf "do_var() {\n"
        printf "  do_var_ARG=\$1\n"
        printf "  shift\n"
        # shellcheck disable=SC2016
        printf "  do_var_NAME=\$(%s)\n" \
            'printf "%s" "$do_var_ARG" | PATH=/usr/bin:/bin sed "s/=.*//"'
        # shellcheck disable=SC2016
        printf "  %s > '%s'/do_var_value.%s.txt\n" \
            'printf "%s" "$do_var_ARG"' \
            "$WORK" \
            '$$'
        printf "  do_var_ARG_CHKSUM=\$(cachekey_for_filename '%s'/do_var_value.%s.txt)\n" \
            "$WORK" \
            '$$'
        printf "  if [ -e '%s'/\"do_var-\${do_var_NAME}-%s.\${do_var_ARG_CHKSUM}.once\" ]; then return 0; fi\n" \
            "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR" "$dkml_root_version"
        # shellcheck disable=SC2016
        printf "  do_var_VALUE=\$(%s)\n" \
            'printf "%s" "$do_var_ARG" | PATH=/usr/bin:/bin sed "s/^[^=]*=//"'
        # VALUE, since it is an OCaml value, will have escaped backslashes and quotes
        printf "  do_var_VALUE=\$(escape_arg_as_ocaml_string \"\$do_var_VALUE\")\n"

        #   Example: var "${do_var_NAME}=${do_var_VALUE}"
        printf "  ";  cat "$WORK"/nonswitchcall.sh
        printf "    var \"\${do_var_NAME}=\${do_var_VALUE}\" "
        if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi; printf "\n"

        #       Done. Don't repeat anymore
        printf "  touch '%s'/\"do_var-\${do_var_NAME}-%s.\${do_var_ARG_CHKSUM}.once\"\n" \
            "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR" "$dkml_root_version"

        printf "}\n"

        printf "%s" "$DO_VARS" ; printf "\n"
        # debugging: printf "do_var 'dkml-test=C:%sUsers%sJoe Smith%sWith%sQuotes'\n" '\' '\' '\' '"'
    } > "$WORK"/setvars.sh
    log_shell "$WORK"/setvars.sh
fi

# Run the `option setenv` commands
if [ -n "$DO_SETENV_OPTIONS" ]; then
    {
        printf "#!%s\n" "$DKML_POSIX_SHELL"
        printf "#   shellcheck disable=SC1091\n"
        printf ". '%s'\n" "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

        #   Example: opam option setenv | sed "s/]/\n/g; s/\[/\n/g" > commands_env.txt; do
        printf "rm -f '%s'/commands_env.txt\n" \
            "$WORK"
        printf "make_commands_env() {\n"
        printf "  if [ -e '%s'/commands_env.txt ]; then return 0; fi\n" \
            "$WORK"
        cat "$WORK"/nonswitchcall.sh
        printf "    option setenv | %s > '%s'/commands_env.txt\n" \
            'sed "s/]/\n/g; s/\[/\n/g"' \
            "$WORK"
        printf "}\n"

        # No clean way to remove a setenv entry. We print any existing entries
        # and then remove each separately.
        printf "remove_setenv() {\n"
        printf "  remove_setenv_NAME=\$1\n"
        printf "  shift\n"
        printf "  remove_setenv_OP=\$1\n"
        printf "  shift\n"

        #   Example: awk '$1=="DKML_3P_PREFIX_PATH"{print}' commands_env.txt | while read remove_setenv_VALUE; do
        printf "  make_commands_env\n"
        printf "  awk -v \"NAME=\$remove_setenv_NAME\" -v \"OP=\$remove_setenv_OP\" '\$1==NAME && \$2==OP {print}' '%s/commands_env.txt' > '%s'/do_setenv_option_vars.%s.txt\n" \
            "$WORK" \
            "$WORK" \
            '$$'
        printf "  cat '%s'/do_setenv_option_vars.%s.txt | while IFS="" read -r remove_setenv_VALUE; do\n" \
            "$WORK" \
            '$$'
        #       Example: option "setenv-=${remove_setenv_VALUE}"
        printf "    ";  cat "$WORK"/nonswitchcall.sh
        printf "      option \"setenv-=\${remove_setenv_VALUE}\"\n"
        #   Example: done
        printf "  done\n"

        printf "}\n"

        # [do_setenv_option 'NAME=VALUE'] and [do_setenv_option 'NAME+=VALUE'] remove all
        # matching entries from the Opam setenv options, and then add it to the
        # Opam setenv options.
        printf "do_setenv_option() {\n"
        printf "  do_setenv_option_ARG=\$1\n"
        printf "  shift\n"
        # shellcheck disable=SC2016
        printf "  do_setenv_option_NAME=\$(%s)\n" \
            'printf "%s" "$do_setenv_option_ARG" | PATH=/usr/bin:/bin sed "s/+*=.*//"'
        # shellcheck disable=SC2016
        printf "  do_setenv_option_OP=\$(%s)\n" \
            'printf "%s" "$do_setenv_option_ARG" | PATH=/usr/bin:/bin sed "s/^[^+=]*//; s/=.*/=/"'
        # shellcheck disable=SC2016
        printf "  %s > '%s'/do_setenv_option_value.%s.txt\n" \
            'printf "%s" "$do_setenv_option_ARG"' \
            "$WORK" \
            '$$'
        printf "  do_setenv_option_ARG_CHKSUM=\$(cachekey_for_filename '%s'/do_setenv_option_value.%s.txt)\n" \
            "$WORK" \
            '$$'
        printf "  if [ -e '%s'/\"do_setenv_option-\${do_setenv_option_NAME}-%s.\${do_setenv_option_ARG_CHKSUM}.once\" ]; then return 0; fi\n" \
            "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR" "$dkml_root_version"
        # shellcheck disable=SC2016
        printf "  do_setenv_option_VALUE=\$(%s)\n" \
            'printf "%s" "$do_setenv_option_ARG" | PATH=/usr/bin:/bin sed "s/^[^=]*=//"'
        # VALUE, since it is an OCaml value, will have escaped backslashes and quotes
        printf "  do_setenv_option_VALUE=\$(escape_arg_as_ocaml_string \"\$do_setenv_option_VALUE\")\n"

        # Remove setenv entry
        printf "  remove_setenv \"\$do_setenv_option_NAME\" \"\$do_setenv_option_OP\"\n"

        #   Example: option setenv+="${do_setenv_option_NAME} = \"${do_setenv_option_VALUE}\""
        printf "  ";  cat "$WORK"/nonswitchcall.sh
        printf "    option setenv+=\"\${do_setenv_option_NAME} \$do_setenv_option_OP \\\\\"\${do_setenv_option_VALUE}\\\\\"\" "
        if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi; printf "\n"

        #       Done. Don't repeat anymore
        printf "  touch '%s'/\"do_setenv_option-\${do_setenv_option_NAME}-%s.\${do_setenv_option_ARG_CHKSUM}.once\"\n" \
            "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR" "$dkml_root_version"

        printf "}\n"

        printf "%s" "$DO_SETENV_OPTIONS" ; printf "\n"
    } > "$WORK"/setenv.sh
    # debugging:
    if [ -e /home/jonahbeckford/source/dkml/setvars.sh ]; then install "$WORK/setenv.sh" /home/jonahbeckford/source/dkml/setvars.sh; fi
    log_shell "$WORK"/setenv.sh
fi

# We don't put with-dkml.exe into the `dkml` tools switch because with-dkml.exe (currently) needs a tools switch to compile itself.
do_set_wrap_commands() {
    do_set_wrap_commands_TOMBSTONE_KEY=tombstone
    if [ -z "$WRAP_COMMAND" ]; then
        # Set WITHDKMLEXE_DOS83_OR_BUILDHOST
        if [ "$NO_WITHDKML" = OFF ]; then
            autodetect_withdkmlexe
            do_set_wrap_commands_WRAP="$WITHDKMLEXE_DOS83_OR_BUILDHOST"
            do_set_wrap_commands_KEY=${WRAP_COMMANDS_CACHE_KEY}
        else
            # No wrapping supplied so not wrapping should be done.
            # But we are idempotent so we have to remove any old
            # wrapping commands.
            do_set_wrap_commands_WRAP=
            do_set_wrap_commands_KEY=${do_set_wrap_commands_TOMBSTONE_KEY}
        fi
    else
        do_set_wrap_commands_WRAP="$WRAP_COMMAND"
        do_set_wrap_commands_KEY=${WRAP_COMMANDS_CACHE_KEY}_$(sha256compute "$WRAP_COMMAND")
    fi
    if [ ! -e "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/$do_set_wrap_commands_KEY" ]; then
        # Ensure partial failures, or switching between tombstone deletions and real values, works
        rm -f "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/$do_set_wrap_commands_TOMBSTONE_KEY"
        rm -f "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/$do_set_wrap_commands_KEY"

        if [ -z "$do_set_wrap_commands_WRAP" ]; then
            # Deletions (tombstone values) are an empty array
            DOW_PATH='[]'
        else
            # Real wrapping commands are a single-element array with a quoted item
            printf '["%s"]' "$do_set_wrap_commands_WRAP" | sed 's/\\/\\\\/g' > "$WORK"/dow.path
            DOW_PATH=$(cat "$WORK"/dow.path)
        fi
        {
            cat "$WORK"/nonswitchexec.sh
            printf "  option wrap-build-commands='%s' " "$DOW_PATH"
            if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
        } > "$WORK"/wbc.sh
        log_shell "$WORK"/wbc.sh
        {
            cat "$WORK"/nonswitchexec.sh
            printf "  option wrap-install-commands='%s' " "$DOW_PATH"
            if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
        } > "$WORK"/wbc.sh
        log_shell "$WORK"/wbc.sh
        {
            cat "$WORK"/nonswitchexec.sh
            printf "  option wrap-remove-commands='%s' " "$DOW_PATH"
            if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
        } > "$WORK"/wbc.sh
        log_shell "$WORK"/wbc.sh

        # Done. Don't repeat anymore
        touch "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/$do_set_wrap_commands_KEY"
    fi
}
if [ "$DKML_TOOLS_SWITCH" = OFF ]; then
    do_set_wrap_commands
fi

option_command() {
    option_command_OPTION=$1
    shift
    option_command_VALUE=$1
    shift
    printf "%s|%s" "$dkml_root_version" "$option_command_VALUE" > "$WORK"/"$option_command_OPTION".key
    option_command_CACHE_KEY="$option_command_OPTION"."$dkml_root_version".$(cachekey_for_filename "$WORK"/"$option_command_OPTION".key)
    if [ ! -e "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/$option_command_CACHE_KEY" ]; then
        option_command_ESCAPED=$(escape_args_for_shell "$option_command_VALUE")
        {
            cat "$WORK"/nonswitchexec.sh
            printf "  option %s=[%s] " "$option_command_OPTION" "$option_command_ESCAPED"
            if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
        } > "$WORK"/option-"$option_command_OPTION".sh
        log_shell "$WORK"/option-"$option_command_OPTION".sh

        # Done. Don't repeat anymore
        touch "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/$option_command_CACHE_KEY"
    fi
}
option_command pre-build-commands "$PREBUILDS"
option_command post-install-commands "$POSTINSTALLS"
option_command pre-remove-commands "$PREREMOVES"

# END opam option
# --------------------------------

# --------------------------------
# BEGIN opam pin add
#
# Since opam pin add is way too slow for hundreds of pins, we directly add the pins to the
# switch-state file. And since as an escape hatch we want developer to be able to override
# the pins, we only insert the pins if there are no other pins.
# The only thing we force pin is ocaml-variants if we are on Windows.
#
# Also, the pins are tied to the $dkml_root_version, so we use $dkml_root_version
# as a cache key. When the cache key changes (aka an upgrade) the pins are reset.

# Set DKML_POSIX_SHELL
autodetect_posix_shell

# Set DKMLPARENTHOME_BUILDHOST
set_dkmlparenthomedir

do_pin_adds() {
    # We insert our pins if no pinned: [ ] section
    # OR it is empty like:
    #   pinned: [
    #   ]
    # OR the dkml_root_version changed
    get_opam_switch_state_toplevelsection "$OPAMSWITCHFINALDIR_BUILDHOST" pinned > "$WORK"/pinned
    PINNED_NUMLINES=$(awk 'END{print NR}' "$WORK"/pinned)
    if [ "$PINNED_NUMLINES" -le 2 ] || ! [ -e "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/pins-set.$dkml_root_version" ]; then
        # Make the new switch state
        {
            # everything except any old pinned section
            delete_opam_switch_state_toplevelsection "$OPAMSWITCHFINALDIR_BUILDHOST" pinned

### BEGIN pinned-section. DO NOT EDIT THE LINES IN THIS SECTION
# Managed by bump-packages.cmake
echo 'pinned: [
  "angstrom.0.16.0"
  "astring.0.8.5"
  "base.v0.16.1"
  "bigarray-compat.1.1.0"
  "bigstringaf.0.10.0"
  "bos.0.2.1"
  "camlp-streams.5.0.1"
  "chrome-trace.3.15.0"
  "cmdliner.1.2.0"
  "conf-bash.1"
  "conf-dkml-sys-opam.1"
  "conf-pkg-config.3+cpkgs"
  "conf-sqlite3.3.1+cpkgs"
  "cppo.1.6.9"
  "crunch.3.3.1"
  "csexp.1.5.2"
  "cstruct.6.2.0"
  "ctypes-foreign.0.19.2-windowssupport-r8"
  "ctypes.0.19.2-windowssupport-r8"
  "cudf.0.10"
  "digestif.1.2.0"
  "diskuvbox.0.2.0"
  "dkml-apps.2.1.3"
  "dkml-base-compiler.4.14.2~v2.1.3"
  "dkml-build-desktop.2.1.3"
  "dkml-c-probe.3.0.0"
  "dkml-compiler-src.2.1.3"
  "dkml-component-xx-console.0.1.1"
  "dkml-exe-lib.2.1.3"
  "dkml-exe.2.1.3"
  "dkml-install-installer.0.5.2"
  "dkml-install-runner.0.5.2"
  "dkml-install.0.5.2"
  "dkml-installer-ocaml-common.2.1.3"
  "dkml-installer-ocaml-network.2.1.3"
  "dkml-installer-ocaml-offline.2.1.3"
  "dkml-package-console.0.5.2"
  "dkml-runtime-common-native.2.1.1"
  "dkml-runtime-common.2.1.3"
  "dkml-runtime-distribution.2.1.3"
  "dkml-runtimelib.2.1.3"
  "dkml-runtimescripts.2.1.3"
  "dkml-workflows.2.1.3"
  "dune-action-plugin.3.15.0"
  "dune-build-info.3.15.0"
  "dune-configurator.3.15.0"
  "dune-glob.3.15.0"
  "dune-private-libs.3.15.0"
  "dune-rpc-lwt.3.15.0"
  "dune-rpc.3.15.0"
  "dune-site.3.15.0"
  "dune.3.15.0"
  "dyn.3.15.0"
  "either.1.0.0"
  "eqaf.0.9"
  "extlib.1.7.9"
  "feather.0.3.0"
  "fiber.3.7.0"
  "fix.20230505"
  "fmt.0.9.0"
  "fpath.0.7.3"
  "graphics.5.1.2"
  "hmap.0.8.1"
  "host-arch-x86_64.1"
  "integers.0.7.0"
  "iostream.0.2.2"
  "jane-street-headers.v0.16.0"
  "jingoo.1.5.0"
  "jsonrpc.1.17.0"
  "jst-config.v0.16.0"
  "lambda-term.3.3.2"
  "logs.0.7.0"
  "lsp.1.17.0"
  "lwt.5.7.0"
  "lwt_react.1.2.0"
  "mccs.1.1+13"
  "mdx.2.4.1"
  "menhir.20231231"
  "menhirCST.20231231"
  "menhirLib.20231231"
  "menhirSdk.20231231"
  "merlin-lib.4.14-414"
  "metapp.0.4.4+win"
  "metaquot.0.5.2"
  "mew.0.1.0"
  "mew_vi.0.5.0"
  "msys2-clang64.1"
  "msys2.0.1.0+dkml"
  "num.1.5"
  "ocaml-compiler-libs.v0.12.4"
  "ocaml-lsp-server.1.17.0"
  "ocaml-syntax-shims.1.0.0"
  "ocaml-version.3.6.5"
  "ocaml.4.14.2"
  "ocamlbuild.0.14.2+win+unix"
  "ocamlc-loc.3.15.0"
  "ocamlfind.1.9.5"
  "ocamlformat-lib.0.26.1"
  "ocamlformat-rpc-lib.0.26.1"
  "ocamlformat.0.26.1"
  "ocp-indent.1.8.2-windowssupport"
  "ocplib-endian.1.2"
  "odoc-parser.2.4.1"
  "odoc.2.4.1"
  "ordering.3.15.0"
  "parsexp.v0.16.0"
  "posixat.v0.16.0"
  "pp.1.2.0"
  "ppx_assert.v0.16.0"
  "ppx_base.v0.16.0"
  "ppx_cold.v0.16.0"
  "ppx_compare.v0.16.0"
  "ppx_derivers.1.2.1"
  "ppx_deriving.5.2.1"
  "ppx_enumerate.v0.16.0"
  "ppx_expect.v0.16.0"
  "ppx_globalize.v0.16.0"
  "ppx_hash.v0.16.0"
  "ppx_here.v0.16.0"
  "ppx_ignore_instrumentation.v0.16.0"
  "ppx_inline_test.v0.16.1"
  "ppx_optcomp.v0.16.0"
  "ppx_pipebang.v0.16.0"
  "ppx_sexp_conv.v0.16.0"
  "ppx_yojson_conv_lib.v0.16.0"
  "ppxlib.0.30.0"
  "ptime.1.1.0"
  "qrc.0.1.1~dune"
  "re.1.11.0"
  "react.1.2.2"
  "refl.0.4.1"
  "result.1.5"
  "rresult.0.7.0"
  "seq.base"
  "sexplib.v0.16.0"
  "sexplib0.v0.16.0"
  "sha.1.15.4"
  "shexp.v0.16.0"
  "spawn.v0.15.1"
  "sqlite3.5.2.0"
  "stdcompat.19+optautoconf"
  "stdio.v0.16.0"
  "stdlib-shims.0.3.0"
  "stdune.3.15.0"
  "stringext.1.6.0"
  "time_now.v0.16.0"
  "tiny_httpd.0.16"
  "topkg.1.0.7"
  "traverse.0.3.0"
  "trie.1.0.0"
  "tsort.2.1.0"
  "tyxml.4.6.0"
  "uchar.0.0.2"
  "uri.4.4.0"
  "utop.2.13.1"
  "uucp.15.0.0"
  "uuidm.0.9.8"
  "uuseg.15.0.0"
  "uutf.1.0.3"
  "with-dkml.2.1.3"
  "xdg.3.15.0"
  "yojson.2.1.2"
  "zed.3.2.3"
]
'
### END pinned-section. DO NOT EDIT THE LINES ABOVE

        } > "$WORK"/new-switch-state

        # Reset the switch state
        mv "$WORK"/new-switch-state "$OPAMSWITCHFINALDIR_BUILDHOST"/.opam-switch/switch-state

        # Done for this DKML version
        touch "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR/pins-set.$dkml_root_version"
    fi
}
if [ "$DISABLE_SWITCH_CREATE" = OFF ]; then
    # When there are no invariants (ie. --empty), there can't be any pins since
    # `.opam-switch/switch-state` will not be present (at least in prereleases of opam 2.2).
    if [ "$DISABLE_DEFAULT_INVARIANTS" = OFF ] || [ -n "$EXTRAINVARIANTS" ]; then
        do_pin_adds
    fi
fi

# END opam pin add
# --------------------------------

# --------------------------------
# BEGIN opam post create hook

if [ -n "$DO_HOOKS" ]; then
    # If Windows, expect the commands to be executed in Windows/DOS context,
    # not a MSYS2 context. So use mixed and host paths rather than Unix paths.
    if [ -x /usr/bin/cygpath ]; then
        DKMLSYS_ENV_MIXED=$(/usr/bin/cygpath -am "$DKMLSYS_ENV")
    else
        DKMLSYS_ENV_MIXED=$DKMLSYS_ENV
    fi
    {
        printf "#!%s\n" "$DKML_POSIX_SHELL"
        printf ". '%s'\n" "$DKMLDIR"/vendor/drc/unix/crossplatform-functions.sh

        printf "do_hook() {\n"
        printf "  do_hook_FILE=\$1\n"
        printf "  shift\n"
        printf "  do_hook_FILE_CHKSUM=\$(cachekey_for_filename \"\$do_hook_FILE\")\n"
        printf "  if [ -e '%s'/do_hook-%s.\${do_hook_FILE_CHKSUM}.once ]; then return 0; fi\n" \
            "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR" "$dkml_root_version"

        printf "  ";  cat "$WORK"/nonswitchcall.sh
        printf "    exec -- '%s' 'OPAMEXE=%s' 'OPAMCONFIRMLEVEL=unsafe-yes' '__INTERNAL__DKMLDIR=%s' '%s' -euf \"\$do_hook_FILE\"" \
            "$DKMLSYS_ENV_MIXED" "$OPAMEXE" "$DKMLDIR" "$DKML_HOST_POSIX_SHELL"
        if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi; printf "\n"

        #       Done. Don't repeat anymore
        printf "  touch '%s'/do_hook-%s.\${do_hook_FILE_CHKSUM}.once\n" \
            "$OPAMSWITCHFINALDIR_BUILDHOST/$OPAM_CACHE_SUBDIR" "$dkml_root_version"

        printf "}\n"

        printf "%s" "$DO_HOOKS" ; printf "\n"
    } > "$WORK"/hooks.sh
    log_shell "$WORK"/hooks.sh
fi

# END opam post create hook
# --------------------------------

# --------------------------------
# BEGIN opam switch set-invariant

if [ "$NEEDS_INVARIANT" = ON ] && [ -s "$WORK"/invariant.formula.txt ]; then
    # We also should change the switch invariant if an upgrade occurred. The best way to detect
    # that we need to upgrade after the switch invariant change is to see if the switch-config changed
    OLD_HASH=$(cachekey_for_filename "$OPAMSWITCHFINALDIR_BUILDHOST/.opam-switch/switch-config")
    {
        cat "$WORK"/nonswitchexec.sh
        printf "  switch set-invariant --quiet --packages="
        cat "$WORK"/invariant.formula.txt
        if [ "$YES" = ON ]; then printf " --yes"; fi
    } > "$WORK"/set-invariant.sh
    log_shell "$WORK"/set-invariant.sh

    NEW_HASH=$(cachekey_for_filename "$OPAMSWITCHFINALDIR_BUILDHOST/.opam-switch/switch-config")
    if [ ! "$OLD_HASH" = "$NEW_HASH" ]; then
        {
            cat "$WORK"/nonswitchexec.sh
            printf "  upgrade --fixup"
            if [ "$YES" = ON ]; then printf " --yes"; fi
            if [ "${DKML_BUILD_TRACE:-OFF}" = ON ]; then printf "%s" " --debug-level 2"; fi
        } > "$WORK"/upgrade.sh
        #   Troubleshoot if the upgrade fails (it shouldn't!)
        if ! log_shell "$WORK"/upgrade.sh; then
            "$WORK"/troubleshoot-opam.sh
            exit 107
        fi
    fi
fi

# END opam switch set-invariant
# --------------------------------
