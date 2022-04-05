# Reproducible: Fetch Opam repository used by ocaml/opam Docker image

Prerequisites:
* On Windows you will need:
  * Cygwin (MSYS2 will not work)

Then run the following in Bash (for Windows use `bin\mintty.exe -` in your Cygwin installation folder):

```bash
if [ ! -e @@BOOTSTRAPDIR_UNIX@@README.md ]; then
    echo "You are not in a reproducible target directory" >&2
    exit 1
fi

# Install required system packages
@@BOOTSTRAPDIR_UNIX@@vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-0-system.sh

# Install the source code
# (Typically you can skip this step. It is only necessary if you changed any of these scripts or don't have a complete reproducible directory)
@@BOOTSTRAPDIR_UNIX@@vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-1-setup-noargs.sh

# Download Opam repository
@@BOOTSTRAPDIR_UNIX@@vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-2-build-noargs.sh

# Remove unused package versions
@@BOOTSTRAPDIR_UNIX@@vendor/dkml-runtime-distribution/src/unix/private/r-f-oorepo-9-trim-noargs.sh
```
