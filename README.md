# Project 3 — Healthcare ETL Validation & Data Quality Engine

> **PostgreSQL 15 · Synthetic EDI Data · 12-Rule DQ Engine · End-to-End Pipeline**

A production-style healthcare ETL pipeline built entirely in SQL. Raw EDI files (837 claims, 834 eligibility, 835 payments) land in staging tables and pass through an automated 12-rule data quality engine before promotion to curated tables. Eight categories of deliberate errors are seeded in the 2022 batch to demonstrate real-world failure detection. The 2023 batch is clean — demonstrating the baseline.

Built to demonstrate readiness for **Healthcare Data Analyst**, **ETL Validation Analyst**, and **Claims Data Quality** roles.

---

## Quick Stats

| Metric | Value |
|---|---|
| Platform | PostgreSQL 15 (db<>fiddle) |
| Batches | 2 (BATCH_2022_01 · BATCH_2023_01) |
| Staging claims | 27 headers · 39 lines |
| Staging payments | 22 |
| Staging eligibility spans | 26 |
| DQ rules | 12 (4 CRITICAL · 6 HIGH · 2 MEDIUM) |
| Errors seeded | 8 categories / 13 individual records |
| 2022 rules failing | 12 / 12 |
| 2023 rules failing | 0 / 12 |
| All 5 sanity checks | ✅ PASS |

---

## Repository Structure

```
healthcare-etl-dq-engine/
│
├── sql/
│   ├── 01_ddl.sql                  # Full schema — staging, curated, DQ engine tables
│   ├── 02_synthetic_data.sql       # Synthetic data — 2 batches with seeded errors
│   ├── 03_dq_engine.sql            # 12-rule DQ engine — results + exception logging
│   └── 04_reporting_outputs.sql    # 6 reporting queries + 5 sanity checks
│
├── outputs/
│   ├── query1_dq_dashboard.csv         # All 12 rules × 2 batches — pass/fail/counts
│   ├── query2_dq_pivot.csv             # Side-by-side batch comparison pivot
│   ├── query3_top_exceptions.csv       # All 18 failing records with reason + JSON payload
│   ├── query4_financial_recon.csv      # Rowcount + charge + payment recon per batch
│   ├── query5_exception_count_by_rule.csv  # Remediation priority ranked by failure count
│   ├── query6_batch_health_scorecard.csv   # Daily ops view — overall pass rate per batch
│   └── sanity_checks.csv               # 5 internal validation checks — all 0
│
└── README.md
```

---

## What This Simulates

In a real payer or health system environment, EDI files arrive daily or weekly:

- **837** — Medical claim transactions (header + service lines)
- **834** — Member eligibility enrollment files
- **835** — Remittance advice / payment files

Before any of this data touches downstream analytics or adjudication, a DQ gate checks every record against defined rules. Failures are logged to an exception table for analyst review and routing. Only clean records are promoted to curated tables. This project implements that entire pipeline end-to-end in SQL.

