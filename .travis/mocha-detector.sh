#! /bin/bash
test_files=$(find test/ -name "*.js")
if [ ! -z "$test_files" ];
then mocha-only-detector $test_files
fi
