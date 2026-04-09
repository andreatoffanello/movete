#!/usr/bin/env python3
"""
Movete — GTFS → JSON pipeline.

Converts any standard GTFS feed into optimized JSON for the Movete transit app.

Usage:
    python pipeline/build.py roma
"""

from __future__ import annotations

import csv
import io
import json
import os
import re
import ssl
import sys
import zipfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen, Request

# --- Paths ---

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent

DAY_NAMES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

# Headsign values that carry no destination meaning for riders.
# When a trip's headsign matches one of these, the pipeline will
# substitute the name of the trip's last stop instead.
GENERIC_HEADSIGNS = {
    "inbound", "outbound", "loop", "cw", "ccw",
    "direction 1", "direction 2", "dir 1", "dir 2",
    "north", "south", "east", "west",
    "clockwise", "counterclockwise",
    "route", "service",
}


def is_generic_headsign(headsign: str) -> bool:
    """Return True if the headsign conveys no useful destination info."""
    return headsign.strip().lower() in GENERIC_HEADSIGNS


# GTFS route_type → transit type string
ROUTE_TYPE_MAP = {
    "0": "tram",
    "1": "metro",
    "2": "rail",
    "3": "bus",
    "4": "ferry",
    "5": "cable_tram",
    "6": "gondola",
    "7": "funicular",
    "11": "trolleybus",
    "12": "monorail",
}


# --- Operator Config ---

def load_operator_config(operator_id: str) -> dict:
    """Load operator config from shared/operators/<id>/config.json."""
    config_path = REPO_ROOT / "shared" / operator_id / "config.json"
    if not config_path.exists():
        print(f"ERROR: Config not found: {config_path}")
        sys.exit(1)
    with open(config_path) as f:
        return json.load(f)


# --- GTFS Loading ---

