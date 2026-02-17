# Testing Guide

This document explains the testing side of the application, how `npm test` runs, and how the test-related files interact. It is structured by file, then by related code blocks.

**File: `tests/helpers.ts`**
This file builds the in-memory Postgres database used by the tests. It registers missing SQL functions, loads the schema and seed data, and exposes a pg‑compatible pool.

Code block:
```ts
import fs from "fs";
import path from "path";
import { DataType, newDb } from "pg-mem";
```
Explanation:
- `fs` reads `db/schema.sql` and `db/seed.sql` from disk.
- `path` builds cross‑platform file paths.
- `newDb` creates the pg‑mem in‑memory Postgres.
- `DataType` defines SQL types for pg‑mem function registration.

Code block:
```ts
export function createTestPool() {
  const db = newDb({ autoCreateForeignKeyIndices: true });
```
Explanation:
- `createTestPool()` is the single entry point used by every test.
- `newDb(...)` creates an isolated, in‑memory database.
- `autoCreateForeignKeyIndices: true` makes pg‑mem add indexes for FK constraints, which makes queries behave closer to real Postgres.

**String normalization helpers (used by `db/schema.sql`)**
These functions are referenced inside the SQL normalization functions (`ops.normalize_lot_id`, `ops.normalize_label`). pg‑mem doesn’t implement them, so we register JS equivalents.

Code block:
```ts
db.public.registerFunction({
  name: "regexp_replace",
  args: [DataType.text, DataType.text, DataType.text, DataType.text],
  returns: DataType.text,
  implementation: (input: string, pattern: string, replacement: string, flags: string) => {
    const regex = new RegExp(pattern, flags);
    return input.replace(regex, replacement);
  }
});
```
Explanation:
- Registers SQL `regexp_replace(text, text, text, text)`.
- Uses JavaScript `RegExp` to simulate Postgres regex replacement.
- Used to normalize lot IDs and labels (replace patterns, collapse spaces, etc.).

Code block:
```ts
db.public.registerFunction(
  {
    name: "trim",
    args: [DataType.text],
    returns: DataType.text,
    implementation: (input: string | null) => {
      if (input === null || input === undefined) {
        return null;
      }
      return String(input).trim();
    }
  },
  true
);
```
Explanation:
- Registers SQL `trim(text)`.
- Removes leading and trailing whitespace.
- `true` means “replace if already registered.”

Code block:
```ts
db.public.registerFunction(
  {
    name: "upper",
    args: [DataType.text],
    returns: DataType.text,
    implementation: (input: string | null) => {
      if (input === null || input === undefined) {
        return null;
      }
      return String(input).toUpperCase();
    }
  },
  true
);

db.public.registerFunction(
  {
    name: "lower",
    args: [DataType.text],
    returns: DataType.text,
    implementation: (input: string | null) => {
      if (input === null || input === undefined) {
        return null;
      }
      return String(input).toLowerCase();
    }
  },
  true
);
```
Explanation:
- Registers `upper(text)` and `lower(text)` for case normalization.
- Keeps normalization deterministic across test runs.

Code block:
```ts
db.public.registerFunction(
  {
    name: "nullif",
    args: [DataType.text, DataType.text],
    returns: DataType.text,
    implementation: (value: string | null, compare: string | null) => {
      if (value === null || value === undefined) {
        return null;
      }
      if (compare === null || compare === undefined) {
        return value;
      }
      return value === compare ? null : value;
    }
  },
  true
);
```
Explanation:
- Registers SQL `NULLIF(a, b)`.
- Used to convert empty strings to `NULL` after normalization.

**Seed‑file helpers (used by `db/seed.sql`)**
These functions appear in the seed SQL and are not implemented by pg‑mem by default.

Code block:
```ts
db.public.registerFunction(
  {
    name: "now",
    args: [],
    returns: DataType.timestamptz,
    implementation: () => new Date()
  },
  true
);
```
Explanation:
- Implements SQL `now()` returning the current timestamp.
- Used in seed inserts for `created_at` and audit columns.

