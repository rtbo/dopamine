FROM rtbo/dopamine-pm:build-deps AS build

ARG web_api_host
ARG web_api_prefix
ARG web_github_clientid
ARG web_google_clientid

# copy source code
COPY . /source

# build registry D app
WORKDIR /source
RUN DC=ldc2 meson /build \
    -Denable_registry=true \
    -Dregistry_storage=fs \
    -Denable_server=false \
    -Denable_client=false \
    -Denable_test=false \
    -Dalpine=true \
    --reconfigure \
    --buildtype=release \
    --prefix=/install

WORKDIR /build
RUN ninja install

# build vue front end
RUN apk add --no-cache nodejs npm tree

RUN echo "API URL at ${web_api_host}${web_api_prefix}"

ENV VITE_API_HOST=${web_api_host}
ENV VITE_API_PREFIX=${web_api_prefix}
ENV VITE_GITHUB_CLIENTID=${web_github_clientid}
ENV VITE_GOOGLE_CLIENTID=${web_google_clientid}

RUN tree /source/web

WORKDIR /source/web
RUN npm install
RUN npm run build

# copy built front end to installation dir
RUN mkdir -p /install/share/dopamine/public/assets
RUN cp -r /source/web/dist/* /install/share/dopamine/public

RUN tree /install

FROM alpine:3.16

# install runtime dependencies
RUN apk add --no-cache libpq zlib libbz2 xz-libs lua ldc-runtime

# copy installation
COPY --from=build /install /app

USER nobody

CMD /app/bin/dop-registry
