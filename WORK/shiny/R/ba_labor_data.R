# Bundesagentur für Arbeit — STEA (gemeldete Stellen) + BST (Beschäftigung).
# API docs: https://statistik.arbeitsagentur.de/DE/Navigation/Service/API/API-Start-Nav.html

BA_API_BASE <- "https://statistik-dr.arbeitsagentur.de/bifrontend/bids-api/pc/v1/tableFetch/dia"
BA_FACHKRAEFTE_CACHE_HOURS <- 24L

.ba_fachkraefte_cache <- new.env(parent = emptyenv())

.ba_cache_rds_path <- function() {
  file.path(.thueringen_data_dir(), "ba_fachkraefte_cache.rds")
}

.ba_fetch_json <- function(path_query) {
  url <- paste0(BA_API_BASE, path_query)
  resp <- httr2::request(url) |>
    httr2::req_timeout(45) |>
    httr2::req_retry(max_tries = 2, backoff = ~1) |>
    httr2::req_perform()
  jsonlite::fromJSON(httr2::resp_body_string(resp), simplifyVector = FALSE)
}

.ba_first_metric <- function(rows, metric_name) {
  if (is.null(rows) || !length(rows)) {
    return(list(value = NA_real_, period = NA_character_))
  }
  for (row in rows) {
    if (!identical(row$metricName, metric_name)) {
      next
    }
    attrs <- row$attributes
    period <- NA_character_
    if (!is.null(attrs) && length(attrs)) {
      a0 <- attrs[[1]]
      if (!is.null(a0$DESC)) {
        period <- as.character(a0$DESC)
      }
    }
    return(list(value = suppressWarnings(as.numeric(row$value)), period = period))
  }
  list(value = NA_real_, period = NA_character_)
}

.ba_kreis_api_name <- function(kreis) {
  overrides <- c(
    "Landkreis Gotha" = "Gotha",
    "Landkreis Greiz" = "Greiz",
    "Landkreis Hildburghausen" = "Hildburghausen",
    "Landkreis Schmalkalden-Meiningen" = "Schmalkalden-Meiningen",
    "Nordhausen, Landkreis" = "Nordhausen",
    "Sonneberg, Landkreis" = "Sonneberg",
    "S\u00f6mmerda, Landkreis" = "S\u00f6mmerda"
  )
  if (identical(kreis, "Eisenach, Stadt")) {
    return(list(
      name = NA_character_,
      note = "Seit 07/2024 im Wartburgkreis \u2014 keine separate BA-Kreisstatistik"
    ))
  }
  if (kreis %in% names(overrides)) {
    return(list(name = unname(overrides[[kreis]]), note = NA_character_))
  }
  list(name = kreis, note = NA_character_)
}

.ba_fetch_kreis_labor <- function(kreis) {
  api <- .ba_kreis_api_name(kreis)
  if (is.na(api$name)) {
    return(data.frame(
      kreis = kreis,
      beschaeftigte = NA_real_,
      beschaeftigte_tausend = NA_real_,
      offene_stellen = NA_real_,
      quote_vakanz_pct = NA_real_,
      stellen_yoy_pct = NA_real_,
      recruiting_index = NA_real_,
      stea_periode = NA_character_,
      bst_periode = NA_character_,
      ba_note = api$note,
      stringsAsFactors = FALSE
    ))
  }

  enc <- utils::URLencode(api$name, reserved = TRUE)
  stea <- .ba_fetch_json(paste0("/EckwerteTabelleSTEA?Kreis=", enc))
  bst <- .ba_fetch_json(paste0("/EckwerteTabelleBST?Kreis%20AO=", enc))

  stellen <- .ba_first_metric(stea, "Bestand Arbeitsstellen")
  yoy <- .ba_first_metric(stea, "STEA_VJV_rel")
  besch <- .ba_first_metric(bst, "Beschäftigte")

  besch_n <- besch$value
  stellen_n <- stellen$value
  quote <- if (!is.na(besch_n) && besch_n > 0 && !is.na(stellen_n)) {
    stellen_n / besch_n * 100
  } else {
    NA_real_
  }
  index <- if (!is.na(besch_n) && besch_n > 0 && !is.na(stellen_n)) {
    stellen_n / besch_n * 1000
  } else {
    NA_real_
  }

  data.frame(
    kreis = kreis,
    beschaeftigte = besch_n,
    beschaeftigte_tausend = if (!is.na(besch_n)) besch_n / 1000 else NA_real_,
    offene_stellen = stellen_n,
    quote_vakanz_pct = quote,
    stellen_yoy_pct = yoy$value,
    recruiting_index = index,
    stea_periode = stellen$period,
    bst_periode = besch$period,
    ba_note = NA_character_,
    stringsAsFactors = FALSE
  )
}

