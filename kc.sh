#!/bin/bash
# kc.sh: compile a Kimiya program with Phase 2 and run it.   Usage: bash kc.sh tests/compile/c9_chemistry.kim
name="${1%.kim}"
./kimiya -c "$1" || exit 1
clang "$name.ll" src/runtime.c src/chem.c -Isrc -o "$name" 2>/dev/null || exit 1
"./$name"
