#!/bin/bash
# Runs every .kim file in tests/ and compares its output with the saved
# expected output in tests/expected/.  Usage:  ./run_tests.sh
#   ./run_tests.sh --save   saves the current outputs as the expected ones

cd "$(dirname "$0")"
pass=0; fail=0
mkdir -p tests/expected

for file in tests/*.kim tests/examples/*.kim tests/errors/*.kim; do
    name=$(echo "$file" | sed 's|tests/||; s|/|_|g; s|\.kim$||')
    expected="tests/expected/$name.out"
    actual=$(./kimiya "$file" 2>&1)

    if [ "$1" == "--save" ]; then
        echo "$actual" > "$expected"
        echo "saved   $file"
        continue
    fi

    if [ "$actual" == "$(cat "$expected" 2>/dev/null)" ]; then
        echo "PASS    $file"
        pass=$((pass + 1))
    else
        echo "FAIL    $file"
        diff <(echo "$actual") "$expected" | head -10
        fail=$((fail + 1))
    fi
done

[ "$1" == "--save" ] || echo "----- $pass passed, $fail failed -----"
[ $fail -eq 0 ]
