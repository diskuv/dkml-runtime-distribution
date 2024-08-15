(lang dune 2.9)

(name dkml-runtime-distribution)
(version 2.1.2)

(generate_opam_files true)

(source
 (github diskuv/dkml-runtime-distribution))
(license Apache-2.0)
(authors "Diskuv, Inc. <opensource+dkml@support.diskuv.com>")
(maintainers "opensource+dkml@support.diskuv.com")

(package
 (name dkml-runtime-distribution)
 (synopsis "Scripts used by the Diskuv OCaml distribution during installation")
 (description
  "Scripts used by the Diskuv OCaml distribution during the installation of:
* a local project (ie. a Opam switch created with `dkml init`)
* a user profile (ex. OCaml binaries installed within the user's home directory)
* a machine (ex. system or Administrator assembly/C compilers)")
 (depends
  (ocaml
    ; src/none/full-<VER>-pkgs.txt has a list of DKML packages for that version of OCaml
    (or
      (and (>= 4.12.1~) (< 4.12.2~))
      (and (>= 4.14.0~) (< 4.14.1~))
      (and (>= 4.14.2~) (< 4.14.3~))
    )
  )
  (diskuvbox (and (>= 0.1.0) :build))))
