# (c) Copyright 2019-2020, James Stevens ... see LICENSE for details
# Alternative license arrangements are possible, contact me for more information

FROM alpine:3.22

RUN apk update
RUN apk upgrade

RUN rm -f /etc/periodic/monthly/dns-root-hints

RUN apk add dnsdist
RUN apk add haproxy
RUN apk add bind prometheus-bind-exporter
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
