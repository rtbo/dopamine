FROM alpine:3.16

RUN apk add --no-cache musl-dev libpq-dev zlib-dev xz-dev bzip2-dev git gcc dub ldc dmd gcc ninja py3-pip
RUN python3 -m pip install meson==0.63.0

RUN dub run --yes dub-build-deep --build=release -- vibe-d:http@0.9.4 --compiler=ldc2 --build=release
RUN dub run --yes dub-build-deep --build=release -- vibe-d:http@0.9.4 --compiler=dmd --build=release
RUN dub run --yes dub-build-deep --build=release -- vibe-d:http@0.9.4 --compiler=ldc2 --build=debug
RUN dub run --yes dub-build-deep --build=release -- vibe-d:http@0.9.4 --compiler=dmd --build=debug
RUN dub run --yes dub-build-deep --build=release -- unit-threaded:assertions@2.0.3 --compiler=ldc2 --build=debug
RUN dub run --yes dub-build-deep --build=release -- unit-threaded:assertions@2.0.3 --compiler=dmd --build=debug
