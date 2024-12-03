FROM linuxserver/wireguard:latest

RUN apk --no-cache upgrade && apk add --no-cache tinyproxy coreutils

COPY --chmod=755 ./scripts/ ./conf.d/tinyproxy/ /app/

EXPOSE 8888/tcp
WORKDIR /app
HEALTHCHECK --start-period=10s --interval=10s --timeout=5s --retries=5 \
  CMD "./healthcheck.sh" || exit 1

ENTRYPOINT ["./start.sh"]