# dkml-runtime-distribution 2.1.1

Scripts used by the Diskuv OCaml distribution during the installation of:

* a local project (ie. a Opam switch created with `dkml init`)
* a user profile (ex. OCaml binaries installed within the user's home directory)
* a machine (ex. system or Administrator assembly/C compilers)

Typically this code is downloaded as a .tar.gz source release, git cloned
or vendored (git submodule).

## Metadata

| Name                         | Location                                               | What                                                          |
| ---------------------------- | ------------------------------------------------------ | ------------------------------------------------------------- |
| `$DV_WindowsMsvcDockerImage` | `src/windows/DeploymentVersion/DeploymentVersion.psm1` | ocurrent CI MSVC image which is source of most automatic pins |

## ContributingF

See [the Contributors section of dkml-install-api](https://github.com/diskuv/dkml-install-api/blob/main/contributors/README.md).

## Status

[![Syntax check](https://github.com/diskuv/dkml-runtime-distribution/actions/workflows/syntax.yml/badge.svg)](https://github.com/diskuv/dkml-runtime-distribution/actions/workflows/syntax.yml)
