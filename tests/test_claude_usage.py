"""Failing-first test suite for the claude-usage-bar SwiftBar plugin.

All 36 tests come from the approved spec's Failing Tests table. They use the
injectable seams only: stub fetcher, stub keychain reader, fixture scan_root,
temp-dir cache_path, and an injected now. No network, no Keychain, no writes
outside temp dirs. Run with: /usr/bin/python3 -m unittest
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import claude_usage  # noqa: E402

TZ = ZoneInfo("Europe/Copenhagen")
FIXED_NOW = datetime(2026, 6, 13, 12, 0, 0, tzinfo=TZ)
SCAN_NOW = datetime.now(TZ)

FIVE_HOUR_RESET = "2026-06-13T02:20:00+00:00"
MONDAY_RESET = "2026-06-15T14:00:01+00:00"  # Monday 14:00 UTC == Mon 16:00 CEST
SONNET_RESET = "2026-06-15T14:00:00+00:00"

DEFAULT_COUNTS = {"input": 10, "output": 20, "cache_read": 30, "cache_write": 40}


def make_limit(utilization, resets_at):
    return {"utilization": utilization, "resets_at": resets_at}


def make_response(five_hour=43.0, seven_day=48.0, seven_day_sonnet=0.0):
    response = {"five_hour": None, "seven_day": None, "seven_day_sonnet": None}
    if five_hour is not None:
        response["five_hour"] = make_limit(five_hour, FIVE_HOUR_RESET)
    if seven_day is not None:
        response["seven_day"] = make_limit(seven_day, MONDAY_RESET)
    if seven_day_sonnet is not None:
        response["seven_day_sonnet"] = make_limit(seven_day_sonnet, SONNET_RESET)
    return response


def iso_z(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def transcript_entry(message_id, model="claude-fable-5", timestamp=None,
                     input_tokens=10, output_tokens=20, cache_read=30, cache_write=40):
    entry = {
        "type": "assistant",
        "message": {
            "id": message_id,
            "model": model,
            "usage": {
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "cache_read_input_tokens": cache_read,
                "cache_creation_input_tokens": cache_write,
                "cache_creation": {"ephemeral_5m_input_tokens": cache_write,
                                   "ephemeral_1h_input_tokens": 0},
                "server_tool_use": {"web_search_requests": 0},
                "service_tier": "standard",
            },
        },
    }
    if timestamp is not None:
        entry["timestamp"] = timestamp
    return entry


def write_jsonl(path, entries):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [json.dumps(entry) for entry in entries]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def raise_fetch_error(token):
    raise RuntimeError("network down")


def raise_auth_error(token):
    raise claude_usage.AuthError("401")


class ClaudeUsageTestCase(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.scan_root = self.tmp / "projects"
        self.scan_root.mkdir()
        self.cache_path = self.tmp / "cache-dir" / "last.json"

    def run_main(self, response=None, fetcher=None, keychain_reader=None, now=FIXED_NOW):
        if fetcher is None:
            payload = make_response() if response is None else response
            fetcher = lambda token: payload  # noqa: E731
        if keychain_reader is None:
            keychain_reader = lambda: "TEST-TOKEN"  # noqa: E731
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            claude_usage.main(fetcher=fetcher, keychain_reader=keychain_reader,
                              scan_root=self.scan_root, cache_path=self.cache_path,
                              now=now)
        return buffer.getvalue()

    def menu_line(self, output):
        return output.splitlines()[0]

    def menu_text(self, output):
        return self.menu_line(output).split("|")[0].strip()


class MenuLineTests(ClaudeUsageTestCase):
    def test_menu_line_shows_session_and_week_percent(self):
        output = self.run_main(make_response(five_hour=43.0, seven_day=48.0))
        self.assertEqual("⚡ 43% · 48%", self.menu_text(output))

    def test_menu_line_rounds_float_utilization(self):
        output = self.run_main(make_response(five_hour=43.7))
        self.assertIn("44%", self.menu_line(output))

    def test_menu_color_green_below_50(self):
        output = self.run_main(make_response(five_hour=49.9, seven_day=10.0))
        self.assertIn("color=green", self.menu_line(output))

    def test_menu_color_yellow_at_50(self):
        output = self.run_main(make_response(five_hour=50.0, seven_day=10.0))
        self.assertIn("color=yellow", self.menu_line(output))

    def test_menu_color_yellow_below_80(self):
        output = self.run_main(make_response(five_hour=79.9, seven_day=10.0))
        self.assertIn("color=yellow", self.menu_line(output))

    def test_menu_color_red_at_80(self):
        output = self.run_main(make_response(five_hour=80.0, seven_day=10.0))
        self.assertIn("color=red", self.menu_line(output))

    def test_menu_color_ignores_null_limit(self):
        output_first_null = self.run_main(make_response(five_hour=None, seven_day=30.0))
        output_second_null = self.run_main(make_response(five_hour=30.0, seven_day=None))
        self.assertEqual("⚡ – · 30%", self.menu_text(output_first_null))
        self.assertIn("color=green", self.menu_line(output_first_null))
        self.assertEqual("⚡ 30% · –", self.menu_text(output_second_null))
        self.assertIn("color=green", self.menu_line(output_second_null))

    def test_menu_percent_above_100_unclamped(self):
        output = self.run_main(make_response(five_hour=105.0))
        self.assertIn("105%", self.menu_line(output))

    def test_both_limits_null_renders_double_dash_gray(self):
        output = self.run_main(make_response(five_hour=None, seven_day=None,
                                             seven_day_sonnet=None))
        self.assertEqual("⚡ – · –", self.menu_text(output))
        self.assertIn("color=gray", self.menu_line(output))


class DropdownTests(ClaudeUsageTestCase):
    def test_dropdown_reset_time_in_copenhagen_tz(self):
        output = self.run_main(make_response(seven_day=48.0), now=FIXED_NOW)
        self.assertIn("Mon 16:00", output)

    def test_dropdown_bar_clamps_above_100(self):
        output = self.run_main(make_response(five_hour=105.0))
        self.assertIn("█" * 10, output)
        self.assertIn("105%", output)

    def test_null_limit_key_is_skipped(self):
        output = self.run_main(make_response(seven_day_sonnet=None))
        self.assertNotIn("Sonnet", output)

    def test_partial_limit_object_treated_as_null(self):
        response = make_response(seven_day_sonnet=None)
        del response["seven_day"]["resets_at"]
        output = self.run_main(response)
        self.assertEqual("⚡ 43% · –", self.menu_text(output))
        self.assertNotIn("Week (7d)", output)

    def test_dropdown_renders_four_token_categories(self):
        write_jsonl(self.scan_root / "proj" / "sess.jsonl",
                    [transcript_entry("msg-1", timestamp=iso_z(SCAN_NOW))])
        output = self.run_main(now=SCAN_NOW)
        self.assertIn("in: 10", output)
        self.assertIn("out: 20", output)
        self.assertIn("cache read: 30", output)
        self.assertIn("cache write: 40", output)

    def test_refresh_row_carries_refresh_param(self):
        output = self.run_main()
        self.assertIn("Refresh | refresh=true", output)

    def test_empty_scan_root_renders_zero_today(self):
        output = self.run_main()
        self.assertIn("0 tokens today", output)


class TimestampTests(unittest.TestCase):
    def test_timestamp_helper_parses_z_and_offset_forms(self):
        z_form = claude_usage.parse_timestamp("2026-06-12T22:49:48.413Z")
        offset_form = claude_usage.parse_timestamp("2026-06-15T14:00:01+00:00")
        self.assertEqual(datetime(2026, 6, 12, 22, 49, 48, 413000,
                                  tzinfo=timezone.utc), z_form)
        self.assertEqual(datetime(2026, 6, 15, 14, 0, 1,
                                  tzinfo=timezone.utc), offset_form)


class TranscriptScanTests(ClaudeUsageTestCase):
    def test_duplicate_message_ids_counted_once_across_files(self):
        duplicated = transcript_entry("msg-dup", timestamp=iso_z(SCAN_NOW))
        write_jsonl(self.scan_root / "proj" / "a.jsonl",
                    [duplicated, duplicated, duplicated])
        write_jsonl(self.scan_root / "proj" / "b.jsonl", [duplicated])
        per_model = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        self.assertEqual({"claude-fable-5": DEFAULT_COUNTS}, per_model)

    def test_today_sum_excludes_yesterday_entries(self):
        yesterday = transcript_entry("msg-y", input_tokens=999,
                                     timestamp=iso_z(SCAN_NOW - timedelta(hours=24)))
        today = transcript_entry("msg-t", timestamp=iso_z(SCAN_NOW))
        write_jsonl(self.scan_root / "proj" / "sess.jsonl", [yesterday, today])
        per_model = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        self.assertEqual({"claude-fable-5": DEFAULT_COUNTS}, per_model)

    def test_subagent_transcripts_included_in_today(self):
        timestamp = iso_z(SCAN_NOW)
        write_jsonl(self.scan_root / "proj" / "sess.jsonl",
                    [transcript_entry("msg-main", timestamp=timestamp)])
        write_jsonl(self.scan_root / "proj" / "sess" / "subagents" / "agent-x.jsonl",
                    [transcript_entry("msg-sub", timestamp=timestamp)])
        per_model = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        expected = {"input": 20, "output": 40, "cache_read": 60, "cache_write": 80}
        self.assertEqual({"claude-fable-5": expected}, per_model)

    def test_latest_session_includes_own_subagents(self):
        timestamp = iso_z(SCAN_NOW)
        old_path = self.scan_root / "proj" / "old.jsonl"
        write_jsonl(old_path, [transcript_entry("msg-old", input_tokens=999,
                                                timestamp=timestamp)])
        old_time = SCAN_NOW.timestamp() - 5000
        os.utime(old_path, (old_time, old_time))
        write_jsonl(self.scan_root / "proj" / "sess.jsonl",
                    [transcript_entry("msg-main", timestamp=timestamp)])
        write_jsonl(self.scan_root / "proj" / "sess" / "subagents" / "agent-x.jsonl",
                    [transcript_entry("msg-sub", timestamp=timestamp)])
        totals = claude_usage.scan_latest_session(self.scan_root)
        self.assertEqual({"input": 20, "output": 40, "cache_read": 60,
                          "cache_write": 80}, totals)

    def test_truncated_jsonl_line_skipped(self):
        path = self.scan_root / "proj" / "sess.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        valid_line = json.dumps(transcript_entry("msg-ok", timestamp=iso_z(SCAN_NOW)))
        path.write_text(valid_line + '\n{"type":"assistant","mess', encoding="utf-8")
        per_model = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        self.assertEqual({"claude-fable-5": DEFAULT_COUNTS}, per_model)

    def test_vanished_file_skipped(self):
        timestamp = iso_z(SCAN_NOW)
        write_jsonl(self.scan_root / "proj" / "good.jsonl",
                    [transcript_entry("msg-good", timestamp=timestamp)])
        write_jsonl(self.scan_root / "proj" / "vanished.jsonl",
                    [transcript_entry("msg-gone", input_tokens=999,
                                      timestamp=timestamp)])
        real_open = open

        def fake_open(file, *args, **kwargs):
            if "vanished" in str(file):
                raise OSError("file vanished between glob and open")
            return real_open(file, *args, **kwargs)

        with mock.patch("claude_usage.open", side_effect=fake_open, create=True):
            per_model = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        self.assertEqual({"claude-fable-5": DEFAULT_COUNTS}, per_model)

    def test_empty_session_renders_zero_tokens(self):
        path = self.scan_root / "proj" / "sess.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("", encoding="utf-8")
        output = self.run_main(now=SCAN_NOW)
        self.assertIn("Latest session: 0 tokens", output)

    def test_subagent_file_never_selected_as_latest_session(self):
        base_time = SCAN_NOW.timestamp()
        older_path = self.scan_root / "proj" / "older.jsonl"
        session_path = self.scan_root / "proj" / "sess.jsonl"
        subagent_path = self.scan_root / "proj" / "sess" / "subagents" / "agent-x.jsonl"
        write_jsonl(older_path, [transcript_entry("msg-older")])
        write_jsonl(session_path, [transcript_entry("msg-main")])
        write_jsonl(subagent_path, [transcript_entry("msg-sub")])
        os.utime(older_path, (base_time - 500, base_time - 500))
        os.utime(session_path, (base_time - 100, base_time - 100))
        os.utime(subagent_path, (base_time, base_time))
        files = claude_usage.find_latest_session_files(self.scan_root)
        self.assertEqual(session_path, files[0])

    def test_old_mtime_files_excluded_from_today_scan(self):
        path = self.scan_root / "proj" / "stale.jsonl"
        write_jsonl(path, [transcript_entry("msg-stale", timestamp=iso_z(SCAN_NOW))])
        old_time = SCAN_NOW.timestamp() - 40 * 3600
        os.utime(path, (old_time, old_time))
        per_model = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        self.assertEqual({}, per_model)

    def test_entry_without_timestamp_counts_in_session_not_today(self):
        with_ts = transcript_entry("msg-ts", timestamp=iso_z(SCAN_NOW))
        without_ts = transcript_entry("msg-nots", input_tokens=7, output_tokens=0,
                                      cache_read=0, cache_write=0)
        write_jsonl(self.scan_root / "proj" / "sess.jsonl", [with_ts, without_ts])
        per_model_today = claude_usage.scan_today(self.scan_root, SCAN_NOW)
        session_totals = claude_usage.scan_latest_session(self.scan_root)
        self.assertEqual({"claude-fable-5": DEFAULT_COUNTS}, per_model_today)
        self.assertEqual({"input": 17, "output": 20, "cache_read": 30,
                          "cache_write": 40}, session_totals)


class ErrorStateTests(ClaudeUsageTestCase):
    def test_fetch_failure_renders_dash_and_cached_age(self):
        claude_usage.write_cache(self.cache_path, make_response(),
                                 FIXED_NOW - timedelta(minutes=12))
        output = self.run_main(fetcher=raise_fetch_error)
        self.assertEqual("⚡ —", self.menu_text(output))
        self.assertIn("color=gray", self.menu_line(output))
        self.assertIn("12m", output)
        self.assertIn("43%", output)
        self.assertIn("48%", output)

    def test_fetch_failure_without_cache(self):
        output = self.run_main(fetcher=raise_fetch_error)
        self.assertEqual("⚡ —", self.menu_text(output))
        self.assertIn("no cached data yet", output)

    def test_stale_cache_suppressed_at_exactly_24h(self):
        claude_usage.write_cache(self.cache_path, make_response(),
                                 FIXED_NOW - timedelta(hours=24))
        output = self.run_main(fetcher=raise_fetch_error)
        self.assertIn("Error", output)
        self.assertNotIn("43%", output)

    def test_401_renders_warning_and_signin_hint(self):
        claude_usage.write_cache(self.cache_path, make_response(),
                                 FIXED_NOW - timedelta(minutes=12))
        output = self.run_main(fetcher=raise_auth_error)
        self.assertEqual("⚡ ⚠", self.menu_text(output))
        self.assertIn("color=red", self.menu_line(output))
        self.assertIn("Sign in to Claude Code", output)
        self.assertIn("12m", output)
        self.assertIn("43%", output)


class CacheTests(ClaudeUsageTestCase):
    def test_successful_fetch_writes_cache(self):
        response = make_response()
        self.run_main(response=response, keychain_reader=lambda: "SECRET123")
        self.assertTrue(self.cache_path.exists())
        raw = self.cache_path.read_text(encoding="utf-8")
        cached = json.loads(raw)
        self.assertEqual(response, cached["response"])
        self.assertIn("fetched_at", cached)
        self.assertNotIn("SECRET123", raw)


class CostTests(ClaudeUsageTestCase):
    def test_cost_estimate_for_known_model(self):
        write_jsonl(self.scan_root / "proj" / "sess.jsonl",
                    [transcript_entry("msg-1", model="synthetic-test-model",
                                      timestamp=iso_z(SCAN_NOW), input_tokens=0,
                                      output_tokens=1000000, cache_read=0,
                                      cache_write=0)])
        pricing = {"synthetic-test-model": {"input": 0.0, "output": 15.0,
                                            "cache_read": 0.0, "cache_write": 0.0}}
        with mock.patch.dict(claude_usage.PRICING, pricing):
            output = self.run_main(now=SCAN_NOW)
        self.assertIn("$15.00", output)

    def test_unknown_model_gets_geq_prefix(self):
        priced = transcript_entry("msg-priced", model="synthetic-test-model",
                                  timestamp=iso_z(SCAN_NOW), input_tokens=0,
                                  output_tokens=1000000, cache_read=0, cache_write=0)
        unpriced = transcript_entry("msg-unpriced", model="mystery-model-9",
                                    timestamp=iso_z(SCAN_NOW))
        write_jsonl(self.scan_root / "proj" / "sess.jsonl", [priced, unpriced])
        pricing = {"synthetic-test-model": {"input": 0.0, "output": 15.0,
                                            "cache_read": 0.0, "cache_write": 0.0}}
        with mock.patch.dict(claude_usage.PRICING, pricing):
            output = self.run_main(now=SCAN_NOW)
        self.assertIn("≥ $15.00", output)

    def test_all_unpriced_models_renders_na(self):
        write_jsonl(self.scan_root / "proj" / "sess.jsonl",
                    [transcript_entry("msg-1", model="mystery-model-9",
                                      timestamp=iso_z(SCAN_NOW))])
        output = self.run_main(now=SCAN_NOW)
        self.assertIn("cost n/a (unpriced models)", output)


class SecurityTests(ClaudeUsageTestCase):
    def test_token_never_in_output(self):
        received = {}

        def recording_fetcher(token):
            received["token"] = token
            return make_response()

        output = self.run_main(fetcher=recording_fetcher,
                               keychain_reader=lambda: "SECRET123")
        self.assertEqual("SECRET123", received["token"])
        self.assertNotIn("SECRET123", output)


if __name__ == "__main__":
    unittest.main()
