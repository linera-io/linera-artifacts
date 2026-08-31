#!/usr/bin/env python3
"""Assert every `job` selector in the rule files names a real scrape job.

`promtool check rules` validates syntax, so it passes happily on a rule that
selects a job nobody scrapes — the rule is then silently dead. Every alert in
alerts.rules.yaml was dead this way: the rules said `job="shards"` while
prometheus.yaml has scraped `linera-shard` since it was written.
"""

import re
import sys
from pathlib import Path

import yaml

DOCKER = Path(__file__).resolve().parent.parent / "docker"
SCRAPE_CONFIG = DOCKER / "prometheus.yaml"
RULE_FILES = [DOCKER / "alerts.rules.yaml", DOCKER / "recording.rules.yaml"]

# job="x", job!="x", job=~"a|b", job!~"a|b" — capture operator and value.
JOB_SELECTOR = re.compile(r'job\s*(=~|!~|=|!=)\s*"([^"]*)"')


def scraped_jobs() -> set[str]:
    config = yaml.safe_load(SCRAPE_CONFIG.read_text())
    return {c["job_name"] for c in config.get("scrape_configs", [])}


def rule_expressions(path: Path):
    document = yaml.safe_load(path.read_text())
    for group in document.get("groups", []):
        for rule in group.get("rules", []):
            yield rule.get("alert") or rule.get("record"), rule["expr"]


def main() -> int:
    jobs = scraped_jobs()
    failures = []

    for path in RULE_FILES:
        for name, expr in rule_expressions(path):
            for operator, value in JOB_SELECTOR.findall(expr):
                # Negative matchers exclude jobs; naming an absent one is
                # harmless, so only positive matchers have to resolve.
                if operator in ("!=", "!~"):
                    continue
                # PromQL anchors =~ against the whole label value, which is
                # what fullmatch gives us. A selector is dead when no scraped
                # job satisfies it.
                if operator == "=~":
                    matched = any(re.fullmatch(value, job) for job in jobs)
                else:
                    matched = value in jobs
                if not matched:
                    failures.append(
                        f'{path.name}: {name} selects job {operator}"{value}", '
                        f"which no job in {SCRAPE_CONFIG.name} satisfies"
                    )

    if failures:
        print("::error::rule job selectors do not match the scrape config")
        for failure in failures:
            print(f"  {failure}")
        print(f"\nscraped jobs: {sorted(jobs)}")
        return 1

    print(f"all rule job selectors resolve against {sorted(jobs)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
