# =============================================================================
# mastr_data.R — shared data-access layer for every dashboard in apps/
#
# The user NEVER downloads the XML. They also don't strictly need to download
# the DuckDB: every function here queries the Parquet files remotely through
# DuckDB's httpfs extension. Only the (usually tiny) result set is transferred.
#
# How it works:
#   1. Release resolution: optional `MASTR_TAG=...`, else newest `data-*` tag by
#      GitHub `published_at` (not `/releases/latest`, which can point at an old
#      snapshot if the "Latest" flag was set wrong), else fallback to `/latest`.
#   2. `mastr_con()` returns an in-memory DuckDB connection with httpfs + a
#      few CREATE VIEW statements that point at the remote Parquet files.
#   3. `mastr_query()` / `mastr_table()` are thin wrappers around DBI::dbGetQuery.
#   4. Optional: users can call `mastr_use_local(path)` once to switch to a
#      locally downloaded DuckDB file for fully offline use.
# =============================================================================

suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(memoise)
  library(cachem)
  library(httr2)
  library(rlang)
})

# ----- configuration ---------------------------------------------------------

.mastr_env <- new.env(parent = emptyenv())
.mastr_env$repo        <- Sys.getenv("MASTR_REPO", "Tarekchehahde/mastr-shiny")
.mastr_env$release_tag <- NULL            # resolved on first use
.mastr_env$base_url    <- NULL            # e.g. https://github.com/.../releases/download/data-2026-04-21
.mastr_env$local_db    <- NULL            # optional local .duckdb
.mastr_env$con         <- NULL
# Prefetch strategy: download the small (<20 MB total) aggregate parquets to a
# persistent on-disk cache on first use so charts render from local I/O instead
# of HTTPS range-requests. Override with MASTR_PREFETCH=0 to force streaming.
.mastr_env$prefetch    <- !identical(Sys.getenv("MASTR_PREFETCH", "1"), "0")
.mastr_env$cache_dir   <- NULL            # resolved once tag is known
.mastr_env$local_aggs  <- character(0)    # names of aggs served from local cache

mastr_set_repo <- function(repo) {
  .mastr_env$repo <- repo
  .mastr_env$release_tag <- NULL
  .mastr_env$base_url <- NULL
  mastr_disconnect()
  invisible(repo)
}

mastr_use_local <- function(duckdb_path) {
  stopifnot(file.exists(duckdb_path))
  .mastr_env$local_db <- normalizePath(duckdb_path)
  mastr_disconnect()
  invisible(duckdb_path)
}

# ----- resolve latest release ------------------------------------------------

.github_newest_data_release <- function(repo) {
  tok <- Sys.getenv("GITHUB_TOKEN", "")
  rows <- list()
  for (page in seq_len(10L)) {
    url <- sprintf("https://api.github.com/repos/%s/releases", repo)
    req <- httr2::request(url) |>
      httr2::req_url_query(per_page = 100L, page = page) |>
      httr2::req_headers("Accept" = "application/vnd.github+json")
    if (nzchar(tok)) req <- httr2::req_auth_bearer_token(req, tok)
    resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
    if (is.null(resp) || httr2::resp_status(resp) >= 400) break
    batch <- httr2::resp_body_json(resp)
    if (!length(batch)) break
    for (rel in batch) {
      if (isTRUE(rel[["draft"]])) next
      if (isTRUE(rel[["prerelease"]])) next
      tag <- rel[["tag_name"]]
      if (!is.character(tag) || length(tag) != 1L || !nzchar(tag)) next
      if (!startsWith(tag, "data-")) next
      pub <- rel[["published_at"]] %||% ""
      rows[[length(rows) + 1L]] <- list(tag_name = tag, published_at = pub)
    }
    if (length(batch) < 100L) break
  }
  if (!length(rows)) return(NULL)
  pubs <- vapply(rows, function(r) r$published_at %||% "", character(1))
  if (!any(nzchar(pubs))) return(rows[[1L]])
  pick <- order(pubs, decreasing = TRUE, na.last = TRUE)[1L]
  rows[[pick]]
}

