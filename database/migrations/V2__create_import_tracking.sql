-- V2: import traceability (import_runs, import_errors). No business data is inserted.

CREATE TABLE import_runs (
    id             BIGINT GENERATED ALWAYS AS IDENTITY,
    batch_id       UUID         NOT NULL,   -- groups the per-file runs of one scheduler/manual trigger
    source_file    VARCHAR(255) NOT NULL,   -- file name only, never a local path
    trigger_type   VARCHAR(20)  NOT NULL DEFAULT 'SCHEDULER',
    started_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    finished_at    TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'RUNNING',
    rows_read      INTEGER      NOT NULL DEFAULT 0,
    rows_inserted  INTEGER      NOT NULL DEFAULT 0,
    rows_updated   INTEGER      NOT NULL DEFAULT 0,
    rows_rejected  INTEGER      NOT NULL DEFAULT 0,
    error_message  TEXT,
    CONSTRAINT pk_import_runs PRIMARY KEY (id),
    CONSTRAINT ck_import_runs_status CHECK (status IN ('RUNNING', 'SUCCESS', 'PARTIAL', 'FAILED')),
    CONSTRAINT ck_import_runs_trigger CHECK (trigger_type IN ('SCHEDULER', 'MANUAL')),
    CONSTRAINT ck_import_runs_counters CHECK (
        rows_read >= 0 AND rows_inserted >= 0 AND rows_updated >= 0 AND rows_rejected >= 0
    ),
    CONSTRAINT ck_import_runs_finished CHECK (
        (status = 'RUNNING' AND finished_at IS NULL) OR (status <> 'RUNNING' AND finished_at IS NOT NULL)
    )
);

-- DB-level guard against concurrent imports: at most ONE run may be RUNNING at any time.
CREATE UNIQUE INDEX uq_import_runs_single_running ON import_runs ((status)) WHERE status = 'RUNNING';
CREATE INDEX ix_import_runs_batch   ON import_runs (batch_id);
CREATE INDEX ix_import_runs_started ON import_runs (started_at DESC);

CREATE TABLE import_errors (
    id             BIGINT GENERATED ALWAYS AS IDENTITY,
    import_run_id  BIGINT       NOT NULL,
    source_file    VARCHAR(255) NOT NULL,
    row_number     INTEGER,                -- NULL for file-level errors
    sku            VARCHAR(100),
    error_code     VARCHAR(50)  NOT NULL,
    error_message  TEXT         NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_import_errors PRIMARY KEY (id),
    CONSTRAINT fk_import_errors_run FOREIGN KEY (import_run_id) REFERENCES import_runs (id) ON DELETE CASCADE
);
CREATE INDEX ix_import_errors_run ON import_errors (import_run_id);

ALTER TABLE esim_products
    ADD CONSTRAINT fk_esim_products_last_import_run
    FOREIGN KEY (last_import_run_id) REFERENCES import_runs (id) ON DELETE SET NULL;
CREATE INDEX ix_esim_products_last_run ON esim_products (last_import_run_id);
