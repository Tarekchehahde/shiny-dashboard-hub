# =============================================================================
# mastr_data.R — shared data-access layer for every dashboard in apps/
#
# The user NEVER downloads the XML. They also don't strictly need to download
# the DuckDB: every function here queries the Parquet files remotely through
# DuckDB's httpfs extension. Only the (usually tiny) result set is transferred.
#
# How it works:
#   1. `mastr_release_base()` resolves the most recent GitHub Release tag
#      (e.g. data-2026-04-21) and caches the base URL.
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
  library(httr2)
  library(rlang)
})

# ----- configuration ---------------------------------------------------------

.mastr_env <- new.env(parent = emptyenv())
.mastr_env$repo        <- Sys.getenv("MASTR_REPO", "Tarekchehahde/shiny-dashboard-hub")
.mastr_env$release_tag <- NULL            # resolved on first use
.mastr_env$base_url    <- NULL            # e.g. https://github.com/.../releases/download/data-2026-04-21
.mastr_env$local_db    <- NULL            # optional local .duckdb
.mastr_env$con         <- NULL

mastr_set_repo <- function(repo) {
  .mastr_env$repo <- repo
  .mastr_env$release_tag <- NULL
  .mastr_env$base_url <- NULL
  mastr_disconnect()
  invisible(repo)
}

mastr_clear_local_db <- function() {
  .mastr_env$local_db <- NULL
  mastr_disconnect()
  invisible(NULL)
}

mastr_use_local <- function(duckdb_path) {
  stopifnot(file.exists(duckdb_path))
  .mastr_env$local_db <- normalizePath(duckdb_path)
  mastr_disconnect()
  invisible(duckdb_path)
}

# ----- resolve latest release ------------------------------------------------

# RStudio often has no `gh` on PATH; private repos need a token for /releases/latest.
.strip_ansi <- function(x) {
  if (!nzchar(x)) return(x)
  gsub("\u001b\\[[0-9;]*m", "", x, perl = TRUE)
}

.ensure_github_token_from_gh <- function() {
  if (nzchar(Sys.getenv("GITHUB_TOKEN", ""))) return(invisible())
  candidates <- unique(c(
    path.expand("~/.homebrew/bin/gh"),
    "/opt/homebrew/bin/gh",
    "/usr/local/bin/gh",
    Sys.which("gh")
  ))
  candidates <- candidates[nzchar(candidates) & vapply(candidates, file.exists, logical(1))]
  for (gh in candidates) {
    out <- tryCatch(
      system2(gh, c("auth", "token"), stdout = TRUE, stderr = FALSE),
      error = function(e) character(0)
    )
    tok <- trimws(paste(out, collapse = ""))
    if (nzchar(tok) && nchar(tok) > 8L) {
      Sys.setenv(GITHUB_TOKEN = tok)
      return(invisible())
    }
  }
  invisible()
}

.resolve_release <- function() {
  if (!is.null(.mastr_env$release_tag)) return(invisible())
  repo <- .mastr_env$repo

  # Pin a release without calling the API (documented as MASTR_TAG but missing until now).
  tag_env <- Sys.getenv("MASTR_TAG", "")
  if (nzchar(tag_env)) {
    .mastr_env$release_tag <- tag_env
    .mastr_env$base_url <- sprintf("https://github.com/%s/releases/download/%s", repo, tag_env)
    return(invisible())
  }

  .ensure_github_token_from_gh()

  url  <- sprintf("https://api.github.com/repos/%s/releases/latest", repo)
  req  <- httr2::request(url) |>
    httr2::req_headers("Accept" = "application/vnd.github+json")
  tok  <- Sys.getenv("GITHUB_TOKEN", "")
  if (nzchar(tok)) req <- httr2::req_auth_bearer_token(req, tok)
  req_err <- NULL
  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      req_err <<- conditionMessage(e)
      NULL
    }
  )
  st <- if (!is.null(resp)) httr2::resp_status(resp) else NA_integer_
  no_resp <- is.null(resp) || (length(st) == 1L && is.na(st))
  if (no_resp || st >= 400) {
    hint_net <- if (no_resp && nzchar(req_err %||% "")) {
      paste0("\n  • Request failed before HTTP status: ", .strip_ansi(req_err))
    } else if (no_resp) {
      "\n  • No HTTP response (offline?, firewall/proxy blocking api.github.com?, or TLS issue in R)."
    } else {
      ""
    }
    hint404 <- if (identical(st, 404L)) {
      paste0(
        "\n  • GitHub returned 404: often means **no published releases**, **wrong MASTR_REPO**, or a **private** repo (set GITHUB_TOKEN with `repo` scope), or use:\n",
        "  • `Sys.setenv(MASTR_TAG = \"data-YYYY-MM-DD\")` if you know the data release tag, or\n",
        "  • `mastr_use_local(\"/path/to/mastr.duckdb\")` after downloading the asset, or\n",
        "  • `Sys.setenv(MASTR_LOCAL_DB = \"/path/to/mastr.duckdb\")` before loading apps (see README)."
      )
    } else if (!no_resp) {
      paste0("\n  • HTTP ", st, ". Check token, repo name, or use MASTR_TAG / mastr_use_local().")
    } else {
      ""
    }
    abort(paste0(
      "Could not resolve latest release for ", repo, " (HTTP ", ifelse(no_resp, "NA", st), ").",
      hint_net,
      hint404
    ))
  }
  body <- httr2::resp_body_json(resp)
  .mastr_env$release_tag <- body$tag_name
  .mastr_env$base_url    <- sprintf("https://github.com/%s/releases/download/%s",
                                    repo, body$tag_name)
  invisible()
}