.resolve_release <- function() {
  if (!is.null(.mastr_env$release_tag)) return(invisible())
  repo <- .mastr_env$repo

  tag_override <- Sys.getenv("MASTR_TAG", "")
  if (nzchar(tag_override)) {
    .mastr_env$release_tag <- tag_override
    .mastr_env$base_url <- sprintf("https://github.com/%s/releases/download/%s",
                                   repo, tag_override)
    return(invisible())
  }

  best <- .github_newest_data_release(repo)
  if (!is.null(best) && nzchar(best$tag_name %||% "")) {
    .mastr_env$release_tag <- best$tag_name
    .mastr_env$base_url <- sprintf("https://github.com/%s/releases/download/%s",
                                   repo, best$tag_name)
    return(invisible())
  }

  url <- sprintf("https://api.github.com/repos/%s/releases/latest", repo)
  req <- httr2::request(url) |>
    httr2::req_headers("Accept" = "application/vnd.github+json")
  tok <- Sys.getenv("GITHUB_TOKEN", "")
  if (nzchar(tok)) req <- httr2::req_auth_bearer_token(req, tok)
  resp <- tryCatch(httr2::req_perform(req), error = function(e) NULL)
  if (is.null(resp) || httr2::resp_status(resp) >= 400) {
    abort(sprintf(
      "Could not resolve a data release for %s. Set MASTR_REPO or MASTR_TAG, or call mastr_use_local().",
      repo))
  }
  body <- httr2::resp_body_json(resp)
  .mastr_env$release_tag <- body$tag_name
  .mastr_env$base_url <- sprintf("https://github.com/%s/releases/download/%s",
                                 repo, body$tag_name)
  invisible()
}

mastr_release_info <- function() {
  .resolve_release()
  list(repo = .mastr_env$repo,
       tag  = .mastr_env$release_tag,
       base = .mastr_env$base_url)
}

# ----- connection ------------------------------------------------------------

#' Get a DuckDB connection bound to the latest MaStR release (or local db).
#'
#' Safe to call from many reactive expressions — the connection is cached.
mastr_con <- function() {
  if (!is.null(.mastr_env$con) && DBI::dbIsValid(.mastr_env$con)) return(.mastr_env$con)

  if (!is.null(.mastr_env$local_db)) {
    con <- dbConnect(duckdb::duckdb(), dbdir = .mastr_env$local_db, read_only = TRUE)
  } else {
    .resolve_release()
    con <- dbConnect(duckdb::duckdb())
    dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
    # ICU is needed because some aggregate parquets carry TIMESTAMPTZ columns
    # (e.g. agg_buildout_monthly). DuckDB's autoloader fails on some networks,
    # so we install+load eagerly and fall back gracefully if unreachable.
    try(dbExecute(con, "INSTALL icu; LOAD icu;"), silent = TRUE)
    dbExecute(con, "SET enable_http_metadata_cache=true;")
    dbExecute(con, "SET http_keep_alive=true;")
    # Fast path: only wire the tiny pre-rolled aggregate parquets (7 files,
    # total ~300 KB, all cached to local disk). The heavy entity views +
    # v_units_all are created lazily on first query that references them —
    # see .ensure_entity_views(). This keeps cold-start under ~2s for any
    # dashboard that reads aggregates only (01 Overview, 15 EE quote, …).
    .create_aggregate_views(con)
    .mastr_env$entities_ready <- FALSE
  }
  .mastr_env$con <- con
  con
}

#' Resolve (and lazily create) the per-release local cache directory.
#'
#' We key the cache on the release tag so a new nightly release automatically
#' invalidates all cached bytes without the user lifting a finger.
.cache_dir <- function() {
  if (!is.null(.mastr_env$cache_dir)) return(.mastr_env$cache_dir)
  tag <- .mastr_env$release_tag %||% "unknown"
  # tools::R_user_dir is available since R 4.0; falls back to tempdir in tests.
  root <- tryCatch(tools::R_user_dir("mastr-shiny", which = "cache"),
                   error = function(e) file.path(tempdir(), "mastr-shiny-cache"))
  dir <- file.path(root, tag)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  .mastr_env$cache_dir <- dir
  dir
}

