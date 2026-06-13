#!/usr/bin/env python3
"""SwiftBar plugin: Claude Code usage limits and local token stats.

Menu bar shows 5h-session and 7d-week utilization from the OAuth usage
endpoint. The dropdown adds per-limit progress bars with reset times
(Europe/Copenhagen), today's deduplicated transcript token counts with an
estimated cost, and latest-session stats.

Python 3.9 compatible, stdlib only. All I/O sits behind injectable seams
(fetcher, keychain_reader, scan_root, cache_path, now) so the test suite
runs with no network, no Keychain, and no writes outside temp dirs.
"""

# <xbar.title>Claude Usage Bar</xbar.title>
# <xbar.desc>Claude Code session/week limit utilization in the menu bar.</xbar.desc>
# <xbar.dependencies>python3</xbar.dependencies>

import json
import subprocess
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Europe/Copenhagen")
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
OAUTH_BETA_HEADER = "oauth-2025-04-20"
KEYCHAIN_SERVICE = "Claude Code-credentials"
DEFAULT_SCAN_ROOT = Path.home() / ".claude" / "projects"
DEFAULT_CACHE_PATH = Path.home() / ".cache" / "claude-usage-bar" / "last.json"
HTTP_TIMEOUT_SECONDS = 10
TODAY_SCAN_WINDOW_SECONDS = 36 * 3600
CACHE_MAX_AGE_SECONDS = 24 * 3600
BAR_WIDTH = 10
SUBAGENT_DIR_NAME = "subagents"
COUNT_KEYS = ("input", "output", "cache_read", "cache_write")
LIMIT_LABELS = (
    ("five_hour", "Session (5h)"),
    ("seven_day", "Week (7d)"),
    ("seven_day_sonnet", "Sonnet (7d)"),
)
MENU_LIMIT_KEYS = ("five_hour", "seven_day")

# USD per MTok, exact-match on full model id strings as they appear in
# transcripts. cache_read = 0.1 x input, cache_write = 1.25 x input (5m tier).
PRICING = {
    "claude-fable-5":              {"input": 10.0, "output": 50.0, "cache_read": 1.0,  "cache_write": 12.5},
    "claude-opus-4-8":             {"input": 5.0,  "output": 25.0, "cache_read": 0.5,  "cache_write": 6.25},
    "claude-opus-4-7":             {"input": 5.0,  "output": 25.0, "cache_read": 0.5,  "cache_write": 6.25},
    "claude-opus-4-6":             {"input": 5.0,  "output": 25.0, "cache_read": 0.5,  "cache_write": 6.25},
    "claude-opus-4-5-20251101":    {"input": 5.0,  "output": 25.0, "cache_read": 0.5,  "cache_write": 6.25},
    "claude-sonnet-4-6":           {"input": 3.0,  "output": 15.0, "cache_read": 0.3,  "cache_write": 3.75},
    "claude-sonnet-4-5-20250929":  {"input": 3.0,  "output": 15.0, "cache_read": 0.3,  "cache_write": 3.75},
    "claude-haiku-4-5-20251001":   {"input": 1.0,  "output": 5.0,  "cache_read": 0.1,  "cache_write": 1.25},
}

Counts = Dict[str, int]
PerModelCounts = Dict[str, Counts]
Limit = Optional[Dict[str, object]]
Limits = Dict[str, Limit]


class AuthError(Exception):
    """Keychain item missing/unreadable or the OAuth token was rejected (401)."""


# --- Parsing helpers ---------------------------------------------------------

def parse_timestamp(value: str) -> datetime:
    """Parse ISO 8601 accepting both 'Z' and '+00:00' offsets (3.9-safe)."""
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def extract_limits(response: object) -> Limits:
    """Parse the usage response; raise ValueError if it is not an object."""
    if not isinstance(response, dict):
        raise ValueError("usage response is not a JSON object")
    return {key: parse_limit_object(response.get(key)) for key, _label in LIMIT_LABELS}


