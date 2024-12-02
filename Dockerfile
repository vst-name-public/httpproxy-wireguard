FROM linuxserver/wireguard:latest

RUN apk update && apk upgrade && apk add tinyproxy coreutils


COPY --chmod=755 ./scripts/ ./conf.d/tinyproxy/ /app/

EXPOSE 8888/tcp

HEALTHCHECK --start-period=10s --interval=10s --timeout=5s --retries=5 \
  CMD "/app/healthcheck.sh" || exit 1

ENTRYPOINT ["/app/start.sh"]