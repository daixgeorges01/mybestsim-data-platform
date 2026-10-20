%dw 2.0
/**
 * Validation and normalisation of provider CSV rows (DataWeave module, usable in Mule Community).
 *
 *   RowValidator::validateRows(rows, allowedCurrenciesCsv)
 *     -> { rowsRead, missingColumns[], valid[], rejected[] }
 *
 * `valid` rows use the snake_case keys expected by the SQL loader (jsonb_to_recordset).
 * Rules are documented in docs/data-flow.md. The first occurrence of a (provider, sku) key wins;
 * later duplicates in the same file are rejected with DUPLICATE_SKU.
 */
var requiredColumns = ["sku", "provider", "product_name", "country_code", "country_name", "data_gb",
                       "data_display", "validity_days", "price", "currency", "network", "top_up"]
var trueValues = ["oui", "yes", "true", "1", "y"]
var falseValues = ["non", "no", "false", "0", "n"]

fun clean(k: String): String = trim(k replace "﻿" with "")
fun txt(v: Any): String = if (v == null) "" else trim(v as String)
fun cut(s: String, n: Number): String = if (sizeOf(s) > n) s[0 to (n - 1)] else s
fun isUnlimitedLabel(s: String): Boolean = s matches /(?i)(illimit[ée]e?s?|unlimited)/

fun check(r: Object, allowedCurrencies: Array<String>): Object = do {
    var sku = txt(r.sku)
    var provider = txt(r.provider)
    var name = txt(r.product_name)
    var cc = upper(txt(r.country_code))
    var cn = txt(r.country_name)
    var dg = txt(r.data_gb)
    var dd = txt(r.data_display)
    var vd = txt(r.validity_days)
    var pr = txt(r.price)
    var cur = upper(txt(r.currency))
    var net = upper(txt(r.network))
    var tu = lower(txt(r.top_up))
    var unlimited = (dg == "") and isUnlimitedLabel(dd)
    var err =
        if (sku == "" or sizeOf(sku) > 100 or not (sku matches /[A-Za-z0-9._\-]+/))
            {c: "INVALID_SKU", m: "SKU is empty, longer than 100 characters or contains invalid characters"}
        else if (provider == "" or sizeOf(provider) > 100)
            {c: "INVALID_PROVIDER", m: "Provider is empty or longer than 100 characters"}
        else if (name == "" or sizeOf(name) > 255)
            {c: "INVALID_PRODUCT_NAME", m: "Product name is empty or longer than 255 characters"}
        else if (not (cc matches /[A-Z]{2,3}/))
            {c: "INVALID_COUNTRY_CODE", m: "Country code must be 2-3 letters, got '" ++ cut(cc, 20) ++ "'"}
        else if (cn == "" or sizeOf(cn) > 100)
            {c: "INVALID_COUNTRY_NAME", m: "Country name is empty or longer than 100 characters"}
        else if (dd == "" or sizeOf(dd) > 50)
            {c: "INVALID_DATA_DISPLAY", m: "Data label is empty or longer than 50 characters"}
        else if (dg == "" and not unlimited)
            {c: "MISSING_DATA", m: "data_gb is empty and the offer is not labelled unlimited (data_display='" ++ cut(dd, 30) ++ "')"}
        else if (dg != "" and not (dg matches /\d{1,6}(\.\d{1,2})?/))
            {c: "INVALID_DATA", m: "data_gb must be a positive decimal, got '" ++ cut(dg, 20) ++ "'"}
        else if (dg != "" and (dg as Number) <= 0)
            {c: "INVALID_DATA", m: "data_gb must be greater than 0"}
        else if (dg != "" and isUnlimitedLabel(dd))
            {c: "INCONSISTENT_DATA", m: "data_gb has a value but the offer is labelled unlimited"}
        else if ((not (vd matches /\d{1,4}/)) or ((vd as Number) <= 0))
            {c: "INVALID_VALIDITY", m: "validity_days must be a positive integer, got '" ++ cut(vd, 20) ++ "'"}
        else if (not (pr matches /\d{1,8}(\.\d{1,2})?/))
            {c: "INVALID_PRICE", m: "price must be a non-negative decimal with at most 2 decimals, got '" ++ cut(pr, 20) ++ "'"}
        else if (not (allowedCurrencies contains cur))
            {c: "INVALID_CURRENCY", m: "Currency '" ++ cut(cur, 10) ++ "' is not allowed (" ++ (allowedCurrencies joinBy ",") ++ ")"}
        else if (not (["2G", "3G", "4G", "5G"] contains net))
            {c: "INVALID_NETWORK", m: "Network must be 2G, 3G, 4G or 5G, got '" ++ cut(net, 10) ++ "'"}
        else if (not ((trueValues ++ falseValues) contains tu))
            {c: "INVALID_TOP_UP", m: "top_up must be oui/non, got '" ++ cut(tu, 10) ++ "'"}
        else null
    ---
    if (err != null)
        {ok: false, sku: cut(sku, 100), code: err.c, message: err.m}
    else
        {
            ok: true,
            sku: sku,
            row: {
                provider: provider,
                sku: sku,
                product_name: name,
                country_code: cc,
                country_name: cn,
                data_gb: if (unlimited) null else (dg as Number),
                data_display: dd,
                is_unlimited: unlimited,
                validity_days: vd as Number,
                price: pr as Number,
                currency: cur,
                network: net,
                top_up: trueValues contains tu
            }
        }
}

fun validateRows(csvRows: Any, allowedCurrenciesCsv: String) = do {
    var allowed = (allowedCurrenciesCsv default "EUR") splitBy "," map upper(trim($))
    var rows = (csvRows default []) map ((r) -> r mapObject ((v, k) -> (clean(k as String)): v))
    var present = if (isEmpty(rows)) requiredColumns else (rows[0] pluck ((v, k) -> k as String))
    var checked = rows map ((r, i) -> check(r, allowed) ++ {rowNumber: i + 2})
    var deduped = checked reduce ((item, acc = {seen: {}, out: []}) -> do {
        var key = if (item.ok) (item.row.provider ++ "|" ++ item.row.sku) else ""
        ---
        if (item.ok and acc.seen[key] != null)
            {
                seen: acc.seen,
                out: acc.out ++ [{
                    ok: false,
                    sku: item.sku,
                    rowNumber: item.rowNumber,
                    code: "DUPLICATE_SKU",
                    message: "Duplicate SKU in file, first occurrence at row " ++ acc.seen[key] ++ " is kept"
                }]
            }
        else if (item.ok)
            {seen: acc.seen ++ {(key): item.rowNumber}, out: acc.out ++ [item]}
        else
            {seen: acc.seen, out: acc.out ++ [item]}
    })
    ---
    {
        rowsRead: sizeOf(rows),
        missingColumns: requiredColumns -- present,
        valid: deduped.out filter ((e) -> e.ok) map ((e) -> e.row),
        rejected: deduped.out filter ((e) -> not e.ok) map ((e) -> {
            rowNumber: e.rowNumber,
            sku: e.sku,
            errorCode: e.code,
            errorMessage: e.message,
            raw: rows[e.rowNumber - 2]
        })
    }
}
