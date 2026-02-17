/**
 * End-to-end service tests for the weekly reporting workflow.
 *
 * These tests validate the acceptance criteria using an in-memory DB.
 */

import { Pool } from "pg";
import { createTestPool } from "./helpers";
import { getFlagCounts, getWeeklyDetails, getWeeklySummary } from "../src/services/reportService";

// Shared pool instance for each test suite.
let pool: Pool;

beforeEach(() => {
  // Recreate a fresh in-memory DB per test for isolation.
  const created = createTestPool();
  pool = created.pool as unknown as Pool;
});

afterEach(async () => {
  // Close the pool to avoid open handles in Jest.
  if (pool) {
    await pool.end();
  }
});

test("weekly summary groups by line and defect type and excludes qty 0", async () => {
  // Query the weekly summary across the seeded weeks.
  const summary = await getWeeklySummary(pool, "2026-01-19", "2026-02-09");

  // Expect a Scratch row for Line 1 on the first week.
  const scratchRow = summary.find(
    (row) => row.week_start_date === "2026-01-19" && row.production_line === "Line 1" && row.defect_type === "Scratch"
  );
  expect(scratchRow?.total_defects).toBe(5);

  // Ensure qty=0 events are excluded (Leak on 2026-02-02).
  const leakRow = summary.find(
    (row) => row.week_start_date === "2026-02-02" && row.defect_type === "Leak"
  );
  expect(leakRow).toBeUndefined();

  // Ensure the week format is consistent (AC10).
  expect(scratchRow?.week_start_date).toBe("2026-01-19");
});

test("detail view returns underlying records for a summary cell", async () => {
  // Fetch detail records for the Scratch defects on Line 1.
  const details = await getWeeklyDetails(pool, "2026-01-19", "Line 1", "Scratch");

  // Expect one detail record matching the Scratch issue type.
  expect(details.length).toBe(1);

  // Validate traceability fields exist (AC11).
  const hasProductionLog = details.some((row) => row.production_log_key !== null);
  expect(hasProductionLog).toBe(true);
});

test("flags unmatched, conflict, and incomplete records", async () => {
  // Aggregate flags directly to verify counts.
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

test("flag counts endpoint query groups by week and reason", async () => {
  // Use the service query to fetch flag counts.
  const flags = await getFlagCounts(pool, "2026-01-19", "2026-02-09");

  // Expect the 2026-02-02 week to contain two unmatched lots.
  const unmatchedRow = flags.find(
    (row) => row.week_start_date === "2026-02-02" && row.flag_type === "UNMATCHED_LOT_ID"
  );
  expect(unmatchedRow?.flagged_count).toBe(2);
});