#' Download all aggregate parquets to local disk on first use. Returns a named
#' list: name -> local path (absolute). Files already present on disk are
#' reused. If prefetch is disabled or any download fails, that name is missing
#' from the returned list so the caller falls back to streaming via httpfs.
.prefetch_aggregates <- function(names) {
  if (!isTRUE(.mastr_env$prefetch)) return(setNames(vector("list", 0), character()))
  base <- .mastr_env$base_url
  dir  <- .cache_dir()
  out  <- list()
  total_bytes <- 0
  started <- Sys.time()
  for (a in names) {
    dest <- file.path(dir, paste0(a, ".parquet"))
    if (file.exists(dest) && file.info(dest)$size > 0) {
      out[[a]] <- dest
      next
    }
    url <- sprintf("%s/%s.parquet", base, a)
    ok <- tryCatch({
      utils::download.file(url, dest, mode = "wb", quiet = TRUE,
                           method = "libcurl")
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (ok && file.exists(dest) && file.info(dest)$size > 0) {
      out[[a]] <- dest
      total_bytes <- total_bytes + file.info(dest)$size
    } else {
      try(file.remove(dest), silent = TRUE)
    }
  }
  .mastr_env$local_aggs <- names(out)
  if (length(out)) {
    elapsed <- difftime(Sys.time(), started, units = "secs")
    message(sprintf("[mastr] cached %d aggregate parquet(s) to %s (%.1f MB in %.1fs)",
                    length(out), dir, total_bytes / 1e6, as.numeric(elapsed)))
  }
  out
}

#' Manually pre-warm the cache. Useful in a one-shot script before launching a
#' dashboard. Returns invisibly the list of (name -> path) entries it stored.
mastr_prefetch <- function(force = FALSE) {
  .resolve_release()
  if (force) {
    dir <- .cache_dir()
    unlink(list.files(dir, full.names = TRUE), force = TRUE)
  }
  mastr_disconnect()      # force re-bind with fresh local paths
  mastr_con()
  invisible(.mastr_env$local_aggs)
}

mastr_disconnect <- function() {
  if (!is.null(.mastr_env$con) && DBI::dbIsValid(.mastr_env$con)) {
    try(dbDisconnect(.mastr_env$con, shutdown = TRUE), silent = TRUE)
  }
  .mastr_env$con <- NULL
  invisible()
}

# The entity list mirrors WORK/etl/src/mastr_etl/config.py ENTITIES. Keep in sync.
.remote_entities <- c(
  "solar", "wind", "biomasse", "wasser", "geothermie", "kernkraft",
  "verbrennung", "stromspeicher", "gaserzeuger", "gasverbraucher",
  "gasspeicher", "kwk", "eeg_solar", "eeg_wind", "eeg_biomasse", "eeg_wasser",
  "marktakteure", "netzanschlusspunkte", "bilanzierungsgebiete", "lokationen"
)

#' Create the 7 small aggregate views from local-cached parquet files.
#' Fast (<1s) because the parquets are <300 KB total and resolved to on-disk
#' paths. Safe to call on every connection.
.create_aggregate_views <- function(con) {
  base <- .mastr_env$base_url
  agg_files <- c(
    "kpi_overview", "capacity_by_state", "buildout_monthly",
    "capacity_by_plz_top5000", "solar_size_classes",
    "wind_hub_height", "ee_quote_by_year"
  )
  local_paths <- .prefetch_aggregates(agg_files)
  for (a in agg_files) {
    path_or_url <- local_paths[[a]]
    if (is.null(path_or_url)) path_or_url <- sprintf("%s/%s.parquet", base, a)
    sql <- sprintf(
      "CREATE OR REPLACE VIEW agg_%s AS SELECT * FROM read_parquet('%s')",
      a, path_or_url)
    try(dbExecute(con, sql), silent = TRUE)
  }
}

# Bundesland code -> name lookup (mirrors WORK/etl/src/mastr_etl/config.py:BUNDESLAND).
# Keep in sync with the Python side; this is the client-side copy so v_units_all
# can expose bundesland_name without having to read the server-built duckdb.
# Verified empirically by correlating each code with its dominant PLZ prefix
# across the full MaStR solar table (2026-04-21 data release). Do NOT reorder
# without re-running that check — the BNetzA Katalog ordering is NOT alphabetic.
.BUNDESLAND <- c(
  "1400" = "Brandenburg",            "1401" = "Berlin",
  "1402" = "Baden-Württemberg",      "1403" = "Bayern",
  "1404" = "Bremen",                 "1405" = "Hessen",
  "1406" = "Hamburg",                "1407" = "Mecklenburg-Vorpommern",
  "1408" = "Niedersachsen",          "1409" = "Nordrhein-Westfalen",
  "1410" = "Rheinland-Pfalz",        "1411" = "Schleswig-Holstein",
  "1412" = "Saarland",               "1413" = "Sachsen",
  "1414" = "Sachsen-Anhalt",         "1415" = "Thüringen",
  "1416" = "Ausschließliche Wirtschaftszone"
)

.create_bundesland_lookup <- function(con) {
  rows <- paste(
    sprintf("('%s','%s')",
            names(.BUNDESLAND),
            gsub("'", "''", unname(.BUNDESLAND))),
    collapse = ", "
  )
  dbExecute(con, "CREATE OR REPLACE TABLE bundesland (code VARCHAR, name VARCHAR)")
  dbExecute(con, sprintf("INSERT INTO bundesland VALUES %s", rows))
}

#' Heavy path: create entity views (one per raw Parquet on GitHub Releases)
#' and the schema-aware v_units_all UNION ALL view. Costs ~20-30 s cold because
#' DuckDB probes each remote parquet footer over HTTPS to learn the schema.
#' Called lazily from mastr_query() only when the SQL references v_units_all
#' or a bare entity name.
.ensure_entity_views <- function(con) {
  if (isTRUE(.mastr_env$entities_ready)) return(invisible())
  base <- .mastr_env$base_url
  for (e in .remote_entities) {
    url <- sprintf("%s/%s.parquet", base, e)
    sql <- sprintf(
      "CREATE OR REPLACE VIEW %s AS SELECT * FROM read_parquet('%s')",
      e, url)
    try(dbExecute(con, sql), silent = TRUE)
  }
  .create_bundesland_lookup(con)
  .create_units_view(con)
  .mastr_env$entities_ready <- TRUE
  invisible()
}

# Back-compat alias so downstream code (or users) that call the old name still
# work; this is what shinylive / runApp sessions used to invoke.
.create_remote_views <- function(con) {
  .create_aggregate_views(con)
  .ensure_entity_views(con)
}

# Regex that matches any reference to a raw entity table or v_units_all. We
# use word-boundary matching so that `agg_capacity_by_state` (which contains
# "state" but no entity names) is NOT treated as needing entity views.
.ENTITY_RE <- paste0(
  "\\b(", paste(c(.remote_entities, "v_units_all"), collapse = "|"), ")\\b"
)

.needs_entity_views <- function(sql) {
  grepl(.ENTITY_RE, sql, perl = TRUE, ignore.case = TRUE)
}

# Mirror of build_duckdb._table_columns / _col_or_null. Needed because BNetzA
# ships heterogeneous schemas across entity types (e.g. kernkraft has ~45
# columns vs solar's ~70), and a single missing column in one branch of the
# UNION ALL would otherwise fail the whole view binder — the same bug that
# bit the server-side build in run #4. Keep this in sync with the Python.
.table_columns <- function(con, table) {
  res <- tryCatch(
    DBI::dbGetQuery(con, sprintf("SELECT column_name FROM information_schema.columns WHERE table_name = '%s'", table)),
    error = function(e) NULL
  )
  if (is.null(res) || nrow(res) == 0) return(character(0))
  tolower(res$column_name)
}

.col_or_null <- function(cols, name, cast = NULL, alias = "t") {
  expr <- if (tolower(name) %in% cols) sprintf("%s.%s", alias, name) else "NULL"
  if (!is.null(cast)) sprintf("TRY_CAST(%s AS %s)", expr, cast) else expr
}

.create_units_view <- function(con) {
  unit_map <- c(
    solar         = "SolareStrahlungsenergie",
    wind          = "Wind",
    biomasse      = "Biomasse",
    wasser        = "Wasser",
    geothermie    = "GeothermieGrubenKlaerschlamm",
    kernkraft     = "Kernenergie",
    verbrennung   = "FossilOderSonstige",
    stromspeicher = "Speicher"
  )
  parts <- character(0)
  for (k in names(unit_map)) {
    cols <- .table_columns(con, k)
    if (length(cols) == 0L) next  # remote view never materialised
    eg <- unit_map[[k]]
    bundesland_expr <- .col_or_null(cols, "Bundesland")
    parts <- c(parts, sprintf("
      SELECT
        '%1$s'                                                     AS source_table,
        '%2$s'                                                     AS energietraeger,
        %3$s                                                       AS mastr_nr,
        %4$s                                                       AS bruttoleistung_kw,
        %5$s                                                       AS nettonennleistung_kw,
        %6$s                                                       AS bundesland_code,
        bl.name                                                    AS bundesland_name,
        %7$s                                                       AS gemeinde,
        %8$s                                                       AS plz,
        %9$s                                                       AS lon,
        %10$s                                                      AS lat,
        %11$s                                                      AS inbetriebnahme_datum,
        %12$s                                                      AS betriebsstatus
      FROM %1$s t
      LEFT JOIN bundesland bl ON bl.code = %6$s",
      k, eg,
      .col_or_null(cols, "EinheitMastrNummer"),
      .col_or_null(cols, "Bruttoleistung",     cast = "DOUBLE"),
      .col_or_null(cols, "Nettonennleistung",  cast = "DOUBLE"),
      bundesland_expr,
      .col_or_null(cols, "Gemeinde"),
      .col_or_null(cols, "Postleitzahl"),
      .col_or_null(cols, "Laengengrad",        cast = "DOUBLE"),
      .col_or_null(cols, "Breitengrad",        cast = "DOUBLE"),
      .col_or_null(cols, "Inbetriebnahmedatum", cast = "DATE"),
      .col_or_null(cols, "Betriebsstatus")
    ))
  }
  if (length(parts) == 0L) return(invisible())
  sql <- paste("CREATE OR REPLACE VIEW v_units_all AS",
               paste(parts, collapse = "\nUNION ALL\n"))
  try(dbExecute(con, sql), silent = TRUE)
}

# ----- query helpers ---------------------------------------------------------

#' Run a SQL query and return a data.frame. Results are cached on disk (keyed
#' by the current release tag + the normalised SQL), so repeat launches of any
#' dashboard skip the query entirely. Cache survives R restarts; a new nightly
#' release automatically invalidates everything because the tag is part of the
#' key. Override with MASTR_QUERY_CACHE=0 to force re-execution.
.build_query_cache <- function() {
  if (identical(Sys.getenv("MASTR_QUERY_CACHE", "1"), "0")) {
    return(cachem::cache_mem())
  }
  dir <- tryCatch({
    tag <- .mastr_env$release_tag %||% "unknown"
    root <- tryCatch(tools::R_user_dir("mastr-shiny", which = "cache"),
                     error = function(e) file.path(tempdir(), "mastr-shiny-cache"))
    d <- file.path(root, tag, "_queries")
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    d
  }, error = function(e) NULL)
  if (is.null(dir)) return(cachem::cache_mem())
  cachem::cache_disk(dir, max_size = 256 * 1024^2, evict = "lru")
}
.mastr_env$query_cache <- NULL
.mastr_env$query_memo  <- NULL

mastr_query <- function(sql, params = list()) {
  .resolve_release()
  if (is.null(.mastr_env$query_cache)) {
    .mastr_env$query_cache <- .build_query_cache()
    .mastr_env$query_memo  <- memoise::memoise(
      function(sql, params) {
        con <- mastr_con()
        if (.needs_entity_views(sql)) .ensure_entity_views(con)
        if (length(params)) DBI::dbGetQuery(con, sql, params = params)
        else                DBI::dbGetQuery(con, sql)
      },
      cache = .mastr_env$query_cache
    )
  }
  .mastr_env$query_memo(sql, params)
}

#' Pull an entire (small) view/table as a data.frame. Intended for KPI tiles
#' and aggregate parquets; do NOT call on a full units table.
mastr_table <- function(name) {
  mastr_query(sprintf("SELECT * FROM %s", DBI::dbQuoteIdentifier(mastr_con(), name)))
}

#' List of Bundesländer (with code) — constant, fine to cache forever.
mastr_bundeslaender <- memoise::memoise(function() {
  mastr_query("
    SELECT DISTINCT bundesland_name AS name
    FROM v_units_all
    WHERE bundesland_name IS NOT NULL
    ORDER BY 1
  ")$name
})

mastr_energietraeger <- memoise::memoise(function() {
  mastr_query("SELECT DISTINCT energietraeger FROM v_units_all ORDER BY 1")$energietraeger
})

#' Build a safe SQL string list for an IN (...) clause. R's base `sQuote()`
#' uses Unicode curly quotes (U+2018 / U+2019), which DuckDB parses as an
#' identifier, producing the infamous 'Referenced column "Bayern" not found'
#' error. Use this helper in every dashboard's WHERE generator instead of
#' paste(sQuote(x), collapse = ", ").
#'
#' @examples
#'   sprintf("bundesland_name IN (%s)", mastr_sql_in(c("Bayern","Hessen")))
#'   # -> bundesland_name IN ('Bayern','Hessen')
mastr_sql_in <- function(values) {
  if (!length(values)) return("NULL")
  escaped <- gsub("'", "''", as.character(values), fixed = TRUE)
  paste0("'", escaped, "'", collapse = ", ")
}

# ----- footer helper ---------------------------------------------------------

mastr_attribution <- function() {
  info <- tryCatch(mastr_release_info(), error = function(e) list(tag = "unknown"))
  sprintf(
    "Datenquelle: Marktstammdatenregister — \u00a9 Bundesnetzagentur (Stand: %s), bereitgestellt unter DL-DE-BY-2.0.",
    sub("^data-", "", info$tag %||% "unknown")
  )
}
