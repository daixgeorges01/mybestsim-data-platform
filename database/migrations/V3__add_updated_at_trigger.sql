-- V3: keep esim_products.updated_at accurate on every real UPDATE.

CREATE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_esim_products_updated_at
    BEFORE UPDATE ON esim_products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
