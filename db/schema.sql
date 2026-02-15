-- PostgreSQL DDL (Corrected): NO business PKs (surrogate *_key only)

CREATE SCHEMA IF NOT EXISTS ops;

-- ============
-- Normalization
-- ============
CREATE OR REPLACE FUNCTION ops.normalize_lot_id(raw TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT NULLIF(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          upper(trim(raw)),
          'L0T', 'LOT', 'g'
        ),
        '[ _]+', '-', 'g'
      ),
      '-{2,}', '-', 'g'
    ),
    ''
  );
$$;

CREATE OR REPLACE FUNCTION ops.normalize_label(raw TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
AS $$
  SELECT NULLIF(regexp_replace(lower(trim(raw)), '\s+', ' ', 'g'), '');
$$;

-- ==========
-- Dimensions
-- ==========

CREATE TABLE IF NOT EXISTS ops.dim_production_line (
  production_line_key BIGSERIAL PRIMARY KEY,         -- surrogate PK
  line_name TEXT NOT NULL,
  line_name_norm TEXT NOT NULL UNIQUE                 -- business identifier (UNIQUE, not PK)
);

CREATE TABLE IF NOT EXISTS ops.dim_part (
  part_key BIGSERIAL PRIMARY KEY,                     -- surrogate PK
  part_number TEXT NOT NULL UNIQUE                    -- business identifier (UNIQUE, not PK)
);

CREATE TABLE IF NOT EXISTS ops.dim_lot (
  lot_key BIGSERIAL PRIMARY KEY,                      -- surrogate PK
  lot_id_norm TEXT NOT NULL UNIQUE,                   -- business identifier (UNIQUE, not PK)
  part_key BIGINT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_lot_part
    FOREIGN KEY (part_key)
    REFERENCES ops.dim_part(part_key)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);

-- Optional but useful: "Which line produced this lot?"
-- (supports tying shipping issues back to a production line for AC1 grouping)
CREATE TABLE IF NOT EXISTS ops.lot_line_assignment (
  lot_line_key BIGSERIAL PRIMARY KEY,                 -- surrogate PK
  lot_key BIGINT NOT NULL UNIQUE,                     -- each lot assigned to one line
  production_line_key BIGINT NOT NULL,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_assign_lot
    FOREIGN KEY (lot_key)
    REFERENCES ops.dim_lot(lot_key)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  CONSTRAINT fk_assign_line
    FOREIGN KEY (production_line_key)
    REFERENCES ops.dim_production_line(production_line_key)
    ON DELETE RESTRICT
    ON UPDATE CASCADE
);

-- Ops “defect type” bucket
CREATE TABLE IF NOT EXISTS ops.dim_issue_type (
  issue_type_key BIGSERIAL PRIMARY KEY,               -- surrogate PK
  source TEXT NOT NULL CHECK (source IN ('PRODUCTION', 'SHIPPING')),
  issue_label TEXT NOT NULL,
  issue_label_norm TEXT NOT NULL,
  CONSTRAINT uq_issue_type UNIQUE (source, issue_label_norm)
);

-- =====================
-- Facts: Source Records
-- =====================

CREATE TABLE IF NOT EXISTS ops.fact_production_log (
  production_log_key BIGSERIAL PRIMARY KEY,           -- surrogate PK

  run_date DATE NOT NULL,
  shift TEXT NULL,

  production_line_key BIGINT NOT NULL,
  lot_key BIGINT NULL,                                -- may be NULL if invalid/unmatched (AC5)
  part_key BIGINT NULL,

  units_planned INT NULL CHECK (units_planned >= 0),
  units_actual  INT NULL CHECK (units_actual  >= 0),
  downtime_minutes INT NULL CHECK (downtime_minutes >= 0),

  line_issue_flag BOOLEAN NULL,
  primary_issue TEXT NULL,
  supervisor_notes TEXT NULL,

  -- raw/audit
  lot_id_raw TEXT NULL,
  production_line_raw TEXT NULL,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT fk_prod_line
    FOREIGN KEY (production_line_key)
    REFERENCES ops.dim_production_line(production_line_key)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT fk_prod_lot
    FOREIGN KEY (lot_key)
    REFERENCES ops.dim_lot(lot_key)
    ON DELETE SET NULL
    ON UPDATE CASCADE,

  CONSTRAINT fk_prod_part
    FOREIGN KEY (part_key)
    REFERENCES ops.dim_part(part_key)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_prod_run_date ON ops.fact_production_log(run_date);
CREATE INDEX IF NOT EXISTS ix_prod_line     ON ops.fact_production_log(production_line_key);
CREATE INDEX IF NOT EXISTS ix_prod_lot      ON ops.fact_production_log(lot_key);

CREATE TABLE IF NOT EXISTS ops.fact_shipping_log (
  shipping_log_key BIGSERIAL PRIMARY KEY,             -- surrogate PK

  ship_date DATE NOT NULL,
  lot_key BIGINT NULL,                                -- may be NULL if invalid/unmatched (AC5)

  sales_order_number TEXT NULL,
  customer TEXT NULL,
  destination_state TEXT NULL,
  carrier TEXT NULL,
  bol_number TEXT NULL,
  tracking_pro TEXT NULL,

  qty_shipped INT NULL CHECK (qty_shipped >= 0),
  ship_status TEXT NULL,
  hold_reason TEXT NULL,
  shipping_notes TEXT NULL,

  -- raw/audit
  lot_id_raw TEXT NULL,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT fk_ship_lot
    FOREIGN KEY (lot_key)
    REFERENCES ops.dim_lot(lot_key)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_ship_date ON ops.fact_shipping_log(ship_date);
CREATE INDEX IF NOT EXISTS ix_ship_lot  ON ops.fact_shipping_log(lot_key);

-- =========================================
-- Fact: Normalized Issue Events (Reporting)
-- =========================================
-- IMPORTANT: This table holds ONLY "reportable" records.
-- Therefore: lot_key and production_line_key are NOT NULL (AC4 + AC8).
-- Invalid/unmatched/conflicts go to ops.data_quality_flag instead.

CREATE TABLE IF NOT EXISTS ops.fact_issue_event (
  issue_event_key BIGSERIAL PRIMARY KEY,              -- surrogate PK

  event_source TEXT NOT NULL CHECK (event_source IN ('PRODUCTION', 'SHIPPING')),
  event_date DATE NOT NULL,
  week_start_date DATE NOT NULL,

  production_line_key BIGINT NOT NULL,
  lot_key BIGINT NOT NULL,
  issue_type_key BIGINT NOT NULL,

  qty_impacted INT NOT NULL DEFAULT 0 CHECK (qty_impacted >= 0),

  -- traceability (AC11)
  production_log_key BIGINT NULL,
  shipping_log_key BIGINT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT fk_issue_line
    FOREIGN KEY (production_line_key)
    REFERENCES ops.dim_production_line(production_line_key)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT fk_issue_lot
    FOREIGN KEY (lot_key)
    REFERENCES ops.dim_lot(lot_key)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT fk_issue_type
    FOREIGN KEY (issue_type_key)
    REFERENCES ops.dim_issue_type(issue_type_key)
    ON DELETE RESTRICT
    ON UPDATE CASCADE,

  CONSTRAINT fk_issue_prod_row
    FOREIGN KEY (production_log_key)
    REFERENCES ops.fact_production_log(production_log_key)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT fk_issue_ship_row
    FOREIGN KEY (shipping_log_key)
    REFERENCES ops.fact_shipping_log(shipping_log_key)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT ck_issue_source_row
    CHECK (
      (event_source = 'PRODUCTION' AND production_log_key IS NOT NULL AND shipping_log_key IS NULL)
      OR
      (event_source = 'SHIPPING' AND shipping_log_key IS NOT NULL AND production_log_key IS NULL)
    )
);

-- prevent duplicate issue rows per source record
CREATE UNIQUE INDEX IF NOT EXISTS uq_issue_from_prod
  ON ops.fact_issue_event(production_log_key)
  WHERE production_log_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_issue_from_ship
  ON ops.fact_issue_event(shipping_log_key)
  WHERE shipping_log_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_issue_week_line_type
  ON ops.fact_issue_event(week_start_date, production_line_key, issue_type_key);

CREATE INDEX IF NOT EXISTS ix_issue_lot ON ops.fact_issue_event(lot_key);

-- ==================
-- Data Quality Flags
-- ==================

CREATE TABLE IF NOT EXISTS ops.data_quality_flag (
  data_quality_flag_key BIGSERIAL PRIMARY KEY,        -- surrogate PK

  flag_type TEXT NOT NULL CHECK (flag_type IN (
    'UNMATCHED_LOT_ID',
    'INVALID_LOT_ID',
    'CONFLICT',
    'INCOMPLETE_DATA'
  )),

  source TEXT NOT NULL CHECK (source IN (
    'PRODUCTION_LOG',
    'SHIPPING_LOG',
    'ISSUE_EVENT'
  )),

  flag_reason TEXT NOT NULL,
  missing_fields TEXT NULL,

  lot_id_raw TEXT NULL,
  lot_id_norm TEXT NULL,

  production_log_key BIGINT NULL,
  shipping_log_key BIGINT NULL,
  issue_event_key BIGINT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT fk_dq_prod
    FOREIGN KEY (production_log_key)
    REFERENCES ops.fact_production_log(production_log_key)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT fk_dq_ship
    FOREIGN KEY (shipping_log_key)
    REFERENCES ops.fact_shipping_log(shipping_log_key)
    ON DELETE CASCADE
    ON UPDATE CASCADE,

  CONSTRAINT fk_dq_issue
    FOREIGN KEY (issue_event_key)
    REFERENCES ops.fact_issue_event(issue_event_key)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS ix_dq_flag_type_date
  ON ops.data_quality_flag(flag_type, created_at);