Code block:
```ts
db.public.registerFunction(
  {
    name: "pg_get_serial_sequence",
    args: [DataType.text, DataType.text],
    returns: DataType.text,
    implementation: (table: string, column: string) => `${table}.${column}`
  },
  true
);
```
Explanation:
- Implements `pg_get_serial_sequence(...)` used by seed to reset sequences.
- Returns a synthetic sequence name string in pg‑mem.

Code block:
```ts
db.public.registerFunction(
  {
    name: "setval",
    args: [DataType.text, DataType.bigint, DataType.bool],
    returns: DataType.bigint,
    implementation: (_sequence: string, value: number) => Number(value)
  },
  true
);
```
Explanation:
- Implements `setval(...)` for sequence resets.
- Returns the provided value so seed SQL completes successfully.

**Week grouping helpers (used by reporting queries)**
These map Postgres `date_trunc('week', ...)` into JavaScript so weekly grouping works in pg‑mem.

Code block:
```ts
db.public.registerFunction({
  name: "date_trunc",
  args: [DataType.text, DataType.timestamp],
  returns: DataType.timestamp,
  implementation: (unit: string, value: Date) => {
    if (unit !== "week") {
      return value;
    }

    const date = new Date(value);
    const utcDay = date.getUTCDay();
    const daysSinceMonday = (utcDay + 6) % 7;

    date.setUTCDate(date.getUTCDate() - daysSinceMonday);
    date.setUTCHours(0, 0, 0, 0);

    return date;
  }
});
```
Explanation:
- Handles `date_trunc('week', timestamp)` for weekly grouping.
- Computes Monday 00:00:00 UTC for the given timestamp.

Code block:
```ts
db.public.registerFunction(
  {
    name: "date_trunc",
    args: [DataType.text, DataType.date],
    returns: DataType.timestamp,
    implementation: (unit: string, value: Date) => {
      if (unit !== "week") {
        return value;
      }

      const date = new Date(value);
      const utcDay = date.getUTCDay();
      const daysSinceMonday = (utcDay + 6) % 7;

      date.setUTCDate(date.getUTCDate() - daysSinceMonday);
      date.setUTCHours(0, 0, 0, 0);

      return date;
    }
  },
  true
);
```
Explanation:
- Handles `date_trunc('week', date)` for weekly grouping.
- Same logic, but for date‑typed inputs.

**Schema + seed loading**
These statements load the schema and seed data into the in‑memory database.

Code block:
```ts
const schemaPath = path.join(__dirname, "..", "db", "schema.sql");
const schemaSql = fs.readFileSync(schemaPath, "utf8");
db.public.none(schemaSql);
```
Explanation:
- Reads and executes `db/schema.sql` inside pg‑mem.
- This creates tables, functions, and constraints in memory.

Code block:
```ts
const seedPath = path.join(__dirname, "..", "db", "seed.sql");
if (fs.existsSync(seedPath)) {
  const seedSql = fs.readFileSync(seedPath, "utf8");
  db.public.none(seedSql);
}
```
Explanation:
- Loads `db/seed.sql` if it exists.
- Populates the in‑memory DB with the standard seed dataset.

**Pool adapter creation**
This creates a pg‑compatible pool so tests can call `pool.query(...)` exactly like production code.

Code block:
```ts
const pg = db.adapters.createPg();
const pool = new pg.Pool();

return { pool, db };
```
Explanation:
- `createPg()` returns a pg‑compatible adapter object.
- `new pg.Pool()` returns a pool with `.query(...)`.
- The pool is returned to the tests so they can call service functions.

**File: `db/seed.sql`**
This file seeds deterministic test data. It is executed by `tests/helpers.ts` after the schema is loaded.

**Reset section**
Code block:
```sql
TRUNCATE TABLE ops.data_quality_flag RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.fact_issue_event RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.fact_shipping_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.fact_production_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.lot_line_assignment RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_issue_type RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_lot RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_part RESTART IDENTITY CASCADE;
TRUNCATE TABLE ops.dim_production_line RESTART IDENTITY CASCADE;
```
Explanation:
- Clears all tables so the seed can be re‑run.
- `RESTART IDENTITY` resets serial keys.
- `CASCADE` removes dependent rows.

