#!/bin/sh

if [[ $# -eq 0 ]] ; then
    echo 'Invoke with compiler name as argument'
    exit 1
fi

DC=$1

dub build -n dini --compiler=$DC
dub build -n unit-threaded --compiler=$DC
dub build -n unit-threaded:runner --compiler=$DC
dub build -n unit-threaded:exception --compiler=$DC
dub build -n unit-threaded:assertions --compiler=$DC
dub build -n unit-threaded:integration --compiler=$DC
dub build -n unit-threaded:property --compiler=$DC
dub build -n unit-threaded:from --compiler=$DC
dub build -n unit-threaded:mocks --compiler=$DC
