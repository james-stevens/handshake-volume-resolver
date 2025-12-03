
// This was made by AI and needed a few corrections, so likely isn't the most ideal set of values!!

    rate-limit {
        // Maximum responses per second to the same client (IP)
        responses-per-second 15;

        // If a client exceeds the limit, slip/truncate some responses
        // slip 2 means: for every 2 exceeding responses, send 1 truncated (TC=1)
        // This makes the client retry over TCP, which is much harder to abuse
        slip 2;

        // For very abusive clients, temporarily exempt them from NXDOMAIN responses
        // This stops NXDOMAIN amplification (very common in attacks)
        nxdomains-per-second 5;

        // Limit referrals (less common but still useful)
        referrals-per-second 10;

        // Apply a shorter window for identical queries (helps against random-subdomain attacks)
        window 5;

        // Maximum number of logged rate-limit events per second (prevents log flooding)
        log-only no;          // set to yes if you don't want to slip, only log
        min-table-size 4096;  // increase for better precision on busy servers
        max-table-size 65536;

        // whitelist trusted networks (e.g., your own infrastructure, CDNs, etc.)
        exempt-clients { 127.0.0.1; ::1; allowed-nets; };

        // Enable IPv4 and IPv6 truncation (recommended)
        all-per-second 15;
        ipv4-prefix-length 24;   // treat /24 as one "client" (common for broadband)
        ipv6-prefix-length 56;   // treat /56 as one "client" (typical residential block)
    };

    // Very important: always enable DNS COOKIE (RFC 7873) - greatly improves RRL effectiveness
    send-cookie yes;
    answer-cookie yes;
    require-server-cookie {{REQUIRE_COOKIES}};      // optional but highly recommended on open resolvers

    // Additional hardening
    minimal-responses yes;      // reduces amplification factor
    minimal-any yes;