**Dimensions section**
Code block:
```sql
INSERT INTO ops.dim_production_line (production_line_key, line_name, line_name_norm)
VALUES
  (1, 'Line 1', ops.normalize_label('Line 1')),
  (2, 'Line 3', ops.normalize_label('Line 3'));

INSERT INTO ops.dim_part (part_key, part_number)
VALUES
  (1, 'PN-100'),
  (2, 'PN-200');

INSERT INTO ops.dim_lot (lot_key, lot_id_norm, part_key, created_at)
VALUES
  (1, ops.normalize_lot_id('LOT 1001'), 1, now()),
  (2, ops.normalize_lot_id(' lot-1002 '), 1, now()),
  (3, ops.normalize_lot_id('L0T_2001'), 2, now()),
  (4, ops.normalize_lot_id('LOT__2002'), 2, now());
```
Explanation:
- Inserts production lines, parts, and lots.
- Uses `normalize_label` and `normalize_lot_id` to ensure consistent identifiers.

**Lot line assignments**
Code block:
```sql
INSERT INTO ops.lot_line_assignment (lot_line_key, lot_key, production_line_key, assigned_at)
VALUES
  (1, 1, 1, now()),
  (2, 2, 1, now()),
  (3, 3, 2, now()),
  (4, 4, 2, now());
```
Explanation:
- Associates each lot with a production line.
- This allows shipping defects to be tied back to a production line.

**Issue types**
Code block:
```sql
INSERT INTO ops.dim_issue_type (issue_type_key, source, issue_label, issue_label_norm)
VALUES
  (1, 'PRODUCTION', 'Scratch', ops.normalize_label('Scratch')),
  (2, 'PRODUCTION', 'Leak', ops.normalize_label('Leak')),
  (3, 'SHIPPING', 'Label mismatch', ops.normalize_label('Label mismatch')),
  (4, 'SHIPPING', 'Damaged box', ops.normalize_label('Damaged box'));
```
Explanation:
- Seeds defect categories for production and shipping.

**Production logs**
Code block:
```sql
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
  (1001, '2026-01-20', 'A', 1, 2, 1, 1000, 980, 10, TRUE,  'Scratch', 'Minor scratches observed', ' lot 1002 ', ' LINE 1 ', now()),
  (1002, '2026-01-27', 'B', 1, 2, 1, 1200, 1190,  5, TRUE,  'Leak',    'Small leak at seal',       'LOT-1002', 'Line 1',   now()),
  (1003, '2026-02-03', 'A', 1, 2, 1, 1100, 1100,  0, FALSE, 'Leak',    'No significant issue',      'LOT 1002', 'line 1',   now()),
  (1004, '2026-02-10', 'B', 2, 3, 2,  900,  870, 20, TRUE,  'Scratch', 'Surface defect trend',      'L0T_2001', 'Line 3',   now()),
  (1099, '2026-02-04', 'A', 1, NULL, NULL, 500, 490, 5, TRUE, 'Scratch', 'Lot ID missing/unmapped', 'LOT-9999', 'Line 1', now()),
  (1101, '2026-01-21', 'A', 1, 1, 1, 800, 790, 0, TRUE, 'Leak', 'Lot seen on Line 1', 'LOT 1001', 'Line 1', now()),
  (1102, '2026-01-22', 'B', 2, 1, 1, 800, 780, 8, TRUE, 'Leak', 'Same lot seen on Line 3 too', 'LOT-1001', 'Line 3', now()),
  (1110, '2026-01-28', 'A', 2, 4, 2, 700, 695, 1, TRUE, NULL, 'Defect label missing', 'LOT__2002', 'Line 3', now());
```
Explanation:
- Inserts production log records with valid, unmatched, conflict, and incomplete cases.
- These support AC5, AC6, and AC8, as well as valid rows for summaries.

