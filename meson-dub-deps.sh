#!/bin/sh

if [[ $# -eq 0 ]] ; then
    echo 'Invoke with compiler name as argument'
    exit 1
fi

DC=$1

dub build dini --compiler=$DC
dub build unit-threaded --compiler=$DC
dub build unit-threaded:runner --compiler=$DC
dub build unit-threaded:exception --compiler=$DC
dub build unit-threaded:assertions --compiler=$DC
dub build unit-threaded:integration --compiler=$DC
dub build unit-threaded:property --compiler=$DC
dub build unit-threaded:from --compiler=$DC
dub build unit-threaded:mocks --compiler=$DC
