#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/tests build/module-cache
swiftc -module-cache-path build/module-cache PlaneTracker/Flight.swift Tests/main.swift -o build/tests/core-tests
build/tests/core-tests