**Shipping logs**
Code block:
```sql
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
  (2001, '2026-01-22', 2, 'SO-5001', 'Acme Corp',   'IN', 'UPS',  'BOL-100', '1Z999', 980, 'SHIPPED', 'Label mismatch', 'Relabeled before ship', 'LOT-1002', now()),
  (2002, '2026-02-05', 3, 'SO-5002', 'Beta Supply', 'IL', 'FedEx','BOL-101', '9999',   870, 'HOLD',    'Damaged box',    'Repack required',        'L0T_2001', now()),
  (2100, '2026-02-06', 4, 'SO-5003', 'Gamma LLC',   'WI', 'UPS',  'BOL-102', '1Z888',  695, 'HOLD',    NULL,            'Hold reason not recorded','LOT 2002', now()),
  (2101, '2026-02-07', NULL, 'SO-5004', 'Delta Inc','MI', 'UPS',  'BOL-103', '1Z777',  100, 'HOLD',    'Label mismatch', 'Lot missing/unmapped',   'LOT-8888', now());
```
Explanation:
- Inserts shipping logs with valid, unmatched, and incomplete data.
- `hold_reason` is `NULL` for one row to test AC8.
- `lot_key` is `NULL` for one row to test AC5.

**Issue events**
Code block:
```sql
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
  (3001, 'PRODUCTION', '2026-01-20', date_trunc('week','2026-01-20'::date)::date, 1, 2, 1, 5, 1001, NULL, now()),
  (3002, 'PRODUCTION', '2026-01-27', date_trunc('week','2026-01-27'::date)::date, 1, 2, 2, 2, 1002, NULL, now()),
  (3003, 'PRODUCTION', '2026-02-03', date_trunc('week','2026-02-03'::date)::date, 1, 2, 2, 0, 1003, NULL, now()),
  (3004, 'PRODUCTION', '2026-02-10', date_trunc('week','2026-02-10'::date)::date, 2, 3, 1, 7, 1004, NULL, now()),
  (3101, 'SHIPPING',   '2026-01-22', date_trunc('week','2026-01-22'::date)::date, 1, 2, 3, 3, NULL, 2001, now()),
  (3102, 'SHIPPING',   '2026-02-05', date_trunc('week','2026-02-05'::date)::date, 2, 3, 4, 1, NULL, 2002, now());
```
Explanation:
- Seeds the reportable issue events used by the summary queries.
- Includes a `qty_impacted = 0` row to verify AC7 filtering.

**Data quality flags**
Code block:
```sql
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
  (4001, 'UNMATCHED_LOT_ID', 'PRODUCTION_LOG',
   'Lot ID is missing/unmapped; excluded from totals',
   'lot_id',
   'LOT-9999', ops.normalize_lot_id('LOT-9999'),
   1099, NULL, NULL, now()),
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
  (4004, 'INCOMPLETE_DATA', 'PRODUCTION_LOG',
   'Missing required field(s); excluded from totals',
   'primary_issue',
   'LOT__2002', ops.normalize_lot_id('LOT__2002'),
   1110, NULL, NULL, now()),
  (4005, 'INCOMPLETE_DATA', 'SHIPPING_LOG',
   'Missing required field(s); excluded from totals',
   'hold_reason',
   'LOT 2002', ops.normalize_lot_id('LOT 2002'),
   NULL, 2100, NULL, now()),
  (4006, 'UNMATCHED_LOT_ID', 'SHIPPING_LOG',
   'Lot ID is missing/unmapped; excluded from totals',
   'lot_id',
   'LOT-8888', ops.normalize_lot_id('LOT-8888'),
   NULL, 2101, NULL, now());
```
Explanation:
- Seeds flagged records for unmatched lots, conflicts, and incomplete data.
- These are used by the flag count report (AC12).

**Sequence reset section**
Code block:
```sql
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
```
Explanation:
- Updates serial sequences to avoid key collisions if more data is inserted later.

**File: `src/db/queries.ts`**
This file defines SQL strings used by the reporting services.

