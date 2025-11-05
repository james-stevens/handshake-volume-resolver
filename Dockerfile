# (c) Copyright 2019-2020, James Stevens ... see LICENSE for details
# Alternative license arrangements are possible, contact me for more information

FROM alpine:3.22

RUN apk update
RUN apk upgrade

RUN apk add nodejs npm
RUN npm install -g express @imperviousinc/id ethers content-hash

RUN apk add bind python3 py3-dnspython py3-requests
RUN rm -f /etc/periodic/monthly/dns-root-hints

RUN apk add dnsdist haproxy tcpdump

RUN rm -rf /run /tmp
RUN ln -s /dev/shm /run
RUN ln -s /dev/shm /tmp

COPY inittab /etc/inittab
COPY cron.root /etc/crontabs/root
COPY etc /usr/local/etc/

COPY bin /usr/local/bin/
RUN python3 -m compileall /usr/local/bin/

RUN rm -f /var/cache/apk/*
CMD [ "/sbin/init" ]
