# Parse nginx combined access logs for the MaStR hub traffic dashboard.

NGINX_COMBINED_RE <- "^([^ ]+) [^ ]+ [^ ]+ \\[([^\\]]+)\\] \"([A-Z]+) ([^ ]+) [^\"]+\" ([0-9]+) ([^ ]+) \"([^\"]*)\" \"(.*)\"$"

nginx_log_path <- function() {
  env <- Sys.getenv("MASTR_NGINX_LOG", "")
  if (nzchar(env) && file.exists(env)) {
    return(env)
  }
  candidates <- c(
    "/var/log/nginx/access.log",
    "/opt/mastr-shiny/logs/nginx-access.log"
  )
  for (p in candidates) {
    if (file.exists(p)) {
      return(p)
    }
  }
  candidates[[1]]
}

parse_nginx_request <- function(request) {
  m <- regexec("^([A-Z]+) ([^ ]+)", request)
  hit <- regmatches(request, m)[[1]]
  if (length(hit) < 3) {
    return(list(method = NA_character_, path = NA_character_))
  }
  list(method = hit[2], path = hit[3])
}

parse_nginx_timestamp <- function(ts) {
  out <- as.POSIXct(ts, format = "%d/%b/%Y:%H:%M:%S %z", tz = "UTC")
  if (all(is.na(out))) {
    out <- as.POSIXct(ts, format = "%d/%b/%Y:%H:%M:%S", tz = "UTC")
  }
  out
}

parse_nginx_line <- function(line) {
  line <- trimws(line)
  m <- regexec(NGINX_COMBINED_RE, line, perl = TRUE)
  hit <- regmatches(line, m)[[1]]
  if (length(hit) < 9) {
    return(NULL)
  }
  data.frame(
    ip = hit[2],
    time = parse_nginx_timestamp(hit[3]),
    method = hit[4],
    path = hit[5],
    status = as.integer(hit[6]),
    bytes = suppressWarnings(as.numeric(hit[7])),
    referer = hit[8],
    user_agent = hit[9],
    stringsAsFactors = FALSE
  )
}

read_nginx_tail <- function(path = nginx_log_path(), max_lines = 100000L) {
  if (!file.exists(path)) {
    stop("Nginx access log not found: ", path, call. = FALSE)
  }
  lines <- tryCatch(
    system2("tail", c("-n", as.character(max_lines), shQuote(path)),
            stdout = TRUE, stderr = FALSE),
    error = function(e) character()
  )
  if (!length(lines)) {
    lines <- readLines(path, warn = FALSE)
    n <- length(lines)
    if (n > max_lines) {
      lines <- lines[(n - max_lines + 1L):n]
    }
  }
  lines
}

read_nginx_access <- function(path = nginx_log_path(), max_lines = 100000L) {
  lines <- read_nginx_tail(path, max_lines)
  lines <- lines[nzchar(lines)]
  if (!length(lines)) {
    return(data.frame(
      ip = character(), time = as.POSIXct(character()),
      method = character(), path = character(),
      status = integer(), bytes = numeric(),
      referer = character(), user_agent = character(),
      stringsAsFactors = FALSE
    ))
  }
  chunks <- lapply(lines, parse_nginx_line)
  chunks <- chunks[!vapply(chunks, is.null, logical(1))]
  if (!length(chunks)) {
    return(read_nginx_access_empty())
  }
  do.call(rbind, chunks)
}

read_nginx_access_empty <- function() {
  data.frame(
    ip = character(), time = as.POSIXct(character()),
    method = character(), path = character(),
    status = integer(), bytes = numeric(),
    referer = character(), user_agent = character(),
    stringsAsFactors = FALSE
  )
}

nginx_is_dashboard_entry <- function(path) {
  if (is.na(path) || !nzchar(path)) {
    return(FALSE)
  }
  path <- sub("\\?.*$", "", path)
  if (path == "/" || grepl("^/+$", path)) {
    return(TRUE)
  }
  grepl("^/[^/]+/?$", path)
}

