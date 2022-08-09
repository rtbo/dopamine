#! /bin/bash

# when docker compose runs in a terminal,
# run this script from another terminal to reset the server state

DOCK_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

docker compose -f "$DOCK_DIR/compose-dev.yml" stop registry
docker compose -f "$DOCK_DIR/compose-dev.yml" start database

docker compose -f "$DOCK_DIR/compose-dev.yml" run --rm --no-deps client \
    /bin/sh -c 'dop-admin --create-db --run-migration v1'

docker compose -f "$DOCK_DIR/compose-dev.yml" run --rm registry \
    /bin/sh -c 'rm -rf /storage/*'

docker compose -f "$DOCK_DIR/compose-dev.yml" up --detach
