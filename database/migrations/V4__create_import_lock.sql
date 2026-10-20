-- V4: technical lock table (NOT business data) preventing two import batches from running concurrently,
-- including across several Mule instances. It holds at most one row (id is constrained to TRUE) and is
-- empty whenever no import is running. A row older than the configured timeout is considered stale.

CREATE TABLE import_lock (
    id         BOOLEAN     NOT NULL DEFAULT TRUE,
    batch_id   UUID        NOT NULL,
    locked_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_import_lock PRIMARY KEY (id),
    CONSTRAINT ck_import_lock_single_row CHECK (id)
);
