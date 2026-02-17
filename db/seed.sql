-- seed.sql
-- Seeds sample Ops data for weekly summaries + auditability + data quality flags
-- Assumes schema.sql has already been executed successfully.

BEGIN;

-- Make sure we insert into ops by default
SET search_path = ops, public;

-- Clean existing data (safe for re-running seed)
TRUNCATE TABLE ops.data_quality_flag RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.fact_issue_event RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.fact_shipping_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.fact_production_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.lot_line_assignment RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_issue_type RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_lot RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_part RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_production_line RESTART IDENTITY CASCADE;

-- =========================
-- Dimensions (surrogate PKs)
-- =========================

-- Production lines (2 lines)
INSERT INTO ops.dim_production_line (production_line_key, line_name, line_name_norm)
VALUES
  (1, 'Line 1', ops.normalize_label('Line 1')),
  (2, 'Line 3', ops.normalize_label('Line 3'));

-- Parts (2 parts)
INSERT INTO ops.dim_part (part_key, part_number)
VALUES
  (1, 'PN-100'),
  (2, 'PN-200');

-- Lots (4 lots)
INSERT INTO ops.dim_lot (lot_key, lot_id_norm, part_key, created_at)
VALUES
  (1, ops.normalize_lot_id('LOT 1001'), 1, now()),
  (2, ops.normalize_lot_id(' lot-1002 '), 1, now()),
  (3, ops.normalize_lot_id('L0T_2001'), 2, now()),
  (4, ops.normalize_lot_id('LOT__2002'), 2, now());

-- Optional: assign each lot to an expected production line (1:1)
INSERT INTO ops.lot_line_assignment (lot_line_key, lot_key, production_line_key, assigned_at)
VALUES
  (1, 1, 1, now()),
  (2, 2, 1, now()),
  (3, 3, 2, now()),
  (4, 4, 2, now());

-- Defect / issue types (at least 3; we add 4)
INSERT INTO ops.dim_issue_type (issue_type_key, source, issue_label, issue_label_norm)
VALUES
  (1, 'PRODUCTION', 'Scratch', ops.normalize_label('Scratch')),
  (2, 'PRODUCTION', 'Leak', ops.normalize_label('Leak')),
  (3, 'SHIPPING', 'Label mismatch', ops.normalize_label('Label mismatch')),
  (4, 'SHIPPING', 'Damaged box', ops.normalize_label('Damaged box'));

-- ======================
-- Source facts (raw logs)
-- ======================

-- Production log rows (4 good + 1 unmatched + 2 conflict + 1 incomplete)
INSERT INTO ops.fact_production_log (
  production_log_key,
  run_date,
  shift,
  production_line_key,
  lot_key,
  part_key,
  units_planned,
  units_actual,
  downtime_minutes,
  line_issue_flag,
  primary_issue,
  supervisor_notes,
  lot_id_raw,
  production_line_raw,
  inserted_at
)
VALUES
  -- GOOD rows (used in issue_event)
  (1001, '2026-01-20', 'A', 1, 2, 1, 1000, 980, 10, TRUE,  'Scratch', 'Minor scratches observed', ' lot 1002 ', ' LINE 1 ', now()),
  (1002, '2026-01-27', 'B', 1, 2, 1, 1200, 1190,  5, TRUE,  'Leak',    'Small leak at seal',       'LOT-1002', 'Line 1',   now()),
  (1003, '2026-02-03', 'A', 1, 2, 1, 1100, 1100,  0, FALSE, 'Leak',    'No significant issue',      'LOT 1002', 'line 1',   now()),
  (1004, '2026-02-10', 'B', 2, 3, 2,  900,  870, 20, TRUE,  'Scratch', 'Surface defect trend',      'L0T_2001', 'Line 3',   now()),

  -- UNMATCHED LOT (lot_key NULL) -> excluded + flagged (AC5)
  (1099, '2026-02-04', 'A', 1, NULL, NULL, 500, 490, 5, TRUE, 'Scratch', 'Lot ID missing/unmapped', 'LOT-9999', 'Line 1', now()),

  -- CONFLICT: same lot_key=1 appears on multiple production lines (AC6)
  (1101, '2026-01-21', 'A', 1, 1, 1, 800, 790, 0, TRUE, 'Leak', 'Lot seen on Line 1', 'LOT 1001', 'Line 1', now()),
  (1102, '2026-01-22', 'B', 2, 1, 1, 800, 780, 8, TRUE, 'Leak', 'Same lot seen on Line 3 too', 'LOT-1001', 'Line 3', now()),

  -- INCOMPLETE: missing defect label (primary_issue NULL) (AC8)
  (1110, '2026-01-28', 'A', 2, 4, 2, 700, 695, 1, TRUE, NULL, 'Defect label missing', 'LOT__2002', 'Line 3', now());

