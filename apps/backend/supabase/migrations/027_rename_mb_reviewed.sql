-- The completed-task MB stores the task's reviewed/advertised MB (not bytes
-- actually deleted), so rename the column to reflect that.
ALTER TABLE completed_cleanup_tasks RENAME COLUMN mb_cleaned TO mb_reviewed;
