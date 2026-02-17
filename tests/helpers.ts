/**
 * Test helpers for setting up an in-memory Postgres instance.
 *
 * Uses pg-mem so tests run without an external database.
 */

import fs from "fs";
import path from "path";
import { DataType, newDb } from "pg-mem";

/**
 * Create a pg-mem database preloaded with the schema.sql file.
 *
 * Time complexity: O(n) in the size of the schema file.
 * Space complexity: O(n) for the in-memory schema structures.
 */
export function createTestPool() {
  // Initialize a new in-memory Postgres instance.
  const db = newDb({ autoCreateForeignKeyIndices: true });

  // Register regexp_replace used by normalization functions in schema.sql.
  db.public.registerFunction({
    name: "regexp_replace",
    args: [DataType.text, DataType.text, DataType.text, DataType.text],
    returns: DataType.text,
    implementation: (input: string, pattern: string, replacement: string, flags: string) => {
      // Convert Postgres-style flags to JS regex flags.
      const regex = new RegExp(pattern, flags);
      return input.replace(regex, replacement);
    }
  });

  // Register trim to support normalize_lot_id/normalize_label.
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

  // Register upper/lower to keep normalization deterministic in pg-mem.
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

  // Register nullif used in normalize_lot_id/normalize_label.
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

  // Register now() to mimic Postgres current timestamp.
  db.public.registerFunction(
    {
      name: "now",
      args: [],
      returns: DataType.timestamptz,
      implementation: () => new Date()
    },
    true
  );

  // Register pg_get_serial_sequence used by seed.sql.
  db.public.registerFunction(
    {
      name: "pg_get_serial_sequence",
      args: [DataType.text, DataType.text],
      returns: DataType.text,
      implementation: (table: string, column: string) => `${table}.${column}`
    },
    true
  );

  // Register setval used by seed.sql sequence resets.
  db.public.registerFunction(
    {
      name: "setval",
      args: [DataType.text, DataType.bigint, DataType.bool],
      returns: DataType.bigint,
      implementation: (_sequence: string, value: number) => Number(value)
    },
    true
  );

  // Register date_trunc for week calculations in reporting queries.
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

  // Register date_trunc overload for date inputs.
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

  // Load the database schema from db/schema.sql.
  const schemaPath = path.join(__dirname, "..", "db", "schema.sql");
  const schemaSql = fs.readFileSync(schemaPath, "utf8");
  db.public.none(schemaSql);

  // Load seed data when available to populate the in-memory DB for tests.
  const seedPath = path.join(__dirname, "..", "db", "seed.sql");
  if (fs.existsSync(seedPath)) {
    const seedSql = fs.readFileSync(seedPath, "utf8");
    db.public.none(seedSql);
  }

  // Create a pg-compatible pool adapter for the in-memory DB.
  const pg = db.adapters.createPg();
  const pool = new pg.Pool();

  return { pool, db };
}