def load_gtfs_from_dir(gtfs_dir: str) -> dict[str, list[dict]]:
    """Load GTFS from an extracted directory of .txt files."""
    result = {}
    gtfs_path = Path(gtfs_dir)
    for txt_file in gtfs_path.glob("*.txt"):
        key = txt_file.stem
        with open(txt_file, encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            result[key] = list(reader)
    return result


def download_gtfs(url: str) -> dict[str, list[dict]]:
    """Download and parse a GTFS zip file in memory."""
    print(f"  Downloading {url}...")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    req = Request(url, headers={"User-Agent": "TransitKit/1.0"})
    resp = urlopen(req, timeout=120, context=ctx)
    data = resp.read()
    print(f"  Downloaded: {len(data) / 1024:.0f} KB")

    result = {}
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for name in zf.namelist():
            if name.endswith(".txt"):
                key = Path(name).stem
                with zf.open(name) as f:
                    text = f.read().decode("utf-8-sig")
                    reader = csv.DictReader(io.StringIO(text))
                    result[key] = list(reader)
    return result


# --- Utilities ---

def parse_time(t: str) -> tuple[int, int] | None:
    """Parse GTFS time (HH:MM:SS) to (hours, minutes). Handles hours > 24."""
    if not t or not t.strip():
        return None
    parts = t.strip().split(":")
    if len(parts) < 2:
        return None
    return int(parts[0]), int(parts[1])


def time_to_minutes(h: int, m: int) -> int:
    return h * 60 + m


def format_time(h: int, m: int) -> str:
    display_h = h % 24
    return f"{display_h:02d}:{m:02d}"


def build_service_day_map(calendar: list[dict], calendar_dates: list[dict] | None = None) -> dict[str, set[int]]:
    """Map service_id → set of weekdays (0=mon, 6=sun).

    Uses calendar.txt as the primary source for weekly patterns.
    If calendar.txt is empty/missing, falls back to calendar_dates.txt
    by collecting all exception_type=1 dates and inferring weekdays.

    Note: calendar_dates exception_type=2 (removals) are date-specific
    exceptions (holidays, etc.) and do NOT remove the weekday from the
    regular pattern — the app shows the regular weekly schedule.
    """
    day_fields = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    result: dict[str, set[int]] = {}

    for row in calendar:
        sid = row["service_id"]
        days = set()
        for i, field in enumerate(day_fields):
            if row.get(field, "0") == "1":
                days.add(i)
        result[sid] = days

    # Only use calendar_dates as fallback when calendar.txt has no entries
    # or to add service_ids not present in calendar.txt
    if calendar_dates:
        for row in calendar_dates:
            sid = row["service_id"]
            if sid in result:
                continue  # calendar.txt is authoritative for this service_id
            exc_type = row.get("exception_type", "1")
            date_str = row.get("date", "")
            if exc_type == "1" and date_str and len(date_str) == 8:
                try:
                    dt = datetime.strptime(date_str, "%Y%m%d")
                    dow = dt.weekday()
                    if sid not in result:
                        result[sid] = set()
                    result[sid].add(dow)
                except ValueError:
                    pass

    return result


# --- Stop Name Cleanup ---

def clean_stop_name(name: str) -> str:
    """Remove common GTFS data artifacts from stop display names."""
    # Strip parenthetical annotations at end: "(UPDATED)", "(TEMP)", etc.
    # Also handles unclosed variants like "(UPDATED" (malformed GTFS data).
    cleaned = re.sub(r'\s*\([A-Z]+\)?\s*$', '', name.strip())
    # Strip trailing punctuation artifacts
    cleaned = cleaned.strip(' ,;-')
    return cleaned if cleaned else name


# --- Headsign Resolution ---

def build_trip_terminus_map(
    stop_times_raw: list[dict],
    stops_raw: list[dict],
) -> dict[str, str]:
    """Return a mapping of trip_id → name of that trip's last stop.

    Used to replace generic headsigns (e.g. "Inbound") with the actual
    destination stop name so riders know where the vehicle is heading.
    """
    # Build stop_id → stop_name lookup
    stop_name_map: dict[str, str] = {
        s["stop_id"].strip(): clean_stop_name(s.get("stop_name", ""))
        for s in stops_raw
    }

    # Find the last stop_id per trip (highest stop_sequence)
    trip_last: dict[str, tuple[int, str]] = {}  # trip_id → (max_seq, stop_id)
    for st in stop_times_raw:
        tid = st["trip_id"].strip()
        try:
            seq = int(st.get("stop_sequence", 0))
        except (ValueError, TypeError):
            continue
        stop_id = st["stop_id"].strip()
        if tid not in trip_last or seq > trip_last[tid][0]:
            trip_last[tid] = (seq, stop_id)

    return {
        tid: stop_name_map.get(stop_id, "")
        for tid, (_, stop_id) in trip_last.items()
    }


def resolve_headsign(trip_id: str, raw_headsign: str, terminus_map: dict[str, str]) -> str:
    """Return a meaningful headsign for display to riders.

    If *raw_headsign* is empty or a known generic term (e.g. "Inbound",
    "Outbound", "Loop"), substitute the name of the trip's last stop from
    *terminus_map*.  Otherwise return *raw_headsign* unchanged.
    """
    if not raw_headsign or is_generic_headsign(raw_headsign):
        terminus = terminus_map.get(trip_id, "")
        return terminus if terminus else raw_headsign
    return raw_headsign


# --- Stop Parsing & Grouping ---

PLATFORM_RE = re.compile(r'^(.+?)\s+([A-Z]\d+)\s*$')
CORSIA_RE = re.compile(r'^(.+?)\s+(?:CORSIA|BAY|PLATFORM|STOP)\s+([A-Z0-9]+)\s*$', re.IGNORECASE)


def _extract_platform(name: str, overrides: dict[str, str] | None = None) -> tuple[str, str]:
    """Extract base name and platform code from stop name."""
    if overrides and name in overrides:
        return overrides[name], ""

    # Platform pattern: "NAME LETTER+DIGIT" (e.g., "MAIN ST B2")
    m = PLATFORM_RE.match(name)
    if m:
        base = m.group(1).strip()
        if overrides and base in overrides:
            return overrides[base], m.group(2)
        return base, m.group(2)

    # Bay/platform pattern
    m = CORSIA_RE.match(name)
    if m:
        base = m.group(1).strip()
        if overrides and base in overrides:
            return overrides[base], m.group(2)
        return base, m.group(2)

    return name, ""


def _make_station_id(operator_id: str, name: str) -> str:
    """Generate station ID from name: 'Main Street' → 'rfta_main_street'."""
    slug = name.lower()
    slug = slug.replace(".", "").replace("'", "").replace('"', '')
    slug = re.sub(r'[^a-z0-9]+', '_', slug).strip('_')
    return f"{operator_id}_{slug}"


def parse_stops(
    stops_raw: list[dict],
    operator_id: str,
    exclude_patterns: list[str] | None = None,
    terminal_overrides: dict[str, str] | None = None,
) -> tuple[dict, dict]:
    """Parse GTFS stops, grouping platforms into stations with docks."""
    exclude_patterns = exclude_patterns or []

    def is_excluded(name: str) -> bool:
        return any(p.lower() in name.lower() for p in exclude_patterns)

    base_groups: dict[str, list] = defaultdict(list)
    group_display_name: dict[str, str] = {}

    for s in stops_raw:
        name = clean_stop_name(s.get("stop_name", "").strip().strip('"'))
        if not name or is_excluded(name):
            continue

        stop_id = s["stop_id"].strip()
        lat = float(s.get("stop_lat", 0) or 0)
        lng = float(s.get("stop_lon", 0) or 0)

        # Skip stops without coordinates
        if lat == 0 and lng == 0:
            continue

        base_name, platform = _extract_platform(name, terminal_overrides)

        # Normalize ALL CAPS names
        if base_name.isupper() and len(base_name) > 3:
            base_name = base_name.title()

        if terminal_overrides and base_name in terminal_overrides:
            base_name = terminal_overrides[base_name]

        group_key = base_name.lower()
        if group_key not in group_display_name or not group_display_name[group_key][0].isupper():
            group_display_name[group_key] = base_name

        base_groups[group_key].append({
            "stop_id": stop_id,
            "original_name": name,
            "platform": platform,
            "lat": lat,
            "lng": lng,
        })

    stations = {}
    stop_to_station = {}

    for group_key, group in base_groups.items():
        base_name = group_display_name[group_key]
        station_id = _make_station_id(operator_id, base_name)

        avg_lat = sum(s["lat"] for s in group) / len(group)
        avg_lng = sum(s["lng"] for s in group) / len(group)

        docks_info = {}
        for s in group:
            if s["platform"]:
                docks_info[s["stop_id"]] = {
                    "letter": s["platform"],
                    "lat": s["lat"],
                    "lng": s["lng"],
                }

        stations[station_id] = {
            "id": station_id,
            "name": base_name,
            "lat": round(avg_lat, 6),
            "lng": round(avg_lng, 6),
            "pontili": [s["stop_id"] for s in group],
            "docks_info": docks_info,
            "original_names": list(set(s["original_name"] for s in group)),
        }

        for s in group:
            stop_to_station[s["stop_id"]] = station_id
        stop_to_station[station_id] = station_id

    return stations, stop_to_station


# --- Departures ---

def build_departures(
    stop_times: list[dict],
    trips: list[dict],
    routes: list[dict],
    service_day_map: dict[str, set[int]],
    valid_stop_ids: set[str],
    stop_to_station: dict[str, str],
    stations: dict[str, dict],
    terminus_map: dict[str, str] | None = None,
) -> dict:
    """Build departures per stop, grouped by day.

    When *terminus_map* is provided, generic headsigns (e.g. "Inbound",
    "Outbound") are replaced with the name of the trip's last stop.
    """
    trip_index = {t["trip_id"]: t for t in trips}
    route_index = {r["route_id"]: r for r in routes}

    # Find last stop of each trip (to exclude terminal arrivals)
    trip_max_seq: dict[str, int] = {}
    for st in stop_times:
        tid = st["trip_id"].strip()
        seq = int(st.get("stop_sequence", 0))
        if tid not in trip_max_seq or seq > trip_max_seq[tid]:
            trip_max_seq[tid] = seq

    departures = defaultdict(lambda: defaultdict(list))

    for st in stop_times:
        stop_id = st["stop_id"].strip()
        if stop_id not in valid_stop_ids:
            continue

        trip_id = st["trip_id"].strip()
        trip = trip_index.get(trip_id)
        if not trip:
            continue

        # Skip terminal: last stop is an arrival, not a departure
        seq = int(st.get("stop_sequence", 0))
        if seq == trip_max_seq.get(trip_id, -1):
            continue

        dep_time = parse_time(st.get("departure_time", ""))
        if not dep_time:
            continue

        route_id = trip["route_id"]
        route = route_index.get(route_id, {})
        service_id = trip["service_id"]
        days = service_day_map.get(service_id, set())

        route_type_code = route.get("route_type", "3")
        transit_type = ROUTE_TYPE_MAP.get(route_type_code, "bus")

        line_name = route.get("route_short_name", route_id).strip()
        raw_headsign = trip.get("trip_headsign", "").strip().strip('"')
        headsign = (
            resolve_headsign(trip_id, raw_headsign, terminus_map)
            if terminus_map is not None
            else raw_headsign
        )

        color = route.get("route_color", "000000").strip()
        text_color = route.get("route_text_color", "FFFFFF").strip()

        h, m = dep_time
        minutes = time_to_minutes(h, m)
        time_str = format_time(h, m)

        dep_entry = {
            "line": line_name,
            "headsign": headsign,
            "time": time_str,
            "minutes": minutes,
            "color": f"#{color}" if not color.startswith("#") else color,
            "textColor": f"#{text_color}" if not text_color.startswith("#") else text_color,
            "transitType": transit_type,
            "tripId": trip_id,
            "routeId": route_id,
        }

        for day in days:
            departures[stop_id][day].append(dep_entry)

    # Sort by time
    for stop_id in departures:
        for day in departures[stop_id]:
            departures[stop_id][day].sort(key=lambda d: d["minutes"])

    return departures


# --- Shapes & Route Directions ---

def parse_shapes(shapes_raw: list[dict]) -> dict[str, list[list[float]]]:
    """Parse shapes.txt into shape_id → [[lat, lng], ...]."""
    shape_points = defaultdict(list)
    for row in shapes_raw:
        sid = row["shape_id"].strip()
        seq = int(row["shape_pt_sequence"])
        lat = float(row["shape_pt_lat"])
        lon = float(row["shape_pt_lon"])
        shape_points[sid].append((seq, [round(lat, 6), round(lon, 6)]))

    result = {}
    for sid, points in shape_points.items():
        points.sort(key=lambda x: x[0])
        result[sid] = [p[1] for p in points]
    return result


def build_route_directions(
    routes_raw: list[dict],
    trips_raw: list[dict],
    stop_times_raw: list[dict],
    shapes: dict[str, list[list[float]]],
    stop_to_station: dict[str, str],
    stations: dict[str, dict],
) -> dict[str, list[dict]]:
    """For each route, build directions with headsign, stopIds, shape."""
    route_trips = defaultdict(lambda: defaultdict(list))
    for t in trips_raw:
        rid = t["route_id"].strip()
        direction = int(t.get("direction_id", 0))
        route_trips[rid][direction].append(t)

    trip_stop_times = defaultdict(list)
    for st in stop_times_raw:
        tid = st["trip_id"].strip()
        trip_stop_times[tid].append(st)

    result = {}
    for r in routes_raw:
        route_id = r["route_id"].strip()
        directions = []

        for direction_id in sorted(route_trips.get(route_id, {}).keys()):
            trips = route_trips[route_id][direction_id]
            if not trips:
                continue

            # Pick trip with most stops as representative
            best_trip = max(trips, key=lambda t: len(trip_stop_times.get(t["trip_id"], [])))
            trip_id = best_trip["trip_id"]
            headsign = best_trip.get("trip_headsign", "").strip().strip('"')
            shape_id = best_trip.get("shape_id", "").strip()

            stops_for_trip = trip_stop_times.get(trip_id, [])
            stops_for_trip.sort(key=lambda x: int(x.get("stop_sequence", 0)))

            ordered_station_ids = []
            seen = set()
            for st in stops_for_trip:
                stop_id = st["stop_id"].strip()
                station_id = stop_to_station.get(stop_id)
                if station_id and station_id not in seen:
                    seen.add(station_id)
                    ordered_station_ids.append(station_id)

            shape_coords = shapes.get(shape_id, [])
            if not shape_coords and ordered_station_ids:
                shape_coords = [
                    [round(stations[sid]["lat"], 6), round(stations[sid]["lng"], 6)]
                    for sid in ordered_station_ids if sid in stations
                ]

            if ordered_station_ids:
                # Derive a meaningful headsign:
                # - circular route (first raw stop == last raw stop): use route long name
                # - linear route (first != last): use "First Stop → Last Stop"
                # Check circularity on raw stop_ids BEFORE deduplication
                raw_first = stop_to_station.get(stops_for_trip[0]["stop_id"].strip()) if stops_for_trip else None
                raw_last = stop_to_station.get(stops_for_trip[-1]["stop_id"].strip()) if stops_for_trip else None
                first_id = ordered_station_ids[0]
                last_id = ordered_station_ids[-1]
                if raw_first == raw_last:
                    long_name = r.get("route_long_name", "").strip().strip('"')
                    derived_headsign = long_name if long_name else headsign
                else:
                    first_name = stations.get(first_id, {}).get("name", first_id)
                    last_name = stations.get(last_id, {}).get("name", last_id)
                    derived_headsign = f"{first_name} → {last_name}"

                directions.append({
                    "id": direction_id,
                    "headsign": derived_headsign,
                    "stopIds": ordered_station_ids,
                    "shape": shape_coords,
                })

        if directions:
            result[route_id] = directions

    return result


# --- Stop Patterns ---

def build_stop_patterns(
    stop_times_raw: list[dict],
    trips_raw: list[dict],
    stop_to_station: dict[str, str],
) -> tuple[list[list[str]], dict[str, int]]:
    """Build unique stop patterns from GTFS trips."""
    trip_stops: dict[str, list] = defaultdict(list)
    for st in stop_times_raw:
        tid = st["trip_id"].strip()
        seq = int(st.get("stop_sequence", 0))
        stop_id = st["stop_id"].strip()
        station_id = stop_to_station.get(stop_id)
        if station_id:
            trip_stops[tid].append((seq, station_id))

    trip_sequences: dict[str, tuple[str, ...]] = {}
    for tid, stops in trip_stops.items():
        stops.sort(key=lambda x: x[0])
        deduped = []
        prev_sid = None
        for _, sid in stops:
            if sid != prev_sid:
                deduped.append(sid)
                prev_sid = sid
        if deduped:
            trip_sequences[tid] = tuple(deduped)

    pattern_to_idx: dict[tuple[str, ...], int] = {}
    patterns: list[list[str]] = []
    trip_to_pattern: dict[str, int] = {}

    unique_patterns = sorted(set(trip_sequences.values()))
    for idx, pat in enumerate(unique_patterns):
        pattern_to_idx[pat] = idx
        patterns.append(list(pat))

    for tid, seq in trip_sequences.items():
        trip_to_pattern[tid] = pattern_to_idx[seq]

    return patterns, trip_to_pattern


# --- Compact Stop Departures ---

def build_stop_departures(
    station: dict,
    all_departures: dict,
    headsign_index: dict[str, int],
    line_index: dict[str, int],
    trip_to_pattern: dict[str, int] | None = None,
    trip_id_index: dict[str, int] | None = None,
) -> dict[str, list[list]]:
    """Collect departures for a station, group identical days."""
    collected = defaultdict(list)
    docks_info = station.get("docks_info", {})

    for pontile in station["pontili"]:
        if pontile in all_departures:
            dock_letter = docks_info.get(pontile, {}).get("letter", "")
            for day_idx, deps in all_departures[pontile].items():
                if dock_letter:
                    tagged = [{**d, "dock": dock_letter} for d in deps]
                    collected[day_idx].extend(tagged)
                else:
                    collected[day_idx].extend(deps)

    station_id = station["id"]
    if station_id in all_departures:
        for day_idx, deps in all_departures[station_id].items():
            collected[day_idx].extend(deps)

    per_day = {}
    for day_idx in range(7):
        deps = collected.get(day_idx, [])
        seen = set()
        unique = []
        for d in deps:
            key = (d["line"], d["time"], d["headsign"], d.get("dock", ""))
            if key not in seen:
                seen.add(key)
                unique.append(d)
        unique.sort(key=lambda d: d["minutes"])

        compact = []
        for d in unique:
            entry = [d["time"], line_index[d["line"]], headsign_index[d["headsign"]]]
            trip_id = d.get("tripId")
            pattern_idx = trip_to_pattern.get(trip_id) if trip_to_pattern and trip_id else None
            trip_id_idx = trip_id_index.get(trip_id) if trip_id_index and trip_id else None
            dock = d.get("dock", "")
            if trip_id_idx is not None:
                entry.append(dock)
                entry.append(pattern_idx if pattern_idx is not None else -1)
                entry.append(trip_id_idx)
            elif pattern_idx is not None:
                entry.append(dock)
                entry.append(pattern_idx)
            elif dock:
                entry.append(dock)
            compact.append(entry)
        if compact:
            per_day[day_idx] = compact

    # Group days with identical schedules
    def schedule_fingerprint(compact_list: list) -> tuple:
        return tuple(
            tuple(entry[:5]) if len(entry) == 6 else tuple(entry)
            for entry in compact_list
        )

    result = {}
    used = set()
    fingerprints = {d: schedule_fingerprint(per_day[d]) for d in per_day}
    for day_idx in range(7):
        if day_idx in used or day_idx not in per_day:
            continue
        same_days = [day_idx]
        for other in range(day_idx + 1, 7):
            if other not in used and other in fingerprints:
                if fingerprints[day_idx] == fingerprints[other]:
                    same_days.append(other)
        for d in same_days:
            used.add(d)
        key = ",".join(DAY_NAMES[d] for d in same_days)
        result[key] = per_day[day_idx]

    return result


# --- Routes List ---

def build_routes_list(
    routes_raw: list[dict],
    directions: dict[str, list[dict]],
) -> list[dict]:
    """Build route list with directions and transit type."""
    routes = []
    for r in routes_raw:
        route_id = r["route_id"].strip()
        name = r.get("route_short_name", route_id).strip()
        color = r.get("route_color", "000000").strip()
        text_color = r.get("route_text_color", "FFFFFF").strip()
        route_type_code = r.get("route_type", "3")
        transit_type = ROUTE_TYPE_MAP.get(route_type_code, "bus")

        route_dirs = directions.get(route_id, [])

        routes.append({
            "id": route_id,
            "name": name,
            "longName": r.get("route_long_name", "").strip().strip('"'),
            "color": f"#{color}" if not color.startswith("#") else color,
            "textColor": f"#{text_color}" if not text_color.startswith("#") else text_color,
            "transitType": transit_type,
            "route_url": r.get("route_url", "").strip(),
            "directions": route_dirs,
        })
    return routes


# --- Output ---

def build_output(
    operator_config: dict,
    stations: list[dict],
    all_departures: dict,
    routes: list[dict],
    feed: dict,
    patterns: list[list[str]] | None = None,
    trip_to_pattern: dict[str, int] | None = None,
) -> dict:
    """Build the final optimized JSON for the app."""

    # Collect all unique values for indexing
    all_headsigns: set[str] = set()
    all_trip_ids: set[str] = set()
    line_to_route_id: dict[str, str] = {}
    for stop_deps in all_departures.values():
        for day_deps in stop_deps.values():
            for d in day_deps:
                all_headsigns.add(d["headsign"])
                line_to_route_id[d["line"]] = d["routeId"]
                if d.get("tripId"):
                    all_trip_ids.add(d["tripId"])

    headsign_list = sorted(all_headsigns)
    line_name_list = sorted(line_to_route_id.keys())
    route_id_list = [line_to_route_id[name] for name in line_name_list]
    headsign_index = {h: i for i, h in enumerate(headsign_list)}
    line_index = {l: i for i, l in enumerate(line_name_list)}
    trip_id_list = sorted(all_trip_ids)
    trip_id_index = {tid: i for i, tid in enumerate(trip_id_list)}

    print(f"  Unique headsigns: {len(headsign_list)}")
    print(f"  Unique line names: {len(line_name_list)}")
    print(f"  Unique trip IDs: {len(trip_id_list)}")

    # Build stops with indexed departures
    stops_output = []
    for st in stations:
        departures = build_stop_departures(
            st, all_departures, headsign_index, line_index,
            trip_to_pattern, trip_id_index,
        )

        lines_serving = set()
        for day_deps in departures.values():
            for d in day_deps:
                lines_serving.add(line_name_list[d[1]])

        if not departures:
            continue

        # Build per-dock info
        dock_by_letter: dict[str, dict] = {}
        for pontile_id, dock_info in st.get("docks_info", {}).items():
            dock_lines = set()
            if pontile_id in all_departures:
                for day_deps in all_departures[pontile_id].values():
                    for d in day_deps:
                        dock_lines.add(d["line"])
            if not dock_lines:
                continue
            letter = dock_info["letter"]
            if letter in dock_by_letter:
                dock_by_letter[letter]["lines"].update(dock_lines)
            else:
                dock_by_letter[letter] = {
                    "letter": letter,
                    "lat": dock_info["lat"],
                    "lng": dock_info["lng"],
                    "lines": dock_lines,
                }
        docks_output = [
            {**d, "lines": sorted(d["lines"])}
            for d in sorted(dock_by_letter.values(), key=lambda d: d["letter"])
        ]

        stop_entry = {
            "id": st["id"],
            "name": st["name"],
            "lat": st["lat"],
            "lng": st["lng"],
            "lines": sorted(lines_serving),
            "departures": departures,
        }
        if docks_output:
            stop_entry["docks"] = docks_output

        stops_output.append(stop_entry)

    stops_output.sort(key=lambda s: s["name"])

    # Feed info
    feed_info = feed.get("feed_info", [{}])
    feed_end = feed_info[0].get("feed_end_date", "") if feed_info else ""
    agency_info = feed.get("agency", [{}])
    agency_name = agency_info[0].get("agency_name", operator_config.get("name", "")) if agency_info else ""
    agency_url = agency_info[0].get("agency_url", "") if agency_info else ""

    output_dict = {
        "operator": {
            "id": operator_config["id"],
            "name": operator_config.get("name", agency_name),
            "url": operator_config.get("url", agency_url),
        },
        "lastUpdated": datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "validUntil": feed_end,
        "headsigns": headsign_list,
        "lineNames": line_name_list,
        "routeIds": route_id_list,
        "tripIds": trip_id_list,
        "routes": routes,
        "stops": stops_output,
    }

    if patterns is not None:
        output_dict["stopPatterns"] = patterns

    return output_dict


# --- Validation ---

def validate_output(output: dict) -> list[str]:
    """Sanity check on produced data. Returns list of errors."""
    errors = []
    stops = output.get("stops", [])
    routes = output.get("routes", [])

    if len(stops) < 5:
        errors.append(f"CRITICAL: only {len(stops)} stops (expected ≥5)")
    if len(routes) < 1:
        errors.append(f"CRITICAL: only {len(routes)} routes (expected ≥1)")

    total_deps = sum(
        sum(len(deps) for deps in s["departures"].values())
        for s in stops
    )
    if total_deps < 100:
        errors.append(f"CRITICAL: only {total_deps} total departures (expected ≥100)")

    if errors:
        print("\n[VALIDATION ERRORS]")
        for e in errors:
            print(f"  {e}")
    else:
        print("  ✓ Validation OK")

    return errors


# --- Main ---





def main():
    import argparse

    parser = argparse.ArgumentParser(description="Movete GTFS pipeline")
    parser.add_argument("operator_id", nargs="?", default="roma", help="Operator ID (default: roma)")
    args = parser.parse_args()
    operator_id = args.operator_id

    print(f"=== Movete — GTFS → JSON for '{operator_id}' ===\n")

    # 1. Load config
    config = load_operator_config(operator_id)
    print(f"Operator: {config.get('name', operator_id)}")

    # 2. Load GTFS
    gtfs_dir = REPO_ROOT / "data" / operator_id / "gtfs"
    gtfs_url = config.get("gtfs_url")

    if gtfs_dir.exists() and any(gtfs_dir.glob("*.txt")):
        print(f"\n[1/4] Loading GTFS from {gtfs_dir}...")
        feed = load_gtfs_from_dir(str(gtfs_dir))
    elif gtfs_url:
        print(f"\n[1/4] Downloading GTFS from {gtfs_url}...")
        feed = download_gtfs(gtfs_url)
    else:
        print(f"ERROR: No GTFS data found. Place files in {gtfs_dir}/ or set gtfs_url in config.")
        sys.exit(1)

    # 3. Process
    print("\n[2/4] Processing data...")
    service_days = build_service_day_map(
        feed.get("calendar", []),
        feed.get("calendar_dates"),
    )
    stations, stop_to_station = parse_stops(
        feed.get("stops", []),
        operator_id,
        exclude_patterns=config.get("exclude_patterns", []),
        terminal_overrides=config.get("terminal_overrides"),
    )
    valid_stop_ids = set(stop_to_station.keys())

    print(f"  GTFS stops: {len(feed.get('stops', []))}")
    print(f"  Grouped stations: {len(stations)}")

    # Build terminus map so generic headsigns can be replaced with the
    # name of the trip's last stop (e.g. "Inbound" → "ASU Peacock Traffic Circle")
    terminus_map = build_trip_terminus_map(
        feed.get("stop_times", []),
        feed.get("stops", []),
    )

    departures = build_departures(
        feed.get("stop_times", []),
        feed.get("trips", []),
        feed.get("routes", []),
        service_days,
        valid_stop_ids,
        stop_to_station,
        stations,
        terminus_map=terminus_map,
    )

    shapes = parse_shapes(feed.get("shapes", []))
    directions = build_route_directions(
        feed.get("routes", []),
        feed.get("trips", []),
        feed.get("stop_times", []),
        shapes,
        stop_to_station,
        stations,
    )
    routes = build_routes_list(feed.get("routes", []), directions)

    # Count by transit type
    type_counts = defaultdict(int)
    for r in routes:
        type_counts[r["transitType"]] += 1
    for tt, count in sorted(type_counts.items()):
        print(f"  {tt}: {count} routes")

    # Stop patterns
    patterns, trip_to_pattern = build_stop_patterns(
        feed.get("stop_times", []),
        feed.get("trips", []),
        stop_to_station,
    )
    print(f"  Unique stop patterns: {len(patterns)}")

    # 4. Build output
    print("\n[3/4] Building JSON...")
    output = build_output(
        config, list(stations.values()), departures, routes, feed,
        patterns, trip_to_pattern,
    )

    print(f"  Stops with departures: {len(output['stops'])}")
    total_deps = sum(
        sum(len(deps) for deps in s["departures"].values())
        for s in output["stops"]
    )
    print(f"  Total departures: {total_deps}")

    # Validate
    print("\n[3b/4] Validating...")
    validation_errors = validate_output(output)
    if validation_errors:
        print(f"\n✘ BUILD FAILED: {len(validation_errors)} critical errors.")
        sys.exit(1)

    # 5. Save — split output: core.json (small) + per-stop schedules
    print("\n[4/4] Saving (split mode)...")
    output_dir = REPO_ROOT / "output" / operator_id
    output_dir.mkdir(parents=True, exist_ok=True)
    stops_dir = output_dir / "stops"
    stops_dir.mkdir(parents=True, exist_ok=True)

    # Core: stops without departures, routes without shapes
    stops_core = []
    for s in output["stops"]:
        stops_core.append({
            "id": s["id"],
            "name": s["name"],
            "lat": s["lat"],
            "lng": s["lng"],
            "lines": s.get("lines", []),
        })

    # Strip shapes from routes for core (they're huge — 8MB+ for Roma)
    routes_core = []
    for r in output["routes"]:
        route_lite = {k: v for k, v in r.items() if k != "directions"}
        # Keep directions but strip the shape arrays
        dirs_lite = []
        for d in r.get("directions", []):
            dirs_lite.append({k: v for k, v in d.items() if k != "shape"})
        route_lite["directions"] = dirs_lite
        routes_core.append(route_lite)

    core = {
        "operator": output["operator"],
        "lastUpdated": output["lastUpdated"],
        "validUntil": output["validUntil"],
        "headsigns": output["headsigns"],
        "lineNames": output["lineNames"],
        "routeIds": output["routeIds"],
        "routes": routes_core,
        "stops": stops_core,
    }

    core_file = output_dir / "core.json"
    with open(core_file, "w", encoding="utf-8") as f:
        json.dump(core, f, ensure_ascii=False, separators=(",", ":"))
    core_size = core_file.stat().st_size / (1024 * 1024)
    print(f"  {core_file.relative_to(REPO_ROOT)} ({core_size:.1f} MB)")

    # Per-route shapes (on-demand)
    routes_dir = output_dir / "routes"
    routes_dir.mkdir(parents=True, exist_ok=True)
    for r in output["routes"]:
        route_shapes = {
            "id": r["id"],
            "directions": r.get("directions", []),
        }
        route_file = routes_dir / f"{r['id']}.json"
        with open(route_file, "w", encoding="utf-8") as f:
            json.dump(route_shapes, f, ensure_ascii=False, separators=(",", ":"))

    # Per-stop departures
    for s in output["stops"]:
        stop_data = {
            "id": s["id"],
            "departures": s["departures"],
        }
        if "docks" in s:
            stop_data["docks"] = s["docks"]
        stop_file = stops_dir / f"{s['id']}.json"
        with open(stop_file, "w", encoding="utf-8") as f:
            json.dump(stop_data, f, ensure_ascii=False, separators=(",", ":"))

    # Also keep full file for reference
    full_file = output_dir / "schedules.json"
    with open(full_file, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, separators=(",", ":"))
    full_size = full_file.stat().st_size / (1024 * 1024)

    # Stats
    stop_files = list(stops_dir.glob("*.json"))
    stop_sizes = [sf.stat().st_size for sf in stop_files]
    avg_stop_kb = (sum(stop_sizes) / len(stop_sizes)) / 1024 if stop_sizes else 0
    max_stop_kb = max(stop_sizes) / 1024 if stop_sizes else 0

    print(f"  {stops_dir.relative_to(REPO_ROOT)}/ ({len(stop_files)} files)")
    print(f"    avg: {avg_stop_kb:.1f} KB, max: {max_stop_kb:.1f} KB")
    print(f"  {full_file.relative_to(REPO_ROOT)} ({full_size:.1f} MB) [reference]")

    print(f"\n✓ Done! {len(output['stops'])} stops, {len(output['routes'])} routes.")
    print(f"  App downloads core.json ({core_size:.1f} MB) + stop files on demand (~{avg_stop_kb:.0f} KB each)")


if __name__ == "__main__":
    main()
