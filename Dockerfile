FROM linuxserver/wireguard:latest

RUN apk --no-cache upgrade && apk add --no-cache tinyproxy coreutils dnsmasq
COPY --chmod=755 ./scripts/ ./conf.d/tinyproxy/ /app/
RUN mkdir -p /app/tinyproxy


EXPOSE 8888/tcp 53/udp 53/tcp
WORKDIR /app
HEALTHCHECK --start-period=10s --interval=10s --timeout=5s --retries=5 \
  CMD "./healthcheck.sh" || exit 1

ENTRYPOINT ["./start.sh"]