nginx_is_asset_request <- function(path) {
  if (is.na(path) || !nzchar(path)) {
    return(TRUE)
  }
  if (!nginx_is_dashboard_entry(path)) {
    return(TRUE)
  }
  grepl(
    "(websocket|/__|/lib/|/shiny-|/bootstrap-|/jquery-|/font-|\\.woff|\\.woff2)",
    path,
    ignore.case = TRUE,
    perl = TRUE
  ) ||
    grepl(
      "\\.(js|css|png|jpg|jpeg|gif|svg|ico|map|json|tsv|wasm)(\\?|$)",
      path,
      ignore.case = TRUE,
      perl = TRUE
    )
}

nginx_dashboard_slug <- function(path) {
  if (is.na(path) || path == "/") {
    return("hub")
  }
  parts <- strsplit(sub("^/+", "", path), "/", fixed = TRUE)[[1]]
  slug <- parts[1]
  if (!nzchar(slug)) {
    return("hub")
  }
  slug
}

traffic_excluded_ips <- function() {
  env <- Sys.getenv("MASTR_TRAFFIC_EXCLUDE_IPS", "")
  from_env <- if (nzchar(env)) {
    trimws(strsplit(env, ",", fixed = TRUE)[[1]])
  } else {
    character()
  }
  from_env <- from_env[nzchar(from_env)]
  unique(c("127.0.0.1", "::1", from_env))
}

nginx_is_excluded_ip <- function(ip) {
  ip %in% traffic_excluded_ips()
}

nginx_is_bot_ua <- function(ua) {
  ua <- tolower(ua %||% "")
  if (!nzchar(ua) || ua == "-") {
    return(TRUE)
  }
  grepl(
    paste(
      "bot|crawl|spider|slurp|scanner|curl|wget|python-requests|go-http|java/",
      "headless|selenium|puppeteer|playwright|axios|okhttp|libwww|httpclient",
      "zgrab|masscan|nikto|semrush|ahrefs|petalbot|bytespider|gptbot|claudebot",
      "bingpreview|facebookexternalhit|linkedinbot|twitterbot|duckduckbot",
      "baiduspider|yandex|archive\\.org|httpunit|netcraft|censys|l9scan"
    ),
    ua,
    perl = TRUE
  )
}

nginx_is_browser_ua <- function(ua) {
  ua <- tolower(ua %||% "")
  nzchar(ua) && ua != "-" &&
    grepl("mozilla/", ua, fixed = TRUE) &&
    !nginx_is_bot_ua(ua)
}

nginx_has_referer <- function(referer) {
  ref <- referer %||% ""
  nzchar(ref) && ref != "-"
}

nginx_classify_visit <- function(ua, referer, ip_hit_count) {
  if (nginx_is_bot_ua(ua)) {
    return("Bot")
  }
  if (!nginx_is_browser_ua(ua)) {
    return("Scanner")
  }
  if (ip_hit_count >= 2L || nginx_has_referer(referer)) {
    return("Organic")
  }
  "Uncertain"
}

nginx_apply_geo_to_kind <- function(kind, hosting, proxy) {
  if (isTRUE(hosting) || isTRUE(proxy)) {
    if (kind %in% c("Organic", "Uncertain")) {
      return("Cloud")
    }
  }
  kind
}

traffic_geo_cache_path <- function() {
  Sys.getenv("MASTR_TRAFFIC_GEO_CACHE", "/var/cache/mastr-shiny/ip-geo.csv")
}

traffic_geo_cache_read <- function() {
  path <- traffic_geo_cache_path()
  empty <- data.frame(
    ip = character(),
    country = character(),
    city = character(),
    isp = character(),
    hosting = logical(),
    proxy = logical(),
    queried_at = character(),
    stringsAsFactors = FALSE
  )
  if (!file.exists(path)) {
    return(empty)
  }
  tryCatch({
    out <- read.csv(path, stringsAsFactors = FALSE)
    out$hosting <- as.logical(out$hosting)
    out$proxy <- as.logical(out$proxy)
    out
  }, error = function(e) empty)
}

traffic_geo_cache_write <- function(df) {
  path <- traffic_geo_cache_path()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tryCatch(
    write.csv(df, path, row.names = FALSE),
    error = function(e) {
      message("Geo cache write skipped: ", conditionMessage(e))
      invisible(FALSE)
    }
  )
}