-- Shipping log rows (2 good + 1 incomplete + 1 unmatched)
INSERT INTO ops.fact_shipping_log (
  shipping_log_key,
  ship_date,
  lot_key,
  sales_order_number,
  customer,
  destination_state,
  carrier,
  bol_number,
  tracking_pro,
  qty_shipped,
  ship_status,
  hold_reason,
  shipping_notes,
  lot_id_raw,
  inserted_at
)
VALUES
  -- GOOD rows (used in issue_event)
  (2001, '2026-01-22', 2, 'SO-5001', 'Acme Corp',   'IN', 'UPS',  'BOL-100', '1Z999', 980, 'SHIPPED', 'Label mismatch', 'Relabeled before ship', 'LOT-1002', now()),
  (2002, '2026-02-05', 3, 'SO-5002', 'Beta Supply', 'IL', 'FedEx','BOL-101', '9999',   870, 'HOLD',    'Damaged box',    'Repack required',        'L0T_2001', now()),

  -- INCOMPLETE: missing defect type label (hold_reason NULL) (AC8)
  (2100, '2026-02-06', 4, 'SO-5003', 'Gamma LLC',   'WI', 'UPS',  'BOL-102', '1Z888',  695, 'HOLD',    NULL,            'Hold reason not recorded','LOT 2002', now()),

  -- UNMATCHED lot id (lot_key NULL) -> excluded + flagged (AC5)
  (2101, '2026-02-07', NULL, 'SO-5004', 'Delta Inc','MI', 'UPS',  'BOL-103', '1Z777',  100, 'HOLD',    'Label mismatch', 'Lot missing/unmapped',   'LOT-8888', now());

-- ==========================================
-- Reportable issue events (weekly reporting)
-- ==========================================
-- Only valid, reportable records go here (AC4/AC8).
-- Qty=0 included to prove AC7 filtering works in queries.

INSERT INTO ops.fact_issue_event (
  issue_event_key,
  event_source,
  event_date,
  week_start_date,
  production_line_key,
  lot_key,
  issue_type_key,
  qty_impacted,
  production_log_key,
  shipping_log_key,
  created_at
)
VALUES
  -- Production-derived events
  (3001, 'PRODUCTION', '2026-01-20', date_trunc('week','2026-01-20'::date)::date, 1, 2, 1, 5, 1001, NULL, now()),
  (3002, 'PRODUCTION', '2026-01-27', date_trunc('week','2026-01-27'::date)::date, 1, 2, 2, 2, 1002, NULL, now()),

  -- qty=0 event (AC7: should be excluded from totals by query filter)
  (3003, 'PRODUCTION', '2026-02-03', date_trunc('week','2026-02-03'::date)::date, 1, 2, 2, 0, 1003, NULL, now()),

  (3004, 'PRODUCTION', '2026-02-10', date_trunc('week','2026-02-10'::date)::date, 2, 3, 1, 7, 1004, NULL, now()),

  -- Shipping-derived events (tied to lots + lines; we assume shipping issues attributable to the lot’s producing line)
  (3101, 'SHIPPING',   '2026-01-22', date_trunc('week','2026-01-22'::date)::date, 1, 2, 3, 3, NULL, 2001, now()),
  (3102, 'SHIPPING',   '2026-02-05', date_trunc('week','2026-02-05'::date)::date, 2, 3, 4, 1, NULL, 2002, now());

-- ==================
-- Data quality flags
-- ==================
-- AC5/AC6/AC8 + AC12 counts

