FROM rtbo/dopamine-pm:build-deps AS build

ARG dc=dmd
ARG build_type=debug

# copy source code
COPY . /source

# build registry D app
WORKDIR /source
RUN --mount=type=cache,target=/build \
    DC=${dc} meson /build \
    -Denable_registry=true \
    -Denable_server=false \
    -Denable_client=false \
    -Denable_test=false \
    -Dalpine=true \
    --buildtype=${build_type} --prefix=/install

WORKDIR /build
RUN --mount=type=cache,target=/build ninja install

FROM alpine:3.16

# install runtime dependencies
RUN apk add --no-cache libpq zlib libbz2 xz-libs lua ldc-runtime dmd

# copy installation
COPY --from=build /install /app

USER nobody

CMD /app/bin/dop-registry
