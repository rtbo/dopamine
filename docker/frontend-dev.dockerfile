FROM alpine:3.16

RUN apk add --no-cache nodejs npm

ARG web_api_host
ARG web_github_clientid
ARG web_google_clientid

ENV VITE_API_HOST=${web_api_host}
ENV VITE_GITHUB_CLIENTID=${web_github_clientid}
ENV VITE_GOOGLE_CLIENTID=${web_google_clientid}

RUN echo "Registry URL at ${web_api_host}"

# copy source code
# this build context must be the web directory
COPY *.html *.json *.js *.ts /app/

WORKDIR /app

RUN npm install

CMD npm run dev -- --host 0.0.0.0
