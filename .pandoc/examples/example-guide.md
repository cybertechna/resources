---
title: "Renewing Wildcard Certificates with Certbot and Cloudflare"
subtitle: "A repeatable procedure for renewing DNS-01 certificates on Alpine"
author: "Kevin Robinson"
date: 2026-11-11
time: "15 minutes"
applies-to: "Alpine Linux, nginx, Certbot"
status: Draft
version: "0.1"
numbersections: true
---

# Before you start

You need shell access to the proxy host and a Cloudflare token with **Zone, DNS, Edit**.

# Check the current state

```
certbot certificates
head -1 /etc/periodic/daily/certbot-renew
```

::: note
The first line of the renewal script must be `#!/bin/sh`. A typo here stops nightly renewal silently.
:::

# Renew

1. Run the forced renewal.
2. Test the nginx configuration.
3. Reload nginx.

```bash
certbot renew --force-renewal
nginx -t && rc-service nginx reload
```

## If it fails

| Symptom | Likely cause | Fix |
|---|---|---|
| Connection reset by peer | Staging server blocked on this host | Ignore for dry runs; test on production |
| 403 from Cloudflare | Token lacks DNS edit | Re-issue the token |

# How renewal works

```mermaid
flowchart TB
    A[crond 02:00] --> B[certbot renew]
    B --> C{Under 30 days left?}
    C -- yes --> D[DNS-01 via Cloudflare]
    C -- no --> E[Skip]
    D --> F[Deploy hook: reload nginx]
```

# Verify

- [ ] `certbot certificates` shows 60+ days remaining
- [ ] Browser shows the new expiry date
