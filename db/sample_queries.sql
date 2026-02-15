``SELECT
  ie.week_start_date AS week,
  pl.line_name       AS production_line,
  it.issue_label     AS defect_type,
  SUM(ie.qty_impacted) AS total_defects
FROM ops.fact_issue_event ie
JOIN ops.dim_production_line pl ON pl.production_line_id = ie.production_line_id
JOIN ops.dim_issue_type it ON it.issue_type_id = ie.issue_type_id
WHERE ie.qty_impacted > 0                               -- AC7
GROUP BY 1,2,3
ORDER BY 1 DESC, 2, 4 DESC;``