**Weekly summary query**
Code block:
```ts
export const WEEKLY_SUMMARY_SQL = `
  SELECT
    ie.week_start_date::date AS week_start_date,
    pl.line_name             AS production_line,
    it.issue_label           AS defect_type,
    SUM(ie.qty_impacted)     AS total_defects
  FROM ops.fact_issue_event ie
  JOIN ops.dim_production_line pl ON pl.production_line_key = ie.production_line_key
  JOIN ops.dim_issue_type it      ON it.issue_type_key      = ie.issue_type_key
  WHERE ie.week_start_date BETWEEN $1 AND $2
    AND ie.qty_impacted > 0
  GROUP BY
    ie.week_start_date::date,
    pl.line_name,
    it.issue_label
  ORDER BY
    ie.week_start_date::date ASC,
    pl.line_name ASC,
    SUM(ie.qty_impacted) DESC;
`;
```
Explanation:
- Aggregates `fact_issue_event` rows into weekly totals.
- Filters out `qty_impacted = 0` (AC7).
- Parameters `$1`, `$2` are the start and end week.

**Weekly detail query**
Code block:
```ts
export const WEEKLY_DETAILS_SQL = `
  SELECT
    ie.week_start_date,
    ie.event_source,
    ie.event_date,
    pl.line_name,
    it.issue_label AS defect_type,
    ie.qty_impacted,
    l.lot_id_norm,
    ie.production_log_key,
    ie.shipping_log_key,
    p.shift,
    p.downtime_minutes,
    p.primary_issue,
    p.supervisor_notes,
    s.ship_status,
    s.hold_reason,
    s.qty_shipped,
    s.shipping_notes
  FROM ops.fact_issue_event ie
  JOIN ops.dim_production_line pl ON pl.production_line_key = ie.production_line_key
  JOIN ops.dim_issue_type it      ON it.issue_type_key      = ie.issue_type_key
  JOIN ops.dim_lot l              ON l.lot_key              = ie.lot_key
  LEFT JOIN ops.fact_production_log p ON p.production_log_key = ie.production_log_key
  LEFT JOIN ops.fact_shipping_log   s ON s.shipping_log_key   = ie.shipping_log_key
  WHERE ie.week_start_date = $1
    AND pl.line_name = $2
    AND it.issue_label = $3
  ORDER BY ie.event_date, l.lot_id_norm;
`;
```
Explanation:
- Returns the underlying records for a weekly summary cell (AC11).
- Uses left joins to bring in optional production or shipping context.

**Flag counts query**
Code block:
```ts
export const FLAG_COUNTS_SQL = `
  WITH dq AS (
    SELECT
      dqf.flag_type,
      COALESCE(p.run_date, s.ship_date)::date AS flag_date
    FROM ops.data_quality_flag dqf
    LEFT JOIN ops.fact_production_log p ON p.production_log_key = dqf.production_log_key
    LEFT JOIN ops.fact_shipping_log   s ON s.shipping_log_key   = dqf.shipping_log_key
    WHERE dqf.flag_type IN ('UNMATCHED_LOT_ID', 'CONFLICT', 'INCOMPLETE_DATA')
  )
  SELECT
    date_trunc('week', dq.flag_date)::date AS week_start_date,
    dq.flag_type,
    COUNT(*) AS flagged_count
  FROM dq
  WHERE dq.flag_date IS NOT NULL
    AND date_trunc('week', dq.flag_date)::date BETWEEN $1 AND $2
  GROUP BY
    date_trunc('week', dq.flag_date)::date,
    dq.flag_type
  ORDER BY
    date_trunc('week', dq.flag_date)::date,
    dq.flag_type;
`;
```
Explanation:
- Aggregates `data_quality_flag` by week and reason (AC12).
- Uses `date_trunc('week', ...)` to align flag counts with report weeks.

**Other query constants**
This file also contains insert, update, and normalization queries used by ingestion services. They are not executed by the current reporting tests but are still part of the module.

**File: `src/services/reportService.ts`**
This file is the service layer that tests call. It runs SQL queries and shapes the responses.

