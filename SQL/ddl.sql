

-- 837 Claim Header (one row per claim)
CREATE TABLE stg_837_claim_header (
    stg_claim_id        BIGINT       PRIMARY KEY,
    claim_control_num   VARCHAR(30)  NOT NULL,        -- ICN from EDI
    member_external_id  VARCHAR(20)  NOT NULL,        -- member id from source
    provider_npi        VARCHAR(15),                  -- rendering provider NPI
    service_from_dt     DATE,
    service_to_dt       DATE,
    total_charge_amt    NUMERIC(12,2),
    claim_type          VARCHAR(10),                  -- IP/OP/ER/PROF
    ingest_file_name    VARCHAR(100),
    load_batch_id       VARCHAR(40)  NOT NULL,
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- 837 Claim Line (one row per service line)
CREATE TABLE stg_837_claim_line (
    stg_claim_line_id   BIGINT       PRIMARY KEY,
    stg_claim_id        BIGINT       NOT NULL,        -- FK to header (not enforced in staging)
    line_num            SMALLINT     NOT NULL,
    cpt_hcpcs           VARCHAR(10),                  -- procedure code
    icd10_dx            VARCHAR(10),                  -- primary diagnosis on line
    units               NUMERIC(8,2),
    line_charge_amt     NUMERIC(12,2),
    load_batch_id       VARCHAR(40)  NOT NULL,
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- 834 Eligibility (member enrollment file)
CREATE TABLE stg_834_eligibility (
    stg_elig_id         BIGINT       PRIMARY KEY,
    member_external_id  VARCHAR(20)  NOT NULL,
    cov_start_dt        DATE         NOT NULL,
    cov_end_dt          DATE         NOT NULL,
    plan_id             VARCHAR(20),
    product_line        VARCHAR(30),
    ingest_file_name    VARCHAR(100),
    load_batch_id       VARCHAR(40)  NOT NULL,
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- 835 Payment (remittance advice)
CREATE TABLE stg_835_payment (
    stg_payment_id      BIGINT       PRIMARY KEY,
    claim_control_num   VARCHAR(30)  NOT NULL,        -- matches 837 header control num
    paid_dt             DATE,
    paid_amt            NUMERIC(12,2),
    adjustment_amt      NUMERIC(12,2) DEFAULT 0,
    denial_reason_code  VARCHAR(20),                  -- CO-97, PR-1, etc.
    ingest_file_name    VARCHAR(100),
    load_batch_id       VARCHAR(40)  NOT NULL,
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- CURATED TABLES (promoted after passing DQ checks)
-- ---------------------------------------------------------------------------

-- Curated member dimension
CREATE TABLE curated_member_dim (
    member_id           BIGINT       PRIMARY KEY,
    member_external_id  VARCHAR(20)  NOT NULL UNIQUE,
    dob                 DATE,
    sex                 CHAR(1),
    zip3                CHAR(3),
    state               CHAR(2),
    load_batch_id       VARCHAR(40),
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Curated eligibility
CREATE TABLE curated_eligibility (
    eligibility_id      BIGINT       PRIMARY KEY,
    member_id           BIGINT       NOT NULL REFERENCES curated_member_dim(member_id),
    member_external_id  VARCHAR(20)  NOT NULL,
    cov_start_dt        DATE         NOT NULL,
    cov_end_dt          DATE         NOT NULL,
    plan_id             VARCHAR(20),
    product_line        VARCHAR(30),
    load_batch_id       VARCHAR(40),
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Curated medical claim (header)
CREATE TABLE curated_claim_header (
    claim_id            BIGINT       PRIMARY KEY,
    stg_claim_id        BIGINT,                       -- lineage back to staging
    claim_control_num   VARCHAR(30)  NOT NULL,
    member_id           BIGINT       REFERENCES curated_member_dim(member_id),
    member_external_id  VARCHAR(20)  NOT NULL,
    provider_npi        VARCHAR(15),
    service_from_dt     DATE,
    service_to_dt       DATE,
    total_charge_amt    NUMERIC(12,2),
    claim_type          VARCHAR(10),
    load_batch_id       VARCHAR(40),
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Curated claim line
CREATE TABLE curated_claim_line (
    claim_line_id       BIGINT       PRIMARY KEY,
    claim_id            BIGINT       NOT NULL REFERENCES curated_claim_header(claim_id),
    stg_claim_line_id   BIGINT,
    line_num            SMALLINT,
    cpt_hcpcs           VARCHAR(10),
    icd10_dx            VARCHAR(10),
    units               NUMERIC(8,2),
    line_charge_amt     NUMERIC(12,2),
    load_batch_id       VARCHAR(40),
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- Curated payment
CREATE TABLE curated_payment (
    payment_id          BIGINT       PRIMARY KEY,
    claim_id            BIGINT       REFERENCES curated_claim_header(claim_id),
    stg_payment_id      BIGINT,
    claim_control_num   VARCHAR(30),
    paid_dt             DATE,
    paid_amt            NUMERIC(12,2),
    adjustment_amt      NUMERIC(12,2),
    load_batch_id       VARCHAR(40),
    load_dt             TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- DQ RULE ENGINE TABLES
-- ---------------------------------------------------------------------------

-- Rule registry — one row per rule, defined once
CREATE TABLE dq_rule_dim (
    dq_rule_id          VARCHAR(10)  PRIMARY KEY,     -- DQ-01 through DQ-12
    rule_name           VARCHAR(80)  NOT NULL,
    rule_description    TEXT         NOT NULL,
    severity            VARCHAR(10)  NOT NULL CHECK (severity IN ('CRITICAL','HIGH','MEDIUM','LOW')),
    target_table        VARCHAR(60)  NOT NULL,         -- which table this rule checks
    expected_result     VARCHAR(100),                  -- what "pass" looks like
    sql_check_snippet   TEXT                           -- short description of logic
);

-- One row per rule per batch execution
CREATE TABLE dq_result_fact (
    dq_result_id        BIGINT       PRIMARY KEY,
    dq_rule_id          VARCHAR(10)  NOT NULL REFERENCES dq_rule_dim(dq_rule_id),
    load_batch_id       VARCHAR(40)  NOT NULL,
    run_dt              TIMESTAMP    NOT NULL DEFAULT NOW(),
    total_checked       INT,
    failed_count        INT,
    passed_count        INT,
    pass_flag           BOOLEAN      NOT NULL,
    notes               TEXT
);

-- One row per failing record
CREATE TABLE dq_exception_detail (
    exception_id        BIGINT       PRIMARY KEY,
    dq_result_id        BIGINT       NOT NULL REFERENCES dq_result_fact(dq_result_id),
    dq_rule_id          VARCHAR(10)  NOT NULL,
    load_batch_id       VARCHAR(40)  NOT NULL,
    record_key          VARCHAR(60)  NOT NULL,         -- PK of failing record as text
    exception_reason    TEXT         NOT NULL,
    sample_payload      TEXT                           -- JSON snippet for debugging
);

-- Batch-level financial reconciliation summary
CREATE TABLE recon_summary (
    recon_id            BIGINT       PRIMARY KEY,
    load_batch_id       VARCHAR(40)  NOT NULL,
    recon_type          VARCHAR(40)  NOT NULL,         -- ROWCOUNT / FINANCIAL / PAYMENT
    source_value        NUMERIC(16,4),
    target_value        NUMERIC(16,4),
    variance            NUMERIC(16,4),
    tolerance           NUMERIC(16,4),
    within_tolerance    BOOLEAN      NOT NULL,
    run_dt              TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- INDEXES
-- ---------------------------------------------------------------------------

CREATE INDEX idx_stg_header_batch     ON stg_837_claim_header(load_batch_id);
CREATE INDEX idx_stg_header_ccn       ON stg_837_claim_header(claim_control_num);
CREATE INDEX idx_stg_header_member    ON stg_837_claim_header(member_external_id);
CREATE INDEX idx_stg_line_claim       ON stg_837_claim_line(stg_claim_id);
CREATE INDEX idx_stg_elig_member      ON stg_834_eligibility(member_external_id);
CREATE INDEX idx_stg_elig_dates       ON stg_834_eligibility(cov_start_dt, cov_end_dt);
CREATE INDEX idx_stg_pay_ccn          ON stg_835_payment(claim_control_num);
CREATE INDEX idx_dq_result_batch      ON dq_result_fact(load_batch_id);
CREATE INDEX idx_dq_result_rule       ON dq_result_fact(dq_rule_id);
CREATE INDEX idx_dq_excep_result      ON dq_exception_detail(dq_result_id);
CREATE INDEX idx_dq_excep_rule_batch  ON dq_exception_detail(dq_rule_id, load_batch_id);
CREATE INDEX idx_curated_header_ccn   ON curated_claim_header(claim_control_num);
CREATE INDEX idx_curated_header_mbr   ON curated_claim_header(member_external_id);

-- =============================================================================
-- END OF DDL
-- =============================================================================
