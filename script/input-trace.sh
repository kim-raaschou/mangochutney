#!/bin/sh
# Log the system side of "my shortcuts do nothing" once a second, to the terminal and to
# /tmp/mango-input-trace.log (see script/input-trace.swift). Stop with Ctrl-C.
set -eu
cd "$(dirname "$0")/.."
bin=.build/input-trace
if [ ! -x "$bin" ] || [ script/input-trace.swift -nt "$bin" ]; then
    mkdir -p .build
    swiftc -O -o "$bin" script/input-trace.swift
fi
exec "$bin" | tee -a /tmp/mango-input-trace.log