**Weekly summary function**
Code block:
```ts
export async function getWeeklySummary(
  pool: Pool,
  startWeek: string,
  endWeek: string
): Promise<WeeklySummaryRow[]> {
  const result = await pool.query(WEEKLY_SUMMARY_SQL, [startWeek, endWeek]);

  console.log(result);
  return result.rows.map((row) => ({
    week_start_date: row.week_start_date instanceof Date
      ? row.week_start_date.toISOString().slice(0, 10)
      : row.week_start_date,
    production_line: row.production_line,
    defect_type: row.defect_type,
    total_defects: Number(row.total_defects)
  }));
}
```
Explanation:
- Executes the weekly summary SQL with the supplied week range.
- `result` is the raw pg result; `result.rows` is the data array.
- `week_start_date` is normalized to `YYYY-MM-DD` when pg‑mem returns a Date object.
- `total_defects` is cast to a number for stable JSON output.
- `console.log(result)` is currently enabled for debugging.

**Weekly detail function**
Code block:
```ts
export async function getWeeklyDetails(
  pool: Pool,
  weekStart: string,
  productionLine: string,
  defectType: string
): Promise<WeeklyDetailRow[]> {
  const result = await pool.query(WEEKLY_DETAILS_SQL, [weekStart, productionLine, defectType]);

  return result.rows.map((row) => ({
    week_start_date: row.week_start_date,
    event_source: row.event_source,
    event_date: row.event_date,
    line_name: row.line_name,
    defect_type: row.defect_type,
    qty_impacted: Number(row.qty_impacted),
    lot_id_norm: row.lot_id_norm,
    production_log_key: row.production_log_key,
    shipping_log_key: row.shipping_log_key,
    shift: row.shift,
    downtime_minutes: row.downtime_minutes,
    primary_issue: row.primary_issue,
    supervisor_notes: row.supervisor_notes,
    ship_status: row.ship_status,
    hold_reason: row.hold_reason,
    qty_shipped: row.qty_shipped,
    shipping_notes: row.shipping_notes
  }));
}
```
Explanation:
- Runs the detail SQL for a specific week + line + defect type.
- Returns the underlying rows for auditability (AC11).

**Flag count function**
Code block:
```ts
export async function getFlagCounts(
  pool: Pool,
  startWeek: string,
  endWeek: string
): Promise<FlagCountRow[]> {
  const result = await pool.query(FLAG_COUNTS_SQL, [startWeek, endWeek]);

  return result.rows.map((row) => ({
    week_start_date: row.week_start_date instanceof Date
      ? row.week_start_date.toISOString().slice(0, 10)
      : row.week_start_date,
    flag_type: row.flag_type,
    flagged_count: Number(row.flagged_count)
  }));
}
```
Explanation:
- Aggregates flags by week and reason (AC12).
- Normalizes `week_start_date` to a string for stable tests and API output.

**File: `tests/reporting.test.ts`**
This file defines the Jest test cases that validate reporting behavior.

**Imports and shared pool**
Code block:
```ts
import { Pool } from "pg";
import { createTestPool } from "./helpers";
import { getFlagCounts, getWeeklyDetails, getWeeklySummary } from "../src/services/reportService";

let pool: Pool;
```
Explanation:
- Imports the pg `Pool` type for typing.
- Imports the test pool factory and reporting service functions.
- Declares a shared `pool` variable for tests to reuse.

**beforeEach / afterEach**
Code block:
```ts
beforeEach(() => {
  const created = createTestPool();
  pool = created.pool as unknown as Pool;
});

afterEach(async () => {
  if (pool) {
    await pool.end();
  }
});
```
Explanation:
- Each test starts with a fresh in‑memory DB + seed.
- The `as unknown as Pool` cast lets TypeScript accept pg‑mem’s pool as a pg pool.
- `pool.end()` prevents Jest from hanging on open handles.

