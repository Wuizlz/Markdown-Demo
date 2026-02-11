# Data Entities & Relationships (Ops User Story + ACs)

This data model supports the Operations need to generate **weekly summaries of issues by Production Line and Defect Type**, using **Lot ID** as the cross-file join key, and enforcing AC rules like **excluding Qty Defects = 0** and flagging **Insufficient Data**.

---

## Entities

### 1) ProductionLine
Represents a physical production line.
- **production_line_id** (PK)
- line_name

### 2) Part
Represents the item being produced.
- **part_number** (PK)

### 3) Lot
Represents a lot/batch identifier used across production, quality, and shipping logs.
- **lot_id** (PK)
- part_number (FK → Part.part_number)

### 4) ProductionRun
Represents a production log entry (a run/shift/day entry tied to a lot + line).
- **production_run_id** (PK)
- run_date
- shift
- production_line_id (FK → ProductionLine.production_line_id)
- lot_id (FK → Lot.lot_id)
- part_number (FK → Part.part_number) *(often redundant but present in logs)*
- units_planned
- units_actual
- downtime_minutes
- line_issue_flag
- primary_issue
- supervisor_notes
- week_start_date *(derived from run_date for weekly reporting)*

### 5) DefectType
Represents a standardized defect category (what Ops groups by).
- **defect_code** (PK)
- defect_description

### 6) InspectionResult
Represents a quality inspection record (often one row per defect code finding).
- **inspection_result_id** (PK)
- inspection_date
- inspection_time
- inspector_name
- production_line_id (FK → ProductionLine.production_line_id)
- lot_id (FK → Lot.lot_id)
- part_number (FK → Part.part_number)
- defect_code (FK → DefectType.defect_code)
- severity
- qty_checked
- qty_defects
- disposition
- notes
- week_start_date *(derived from inspection_date for weekly reporting)*

> Ops weekly defect totals typically use `InspectionResult.qty_defects`, excluding rows where `qty_defects = 0` (per AC).

### 7) Shipment
Represents a shipping log entry for a lot.
- **shipment_id** (PK)
- ship_date
- lot_id (FK → Lot.lot_id)
- sales_order_number
- customer
- destination_state
- carrier
- bol_number
- tracking_pro
- qty_shipped
- ship_status
- hold_reason
- shipping_notes
- week_start_date *(derived from ship_date, if weekly shipping views are needed)*

### 8) DataQualityFlag
Captures records that should not be counted due to **Insufficient Data** / invalid joins.
- **data_quality_flag_id** (PK)
- flag_type *(e.g., INSUFFICIENT_DATA, INVALID_LOT_ID)*
- flag_reason *(plain English reason)*
- source_system *(Production / Inspection / Shipping)*
- missing_fields *(optional text list)*
- created_at
- production_run_id (nullable FK → ProductionRun.production_run_id)
- inspection_result_id (nullable FK → InspectionResult.inspection_result_id)
- shipment_id (nullable FK → Shipment.shipment_id)

---

## Relationships (Summary)
- A **ProductionLine** has many **ProductionRuns** and many **InspectionResults**
- A **Lot** belongs to one **Part**, and can have many **ProductionRuns**, **InspectionResults**, and **Shipments**
- A **DefectType** has many **InspectionResults**
- A **DataQualityFlag** can be attached to a ProductionRun **or** InspectionResult **or** Shipment

---

# Mermaid ERD (mermaid.js)

```mermaid
erDiagram
    PRODUCTION_LINE ||--o{ PRODUCTION_RUN : has
    LOT ||--o{ PRODUCTION_RUN : produced_as
    PART ||--o{ LOT : includes
    PRODUCTION_LINE ||--o{ INSPECTION_RESULT : inspected_on
    LOT ||--o{ INSPECTION_RESULT : inspected
    DEFECT_TYPE ||--o{ INSPECTION_RESULT : categorizes
    LOT ||--o{ SHIPMENT : ships

    PRODUCTION_RUN ||--o{ DATA_QUALITY_FLAG : flagged_by
    INSPECTION_RESULT ||--o{ DATA_QUALITY_FLAG : flagged_by
    SHIPMENT ||--o{ DATA_QUALITY_FLAG : flagged_by

    PRODUCTION_LINE {
      string production_line_id PK
      string line_name
    }

    PART {
      string part_number PK
    }

    LOT {
      string lot_id PK
      string part_number FK
    }

    PRODUCTION_RUN {
      int production_run_id PK
      date run_date
      string shift
      string production_line_id FK
      string lot_id FK
      string part_number FK
      int units_planned
      int units_actual
      int downtime_minutes
      boolean line_issue_flag
      string primary_issue
      string supervisor_notes
      date week_start_date
    }

    DEFECT_TYPE {
      string defect_code PK
      string defect_description
    }

    INSPECTION_RESULT {
      int inspection_result_id PK
      date inspection_date
      string inspection_time
      string inspector_name
      string production_line_id FK
      string lot_id FK
      string part_number FK
      string defect_code FK
      string severity
      int qty_checked
      int qty_defects
      string disposition
      string notes
      date week_start_date
    }

    SHIPMENT {
      int shipment_id PK
      date ship_date
      string lot_id FK
      string sales_order_number
      string customer
      string destination_state
      string carrier
      string bol_number
      string tracking_pro
      int qty_shipped
      string ship_status
      string hold_reason
      string shipping_notes
      date week_start_date
    }

    DATA_QUALITY_FLAG {
      int data_quality_flag_id PK
      string flag_type
      string flag_reason
      string source_system
      string missing_fields
      datetime created_at
      int production_run_id FK
      int inspection_result_id FK
      int shipment_id FK
    }