traffic_fetch_ip_geo_one <- function(ip) {
  if (!grepl("^[0-9.]+$", ip)) {
    return(NULL)
  }
  lines <- tryCatch(
    system2(
      "curl",
      c(
        "-fsS", "--max-time", "8",
        paste0(
          "http://ip-api.com/json/", ip,
          "?fields=status,query,country,city,isp,hosting,proxy"
        )
      ),
      stdout = TRUE
    ),
    error = function(e) NULL
  )
  if (is.null(lines) || !length(lines)) {
    return(NULL)
  }
  raw <- paste(lines, collapse = "")
  if (!grepl('"status":"success"', raw, fixed = TRUE)) {
    return(NULL)
  }
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    x <- tryCatch(jsonlite::fromJSON(raw), error = function(e) NULL)
    if (!is.null(x) && identical(x$status, "success")) {
      return(data.frame(
        ip = x$query %||% ip,
        country = x$country %||% NA_character_,
        city = x$city %||% NA_character_,
        isp = x$isp %||% NA_character_,
        hosting = isTRUE(x$hosting),
        proxy = isTRUE(x$proxy),
        queried_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
        stringsAsFactors = FALSE
      ))
    }
  }
  grab_text <- function(field) {
    m <- regexec(paste0('"', field, '":"([^"]*)"'), raw, perl = TRUE)
    hit <- regmatches(raw, m)[[1]]
    if (length(hit) < 2) {
      return(NA_character_)
    }
    hit[2]
  }
  grab_bool <- function(field) {
    grepl(paste0('"', field, '":true'), raw, fixed = TRUE)
  }
  data.frame(
    ip = grab_text("query"),
    country = grab_text("country"),
    city = grab_text("city"),
    isp = grab_text("isp"),
    hosting = grab_bool("hosting"),
    proxy = grab_bool("proxy"),
    queried_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
}

traffic_geo_lookup_ips <- function(ips, max_new = 25L) {
  ips <- unique(ips[nzchar(ips) & grepl("^[0-9.]+$", ips)])
  if (!length(ips)) {
    return(traffic_geo_cache_read())
  }
  cache <- traffic_geo_cache_read()
  missing <- setdiff(ips, cache$ip)
  if (length(missing) > max_new) {
    missing <- missing[seq_len(max_new)]
  }
  for (ip in missing) {
    row <- traffic_fetch_ip_geo_one(ip)
    if (!is.null(row)) {
      cache <- rbind(cache, row)
    }
    Sys.sleep(0.12)
  }
  if (length(missing)) {
    traffic_geo_cache_write(cache)
  }
  cache[cache$ip %in% ips, , drop = FALSE]
}

traffic_enrich_page_views_geo <- function(pv) {
  if (!nrow(pv)) {
    return(pv)
  }
  geo <- traffic_geo_lookup_ips(unique(pv$ip))
  drop_geo <- intersect(names(pv), c("country", "city", "isp", "hosting", "proxy"))
  if (length(drop_geo)) {
    pv <- pv[, setdiff(names(pv), drop_geo), drop = FALSE]
  }
  if (!nrow(geo)) {
    pv$country <- NA_character_
    pv$city <- NA_character_
    pv$isp <- NA_character_
    pv$hosting <- NA
    pv$proxy <- NA
    return(pv)
  }
  pv <- merge(
    pv,
    geo[, c("ip", "country", "city", "isp", "hosting", "proxy")],
    by = "ip",
    all.x = TRUE
  )
  pv$visitor_kind <- mapply(
    nginx_apply_geo_to_kind,
    pv$visitor_kind,
    pv$hosting,
    pv$proxy,
    USE.NAMES = FALSE
  )
  pv
}

nginx_ip_visitor_kind <- function(kinds) {
  kinds <- kinds[!is.na(kinds)]
  if (!length(kinds)) {
    return("Uncertain")
  }
  if (any(kinds == "Bot")) {
    return("Bot")
  }
  if (any(kinds == "Cloud")) {
    return("Cloud")
  }
  if (any(kinds == "Scanner")) {
    return("Scanner")
  }
  if (all(kinds == "Organic")) {
    return("Organic")
  }
  if (any(kinds == "Organic")) {
    return("Mixed")
  }
  "Uncertain"
}

