from datetime import datetime, timezone

def utcnow() -> datetime:
    """Naive UTC datetime — replacement for deprecated datetime.utcnow()."""
    return datetime.now(timezone.utc).replace(tzinfo=None)

def to_utc(iso_timestamp: str) -> datetime:
    """convert user input local timestamp (iso) into UTC datetime"""
    return datetime.fromisoformat(iso_timestamp).astimezone(timezone.utc).replace(tzinfo=None)