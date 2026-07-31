"""Shared pipeline timing report model (Markdown + HTML v1)."""
from __future__ import annotations

import html
import json
import re
from pathlib import Path
from typing import Any

STAGE_ORDER = ("plan", "implement", "quality", "review", "complete")
SLA_HINT = "40-50 min total (postmortem sla_hints.target_total_min)"


def load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def frontmatter(text: str) -> dict[str, str]:
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def retry_count(stage_doc: dict[str, Any]) -> int:
    events = stage_doc.get("events") or []
    starts = sum(1 for e in events if isinstance(e, dict) and e.get("event") == "start")
    return max(0, starts - 1)


def stage_ms(stages: dict[str, Any], name: str) -> int | None:
    ent = stages.get(name) or {}
    if not isinstance(ent, dict):
        return None
    if ent.get("duration_ms") is not None:
        return int(ent["duration_ms"])
    return None


def merge_quality_ms(stages: dict[str, Any]) -> int | None:
    q = stage_ms(stages, "quality")
    s = stage_ms(stages, "smoke")
    if q is not None and s is not None:
        return q + s
    return q if q is not None else s


def low_value_flags(
    timing: dict[str, Any],
    uvo: dict[str, Any],
    smoke_fm: dict[str, str],
) -> list[str]:
    flags: list[str] = []
    stages = timing.get("stages") or {}
    impl_ms = stage_ms(stages, "implement") or 0
    for step in uvo.get("steps") or []:
        if not isinstance(step, dict):
            continue
        sid = str(step.get("id") or "")
        out = str(step.get("output") or step.get("command") or "")
        if sid == "build" and impl_ms > 0 and ("cache hit" in out.lower() or "skipped" in out.lower()):
            flags.append(
                "R1: UVO build skipped/cache hit — implement wall clock may still include Agent time"
            )
            break
    for key in STAGE_ORDER:
        ent = stages.get(key) or {}
        if not isinstance(ent, dict):
            continue
        events = ent.get("events") or []
        starts = [e for e in events if isinstance(e, dict) and e.get("event") == "start"]
        ends = [e for e in events if isinstance(e, dict) and e.get("event") == "end"]
        if len(starts) >= 2 and not ends:
            flags.append(f"R2: stage `{key}` has {len(starts)} start events without end")
    rev = stages.get("review") or {}
    if isinstance(rev, dict):
        attempt = (rev.get("substeps") or {}).get("attempt") or {}
        if isinstance(attempt, dict) and int(attempt.get("duration_ms") or 0) < 2000:
            flags.append("R3: review.substeps.attempt present with very small duration_ms (fast-fail round)")
    if uvo.get("overall") == "pass":
        flags.append("R4: (manual) cross-check contract-conformance / IQ if present — not auto-evaluated in v0")
    smoke_ms = smoke_fm.get("duration_ms")
    if smoke_ms and uvo.get("smoke_required") is False:
        try:
            if int(smoke_ms) > 60_000:
                flags.append("R5: runtime-smoke duration high but smoke_required=false")
        except ValueError:
            pass
    return flags


