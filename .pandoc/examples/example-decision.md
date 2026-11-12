---
title: "Choose a Managed Detection and Response Provider"
subtitle: "Decision record for the vendor selection, with the options considered and why we chose Option B"
author: ["Kevin Robinson"]
owner: "Security Lead"
audience: "Executive team"
date: 2026-11-11
due-date: 2026-11-25
status: Proposed
version: "0.2"
classification: Internal
decision: |
  **Recommend Option B.** Contract a 24x7 managed detection and response provider for 12 months with a 90-day exit clause.
abstract: |
  We have no after-hours monitoring. Two incidents in the last year were found by users, not by tooling.
  This record compares three ways to close the gap.
---

# Context

We monitor business-hours alerts in-house. The gap is **nights and weekends**, which is when ransomware operators prefer to start.

# Options considered

| Option | Annual cost | Coverage | Time to value | Main risk |
|---|---|---|---|---|
| **A.** Hire two analysts | \$310,000 | Business hours plus on-call | 6 to 9 months | Hiring and retention |
| **B.** Managed provider (24x7) | \$96,000 | Full, with 15-minute triage | 4 to 6 weeks | Vendor lock-in |
| **C.** Do nothing | \$0 | Business hours only | None | Undetected weekend incident |
: Options compared on cost, coverage and risk

## Scoring

| Criterion | Weight | A | B | C |
|---|---|---|---|---|
| Coverage | 35% | 3 | 5 | 1 |
| Cost | 25% | 1 | 4 | 5 |
| Speed | 20% | 1 | 4 | 5 |
| Staff load | 20% | 2 | 4 | 3 |
| **Weighted score** | | **2.0** | **4.4** | **2.9** |

# Risk register

Seven columns is too wide for a portrait page, so this table moves to its own landscape page automatically,
together with its heading and this paragraph.

| ID | Risk | Likelihood | Impact | Owner | Mitigation | Review date |
|---|---|---|---|---|---|---|
| R1 | Provider outage during an active incident | Low | High | Security Lead | Keep in-house runbook and a secondary escalation path | 2027-02-01 |
| R2 | Logs not ingested, so detections never fire | Medium | High | Platform Lead | Proof of value must show every source reporting | 2026-12-15 |
| R3 | Analyst alert fatigue from noisy rules | Medium | Medium | Security Lead | Tune rules weekly for the first 90 days | 2027-01-15 |
| R4 | Contract lock-in beyond the first term | Low | Medium | Procurement | 90-day exit clause and data-export terms | 2026-12-01 |
: Risk register for the provider decision

# Decision

::: note
Option B costs less than a third of Option A and is live inside six weeks. The exit clause limits lock-in.
:::

### Next steps

1. Legal reviews the data-processing terms.
2. Security completes a 30-day proof of value.
3. Finance approves the annual budget line.

::: {.warning title="Open items"}
[CONFIRM] whether the provider can ingest our cloud logs without a new collector.
:::
