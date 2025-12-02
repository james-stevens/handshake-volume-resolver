# A Universal DNS Resolver of ICANN & Web3 Names

This contsiner providers a high volume ICANN, Handshake & ETH aware DNS Resolver
and authoritative ROOT server, with resolver/authoritative queries separated based on the `RD` bit flag.

This container resolves all queries itself, relying on one or more Handshake Full Nodes to provide authoritative answers to Handshake ROOT queries
and acts as an ICANN ROOT Secondary, so internall it keep a live copy of the ICANN ROOT zone, so can answer authoritative ICANN ROOT.

You are required to run one or more [Handshake Nodes](https://github.com/james-stevens/handshake-full-node)
to provide the Handshake resolution.

This container also provides a binary DoH service on port `80` that can be used in a prowser if fronted with a TLS proxy, like `nginx`.

This container runs a "prefer ICANN" model. This means, if the same TLD exists in ICANN and Handshake, the ICANN TLD will be used.


Prometheus stats can be found on ports 9119 (`bind` resolver), 8083 (`dnsdist` load-balance/failover) and 8405 (`haproxy` for DoH).

To enable `dnsdist` stats you must set two Environment Vairables (see below)


# Environment Vairables

| names              | meaning/use |
|--------------------|-------------|
| `ALCHEMY_API_CODE` | API code from [Alchemy](https://www.alchemy.com/) |
| `DNSDIST_STATS_KEY` | Password to access `dnsdist` Promatheus Metric |
| `DNSDIST_STATS_ACL` | ACL for who can access `dnsdist` Promatheus Metric |
| `UWR_IP_ADDRESSES`  | IP Address of a [Universal Web Redirector](https://github.com/james-stevens/universal-web-redirect), require for ETH support
| `HSD_MASTERS`       | Semi-colon separated list of you HSD nodes |


# Additional Zone

This container can also serve additonal authoritative zones. Copy the zones files into a directory, so the file name is the
same as the zone name, then map that directory into the container as `/opt/data/auth_zones`.

Uodates to any of these zones files will be scanned for every 5 mins and the new data checked & loaded.


# ETH Support

ENS domains (domains ending `.eth`) are supported by using an Alchemy RPC account, which must be passed into the container as the
environment variable `ALCHEMY_API_CODE`.

If you do not provide an `ALCHEMY_API_CODE` then the dot-ETH funcationality will be removed.

When you request a DNS record, the first thing it will do is try & find the record you asked for. If this fails, and you asked for 
an IPv4 address, you will be given the IP of a [Universal Web Redirector](https://github.com/james-stevens/universal-web-redirect).
This UWR will then request a URI to send you to.

The ETH support first looks for a `content` record in the domain. If the domain has an IPFS or IPNS content record, you will be redirected to
`https://ipfs.io/....`, if no `content` record exists, you will be rediected to `https://<eth-name>.eth.limo/`

Impervious `forever` domains are handled the same way, except the final redirection is `https://<eth-name>.forever.limo/`, 
which probably doesn't do anything useful.

Try `dig @<this-container> bitsofcode.eth uri`


For this service to work correctly, you must set the environmant variables

`ALCHEMY_API_CODE` - An Alchemy RPC account API code

`UWR_IP_ADDRESSES` - A comma separated list of IPv4 addresses of Universal Web Redirector servers


# docker.com

The lastest build of this container is available from docker.com

https://hub.docker.com/r/jamesstevens/handshake-volume-resolver