def parse_limit_object(raw: object) -> Limit:
    """Return None for null/partial/malformed limit objects, else parsed limit."""
    if not isinstance(raw, dict):
        return None
    utilization = raw.get("utilization")
    resets_at = raw.get("resets_at")
    if isinstance(utilization, bool) or not isinstance(utilization, (int, float)):
        return None
    if not isinstance(resets_at, str):
        return None
    try:
        resets = parse_timestamp(resets_at)
    except ValueError:
        return None
    return {"utilization": float(utilization), "resets_at": resets}


# --- I/O: Keychain, HTTP, cache ----------------------------------------------

def read_token() -> str:
    """Read the OAuth access token from the macOS Keychain."""
    command = ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise AuthError("Keychain item not found")
    try:
        credentials = json.loads(result.stdout.strip())
        token = credentials["claudeAiOauth"]["accessToken"]
    except (ValueError, KeyError, TypeError) as error:
        raise AuthError("Keychain item has unexpected shape") from error
    if not token:
        raise AuthError("Empty access token")
    return token


def fetch_usage(token: str) -> dict:
    """GET the OAuth usage endpoint; raise AuthError on HTTP 401."""
    request = urllib.request.Request(USAGE_URL, headers={
        "Authorization": "Bearer " + token,
        "anthropic-beta": OAUTH_BETA_HEADER,
    })
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code == 401:
            raise AuthError("Token rejected (401)") from error
        raise


def write_cache(cache_path: Path, response: dict, now: datetime) -> None:
    """Persist the last good usage response with its fetch timestamp."""
    cache_path = Path(cache_path)
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"fetched_at": now.isoformat(), "response": response}
    cache_path.write_text(json.dumps(payload), encoding="utf-8")