.ba_fetch_land_labor <- function(bundesland = "Th\u00fcringen") {
  enc <- utils::URLencode(bundesland, reserved = TRUE)
  stea <- .ba_fetch_json(paste0("/EckwerteTabelleSTEA?Bundesland=", enc))
  bst <- .ba_fetch_json(paste0("/EckwerteTabelleBST?Bundesland%20AO=", enc))

  stellen <- .ba_first_metric(stea, "Bestand Arbeitsstellen")
  besch <- .ba_first_metric(bst, "Beschäftigte")
  besch_n <- besch$value
  stellen_n <- stellen$value

  list(
    offene_stellen = stellen_n,
    beschaeftigte = besch_n,
    quote_vakanz_pct = if (!is.na(besch_n) && besch_n > 0 && !is.na(stellen_n)) {
      stellen_n / besch_n * 100
    } else {
      NA_real_
    },
    stea_periode = stellen$period,
    bst_periode = besch$period
  )
}

#' Fetch Kreis-level STEA/BST for all Thüringen districts (+ Land totals).
ba_fetch_fachkraefte <- function(kreis_meta = thueringen_kreis_meta(), progress = NULL) {
  kreise <- kreis_meta$kreis
  n <- length(kreise)
  parts <- vector("list", n)
  for (i in seq_len(n)) {
    if (!is.null(progress)) {
      progress(i / n, detail = kreise[[i]])
    }
    parts[[i]] <- .ba_fetch_kreis_labor(kreise[[i]])
    if (i < n) {
      Sys.sleep(0.05)
    }
  }
  kreise_df <- dplyr::bind_rows(parts)
  kreise_df <- dplyr::left_join(kreise_df, kreis_meta, by = "kreis")
  land <- .ba_fetch_land_labor()

  list(
    kreise = kreise_df,
    land = land,
    meta = list(
      fetched_at = Sys.time(),
      stea_periode = land$stea_periode,
      bst_periode = land$bst_periode,
      source = "Bundesagentur f\u00fcr Arbeit (STEA/BST)"
    )
  )
}

#' Cached BA labor dataset (memory + optional RDS, 24h TTL).
ba_cached_fachkraefte <- function(force = FALSE, progress = NULL) {
  cache_path <- .ba_cache_rds_path()
  ttl_secs <- BA_FACHKRAEFTE_CACHE_HOURS * 3600

  if (!force && !is.null(.ba_fachkraefte_cache$data) && !is.null(.ba_fachkraefte_cache$ts) &&
      difftime(Sys.time(), .ba_fachkraefte_cache$ts, units = "secs") < ttl_secs) {
    return(.ba_fachkraefte_cache$data)
  }

  if (!force && file.exists(cache_path)) {
    disk <- tryCatch(readRDS(cache_path), error = function(e) NULL)
    if (!is.null(disk$data) && !is.null(disk$ts) &&
        difftime(Sys.time(), disk$ts, units = "secs") < ttl_secs) {
      .ba_fachkraefte_cache$data <- disk$data
      .ba_fachkraefte_cache$ts <- disk$ts
      return(disk$data)
    }
  }

  payload <- ba_fetch_fachkraefte(progress = progress)
  .ba_fachkraefte_cache$data <- payload
  .ba_fachkraefte_cache$ts <- Sys.time()
  tryCatch(
    saveRDS(list(ts = .ba_fachkraefte_cache$ts, data = payload), cache_path),
    error = function(e) invisible(NULL)
  )
  payload
}
