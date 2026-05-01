from urllib.parse import urlparse

MAX_URL_LENGTH = 2048

BLOCKED_DOMAINS = {
    "evil.com",
    "malware.example.com",
    "phishing.example.com",
}


def is_blocked_domain(hostname: str | None) -> bool:
    if hostname is None:
        return True
    return hostname.lower() in BLOCKED_DOMAINS


def validate_url(url: str) -> str:
    """Format check, normalization, and blocklist validation."""
    # TODO: Implement this function
    #
    # Design decision: normalization keeps the same destination URL mapping to
    # the same token (no duplicates); blocklist validation prevents short links
    # from becoming phishing vectors.
    #
    # Hints:
    # 1. Validate: length within MAX_URL_LENGTH, scheme is http/https via
    #    urlparse(), hostname is not in is_blocked_domain(). Raise ValueError otherwise.
    # 2. Normalize and return: lowercase, strip trailing slash, upgrade http→https.
    if len(url) > MAX_URL_LENGTH:
        raise ValueError(f"invalid url length: {len(url)} (accept: {MAX_URL_LENGTH})")
    
    parsed_url = urlparse(url)
    if is_blocked_domain(parsed_url.hostname):
        raise ValueError(f"invalid url domain")

    return _normalize_url(url)

def _normalize_url(url: str) -> str:
    u = urlparse(url)

    # due to requirement, http -> https, trailing slash is striped
    schema = u.scheme.lower()
    host = u.hostname.lower()
    p = u.path.rstrip('/')
    q = u.query
    if schema == 'http':
        schema = 'https'
    return f'{schema}://{host}{p}' + (f'?{q}' if q else '')

