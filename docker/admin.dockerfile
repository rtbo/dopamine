FROM rtbo/dopamine-pm:build-deps AS build

ARG dc=dmd
ARG build_type=debug

# copy source code
COPY . /source

# build registry D app
WORKDIR /source
#RUN  \
RUN --mount=type=cache,target=/build-admin \
    DC=${dc} meson /build-admin \
    -Denable_registry=false \
    -Denable_server=false \
    -Denable_client=false \
    -Denable_test=false \
    -Denable_admin=true \
    -Dalpine=true \
    --buildtype=${build_type} --prefix=/install

WORKDIR /build-admin
RUN --mount=type=cache,target=/build-admin ninja install
#RUN ninja install

FROM alpine:3.16

# install runtime dependencies
RUN apk add --no-cache libpq zlib libbz2 xz-libs lua ldc-runtime dmd

# copy installation
COPY --from=build /install /app

ENV PATH="${PATH}:/app/bin"
