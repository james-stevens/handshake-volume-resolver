# A Universal DNS Resolver of ICANN & Web3 Names

This container providers a high volume native ICANN, Handshake & ETH aware DNS Resolver
and authoritative ROOT server, with resolver/authoritative queries separated based on the `RD` bit flag.

This container resolves all queries itself, relying on one or more Handshake Full Nodes to provide authoritative answers to Handshake ROOT queries
and acts as an ICANN ROOT Secondary, so internally it keep a live copy of the ICANN ROOT zone, to get authoritative ICANN ROOT answers.

You are required to run one or more [Handshake Nodes](https://github.com/james-stevens/handshake-full-node)
to provide the Handshake ROOT zone name resolution. You you are not running my `hsd` container, will need to map the `hsd` authoritative port (`5349`) to appear as port `53`.

This container also provides a binary DoH service on port `80` that can be used in a browser, when fronted with a TLS proxy, like `nginx`.

This container runs a "prefer ICANN" model. This means, if the same TLD exists in ICANN and Handshake, the ICANN TLD will be used.


Prometheus stats can be found on ports 9119 (`bind` resolver), 8083 (`dnsdist` load-balance/failover) and 8405 (`haproxy` for DoH).

To enable `dnsdist` stats you must set two Environment Vairables (see below)


# Environment Vairables

| names              | meaning/use |
|--------------------|-------------|
| `DNSDIST_STATS_KEY` | Password to access `dnsdist` Promatheus Metric |
| `DNSDIST_STATS_ACL` | ACL for who can access `dnsdist` Promatheus Metric |
| `HSD_MASTERS`       | Semi-colon separated list of your HSD nodes (required) |
| `ETH_MASTERS`       | Semi-colon separated list of your ETH gateways (optional) |


# Additional Zone

This container can also serve additonal authoritative zones. Copy the zones files into a directory, so the file name is the
same as the zone name, then map that directory into the container at `/opt/data/auth_zones`.

It will scan for updates to any of these zones files every 5 mins and the new data checked & loaded.


# ETH Support

This container supports resolving `.eth` domains, but requires the container `ethereum-dns-gateway` to 
handle those requests, specified as a semi-colon separated list of IP Addresses in `ETH_MASTERS`.

# docker.com

The lastest build of this container is available from docker.com

https://hub.docker.com/r/jamesstevens/handshake-volume-resolver
