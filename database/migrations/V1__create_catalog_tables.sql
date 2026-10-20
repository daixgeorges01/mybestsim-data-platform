-- V1: catalogue structure (providers + esim_products). No business data is inserted.

CREATE TABLE providers (
    id          INTEGER GENERATED ALWAYS AS IDENTITY,
    name        VARCHAR(100) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_providers PRIMARY KEY (id),
    CONSTRAINT uq_providers_name UNIQUE (name),
    CONSTRAINT ck_providers_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE esim_products (
    id            BIGINT GENERATED ALWAYS AS IDENTITY,
    sku           VARCHAR(100)  NOT NULL,
    provider_id   INTEGER       NOT NULL,
    product_name  VARCHAR(255)  NOT NULL,
    country_code  VARCHAR(3)    NOT NULL,
    country_name  VARCHAR(100)  NOT NULL,
    -- NULL + is_unlimited = TRUE  -> unlimited offer
    -- NULL + is_unlimited = FALSE -> forbidden (missing data is rejected at import)
    data_gb       NUMERIC(8,2),
    data_display  VARCHAR(50)   NOT NULL,
    is_unlimited  BOOLEAN       NOT NULL,
    validity_days INTEGER       NOT NULL,
    price         NUMERIC(10,2) NOT NULL,
    currency      CHAR(3)       NOT NULL,
    network       VARCHAR(10)   NOT NULL,
    top_up        BOOLEAN       NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    last_import_run_id BIGINT,  -- FK added in V2 (import_runs is created there)
    CONSTRAINT pk_esim_products PRIMARY KEY (id),
    -- Business key: SKUs are provider-prefixed in the sources, but uniqueness is enforced per provider.
    CONSTRAINT uq_esim_products_provider_sku UNIQUE (provider_id, sku),
    CONSTRAINT fk_esim_products_provider FOREIGN KEY (provider_id) REFERENCES providers (id),
    CONSTRAINT ck_esim_products_sku CHECK (btrim(sku) <> ''),
    CONSTRAINT ck_esim_products_country_code CHECK (country_code ~ '^[A-Z]{2,3}$'),
    CONSTRAINT ck_esim_products_data CHECK (
        (is_unlimited AND data_gb IS NULL) OR (NOT is_unlimited AND data_gb IS NOT NULL AND data_gb > 0)
    ),
    CONSTRAINT ck_esim_products_validity CHECK (validity_days > 0),
    CONSTRAINT ck_esim_products_price CHECK (price >= 0),
    CONSTRAINT ck_esim_products_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_esim_products_network CHECK (network IN ('2G', '3G', '4G', '5G'))
);

CREATE INDEX ix_esim_products_provider   ON esim_products (provider_id);
CREATE INDEX ix_esim_products_country    ON esim_products (country_code);
CREATE INDEX ix_esim_products_price      ON esim_products (price);
CREATE INDEX ix_esim_products_unlimited  ON esim_products (is_unlimited);
CREATE INDEX ix_esim_products_network    ON esim_products (network);
