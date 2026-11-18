---
# Document metadata
title: "GLBA Core Compliance Readiness Audit Matrix"
subtitle: "FTC Safeguards Rule readiness for CISOs, Internal Audit and General Counsel"
category: "Compliance Checklist"
author: "Cybertechna LLC"
date: 2026-11-17
version: "1.0"
status: Final
classification: Public
fields: [Organization, Reviewer, Date]
signoff: [Authorized reviewer]
abstract: |
  Document SEC-GLBA-AUD-2026. The FTC Safeguards Rule under GLBA requires administrative, technical and physical
  controls that protect customer Non-Public Personal Information (NPI). This matrix maps your security architecture
  against those expectations before a statutory audit does. Tick each item when evidence is on file.

# Website card (read by publish-resource.py; pandoc ignores it)
resource:
  id: 66e28eb2-3f9c-449e-a32d-7247ca79d7fb
  slug: glba-checklist
  kind: Checklist
  title: "GLBA Core Readiness Audit Matrix"
  card-title: "GLBA Core Readiness Audit Matrix"
  summary: "Evaluate your safeguards, network segmentation and cryptographic workflows against the FTC Safeguards Rule before an audit does it for you."
  cta: "View the checklist"
  order: 30
  live-href: /resources/glba-compliance-checklist

# Output Control
output-file: "../PDFs/cybertechna_glba-core-readiness-audit-matrix.pdf"
---

# 1. Governance and risk management oversight

- [ ] **Designated Program Coordinator.** Formally appoint one or more qualified individuals responsible for maintaining and enforcing the information security program, documented in board minutes or corporate charters.
- [ ] **Comprehensive Written Information Security Program (WISP).** Verify the WISP is current, reflects active production systems, and has been signed off by executive leadership within the trailing 12 months.
- [ ] **Quantified risk assessment documentation.** Produce documented risk assessments that identify internal and external threats to NPI, evaluate current mitigations, and inventory outstanding risks.

# 2. Technical safeguards and NPI isolation

- [ ] **Data inventory and mapping.** Maintain a data ledger that tracks every database, server, file share and third-party SaaS endpoint where consumer financial NPI is processed or archived.
- [ ] **Multi-factor authentication (MFA) enforcement.** Verify MFA is enforced without exception for all internal staff and remote service providers.
- [ ] **Data encryption.** Validate that all customer NPI is encrypted with AES-256 at rest and TLS 1.3 in transit.

# 3. Network segmentation validation

- [ ] **Isolate the customer data environment (CDE).** Enforce firewall rules so the production environment that manages financial NPI is logically isolated.
- [ ] **Strict inbound and outbound access control lists (ACLs).** Audit routing tables quarterly. Block traffic into the NPI segment by default unless it is explicitly authorized.

# 4. Continuous telemetry and penetration audits

- [ ] **Bi-annual third-party penetration testing.** Retain certified documentation that an independent, accredited firm has run full-scale penetration tests within the trailing 6 months.
- [ ] **Automated quarterly vulnerability scanning.** Scan infrastructure every 90 days, with logged metrics showing critical patches deployed within 30 days.

# 5. Vendor governance and offboarding controls

- [ ] **Vendor risk assessment pipeline.** Subject every third-party provider that handles NPI to background review and SOC 2 attestation.
- [ ] **Secure HR-to-IT offboarding.** Enforce automated rules so user profiles and access tokens are deactivated within 2 hours of staff separation.

# Fiduciary declaration

*By executing this matrix, the undersigned corporate officers affirm that the administrative and technical parameters listed here have been verified against active production infrastructure telemetry.*
