# Distribution Packages

## Flavors

### Dune

Only Dune.

### CI

These are the packages required to build most OCaml packages on a CI system.
Interactive developer tools are almost never part of a CI system.

### Full

Should align very closely to the [OCaml Platform](https://ocaml.org/docs/platform)

## File Format

Lexical rules:

1. Leading and trailing whitespace are ignored in the semantic rules.

Semantic rules:

1. Any line that begins with a '#' and one or more SPACEs is a comment.
2. Any line that begins with a '##' and one or more SPACEs is a directive. See [Directives](#directives)
   for details.
3. Any other line must be blank, or a `Package.Ver` with the format
   `<opam package name>.<opam package version>`. Example: `dune.2.9.3`.
   Package.Ver

The goal of the above rules is to:

1. Have each `Package.Ver` pinned in end-user DKML switches during `dkml init`.
2. In addition, mark some `Package.Ver` for special treatment using directives.

### Directives

#### global-install

The Package.Ver that follows `global-install` will be made available
to the end-user in the global DKML system after installation. All `global-install`
package files are copied as-is into the global DKML system during end-user
installation.

Example:

```text
##      global-install
#       bin/dune
#       bin/dune-real
#       man/man1/dune-build.1
#       man/man1/...
#       man/man1/dune.1
#       man/man5/dune-config.5
dune.2.9.3
```

* Any `global-install` opam package will have its installed binaries (aka "public executables"
  for Dune) in the end-user PATH.
* Any runtime package dependencies of `global-install` opam packages should be marked as
  `global-install` as well.
* All `global-install` opam packages must be relocatable. That is, they should work
  even if they are compiled in one directory yet installed in a different directory.
  The relocation may be to a different machine, but the relocated machine's DKML ABI
  will always match the "target" DKML ABI at compile time. Confer with
  <https://github.com/diskuv/dkml-c-probe#readme> for DKML ABI details.

Other comments and directives **MAY** be between the `global-install` directive
and the opam packager version.

It is convention to use comments to show which binaries and other artifacts are important
to the end-user.

#### global-compile

The Package.Ver that follows `global-compile` will be made available
to the end-user in the global DKML system after installation. All `global-compile`
packages are compiled **during end-user installation** into the global DKML
system.

Example:

```text
##      global-compile
#       bin/ocamlfind
#       lib/findlib.conf
#       man/man1/ocamlfind.1
#       man/man5/META.5
#       man/man5/findlib.conf.5
#       man/man5/site-lib.5
ocamlfind.1.9.1
```

* In contrast to `global-install`, `global-compile` packages take longer to install
  on the end-user machine but they do _not_ need to be relocatable.
* Any `global-compile` opam package will have its installed binaries (aka "public executables"
  for Dune) in the end-user PATH.
* In contrast to `global-install`, runtime package dependencies of `global-compile` opam packages
  do _not_ need to be marked as `global-compile`. All runtime package dependencies of
  `global-compile` are automatically installed into the global DKML system.

## Future Direction

### Using constraints

Each one of the following sections has its own opam constraints ...

All DKML + DKSDK repo pkgs:

* At least one is selected as a cornerstone. Ex. `ocaml-variants.4.12.1+options+dkml+msvc64`
* All other packages must be constrained to versions that are present in UNION(DKML repo,DKSDK repo). Ex. `(mirage-crypto.0.10.3 | mirage-crypto.0.10.4)`

Foundation packages (either ci-packages -or- full-pkgs -or- some other flavor) {nit: rename flavor to foundation}

* All packages are presence constraints. Ex. `dune`

No-go packages (known not to compile on Win32 like Async, or known bad license)

* Some packages are no-presence constraints. Ex. `!async`
* Autoprobe packages are version constraints. Ex. `!async.v0.14.0`

`https://github.com/ocaml-opam/opam-0install-solver ==> solution ALPHA is a list of transitive_reach{cornerstore,foundation} (pkg,ver).`

Remainder of Opam packages are free-floating

* Package `a` picked at random. Test adding `a` to ALPHA; if build and test of `a` on Windows works, add it to "tested" package.
* All packages are presence constraints. Ex. `helloworld`

`https://github.com/ocaml-opam/opam-0install-solver ==> solution is a list of transitive_reach{cornerstore,foundation,tested} (pkg,ver).`

Then:

* Any (pkg,ver) present in both Opam and fdopen that are equivalent are removed from compact fdopen repository. (New rule)
* Any pkg with (pkg,ver) not present in full fdopen repository is removed from compact fdopen repository. (Old rule)
