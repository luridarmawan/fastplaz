#!/bin/sh
# Compile and run the FastPlaz library unit tests with instantfpc.
# Usage: ./run_tests.sh [runner options]   (default: -a)

cd "$(dirname "$0")" || exit 1

# -B: always rebuild, the cache only tracks the main program source.
# The unit paths mirror tools/fastplaz_runtime.lpk.
export INSTANTFPCOPTIONS="-B -Fi.. -Fu../../tools/src -Fu../src/systems -Fu../src/library -Fu../src/vendor -Fu../src/app/about -Fu../src/model -Fu../src/util -Fu../src/helper"

# SQLite client library for the database_lib suite (skipped when missing).
# SQLITE3_LIBRARY wins; otherwise try the usual shared library locations.
if [ -z "$SQLITE3_LIBRARY" ]; then
  for f in /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 /usr/lib64/libsqlite3.so.0            /usr/lib/libsqlite3.so.0 /usr/local/lib/libsqlite3.so.0            /usr/lib/aarch64-linux-gnu/libsqlite3.so.0 /opt/homebrew/lib/libsqlite3.dylib            /usr/local/opt/sqlite/lib/libsqlite3.dylib /usr/lib/libsqlite3.dylib; do
    if [ -f "$f" ]; then
      SQLITE3_LIBRARY="$f"
      export SQLITE3_LIBRARY
      break
    fi
  done
fi
[ -n "$SQLITE3_LIBRARY" ] && echo "SQLite library: $SQLITE3_LIBRARY"

if [ $# -eq 0 ]; then
  set -- -a
fi
exec instantfpc fastplaz_test.lpr "$@"