**Weekly summary test**
Code block:
```ts
test("weekly summary groups by line and defect type and excludes qty 0", async () => {
  const summary = await getWeeklySummary(pool, "2026-01-19", "2026-02-09");

  const scratchRow = summary.find(
    (row) => row.week_start_date === "2026-01-19" && row.production_line === "Line 1" && row.defect_type === "Scratch"
  );
  expect(scratchRow?.total_defects).toBe(5);

  const leakRow = summary.find(
    (row) => row.week_start_date === "2026-02-02" && row.defect_type === "Leak"
  );
  expect(leakRow).toBeUndefined();

  expect(scratchRow?.week_start_date).toBe("2026-01-19");
});
```
Explanation:
- Verifies grouping by week + line + defect type (AC1, AC2).
- Confirms `qty_impacted = 0` rows are excluded (AC7).
- Confirms week format (AC10).

**Weekly detail test**
Code block:
```ts
test("detail view returns underlying records for a summary cell", async () => {
  const details = await getWeeklyDetails(pool, "2026-01-19", "Line 1", "Scratch");

  expect(details.length).toBe(1);

  const hasProductionLog = details.some((row) => row.production_log_key !== null);
  expect(hasProductionLog).toBe(true);
});
```
Explanation:
- Confirms underlying rows exist for a summary value (AC11).
- Uses the seeded `fact_issue_event` row for Scratch on Line 1.

**Flag totals test**
Code block:
```ts
test("flags unmatched, conflict, and incomplete records", async () => {
  const result = await pool.query(
    `SELECT flag_type, COUNT(*) AS count
     FROM ops.data_quality_flag
     GROUP BY flag_type
     ORDER BY flag_type`
  );

  const counts: Record<string, number> = {};
  for (const row of result.rows) {
    counts[row.flag_type] = Number(row.count);
  }

  expect(counts.UNMATCHED_LOT_ID).toBe(2);
  expect(counts.CONFLICT).toBe(2);
  expect(counts.INCOMPLETE_DATA).toBe(2);
});
```
Explanation:
- Confirms the seed produced unmatched, conflict, and incomplete flags (AC5, AC6, AC8).

**Flag counts by week test**
Code block:
```ts
test("flag counts endpoint query groups by week and reason", async () => {
  const flags = await getFlagCounts(pool, "2026-01-19", "2026-02-09");

  const unmatchedRow = flags.find(
    (row) => row.week_start_date === "2026-02-02" && row.flag_type === "UNMATCHED_LOT_ID"
  );
  expect(unmatchedRow?.flagged_count).toBe(2);
});
```
Explanation:
- Confirms the weekly flag count query is correct (AC12).
- Checks that the `2026-02-02` week contains two unmatched‑lot flags.

**Order Of Execution When Running `npm test`**
This is the runtime sequence when you run tests.

1. `npm test` runs the command from `package.json`, which is `jest --runInBand`.
2. Jest loads `jest.config.cjs` and finds test files matching `**/tests/**/*.test.ts`.
3. Jest imports `tests/reporting.test.ts`.
4. The test file imports `createTestPool()` from `tests/helpers.ts` and reporting services from `src/services/reportService.ts`.
5. `beforeEach()` calls `createTestPool()` and creates a fresh in‑memory database.
6. `createTestPool()` registers SQL helper functions, loads `db/schema.sql`, loads `db/seed.sql`, and returns a pg‑mem pool.
7. The test calls `getWeeklySummary`, `getWeeklyDetails`, or `getFlagCounts`.
8. Those service functions run SQL strings defined in `src/db/queries.ts` against the in‑memory pool.
9. The test asserts that the returned results match expectations.
10. `afterEach()` closes the pool to prevent Jest from hanging.

**How The Pieces Correlate**
This is the data flow across files.

1. `tests/helpers.ts` creates the in‑memory DB and loads `db/schema.sql` and `db/seed.sql`.
2. `db/seed.sql` inserts the data that the tests rely on.
3. `tests/reporting.test.ts` calls service functions to read data.
4. `src/services/reportService.ts` runs SQL from `src/db/queries.ts`.
5. The queries aggregate or fetch detail rows from the seeded data and return them to the tests.
