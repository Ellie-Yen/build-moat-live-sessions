# QR Code Generator Prototype

## System Requirements

Build a dynamic QR code system where:

- Users submit a long URL and get back a short URL token + QR code image
- The QR code encodes a short URL that redirects (302) to the original URL via your server
- Users can modify the target URL after QR code creation
- Users can delete a QR code (soft delete)
- Users can optionally set an expiration timestamp on create or update
- Deleted or expired links return appropriate HTTP status codes
- URL validation: format check, normalization, malicious URL blocking

## Design Questions

Answer these before you start coding:

1. **Static vs Dynamic QR Code:** Why does this system use dynamic QR codes (encode short URL) instead of static (encode original URL directly)? When would you choose static instead?
   Dynamic QR codes allows 1. traffic tracking 2. creating an uniq one when 1+ users entering the same target URL 3. re-use for user's later modification. 4. custom traffic routing (for A/B testing, based on device, campaign phase.) 5. Avoid long URLs produce denser QR codes
   Static ones are cheaper (not store anything). No tracking pixel — useful for privacy-conscious contexts (e.g., Wi-Fi credentials, vCards, payment URIs).

2. **Token Generation:** How will you generate short URL tokens? What happens when two different URLs produce the same token? How does collision probability change as the number of tokens grows?
   Counter / Snowflake-like (sequential ID → base62): Zero collisions by construction. Each ID is unique.
   Random (e.g., hash + truncate, or random base62): Collisions happen probabilistically (birthday paradox)
   I'll choose the Snowflake-like one to avoid collisions if there's no requirements like "anti-scraping".
   2 different URLs are not allowed to share the same token. If it happens, the token generator should a. Counter approach: increase the counter. b. Random approach: re-generate randomly.
   The longer the token length, the less collision probability (for base62 hash, length 6 has 62 ^ 6 slots, 7 has 62 ^ 7 slots).

3. **Redirect Strategy:** Why 302 (temporary) instead of 301 (permanent)? What are the trade-offs for analytics, URL modification, and latency?
   302: every requests go through our server. trackable. URL can be modify later. slightly higher latency. (higher server workload)
   301: the browser and CDN would cached the result (hard to modify the destination). not trackable. less latency.

4. **URL Normalization:** What normalization rules do you need? Why is `http://Example.com/` and `https://example.com` potentially the same URL?
   Convert host & schema to lowercase, removing port (eg :80). Based on requirements, the URL fragment (#section), tracking params can be removed or not.
   Technically they're different (http vs https, trailing '/'), but user might reach the same destination.

5. **Error Semantics:** What should happen when someone scans a deleted link vs a non-existent link? Should the HTTP status codes be different?
   deleted link: 410, indicate the resource is deleted permanently.
   non-existent link: 404, indicate the resource is unable to find.
   For privacy consideration, we can return both by 404.

## Verification

Your prototype should pass all of these:

```bash
# Create a QR code
curl -X POST http://localhost:8000/api/qr/create \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
# → 200, returns {"token": "...", "short_url": "...", "qr_code_url": "...", "original_url": "..."}

# Redirect
curl -o /dev/null -w "%{http_code}" http://localhost:8000/r/{token}
# → 302

# Get info
curl http://localhost:8000/api/qr/{token}
# → 200, returns token metadata

# Update target URL
curl -X PATCH http://localhost:8000/api/qr/{token} \
  -H "Content-Type: application/json" \
  -d '{"url": "https://new-url.com"}'
# → 200

# Redirect now goes to new URL
curl -o /dev/null -w "%{redirect_url}" http://localhost:8000/r/{token}
# → https://new-url.com

# Delete
curl -X DELETE http://localhost:8000/api/qr/{token}
# → 200

# Redirect after delete
curl -o /dev/null -w "%{http_code}" http://localhost:8000/r/{token}
# → 410

# Non-existent token
curl -o /dev/null -w "%{http_code}" http://localhost:8000/r/INVALID
# → 404

# QR code image
# (create a new one first, then)
curl -o /dev/null -w "%{http_code} %{content_type}" http://localhost:8000/api/qr/{token}/image
# → 200 image/png

# Analytics
curl http://localhost:8000/api/qr/{token}/analytics
# → 200, returns {"token": "...", "total_scans": N, "scans_by_day": [...]}
```

## Suggested Tech Stack

Python + FastAPI recommended, but you may use any language/framework.