def build_report_model(
    *,
    task_id: str,
    git_short_head: str,
    timing: dict[str, Any],
    uvo: dict[str, Any],
    review_run: dict[str, Any],
    smoke_fm: dict[str, str],
) -> dict[str, Any]:
    tz = timing.get("timezone") or "UTC"
    stages = timing.get("stages") or {}
    summary_rows: list[dict[str, Any]] = []
    for stage in STAGE_ORDER:
        ent = stages.get(stage) or {}
        if stage == "quality" and not ent:
            ent = stages.get("smoke") or {}
        ms = merge_quality_ms(stages) if stage == "quality" else stage_ms(stages, stage)
        retries = retry_count(ent) if isinstance(ent, dict) else 0
        notes = ""
        if stage == "quality" and stages.get("smoke") and stages.get("quality"):
            notes = "merged smoke+quality keys"
        elif stage == "quality" and stages.get("smoke") and not stages.get("quality"):
            notes = "from legacy smoke stage key"
        summary_rows.append(
            {
                "stage": stage,
                "wall_ms": ms,
                "sla_hint": SLA_HINT,
                "retries": retries,
                "notes": notes,
            }
        )

    uvo_rows: list[dict[str, Any]] = []
    for step in uvo.get("steps") or []:
        if not isinstance(step, dict):
            continue
        sid = step.get("id", "")
        dur = step.get("duration_ms", "N/A")
        ok = step.get("ok", step.get("pass", ""))
        note = str(step.get("output") or step.get("command") or "")[:80]
        if "skipped" in note.lower() or "cache hit" in note.lower():
            note = (note or "skipped") + " — cache/skip"
        uvo_rows.append({"id": sid, "ms": dur, "pass": ok, "note": note})

    flags = low_value_flags(timing, uvo, smoke_fm)
    return {
        "task_id": task_id,
        "git_short_head": git_short_head,
        "timezone": tz,
        "updated_at_utc": timing.get("updated_at_utc"),
        "schema_version": timing.get("schema_version"),
        "summary_rows": summary_rows,
        "uvo_rows": uvo_rows,
        "uvo_total_ms": uvo.get("duration_ms"),
        "review": {
            "latency_ms": review_run.get("latency_ms", "N/A"),
            "invocation_count": review_run.get("invocation_count", "N/A"),
            "provider": review_run.get("provider", "N/A"),
        },
        "sla_footnote": SLA_HINT,
        "flags": flags,
    }


def render_markdown(model: dict[str, Any]) -> str:
    lines: list[str] = [
        f"# Pipeline timing — {model['task_id']} ({model['git_short_head']})",
        "",
        f"_timezone: {model['timezone']}_",
        "",
        "## Summary",
        "| Stage | Wall ms | SLA hint | Retries | Notes |",
        "|-------|---------|----------|---------|-------|",
    ]
    for row in model["summary_rows"]:
        ms_s = str(row["wall_ms"]) if row["wall_ms"] is not None else "N/A"
        lines.append(
            f"| {row['stage']} | {ms_s} | {row['sla_hint']} | {row['retries']} | {row['notes']} |"
        )

    lines.extend(["", "## UVO (implement gate)", "| Step | ms | Pass | Note |"])
    if model["uvo_rows"]:
        for row in model["uvo_rows"]:
            lines.append(f"| {row['id']} | {row['ms']} | {row['pass']} | {row['note']} |")
    else:
        lines.append("| — | N/A | N/A | no verification-oracle.json steps |")
    if model.get("uvo_total_ms") is not None:
        lines.append("")
        lines.append(f"_UVO total duration_ms: {model['uvo_total_ms']}_")

    rev = model["review"]
    lines.extend(
        [
            "",
            "## Review provenance",
            f"- latency_ms: {rev['latency_ms']}",
            f"- invocations: {rev['invocation_count']}",
            f"- provider: {rev['provider']}",
            "",
            "## Postmortem / SLA",
            f"- Footnote: {model['sla_footnote']}",
            "- Run `pipeline-postmortem.py` for blocked runs (not invoked automatically by this report).",
            "",
            "## Low-value / high-cost flags",
        ]
    )
    for flag in model["flags"]:
        lines.append(f"- [ ] {flag}")
    if not model["flags"]:
        lines.append("- [ ] (none flagged by v0 rules)")
    lines.append("")
    return "\n".join(lines)


def _esc(s: Any) -> str:
    return html.escape(str(s))


