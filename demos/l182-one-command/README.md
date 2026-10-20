# One-command 27B demo: run records

Each folder is one run of [`run`](https://aienos.com/run), named by its UTC time. Inside, `SHA256SUMS`
lists every file as it was written at the end of the run, so the files are kept byte for byte.

Some files mention paths such as `/home/drakestapleton/...` or `~/.local/bin/quiet-measure`. Those are
our test folder on the shared Spark and the machine's queue tools that kept the GPU step from running
beside other jobs. They are not needed on a stock Spark. The next script version writes relative paths.
