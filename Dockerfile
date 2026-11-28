# (c) Copyright 2019-2020, James Stevens ... see LICENSE for details
# Alternative license arrangements are possible, contact me for more information

FROM alpine:3.24 AS builder
RUN apk add gcc make musl-dev findutils
COPY root_proxy /src
WORKDIR /src
RUN make clean && make ALL && strip -p root_proxy

FROM alpine:3.24

RUN apk update
RUN apk upgrade

COPY --from=builder /src/root_proxy /usr/local/bin/root_proxy
RUN rm -f /etc/periodic/monthly/dns-root-hints

RUN apk add dnsdist
RUN apk add haproxy
RUN apk add bind prometheus-bind-exporter su-exec
RUN apk add tcpdump

RUN rm -rf /run /tmp
RUN ln -s /dev/shm /run
RUN ln -s /dev/shm /tmp

COPY inittab /etc/inittab
COPY cron.root /etc/crontabs/root
COPY etc /usr/local/etc/

COPY bin /usr/local/bin/

RUN rm -f /var/cache/apk/*

COPY build.txt /usr/local/etc/build.txt
CMD [ "/sbin/init" ]
