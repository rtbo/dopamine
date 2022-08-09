FROM rtbo/dopamine-pm:build-deps AS build

ARG dc=dmd
ARG build_type=debug

RUN apk add --no-cache tree

# copy source code
COPY . /source
WORKDIR /source

# build registry D app
RUN --mount=type=cache,target=/build \
    mkdir -p /build/registry

RUN --mount=type=cache,target=/build \
    tree /build

RUN --mount=type=cache,target=/build \
    DC=${dc} meson setup /build/registry \
    -Denable_registry=true \
    -Dregistry_storage=fs \
    -Denable_server=false \
    -Denable_client=false \
    -Denable_test=false \
    -Dalpine=true \
    --buildtype=${build_type} \
    --prefix=/install

WORKDIR /build/registry
RUN --mount=type=cache,target=/build \
    ninja install

FROM alpine:3.16

# install runtime dependencies
RUN apk add --no-cache libpq zlib libbz2 xz-libs lua ldc-runtime dmd

# copy installation
COPY --from=build /install /app

CMD /app/bin/dop-registry
