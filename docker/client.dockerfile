FROM rtbo/dopamine-pm:build-deps AS build

ARG dc=dmd
ARG build_type=debug

RUN apk add --no-cache tree

# copy source code
COPY . /source
WORKDIR /source

RUN --mount=type=cache,target=/build \
    mkdir -p /build/client

RUN --mount=type=cache,target=/build \
    tree /build

RUN --mount=type=cache,target=/build \
    DC=${dc} meson setup /build/client \
    -Denable_client=true \
    -Denable_admin=true \
    -Denable_registry=false \
    -Denable_server=false \
    -Denable_test=false \
    -Dalpine=true \
    --buildtype=${build_type} --prefix=/install

WORKDIR /build/client
RUN --mount=type=cache,target=/build \
    ninja install

FROM alpine:3.16

RUN apk add --no-cache musl-dev libpq-dev zlib-dev xz-dev bzip2-dev git gcc dub ldc dmd gcc ninja py3-pip cmake
RUN python3 -m pip install meson==0.63.0

# copy installation
COPY --from=build /install /app

RUN mkdir /dop
WORKDIR /dop

ENV PATH="${PATH}:/app/bin"