nginx_device_label <- function(ua) {
  ua <- tolower(ua %||% "")
  if (grepl("ipad|tablet", ua)) {
    return("Tablet")
  }
  if (grepl("mobile|iphone|android", ua)) {
    return("Phone")
  }
  if (grepl("bot|crawl|spider|slurp", ua)) {
    return("Bot")
  }
  "Desktop"
}

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

nginx_page_views <- function(df) {
  if (!nrow(df)) {
    return(df)
  }
  df <- df[!vapply(df$ip, nginx_is_excluded_ip, logical(1)), , drop = FALSE]
  df <- df[df$method == "GET" & df$status %in% c(200L, 304L), , drop = FALSE]
  df <- df[vapply(df$path, nginx_is_dashboard_entry, logical(1)), , drop = FALSE]
  df$dashboard <- vapply(df$path, nginx_dashboard_slug, character(1))
  df$device <- vapply(df$user_agent, nginx_device_label, character(1))
  ip_tab <- table(df$ip)
  df$ip_hits <- as.integer(ip_tab[df$ip])
  df$visitor_kind <- mapply(
    nginx_classify_visit,
    df$user_agent,
    df$referer,
    df$ip_hits,
    USE.NAMES = FALSE
  )
  df
}

nginx_filter_page_views <- function(pv, audience = c("all", "organic", "non_organic")) {
  audience <- match.arg(audience)
  if (!nrow(pv) || audience == "all") {
    return(pv)
  }
  if (audience == "organic") {
    return(pv[pv$visitor_kind %in% c("Organic", "Mixed"), , drop = FALSE])
  }
  pv[!pv$visitor_kind %in% c("Organic", "Mixed"), , drop = FALSE]
}