def load_cached_limits(cache_path: Path, now: datetime) -> Tuple[str, Optional[dict]]:
    """Return (state, payload): 'fresh' with limits + age, 'stale', or 'missing'."""
    try:
        with open(cache_path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
        fetched_at = parse_timestamp(data["fetched_at"])
        limits = extract_limits(data["response"])
    except (OSError, ValueError, KeyError, TypeError):
        return ("missing", None)
    age_seconds = (now - fetched_at).total_seconds()
    if age_seconds >= CACHE_MAX_AGE_SECONDS:
        return ("stale", None)
    return ("fresh", {"limits": limits, "age_seconds": age_seconds})


# --- Transcript scanning ------------------------------------------------------

def zero_counts() -> Counts:
    return {key: 0 for key in COUNT_KEYS}


def add_counts(target: Counts, source: Counts) -> None:
    for key in COUNT_KEYS:
        target[key] += source[key]


def read_entries(path: Path) -> List[dict]:
    """Read JSONL entries; skip unparseable lines; empty list if file vanished."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.readlines()
    except OSError:
        return []
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue
    return entries


def extract_message_usage(entry: object) -> Optional[Tuple[str, str, Counts]]:
    """Return (message_id, model, counts) for usage-bearing entries, else None."""
    if not isinstance(entry, dict):
        return None
    message = entry.get("message")
    if not isinstance(message, dict):
        return None
    usage = message.get("usage")
    message_id = message.get("id")
    if not isinstance(usage, dict) or not isinstance(message_id, str):
        return None
    model = message.get("model")
    if not isinstance(model, str):
        model = "unknown"
    counts = {
        "input": read_token_count(usage, "input_tokens"),
        "output": read_token_count(usage, "output_tokens"),
        "cache_read": read_token_count(usage, "cache_read_input_tokens"),
        "cache_write": read_token_count(usage, "cache_creation_input_tokens"),
    }
    return (message_id, model, counts)


def read_token_count(usage: dict, key: str) -> int:
    value = usage.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        return 0
    return value


def entry_date(entry: dict) -> Optional[date]:
    """Entry's calendar date in Europe/Copenhagen, or None if unparseable."""
    raw = entry.get("timestamp")
    if not isinstance(raw, str):
        return None
    try:
        return parse_timestamp(raw).astimezone(TZ).date()
    except ValueError:
        return None


def file_mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def scan_today(scan_root: Path, now: datetime) -> PerModelCounts:
    """Per-model token counts for entries dated today (Europe/Copenhagen).

    Recursive scan (subagent transcripts included) over files modified within
    the last 36 hours, counted once per message.id across all files.
    """
    per_model: PerModelCounts = {}
    seen_ids: Set[str] = set()
    today = now.astimezone(TZ).date()
    cutoff = now.timestamp() - TODAY_SCAN_WINDOW_SECONDS
    for path in sorted(Path(scan_root).glob("**/*.jsonl")):
        if file_mtime(path) < cutoff:
            continue
        for entry in read_entries(path):
            accumulate_today_entry(entry, per_model, seen_ids, today)
    return per_model


def accumulate_today_entry(entry: object, per_model: PerModelCounts,
                           seen_ids: Set[str], today: date) -> None:
    usage_info = extract_message_usage(entry)
    if usage_info is None:
        return
    message_id, model, counts = usage_info
    if message_id in seen_ids:
        return
    seen_ids.add(message_id)
    if entry_date(entry) != today:
        return
    add_counts(per_model.setdefault(model, zero_counts()), counts)


def find_latest_session_files(scan_root: Path) -> List[Path]:
    """Newest non-subagent transcript plus its own subagent transcripts."""
    root = Path(scan_root)
    candidates = [path for path in root.glob("**/*.jsonl")
                  if SUBAGENT_DIR_NAME not in path.relative_to(root).parts]
    if not candidates:
        return []
    latest = max(candidates, key=file_mtime)
    subagent_dir = latest.parent / latest.stem / SUBAGENT_DIR_NAME
    return [latest] + sorted(subagent_dir.glob("*.jsonl"))


def scan_latest_session(scan_root: Path) -> Counts:
    """Total token counts for the latest session, deduplicated by message.id."""
    totals = zero_counts()
    seen_ids: Set[str] = set()
    for path in find_latest_session_files(scan_root):
        for entry in read_entries(path):
            usage_info = extract_message_usage(entry)
            if usage_info is None:
                continue
            message_id, _model, counts = usage_info
            if message_id in seen_ids:
                continue
            seen_ids.add(message_id)
            add_counts(totals, counts)
    return totals


# --- Cost estimation ----------------------------------------------------------

def model_cost_usd(counts: Counts, pricing: Dict[str, float]) -> float:
    token_dollars_per_mtok = (counts["input"] * pricing["input"]
                              + counts["output"] * pricing["output"]
                              + counts["cache_read"] * pricing["cache_read"]
                              + counts["cache_write"] * pricing["cache_write"])
    return token_dollars_per_mtok / 1000000


def render_cost_row(per_model: PerModelCounts) -> str:
    """Estimated cost of today's tokens; '>=' prefix when unpriced tokens exist."""
    priced_cost_usd = 0.0
    priced_models = 0
    unpriced_tokens = 0
    for model, counts in per_model.items():
        pricing = PRICING.get(model)
        if pricing is None:
            unpriced_tokens += sum(counts.values())
            continue
        priced_models += 1
        priced_cost_usd += model_cost_usd(counts, pricing)
    if unpriced_tokens > 0 and priced_models == 0:
        return "cost n/a (unpriced models)"
    prefix = "≥ " if unpriced_tokens > 0 else ""
    return "Cost today: {}${:.2f}".format(prefix, priced_cost_usd)


# --- Rendering (SwiftBar lines) ------------------------------------------------

def round_percent(utilization: float) -> int:
    return int(round(utilization))


def render_slot(limit: Limit) -> str:
    if limit is None:
        return "–"
    return "{}%".format(round_percent(limit["utilization"]))


def menu_color(limits: Limits) -> str:
    utilizations = [limits[key]["utilization"] for key in MENU_LIMIT_KEYS
                    if limits.get(key) is not None]
    if not utilizations:
        return "gray"
    worst = max(utilizations)
    if worst < 50:
        return "green"
    if worst < 80:
        return "yellow"
    return "red"


def render_menu_line(status: str, limits: Optional[Limits]) -> str:
    if status == "auth_error":
        return "⚡ ⚠ | color=red"
    if status == "fetch_error":
        return "⚡ — | color=gray"
    return "⚡ {} · {} | color={}".format(render_slot(limits.get("five_hour")),
                                          render_slot(limits.get("seven_day")),
                                          menu_color(limits))


def render_bar(utilization: float) -> str:
    filled = int(round(min(utilization, 100.0) / 100 * BAR_WIDTH))
    return "█" * filled + "░" * (BAR_WIDTH - filled)


def render_limit_rows(limits: Limits) -> List[str]:
    rows = []
    for key, label in LIMIT_LABELS:
        limit = limits.get(key)
        if limit is None:
            continue
        reset_local = limit["resets_at"].astimezone(TZ).strftime("%a %H:%M")
        rows.append("{} {} {}% · resets {} | font=Menlo".format(
            label, render_bar(limit["utilization"]),
            round_percent(limit["utilization"]), reset_local))
    return rows


def format_age(age_seconds: float) -> str:
    minutes = int(age_seconds // 60)
    if minutes < 60:
        return "{}m".format(minutes)
    return "{}h".format(minutes // 60)


def render_error_rows(status: str, cache_state: str, cached: Optional[dict]) -> List[str]:
    if status == "auth_error":
        rows = ["Sign in to Claude Code (run claude, then /login)"]
    else:
        rows = ["Error: failed to fetch usage limits"]
    if cache_state == "fresh":
        limits = cached["limits"]
        rows.append("Cached: {} · {} ({} ago)".format(
            render_slot(limits.get("five_hour")), render_slot(limits.get("seven_day")),
            format_age(cached["age_seconds"])))
    elif cache_state == "missing":
        rows.append("no cached data yet")
    return rows


def sum_model_counts(per_model: PerModelCounts) -> Counts:
    totals = zero_counts()
    for counts in per_model.values():
        add_counts(totals, counts)
    return totals


def render_breakdown(counts: Counts) -> str:
    return "in: {:,} · out: {:,} · cache read: {:,} · cache write: {:,}".format(
        counts["input"], counts["output"], counts["cache_read"], counts["cache_write"])


def render_stats_rows(today_by_model: PerModelCounts, session_totals: Counts) -> List[str]:
    today_totals = sum_model_counts(today_by_model)
    return [
        "{:,} tokens today".format(sum(today_totals.values())),
        render_breakdown(today_totals),
        render_cost_row(today_by_model),
        "Latest session: {:,} tokens".format(sum(session_totals.values())),
        render_breakdown(session_totals),
    ]


def render_output(status: str, limits: Optional[Limits], cache_state: str,
                  cached: Optional[dict], today_by_model: PerModelCounts,
                  session_totals: Counts) -> str:
    lines = [render_menu_line(status, limits), "---"]
    if status == "ok":
        lines.extend(render_limit_rows(limits))
    else:
        lines.extend(render_error_rows(status, cache_state, cached))
    lines.append("---")
    lines.extend(render_stats_rows(today_by_model, session_totals))
    lines.append("---")
    lines.append("Refresh | refresh=true")
    return "\n".join(lines)


# --- Entry point ----------------------------------------------------------------

def main(fetcher=None, keychain_reader=None, scan_root=None, cache_path=None,
         now=None) -> None:
    if fetcher is None:
        fetcher = fetch_usage
    if keychain_reader is None:
        keychain_reader = read_token
    scan_root = Path(scan_root) if scan_root is not None else DEFAULT_SCAN_ROOT
    cache_path = Path(cache_path) if cache_path is not None else DEFAULT_CACHE_PATH
    if now is None:
        now = datetime.now(TZ)

    today_by_model = scan_today(scan_root, now)
    session_totals = scan_latest_session(scan_root)

    status = "ok"
    limits = None
    try:
        token = keychain_reader()
        response = fetcher(token)
        limits = extract_limits(response)
        write_cache(cache_path, response, now)
    except AuthError:
        status = "auth_error"
    except Exception:
        status = "fetch_error"

    cache_state, cached = ("none", None)
    if status != "ok":
        cache_state, cached = load_cached_limits(cache_path, now)
    print(render_output(status, limits, cache_state, cached,
                        today_by_model, session_totals))


if __name__ == "__main__":
    main()
