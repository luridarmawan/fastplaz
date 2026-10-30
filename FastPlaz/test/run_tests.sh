#!/bin/sh
# Compile and run the FastPlaz library unit tests with instantfpc.
# Usage: ./run_tests.sh [runner options]   (default: -a)

cd "$(dirname "$0")" || exit 1

# -B: always rebuild, the cache only tracks the main program source.
# The unit paths mirror tools/fastplaz_runtime.lpk.
export INSTANTFPCOPTIONS="-B -Fi.. -Fu../../tools/src -Fu../src/systems -Fu../src/library -Fu../src/vendor -Fu../src/app/about -Fu../src/model -Fu../src/util -Fu../src/helper"

if [ $# -eq 0 ]; then
  set -- -a
fi
exec instantfpc fastplaz_test.lpr "$@"
