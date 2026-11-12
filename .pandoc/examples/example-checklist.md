---
title: "Vendor Onboarding Security Checklist"
subtitle: "Complete before a new supplier gets access to systems or data"
category: "Checklist"
author: "Cybertechna LLC"
date: 2026-11-11
version: "1.0"
status: Final
classification: Public
fields: [Vendor, Reviewer, Date]
signoff: [Business owner, Security reviewer]
abstract: |
  Tick each item when evidence is on file. Anything that cannot be ticked needs an owner and a date in the table at the end.
---

# 1. Contract and legal

- [ ] Master agreement signed by an authorized officer
- [ ] Data-processing addendum covers retention, return and deletion
- [x] Breach-notification window is 72 hours or less
- [ ] Right to audit, or an independent report, is in the contract

# 2. Technical review

- [ ] Vendor completed our security questionnaire
  - [ ] SOC 2 Type II or ISO 27001 report received and read
  - [ ] Penetration test summary is less than 12 months old
- [ ] Access is least-privilege and uses single sign-on
- [ ] Data is encrypted in transit and at rest

# 3. Exceptions

| Gap | Risk | Owner | Due | Status |
|---|---|---|---|---|
| No SOC 2 report | Medium | | | |
| MFA not enforced for vendor admins | High | | | |