def render_html(model: dict[str, Any]) -> str:
    rows_summary = "".join(
        f"<tr><td>{_esc(r['stage'])}</td><td>{_esc(r['wall_ms'] if r['wall_ms'] is not None else 'N/A')}</td>"
        f"<td>{_esc(r['sla_hint'])}</td><td>{_esc(r['retries'])}</td><td>{_esc(r['notes'])}</td></tr>"
        for r in model["summary_rows"]
    )
    if model["uvo_rows"]:
        rows_uvo = "".join(
            f"<tr><td>{_esc(r['id'])}</td><td>{_esc(r['ms'])}</td><td>{_esc(r['pass'])}</td>"
            f"<td>{_esc(r['note'])}</td></tr>"
            for r in model["uvo_rows"]
        )
    else:
        rows_uvo = "<tr><td colspan=\"4\">no verification-oracle.json steps</td></tr>"

    uvo_total = ""
    if model.get("uvo_total_ms") is not None:
        uvo_total = f'<p class="meta">UVO total duration_ms: {_esc(model["uvo_total_ms"])}</p>'

    flag_items = "".join(f"<li><label><input type=\"checkbox\" disabled> {_esc(f)}</label></li>" for f in model["flags"])
    if not model["flags"]:
        flag_items = "<li><label><input type=\"checkbox\" disabled> (none flagged by v0 rules)</label></li>"

    rev = model["review"]
    meta_bits = [
        f"schema_version={_esc(model.get('schema_version', '—'))}",
        f"updated_at_utc={_esc(model.get('updated_at_utc', '—'))}",
    ]
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pipeline timing — {_esc(model['task_id'])}</title>
  <style>
    :root {{ font-family: system-ui, sans-serif; line-height: 1.45; color: #1a1a1a; }}
    body {{ max-width: 960px; margin: 1.5rem auto; padding: 0 1rem; }}
    h1 {{ font-size: 1.35rem; }}
    h2 {{ font-size: 1.1rem; margin-top: 1.5rem; border-bottom: 1px solid #ddd; }}
    table {{ border-collapse: collapse; width: 100%; font-size: 0.9rem; }}
    th, td {{ border: 1px solid #ccc; padding: 0.35rem 0.5rem; text-align: left; }}
    th {{ background: #f4f4f4; }}
    .meta {{ color: #555; font-size: 0.85rem; }}
    section {{ margin-bottom: 1rem; }}
    ul.flags {{ list-style: none; padding-left: 0; }}
  </style>
</head>
<body>
  <header>
    <h1>Pipeline timing — {_esc(model['task_id'])} ({_esc(model['git_short_head'])})</h1>
    <p class="meta">timezone: {_esc(model['timezone'])} · {' · '.join(meta_bits)}</p>
  </header>
  <section id="summary">
    <h2>Summary</h2>
    <table>
      <thead><tr><th>Stage</th><th>Wall ms</th><th>SLA hint</th><th>Retries</th><th>Notes</th></tr></thead>
      <tbody>{rows_summary}</tbody>
    </table>
  </section>
  <section id="uvo">
    <h2>UVO (implement gate)</h2>
    <table>
      <thead><tr><th>Step</th><th>ms</th><th>Pass</th><th>Note</th></tr></thead>
      <tbody>{rows_uvo}</tbody>
    </table>
    {uvo_total}
  </section>
  <section id="review-provenance">
    <h2>Review provenance</h2>
    <ul>
      <li>latency_ms: {_esc(rev['latency_ms'])}</li>
      <li>invocations: {_esc(rev['invocation_count'])}</li>
      <li>provider: {_esc(rev['provider'])}</li>
    </ul>
  </section>
  <section id="postmortem-sla">
    <h2>Postmortem / SLA</h2>
    <ul>
      <li>Footnote: {_esc(model['sla_footnote'])}</li>
      <li>Run <code>pipeline-postmortem.py</code> for blocked runs (not invoked automatically).</li>
    </ul>
  </section>
  <section id="low-value-flags">
    <h2>Low-value / high-cost flags</h2>
    <ul class="flags">{flag_items}</ul>
  </section>
</body>
</html>
"""