INSERT INTO ops.data_quality_flag (
  data_quality_flag_key,
  flag_type,
  source,
  flag_reason,
  missing_fields,
  lot_id_raw,
  lot_id_norm,
  production_log_key,
  shipping_log_key,
  issue_event_key,
  created_at
)
VALUES
  -- AC5: unmatched / invalid lot in production log
  (4001, 'UNMATCHED_LOT_ID', 'PRODUCTION_LOG',
   'Lot ID is missing/unmapped; excluded from totals',
   'lot_id',
   'LOT-9999', ops.normalize_lot_id('LOT-9999'),
   1099, NULL, NULL, now()),

  -- AC6: conflict (same lot appears across multiple production lines)
  (4002, 'CONFLICT', 'PRODUCTION_LOG',
   'Same Lot ID appears with multiple production lines; excluded until resolved',
   NULL,
   'LOT 1001', ops.normalize_lot_id('LOT 1001'),
   1101, NULL, NULL, now()),
  (4003, 'CONFLICT', 'PRODUCTION_LOG',
   'Same Lot ID appears with multiple production lines; excluded until resolved',
   NULL,
   'LOT-1001', ops.normalize_lot_id('LOT-1001'),
   1102, NULL, NULL, now()),

  -- AC8: incomplete production data (defect label missing)
  (4004, 'INCOMPLETE_DATA', 'PRODUCTION_LOG',
   'Missing required field(s); excluded from totals',
   'primary_issue',
   'LOT__2002', ops.normalize_lot_id('LOT__2002'),
   1110, NULL, NULL, now()),

  -- AC8: incomplete shipping data (defect type label missing)
  (4005, 'INCOMPLETE_DATA', 'SHIPPING_LOG',
   'Missing required field(s); excluded from totals',
   'hold_reason',
   'LOT 2002', ops.normalize_lot_id('LOT 2002'),
   NULL, 2100, NULL, now()),

  -- AC5: unmatched lot in shipping log
  (4006, 'UNMATCHED_LOT_ID', 'SHIPPING_LOG',
   'Lot ID is missing/unmapped; excluded from totals',
   'lot_id',
   'LOT-8888', ops.normalize_lot_id('LOT-8888'),
   NULL, 2101, NULL, now());

-- Fix sequences so future inserts don’t collide with explicit keys
SELECT setval(pg_get_serial_sequence('ops.dim_production_line','production_line_key'),
              (SELECT COALESCE(MAX(production_line_key),1) FROM ops.dim_production_line), true);
SELECT setval(pg_get_serial_sequence('ops.dim_part','part_key'),
              (SELECT COALESCE(MAX(part_key),1) FROM ops.dim_part), true);
SELECT setval(pg_get_serial_sequence('ops.dim_lot','lot_key'),
              (SELECT COALESCE(MAX(lot_key),1) FROM ops.dim_lot), true);
SELECT setval(pg_get_serial_sequence('ops.lot_line_assignment','lot_line_key'),
              (SELECT COALESCE(MAX(lot_line_key),1) FROM ops.lot_line_assignment), true);
SELECT setval(pg_get_serial_sequence('ops.dim_issue_type','issue_type_key'),
              (SELECT COALESCE(MAX(issue_type_key),1) FROM ops.dim_issue_type), true);

SELECT setval(pg_get_serial_sequence('ops.fact_production_log','production_log_key'),
              (SELECT COALESCE(MAX(production_log_key),1) FROM ops.fact_production_log), true);
SELECT setval(pg_get_serial_sequence('ops.fact_shipping_log','shipping_log_key'),
              (SELECT COALESCE(MAX(shipping_log_key),1) FROM ops.fact_shipping_log), true);
SELECT setval(pg_get_serial_sequence('ops.fact_issue_event','issue_event_key'),
              (SELECT COALESCE(MAX(issue_event_key),1) FROM ops.fact_issue_event), true);
SELECT setval(pg_get_serial_sequence('ops.data_quality_flag','data_quality_flag_key'),
              (SELECT COALESCE(MAX(data_quality_flag_key),1) FROM ops.data_quality_flag), true);

COMMIT;
