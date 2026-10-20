%dw 2.0
/** Response mappers: database rows (snake_case) -> API objects (camelCase, see RAML). */

fun summary(rows: Array) = do {
    var r = rows[0]
    ---
    {
        hasData: r.total_products > 0,
        totalProducts: r.total_products,
        productsOver100: r.over_100,
        priceMin: r.price_min,
        priceMax: r.price_max,
        priceAvg: r.price_avg,
        dataAvgGb: r.data_avg_gb,
        numericDataCount: r.numeric_data_count,
        unlimitedCount: r.unlimited_count,
        providerCount: r.provider_count,
        countryCount: r.country_count,
        currency: r.currency
    }
}

fun providers(rows: Array) = {
    items: rows map ((r) -> {
        provider: r.provider,
        productCount: r.product_count,
        sharePercent: r.share_percent,
        priceAvg: r.price_avg,
        priceMin: r.price_min,
        priceMax: r.price_max,
        unlimitedCount: r.unlimited_count
    })
}

fun prices(rows: Array, currency: String | Null) = {
    currency: currency,
    buckets: rows map ((r) -> {label: r.label, min: r.min, max: r.max, count: r.count})
}

fun dataDistributions(dataRows: Array, validityRows: Array, networkRows: Array) = {
    dataDistribution: dataRows map ((r) -> {
        label: r.label,
        dataGb: r.data_gb,
        isUnlimited: r.is_unlimited,
        count: r.count
    }),
    validityDistribution: validityRows map ((r) -> {label: r.label, count: r.count}),
    networkDistribution: networkRows map ((r) -> {label: r.label, count: r.count})
}

fun products(rows: Array, page: Number, pageSize: Number, total: Number) = {
    items: rows map ((r) -> {
        sku: r.sku,
        provider: r.provider,
        productName: r.product_name,
        countryCode: r.country_code,
        countryName: r.country_name,
        dataGb: r.data_gb,
        dataDisplay: r.data_display,
        isUnlimited: r.is_unlimited,
        validityDays: r.validity_days,
        price: r.price,
        currency: trim(r.currency),
        network: r.network,
        topUp: r.top_up
    }),
    page: page,
    pageSize: pageSize,
    totalItems: total,
    totalPages: ceil(total / pageSize)
}

fun latestImport(runs: Array) = do {
    var count = sizeOf(runs)
    var running = sizeOf(runs filter ((r) -> r.status == "RUNNING"))
    fun countStatus(s) = sizeOf(runs filter ((r) -> r.status == s))
    var status =
        if (count == 0) null
        else if (running > 0) "RUNNING"
        else if (countStatus("SUCCESS") == count) "SUCCESS"
        else if (countStatus("FAILED") == count) "FAILED"
        else "PARTIAL"
    ---
    {
        hasImport: count > 0,
        batchId: if (count > 0) (runs[0].batch_id as String) else null,
        status: status,
        "trigger": if (count > 0) runs[0].trigger_type else null,
        startedAt: if (count > 0) runs[0].started_at else null,
        finishedAt: if (count == 0 or running > 0) null else (runs map $.finished_at) reduce ((a, b) -> if (a > b) a else b),
        filesCount: count,
        rowsRead: sum(runs map ($.rows_read)),
        rowsInserted: sum(runs map ($.rows_inserted)),
        rowsUpdated: sum(runs map ($.rows_updated)),
        rowsRejected: sum(runs map ($.rows_rejected)),
        runs: runs map ((r) -> {
            sourceFile: r.source_file,
            status: r.status,
            startedAt: r.started_at,
            finishedAt: r.finished_at,
            rowsRead: r.rows_read,
            rowsInserted: r.rows_inserted,
            rowsUpdated: r.rows_updated,
            rowsRejected: r.rows_rejected,
            errorMessage: r.error_message
        })
    }
}

fun batchResult(batchId: String, files: Array) = do {
    fun n(status) = sizeOf(files filter ((f) -> f.status == status))
    ---
    {
        batchId: batchId,
        status:
            if (isEmpty(files)) "NO_FILES"
            else if (n("SUCCESS") == sizeOf(files)) "SUCCESS"
            else if (n("FAILED") == sizeOf(files)) "FAILED"
            else "PARTIAL",
        filesFound: sizeOf(files),
        filesProcessed: sizeOf(files),
        rowsRead: sum(files map ($.rowsRead)),
        rowsInserted: sum(files map ($.rowsInserted)),
        rowsUpdated: sum(files map ($.rowsUpdated)),
        rowsRejected: sum(files map ($.rowsRejected)),
        files: files
    }
}

/** Rows written to the "rejected rows" CSV: reason columns + the original columns (prefixed src_). */
fun rejectedRowsCsv(rejected: Array) = rejected map ((e) ->
    {
        row_number: e.rowNumber,
        sku: e.sku,
        error_code: e.errorCode,
        error_message: e.errorMessage
    } ++ ((e.raw default {}) mapObject ((v, k) -> ("src_" ++ k): v))
)

/** JSON rows passed (as one jsonb parameter) to the parameterised SQL statements. */
fun errorsJson(rejected: Array) = rejected map ((e) -> {
    row_number: e.rowNumber, sku: e.sku, error_code: e.errorCode, error_message: e.errorMessage
})

/** Consistent error contract. `err` is the Mule `error` object. */
var errorTable = {
    "APIKIT:BAD_REQUEST": {status: 400, code: "BAD_REQUEST"},
    "APIKIT:NOT_FOUND": {status: 404, code: "NOT_FOUND"},
    "APIKIT:METHOD_NOT_ALLOWED": {status: 405, code: "METHOD_NOT_ALLOWED"},
    "APIKIT:NOT_ACCEPTABLE": {status: 406, code: "NOT_ACCEPTABLE"},
    "APIKIT:UNSUPPORTED_MEDIA_TYPE": {status: 415, code: "UNSUPPORTED_MEDIA_TYPE"},
    "APIKIT:NOT_IMPLEMENTED": {status: 501, code: "NOT_IMPLEMENTED"},
    "MYBESTSIM:UNAUTHORIZED": {status: 401, code: "UNAUTHORIZED"},
    "MYBESTSIM:IMPORT_ALREADY_RUNNING": {status: 409, code: "IMPORT_ALREADY_RUNNING"},
    "MYBESTSIM:NOT_READY": {status: 503, code: "NOT_READY"},
    "DB:CONNECTIVITY": {status: 503, code: "DATABASE_UNAVAILABLE"}
}
fun errorKey(err) = (err.errorType.namespace default "") ++ ":" ++ (err.errorType.identifier default "")
fun errorStatus(err) = errorTable[errorKey(err)].status default 500
fun errorBody(err) = do {
    var known = errorTable[errorKey(err)]
    var safeMessage = {
        "BAD_REQUEST": err.description default "Bad request",
        "NOT_READY": err.description default "Import prerequisites are not met",
        "UNAUTHORIZED": "Missing or invalid API key",
        "IMPORT_ALREADY_RUNNING": "An import is already running",
        "DATABASE_UNAVAILABLE": "The database is currently unavailable"
    }
    ---
    {
        error: {
            code: known.code default "INTERNAL_ERROR",
            message: if (known == null) "Unexpected error" else (safeMessage[known.code] default (known.code replace "_" with " "))
        }
    }
}
