%dw 2.0
/** Query-string handling for GET /products: bound parameters + whitelisted ORDER BY (never user text in SQL). */

fun escapeLike(s: String): String = s replace "\\" with "\\\\" replace "%" with "\\%" replace "_" with "\\_"

fun filters(q: Object) = {
    provider: q.provider default null,
    country: q.country default null,
    network: q.network default null,
    unlimited: q.unlimited default null,
    topUp: q.topUp default null,
    minPrice: q.minPrice default null,
    maxPrice: q.maxPrice default null,
    q: if (q.q != null and trim(q.q) != "") escapeLike(trim(q.q)) else null
}

fun orderBy(q: Object): String = do {
    var columns = {
        price: "p.price", dataGb: "p.is_unlimited, p.data_gb", validityDays: "p.validity_days",
        productName: "p.product_name", provider: "pr.name", country: "p.country_name"
    }
    var dir = if (q.direction == "desc") "DESC" else "ASC"
    ---
    (columns[q.sort default "price"] default "p.price") ++ " " ++ dir ++ ", p.sku ASC"
}

var whereClause = "
    WHERE (CAST(:provider AS text) IS NULL OR pr.name = CAST(:provider AS text))
      AND (CAST(:country AS text) IS NULL OR p.country_code = upper(CAST(:country AS text)))
      AND (CAST(:network AS text) IS NULL OR p.network = CAST(:network AS text))
      AND (CAST(:unlimited AS boolean) IS NULL OR p.is_unlimited = CAST(:unlimited AS boolean))
      AND (CAST(:topUp AS boolean) IS NULL OR p.top_up = CAST(:topUp AS boolean))
      AND (CAST(:minPrice AS numeric) IS NULL OR p.price >= CAST(:minPrice AS numeric))
      AND (CAST(:maxPrice AS numeric) IS NULL OR p.price <= CAST(:maxPrice AS numeric))
      AND (CAST(:q AS text) IS NULL
           OR p.product_name ILIKE '%' || CAST(:q AS text) || '%' ESCAPE '\\'
           OR p.sku ILIKE '%' || CAST(:q AS text) || '%' ESCAPE '\\'
           OR p.country_name ILIKE '%' || CAST(:q AS text) || '%' ESCAPE '\\')
"

fun countSql(): String =
    "SELECT count(*) AS total FROM esim_products p JOIN providers pr ON pr.id = p.provider_id " ++ whereClause

fun pageSql(q: Object): String =
    "SELECT p.sku, pr.name AS provider, p.product_name, p.country_code, p.country_name,
            p.data_gb, p.data_display, p.is_unlimited, p.validity_days, p.price, p.currency,
            p.network, p.top_up
     FROM esim_products p JOIN providers pr ON pr.id = p.provider_id " ++ whereClause ++
    " ORDER BY " ++ orderBy(q) ++ " LIMIT :limit OFFSET :offset"