nginx_traffic_summary <- function(df, days = 7L, audience = "all") {
  pv <- nginx_page_views(df)
  if (!nrow(pv)) {
    return(list(
      page_views = pv,
      total_hits = 0L,
      unique_ips = 0L,
      organic_hits = 0L,
      bot_hits = 0L,
      cloud_hits = 0L,
      uncertain_hits = 0L,
      by_day = data.frame(),
      by_day_kind = data.frame(),
      by_hour = data.frame(),
      by_dashboard = data.frame(),
      by_ip = data.frame(),
      by_device = data.frame(),
      by_visitor_kind = data.frame(),
      recent = data.frame()
    ))
  }
  cutoff <- Sys.time() - as.difftime(days, units = "days")
  pv <- pv[!is.na(pv$time) & pv$time >= cutoff, , drop = FALSE]
  if (!nrow(pv)) {
    return(nginx_traffic_summary(df, days = days * 2, audience = audience))
  }

  pv <- traffic_enrich_page_views_geo(pv)

  organic_hits <- sum(pv$visitor_kind %in% c("Organic", "Mixed"))
  bot_hits <- sum(pv$visitor_kind %in% c("Bot", "Scanner"))
  cloud_hits <- sum(pv$visitor_kind == "Cloud")
  uncertain_hits <- sum(pv$visitor_kind == "Uncertain")

  pv_view <- nginx_filter_page_views(pv, audience = audience)

  by_day <- if (nrow(pv_view)) {
    out <- as.data.frame(table(format(pv_view$time, "%Y-%m-%d")))
    names(out) <- c("day", "hits")
    out$day <- as.Date(out$day)
    out[order(out$day), ]
  } else {
    data.frame(day = as.Date(character()), hits = integer())
  }

  by_day_kind <- if (nrow(pv)) {
    out <- as.data.frame(table(
      format(pv$time, "%Y-%m-%d"),
      pv$visitor_kind
    ))
    names(out) <- c("day", "visitor_kind", "hits")
    out$day <- as.Date(out$day)
    out[order(out$day, out$visitor_kind), ]
  } else {
    data.frame(day = as.Date(character()), visitor_kind = character(), hits = integer())
  }

  by_hour <- if (nrow(pv_view)) {
    out <- as.data.frame(table(format(pv_view$time, "%H:00")))
    names(out) <- c("hour", "hits")
    out
  } else {
    data.frame(hour = character(), hits = integer())
  }

  by_dashboard <- if (nrow(pv_view)) {
    out <- as.data.frame(table(pv_view$dashboard))
    names(out) <- c("dashboard", "hits")
    out[order(-out$hits), ]
  } else {
    data.frame(dashboard = character(), hits = integer())
  }

  ip_tab <- as.data.frame(table(pv$ip))
  names(ip_tab) <- c("ip", "hits")
  ip_tab <- ip_tab[order(-ip_tab$hits), ]
  ip_last <- aggregate(time ~ ip, data = pv, FUN = max)
  names(ip_last)[2] <- "last_seen"
  ip_dev <- aggregate(device ~ ip, data = pv, FUN = function(x) {
    tab <- sort(table(x), decreasing = TRUE)
    names(tab)[1]
  })
  names(ip_dev)[2] <- "device"
  ip_kind <- aggregate(visitor_kind ~ ip, data = pv, FUN = nginx_ip_visitor_kind)
  names(ip_kind)[2] <- "visitor_kind"
  ip_geo <- if (nrow(pv)) {
    out <- aggregate(
      cbind(country, city, isp) ~ ip,
      data = pv,
      FUN = function(x) {
        x <- x[!is.na(x) & nzchar(as.character(x))]
        if (!length(x)) {
          return(NA_character_)
        }
        as.character(x[1])
      }
    )
    out
  } else {
    data.frame(
      ip = character(),
      country = character(),
      city = character(),
      isp = character(),
      stringsAsFactors = FALSE
    )
  }
  by_ip <- merge(ip_tab, ip_last, by = "ip", all.x = TRUE)
  by_ip <- merge(by_ip, ip_dev, by = "ip", all.x = TRUE)
  by_ip <- merge(by_ip, ip_kind, by = "ip", all.x = TRUE)
  by_ip <- merge(by_ip, ip_geo, by = "ip", all.x = TRUE)
  by_ip <- by_ip[order(-by_ip$hits), ]
  if (audience == "organic") {
    by_ip <- by_ip[by_ip$visitor_kind %in% c("Organic", "Mixed"), , drop = FALSE]
  } else if (audience == "non_organic") {
    by_ip <- by_ip[!by_ip$visitor_kind %in% c("Organic", "Mixed"), , drop = FALSE]
  }

  by_device <- if (nrow(pv_view)) {
    out <- as.data.frame(table(pv_view$device))
    names(out) <- c("device", "hits")
    out
  } else {
    data.frame(device = character(), hits = integer())
  }

  by_visitor_kind <- as.data.frame(table(pv$visitor_kind))
  names(by_visitor_kind) <- c("visitor_kind", "hits")
  by_visitor_kind <- by_visitor_kind[order(-by_visitor_kind$hits), ]

  recent <- if (nrow(pv_view)) {
    out <- pv_view[order(pv_view$time, decreasing = TRUE), ]
    out <- out[seq_len(min(200L, nrow(out))), c(
      "time", "ip", "country", "city", "dashboard", "path", "device", "visitor_kind", "status"
    )]
    out
  } else {
    data.frame()
  }

  list(
    page_views = pv_view,
    total_hits = nrow(pv_view),
    unique_ips = if (nrow(pv_view)) length(unique(pv_view$ip)) else 0L,
    organic_hits = organic_hits,
    bot_hits = bot_hits,
    cloud_hits = cloud_hits,
    uncertain_hits = uncertain_hits,
    by_day = by_day,
    by_day_kind = by_day_kind,
    by_hour = by_hour,
    by_dashboard = by_dashboard,
    by_ip = by_ip,
    by_device = by_device,
    by_visitor_kind = by_visitor_kind,
    recent = recent
  )
}

traffic_auth_expected <- function() {
  user <- Sys.getenv("MASTR_TRAFFIC_USER", "admin")
  pass <- Sys.getenv("MASTR_TRAFFIC_PASS", "")
  list(user = user, pass = pass, enabled = nzchar(pass))
}

traffic_check_login <- function(user, pass) {
  exp <- traffic_auth_expected()
  if (!exp$enabled) {
    return(TRUE)
  }
  identical(user, exp$user) && identical(pass, exp$pass)
}