#' Pin Parquet release by tag (same URLs as GitHub Releases assets).
mastr_pin_release <- function(tag) {
  stopifnot(is.character(tag), length(tag) == 1, nzchar(tag))
  .mastr_env$release_tag <- tag
  .mastr_env$base_url <- sprintf("https://github.com/%s/releases/download/%s",
                                  .mastr_env$repo, tag)
  mastr_disconnect()
  invisible(tag)
}

mastr_release_info <- function() {
  .resolve_release()
  list(repo = .mastr_env$repo,
       tag  = .mastr_env$release_tag,
       base = .mastr_env$base_url)
}

# ----- connection ------------------------------------------------------------

# DuckDB 1.5+ autoloads ICU when SQL uses `lower()` etc.; on macOS the bundled
# binary may be missing until INSTALL icu runs (downloads platform extension).
.ensure_duckdb_icu <- function(con) {
  tryCatch(DBI::dbExecute(con, "INSTALL icu;"), error = function(e) NULL)
  tryCatch(
    DBI::dbExecute(con, "LOAD icu;"),
    error = function(e) {
      warning(
        "DuckDB ICU extension could not be loaded. Queries using lower() may fail.\n",
        "Fix: run once in R: DBI::dbExecute(DBI::dbConnect(duckdb::duckdb()), \"INSTALL icu; LOAD icu;\")\n",
        "or ensure network access so DuckDB can download extensions.\n",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
}

#' Get a DuckDB connection bound to the latest MaStR release (or local db).
#'
#' Safe to call from many reactive expressions — the connection is cached.
mastr_con <- function() {
  if (!is.null(.mastr_env$con) && DBI::dbIsValid(.mastr_env$con)) return(.mastr_env$con)

  # Optional env: use a downloaded DuckDB — no GitHub API or remote Parquet.
  if (is.null(.mastr_env$local_db)) {
    lp <- Sys.getenv("MASTR_LOCAL_DB", "")
    if (nzchar(lp)) {
      lp <- normalizePath(path.expand(lp), mustWork = TRUE)
      .mastr_env$local_db <- lp
    }
  }

  if (!is.null(.mastr_env$local_db)) {
    con <- dbConnect(duckdb::duckdb(), dbdir = .mastr_env$local_db, read_only = TRUE)
    .ensure_duckdb_icu(con)
  } else {
    .resolve_release()
    con <- dbConnect(duckdb::duckdb())
    dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
    .ensure_duckdb_icu(con)
    dbExecute(con, "SET enable_http_metadata_cache=true;")
    dbExecute(con, "SET http_keep_alive=true;")
    .create_remote_views(con)
    # Only remote path uses pre-rolled agg_*.parquet; local mastr.duckdb uses v_* instead.
    .verify_agg_views_or_abort(con)
  }
  .mastr_env$con <- con
  con
}

mastr_disconnect <- function() {
  if (!is.null(.mastr_env$con) && DBI::dbIsValid(.mastr_env$con)) {
    try(dbDisconnect(.mastr_env$con, shutdown = TRUE), silent = TRUE)
  }
  .mastr_env$con <- NULL
  invisible()
}

# The entity list mirrors etl/src/mastr_etl/config.py ENTITIES. Keep in sync.
.remote_entities <- c(
  "solar", "wind", "biomasse", "wasser", "geothermie", "kernkraft",
  "verbrennung", "stromspeicher", "gaserzeuger", "gasverbraucher",
  "gasspeicher", "kwk", "eeg_solar", "eeg_wind", "eeg_biomasse", "eeg_wasser",
  "marktakteure", "netzanschlusspunkte", "bilanzierungsgebiete", "lokationen"
)

# DuckDB read_parquet(URL) does not send GITHUB_TOKEN. Private-repo release
# assets 404 without auth; download with httr2 + cache under tempdir() when a
# token is set. Public repos: still works (optional auth download then local read).
.parquet_read_source <- function(stem) {
  .ensure_github_token_from_gh()
  base <- .mastr_env$base_url
  url  <- sprintf("%s/%s.parquet", base, stem)
  tok  <- Sys.getenv("GITHUB_TOKEN", "")
  fname <- paste0(stem, ".parquet")
  tag <- .mastr_env$release_tag %||% "unknown"
  repo <- .mastr_env$repo

  cache_dir <- file.path(
    tempdir(),
    paste0("mastr-gh-", gsub("[^a-zA-Z0-9._-]", "_", tag))
  )
  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(cache_dir, fname)

  .path_for_sql <- function(p) {
    gsub("'", "''", normalizePath(p, winslash = "/", mustWork = TRUE), fixed = TRUE)
  }

  if (file.exists(dest) && file.info(dest)$size > 0L) {
    return(.path_for_sql(dest))
  }

  if (!nzchar(tok)) {
    return(gsub("'", "''", url, fixed = TRUE))
  }

  # Private repos: `releases/download/...` often does not honour Bearer; use
  # GET /releases/tags/{tag} then GET /releases/assets/{id} (octet-stream).
  rel_req <- httr2::request(
    sprintf("https://api.github.com/repos/%s/releases/tags/%s", repo, tag)
  ) |>
    httr2::req_headers("Accept" = "application/vnd.github+json") |>
    httr2::req_auth_bearer_token(tok)
  rel_resp <- tryCatch(httr2::req_perform(rel_req), error = function(e) NULL)
  aid <- NULL
  if (!is.null(rel_resp) && httr2::resp_status(rel_resp) < 400) {
    rel <- httr2::resp_body_json(rel_resp)
    assets <- rel$assets %||% list()
    for (i in seq_along(assets)) {
      a <- assets[[i]]
      if (identical(a$name, fname)) {
        aid <- a$id
        break
      }
    }
  }
  if (!is.null(aid)) {
    ast_req <- httr2::request(
      sprintf("https://api.github.com/repos/%s/releases/assets/%s", repo, aid)
    ) |>
      httr2::req_headers("Accept" = "application/octet-stream") |>
      httr2::req_auth_bearer_token(tok)
    ast_resp <- tryCatch(httr2::req_perform(ast_req), error = function(e) NULL)
    if (!is.null(ast_resp) && httr2::resp_status(ast_resp) < 400) {
      raw <- httr2::resp_body_raw(ast_resp)
      if (length(raw) > 0L) writeBin(raw, dest)
    }
  }

  if (file.exists(dest) && file.info(dest)$size > 0L) {
    return(.path_for_sql(dest))
  }

  # Fallback: direct release URL (works for many public assets)
  resp <- tryCatch(
    httr2::req_perform(httr2::request(url) |> httr2::req_auth_bearer_token(tok)),
    error = function(e) NULL
  )
  if (!is.null(resp) && httr2::resp_status(resp) < 400) {
    raw <- httr2::resp_body_raw(resp)
    if (length(raw) > 0L) writeBin(raw, dest)
  }

  if (file.exists(dest) && file.info(dest)$size > 0L) {
    return(.path_for_sql(dest))
  }

  gsub("'", "''", url, fixed = TRUE)
}

# Exact column names as DuckDB sees them on the raw Parquet-backed view.
.table_pragma_names <- function(con, table) {
  qtbl <- DBI::dbQuoteIdentifier(con, table)
  res <- tryCatch(
    DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", qtbl)),
    error = function(e) NULL
  )
  if (is.null(res) || nrow(res) == 0L || !"name" %in% names(res)) return(character(0))
  res$name
}

# BNetzA sometimes renames storage-capacity fields in EinheitStromSpeicher XML.
# Normalise to a single NutzbareSpeicherkapazitaet (kWh) so apps/08_* and
# thesis SQL stay stable.
.create_stromspeicher_compat_view <- function(con) {
  exact <- .table_pragma_names(con, "stromspeicher_raw")
  if (length(exact) == 0L) {
    try(
      DBI::dbExecute(con, "CREATE OR REPLACE VIEW stromspeicher AS SELECT * FROM stromspeicher_raw WHERE FALSE"),
      silent = TRUE
    )
    return(invisible())
  }

  used <- rep(FALSE, length(exact))
  pieces <- character(0)

  add_num <- function(nm, divisor = 1) {
    idx <- which(tolower(exact) == tolower(nm))
    if (length(idx) == 0L) return(invisible())
    used[idx[1]] <<- TRUE
    q <- DBI::dbQuoteIdentifier(con, exact[idx[1]])
    if (divisor == 1L) {
      pieces <<- c(pieces, sprintf("TRY_CAST(%s AS DOUBLE)", q))
    } else {
      pieces <<- c(pieces, sprintf("(TRY_CAST(%s AS DOUBLE) / %.1f)", q, as.double(divisor)))
    }
  }

  add_num("NutzbareSpeicherkapazitaet")
  add_num("NutzbareSpeicherkapazitaetInKWh")
  add_num("SpeicherKapazitaet")
  add_num("NutzbareSpeicherkapazitaetInWh", 1000)
  add_num("NutzbareSpeicherkapazitaetWh", 1000)

  if (length(pieces) == 0L) {
    for (i in seq_along(exact)) {
      if (used[i]) next
      if (grepl("speicherkapaz", tolower(exact[i]), fixed = TRUE)) {
        used[i] <- TRUE
        q <- DBI::dbQuoteIdentifier(con, exact[i])
        pieces <- c(pieces, sprintf("TRY_CAST(%s AS DOUBLE)", q))
      }
    }
  }

  # MaStR schema drift: capacity sometimes appears as Nutzbar…Kapazität… without
  # "Speicher" in the name, or only as kWh field — pick first plausible numeric.
  if (length(pieces) == 0L) {
    for (i in seq_along(exact)) {
      if (used[i]) next
      tl <- tolower(exact[i])
      if (grepl("datum", tl, fixed = TRUE) || grepl("reserve", tl, fixed = TRUE)) next
      if ((grepl("nutzbar", tl, fixed = TRUE) && grepl("kapaz", tl, fixed = TRUE)) ||
          (grepl("kwh", tl, fixed = TRUE) && grepl("speicher", tl, fixed = TRUE))) {
        used[i] <- TRUE
        q <- DBI::dbQuoteIdentifier(con, exact[i])
        pieces <- c(pieces, sprintf("TRY_CAST(%s AS DOUBLE)", q))
      }
    }
  }

  cap_expr <- if (length(pieces) == 0L) {
    "NULL::DOUBLE"
  } else if (length(pieces) == 1L) {
    pieces
  } else {
    sprintf("COALESCE(%s)", paste(pieces, collapse = ", "))
  }

  pass <- exact[!used]
  sel <- character(0)
  if (length(pass)) {
    for (nm in pass) {
      sel <- c(sel, DBI::dbQuoteIdentifier(con, nm))
    }
  }
  sel <- c(
    sel,
    sprintf("%s AS %s", cap_expr, DBI::dbQuoteIdentifier(con, "NutzbareSpeicherkapazitaet"))
  )

  # Sub-type chemistry (e.g. Li-Ion) — older Parquet may omit this column; apps can still SELECT it.
  if (!any(tolower(exact) == "batterietechnologie")) {
    sel <- c(
      sel,
      sprintf("NULL::VARCHAR AS %s", DBI::dbQuoteIdentifier(con, "Batterietechnologie"))
    )
  }

  sql <- sprintf(
    "CREATE OR REPLACE VIEW stromspeicher AS SELECT %s FROM stromspeicher_raw",
    paste(sel, collapse = ", ")
  )
  try(DBI::dbExecute(con, sql), silent = TRUE)
  invisible()
}

.create_remote_views <- function(con) {
  for (e in .remote_entities) {
    src <- .parquet_read_source(e)
    if (identical(e, "stromspeicher")) {
      sql <- sprintf(
        "CREATE OR REPLACE VIEW stromspeicher_raw AS SELECT * FROM read_parquet('%s')",
        src
      )
      try(dbExecute(con, sql), silent = TRUE)
      .create_stromspeicher_compat_view(con)
      next
    }
    sql <- sprintf(
      "CREATE OR REPLACE VIEW %s AS SELECT * FROM read_parquet('%s')",
      e, src)
    try(dbExecute(con, sql), silent = TRUE)
  }
  # Aggregate parquets (small, ~1 MB each) that Python pre-rolled:
  agg_files <- c(
    "kpi_overview", "capacity_by_state", "buildout_monthly",
    "capacity_by_plz_top5000", "solar_size_classes",
    "wind_hub_height", "ee_quote_by_year"
  )
  for (a in agg_files) {
    src <- .parquet_read_source(a)
    sql <- sprintf(
      "CREATE OR REPLACE VIEW agg_%s AS SELECT * FROM read_parquet('%s')",
      a, src)
    try(dbExecute(con, sql), silent = TRUE)
  }
  # Re-create the cross-entity view (same SQL as build_duckdb.py).
  .create_units_view(con)
}

# After remote views, fail fast if aggregate parquets did not load (try() swallows errors).
.verify_agg_views_or_abort <- function(con) {
  ok <- tryCatch(
    {
      DBI::dbGetQuery(con, "SELECT 1 AS ok FROM agg_kpi_overview LIMIT 1")
      TRUE
    },
    error = function(e) FALSE
  )
  if (ok) return(invisible())
  base <- .mastr_env$base_url %||% ""
  tok  <- nzchar(Sys.getenv("GITHUB_TOKEN", ""))
  abort(paste0(
    "Dashboard views are missing (e.g. agg_kpi_overview). ",
    "Could not load `kpi_overview.parquet` for this release.\n\n",
    "Open (logged into GitHub if the repo is private):\n  ",
    base, "/kpi_overview.parquet\n\n",
    if (!tok) {
      "Private repos: set `GITHUB_TOKEN` before Shiny so parquet can be downloaded (DuckDB HTTP does not send your token).\n\n"
    } else {
      ""
    },
    "Or use `mastr_use_local(\"/path/to/mastr.duckdb\")` after downloading from Releases."
  ))
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
    parts <- c(parts, sprintf("
      SELECT
        '%1$s'                                                     AS source_table,
        '%2$s'                                                     AS energietraeger,
        %3$s                                                       AS mastr_nr,
        %4$s                                                       AS bruttoleistung_kw,
        %5$s                                                       AS nettonennleistung_kw,
        %6$s                                                       AS bundesland_code,
        %7$s                                                       AS gemeinde,
        %8$s                                                       AS plz,
        %9$s                                                       AS lon,
        %10$s                                                      AS lat,
        %11$s                                                      AS inbetriebnahme_datum,
        %12$s                                                      AS betriebsstatus
      FROM %1$s t",
      k, eg,
      .col_or_null(cols, "EinheitMastrNummer"),
      .col_or_null(cols, "Bruttoleistung",     cast = "DOUBLE"),
      .col_or_null(cols, "Nettonennleistung",  cast = "DOUBLE"),
      .col_or_null(cols, "Bundesland"),
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

#' Run a SQL query and return a data.frame. Memoised for the duration of the
#' R session so repeated reactive evaluations don't re-fetch.
mastr_query <- memoise::memoise(function(sql, params = list()) {
  con <- mastr_con()
  if (length(params)) {
    DBI::dbGetQuery(con, sql, params = params)
  } else {
    DBI::dbGetQuery(con, sql)
  }
})

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

# ----- footer helper ---------------------------------------------------------

mastr_attribution <- function() {
  info <- tryCatch(mastr_release_info(), error = function(e) list(tag = "unknown"))
  sprintf(
    "Datenquelle: Marktstammdatenregister — \u00a9 Bundesnetzagentur (Stand: %s), bereitgestellt unter DL-DE-BY-2.0.",
    sub("^data-", "", info$tag %||% "unknown")
  )
}