---

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      EDI STAGING LAYER                       │
│  stg_837_claim_header  ──<  stg_837_claim_line              │
│  stg_834_eligibility                                         │
│  stg_835_payment                                             │
└───────────────────────┬─────────────────────────────────────┘
                        │  DQ Gate (12 rules)
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                       DQ ENGINE                              │
│  dq_rule_dim (1) ──< dq_result_fact ──< dq_exception_detail │
│  recon_summary                                               │
└───────────────────────┬─────────────────────────────────────┘
                        │  Clean records only
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                     CURATED LAYER                            │
│  curated_member_dim ──< curated_eligibility                 │
│  curated_member_dim ──< curated_claim_header                │
│                              ──< curated_claim_line         │
│                              ──< curated_payment            │
└─────────────────────────────────────────────────────────────┘
```

---

## DQ Rules (12 Total)

| Rule ID | Rule Name | Severity | What It Catches | 2022 Result | 2023 Result |
|---|---|---|---|---|---|
| DQ-01 | Rowcount Reconciliation | CRITICAL | Staging header count ≠ curated count per batch | ❌ FAIL | ✅ PASS |
| DQ-02 | Financial Reconciliation | CRITICAL | Header total charge ≠ sum of line charges (>$0.01) | ❌ FAIL | ✅ PASS |
| DQ-10 | Member Not Found in Eligibility | CRITICAL | Claim member has no 834 record in eligibility | ❌ FAIL | ✅ PASS |
| DQ-12 | Duplicate Claim Control Numbers | CRITICAL | Same CCN appears >1 time in a batch | ❌ FAIL | ✅ PASS |
| DQ-03 | Orphan Claim Lines | HIGH | Lines with no matching claim header | ❌ FAIL | ✅ PASS |
| DQ-04 | Orphan Payments | HIGH | 835 payments with no matching 837 claim | ❌ FAIL | ✅ PASS |
| DQ-05 | Eligibility Overlap | HIGH | Member has overlapping coverage spans | ❌ FAIL | ✅ PASS |
| DQ-06 | Invalid CPT/HCPCS Format | HIGH | Procedure codes not exactly 5 alphanumeric chars | ❌ FAIL | ✅ PASS |
| DQ-07 | Missing or Invalid NPI | HIGH | Provider NPI null or not 10 numeric digits | ❌ FAIL | ✅ PASS |
| DQ-11 | Invalid ICD-10 Format | HIGH | Dx codes failing `^[A-Z][0-9]{2}...` regex | ❌ FAIL | ✅ PASS |
| DQ-08 | Negative/Zero Charge Amounts | MEDIUM | Charge amounts ≤ 0 | ❌ FAIL | ✅ PASS |
| DQ-09 | Future Service Dates | MEDIUM | service_from_dt > run date | ❌ FAIL | ✅ PASS |

---

## Errors Deliberately Seeded

| Error Type | Record | Rule Triggered | Charge at Risk |
|---|---|---|---|
| NULL provider NPI | CCN-2022-011 | DQ-07 | $4,300 |
| Invalid NPI (6 digits) | CCN-2022-012 | DQ-07 | $3,500 |
| Negative total charge (-$500) | CCN-2022-013 | DQ-08 | $500 |
| Future service date (2027-01-15) | CCN-2022-014 | DQ-09 | $5,100 |
| Member MBR-016 with no eligibility | CCN-2022-015 | DQ-10 | $7,200 |
| Duplicate CCN within batch | CCN-2022-003 (×2) | DQ-12 | $1,800 |
| Header charge $2,500 / lines sum $1,800 | CCN-2022-016 | DQ-02 | $2,500 |
| Invalid CPT codes ("9921" and "99-14") | Lines 6021, 6022 | DQ-06 | — |
| Invalid ICD-10 codes ("XYZ" and "1234") | Lines 6025, 6026 | DQ-11 | — |
| Orphan lines (stg_claim_id=9999) | Lines 6027, 6028 | DQ-03 | — |
| Orphan payments (no matching 837) | CCN-2022-GHOST, GHOST2 | DQ-04 | $2,050 |
| Overlapping eligibility spans | MBR-005 (Jun–Aug overlap) | DQ-05 | — |
| Staging ≠ curated rowcount | BATCH_2022_01 (17 stg / 10 cur) | DQ-01 | $28,600 |

**Total charges blocked from adjudication: $28,600 across 7 rejected claims**

---

## Batch Health Scorecard

| Batch | Rules Checked | Rules Passed | Rules Failed | CRITICAL Failures | HIGH Failures | Overall Pass % |
|---|---|---|---|---|---|---|
| BATCH_2022_01 | 12 | 0 | 12 | 4 | 6 | 0.0% |
| BATCH_2023_01 | 12 | 12 | 0 | 0 | 0 | 100.0% |

---

## Financial Reconciliation Summary

| Batch | Recon Type | Source Value | Target Value | Variance | Status |
|---|---|---|---|---|---|
| BATCH_2022_01 | ROWCOUNT | 17 | 10 | 7 | ❌ FAIL |
| BATCH_2022_01 | FINANCIAL (charges) | $67,150.00 | $38,200.00 | $28,950.00 | ❌ FAIL |
| BATCH_2022_01 | PAYMENT | $46,062.50 | $32,957.50 | $13,105.00 | ❌ FAIL |
| BATCH_2023_01 | ROWCOUNT | 10 | 10 | 0 | ✅ PASS |
| BATCH_2023_01 | FINANCIAL (charges) | $47,200.00 | $47,200.00 | $0.00 | ✅ PASS |
| BATCH_2023_01 | PAYMENT | $40,120.00 | $40,120.00 | $0.00 | ✅ PASS |

---

## Internal Sanity Checks — All Pass

| Check | Description | Expected | Result |
|---|---|---|---|
| Check 1 | Orphan exceptions (no matching result row) | 0 | ✅ 0 |
| Check 2 | Impossible counts (failed > total) | 0 | ✅ 0 |
| Check 3 | Count arithmetic mismatch (failed + passed ≠ total) | 0 | ✅ 0 |
| Check 4 | Inconsistent pass_flag vs failed_count | 0 | ✅ 0 |
| Check 5 | Rules executed for BATCH_2022_01 | 12 | ✅ 12 |

---

## Key Design Patterns

**Rule registry (`dq_rule_dim`)** — All 12 rules are defined in one table with severity, description, target table, and expected result. Adding a new rule means inserting one row, not modifying procedural code. This mirrors production DQ frameworks like Great Expectations and dbt tests.

**Batch-scoped results (`dq_result_fact`)** — Every rule runs per batch, not globally. Results are reproducible and comparable across batches. The `notes` column stores a human-readable summary visible directly in the dashboard without joining to exceptions.

**JSON debug payloads (`dq_exception_detail`)** — The `sample_payload` column stores a JSON snippet of each failing record's key values. In production, downstream systems use this to route exceptions to the right remediation team without requiring raw staging table access.

**Tolerance-based financial recon (`recon_summary`)** — Financial reconciliation uses a configurable tolerance ($0.01 default) rather than requiring exact equality, handling legitimate floating-point precision differences in EDI file parsing.

**DQ rule pattern** — Every rule follows the same three-step structure:
1. CTE to identify failing records
2. `INSERT INTO dq_result_fact` — one summary row per rule per batch with counts and pass_flag
3. `INSERT INTO dq_exception_detail` — one row per failing record with reason and JSON payload

---

## Reporting Queries

| File | Query | Output |
|---|---|---|
| `04_reporting_outputs.sql` | DQ Dashboard | 24 rows: all 12 rules × 2 batches — severity, status, counts, pass% |
| `04_reporting_outputs.sql` | DQ Pivot | 12 rows: rules as rows, batches as columns for side-by-side comparison |
| `04_reporting_outputs.sql` | Top Exceptions | 18 rows: every failing record with reason + JSON debug payload |
| `04_reporting_outputs.sql` | Financial Recon | 6 rows: rowcount + charge + payment reconciliation per batch |
| `04_reporting_outputs.sql` | Exception Count by Rule | 12 rows: ranked by failure count for remediation prioritization |
| `04_reporting_outputs.sql` | Batch Health Scorecard | 2 rows: overall pass rate and CRITICAL/HIGH breakdown per batch |

---

## How to Run

1. Go to [db<>fiddle](https://dbfiddle.uk) → select **PostgreSQL 15**
2. **Left panel (Schema):** Paste `01_ddl.sql` + `02_synthetic_data.sql` → click **Run**
3. **Right panel (Query):** Paste `03_dq_engine.sql` → click **Run**
4. **Right panel (Query):** Paste `04_reporting_outputs.sql` → click **Run**

> All 5 sanity checks at the bottom of `04_reporting_outputs.sql` return 0, confirming the DQ engine is internally consistent.

---

## Bug Fixed in This Version

The original `03_dq_engine.sql` named the DQ-05 eligibility CTE `overlaps` — a **reserved keyword** in PostgreSQL (used for date-range predicate: `(date1, date2) OVERLAPS (date3, date4)`). This caused a parse error that silently killed the entire script, leaving all result tables empty.

**Fix:** Renamed the CTE to `elig_overlaps` and updated all downstream references. The original `02_synthetic_data.sql` also omitted curated table inserts for BATCH_2023_01, causing the 2023 recon to show false FAILs. Both issues are corrected in this repository.

---

## Key Findings

**1. BATCH_2022_01 has 4 CRITICAL failures — would be blocked from promotion in production.**
Rowcount mismatch (17 staging vs 10 curated), financial mismatch on CCN-2022-016 ($700 variance), member MBR-016 with no eligibility record, and duplicate CCN-2022-003. Any single CRITICAL failure would halt the promotion pipeline until remediated.

**2. The ETL promotion gate works — 7 error claims stayed in staging.**
Of 17 staging claims in BATCH_2022_01, only 10 were promoted to curated tables. The 7 rejected claims represent $28,600 in charges that cannot be adjudicated until source data issues are resolved.

**3. BATCH_2023_01 passes all 12 rules cleanly — 10/10 claims promoted.**
The 2023 batch demonstrates the expected clean EDI baseline: valid NPIs, no duplicate CCNs, all members in eligibility, positive charge amounts, historical service dates.

**4. Eligibility overlap on MBR-005 is a real-world enrollment scenario.**
MBR-005 has two Medicare spans overlapping June–August 2022. In production, this triggers a retroactive enrollment correction request to the plan sponsor.

**5. JSON payloads in `dq_exception_detail` eliminate re-querying staging.**
Every exception row stores key field values as a JSON snippet. An analyst can diagnose and route any issue directly from the exception table without touching raw staging data.

---

## Related Projects

- **[Project 1 — Claims Cohort & Medication Adherence SQL Engine](https://github.com/saikumar2608/SQL-Claims-Cohort-Medication-Adherence-SQL-Engine)**
- **[Project 2 — CMS/HEDIS Quality Measures SQL Simulation](https://github.com/saikumar2608/CMS-HEDIS-Quality-Measures-SQL-Simulation)**

Together these three projects form a complete Healthcare SQL Portfolio covering cohort building, HEDIS measure production, and ETL data quality — the three core competencies of a healthcare data analyst.

---

## About

Built as part of a 3-project Healthcare SQL Portfolio targeting Healthcare Data Analyst and Clinical Analytics roles. All data is 100% synthetic. Schema designed for PostgreSQL 15.

**Topics:** `sql` `postgresql` `etl` `data-quality` `healthcare-analytics` `claims-processing` `edi-837` `edi-834` `edi-835` `data-validation` `dq-engine` `reconciliation` `healthcare-data`
