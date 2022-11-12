(lang dune 2.9)

(name dkml-runtime-distribution)
(version 1.0.2~prerel2)

(generate_opam_files true)

(source
 (github diskuv/dkml-runtime-distribution))
(license Apache-2.0)
(authors "Diskuv, Inc. <opensource+diskuv-ocaml@support.diskuv.com>")
(maintainers "opensource+diskuv-ocaml@support.diskuv.com")

(package
 (name dkml-runtime-distribution)
 (synopsis "Scripts used by the Diskuv OCaml distribution during installation")
 (description
  "Scripts used by the Diskuv OCaml distribution during the installation of:
* a local project (ie. a Opam switch created with `opam dkml init`)
* a user profile (ex. OCaml binaries installed within the user's home directory)
* a machine (ex. system or Administrator assembly/C compilers)")
 (depends
  (diskuvbox (and (>= 0.1.0) :build))))
