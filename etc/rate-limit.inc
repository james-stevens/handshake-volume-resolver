// Values are starting points to tune.

    rate-limit {
        // Maximum responses per second to the same client (IP)
        responses-per-second 15;

        // If a client exceeds the limit, slip/truncate some responses
        // slip 2 means: for every 2 exceeding responses, send 1 truncated (TC=1)
        // This makes the client retry over TCP, which is much harder to abuse
        slip 2;

        // Maximum NXDOMAIN responses per second to the same client
        nxdomains-per-second 5;

        // Limit referrals (less common but still useful)
        referrals-per-second 10;

        // SERVFAIL, FORMERR and other non-NXDOMAIN errors
        errors-per-second 5;

        // Averaging period, in seconds
        window 5;

        log-only no;          // yes logs what would be limited, without slipping or dropping
        min-table-size 4096;  // increase for better precision on busy servers
        max-table-size 65536;

        // Loopback only; see acl rrl-exempt
        exempt-clients { rrl-exempt; };

        // Drops rather than slips, so a value equal to responses-per-second
        // hurts NATed clients. Kept above responses-per-second.
        all-per-second 80;
    };

    // Very important: always enable DNS COOKIE (RFC 7873) - greatly improves RRL effectiveness
    send-cookie yes;
    answer-cookie yes;
    require-server-cookie {{REQUIRE_COOKIES}};      // cookie-less stub clients are pushed to TCP

    // Additional hardening
    minimal-responses yes;      // reduces amplification factor
    minimal-any yes;

    // Resolver-side protection against random-subdomain and fetch floods
    fetches-per-zone 200;
    fetches-per-server 400;
    clients-per-query 10;
    max-clients-per-query 100;
    recursive-clients 10000;
