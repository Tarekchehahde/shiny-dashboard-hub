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
  df <- df[df$method == "GET" & df$status %in% c(200L, 304L), , drop = FALSE]
  df <- df[vapply(df$path, nginx_is_dashboard_entry, logical(1)), , drop = FALSE]
  df$dashboard <- vapply(df$path, nginx_dashboard_slug, character(1))
  df$device <- vapply(df$user_agent, nginx_device_label, character(1))
  df
}

nginx_traffic_summary <- function(df, days = 7L) {
  pv <- nginx_page_views(df)
  if (!nrow(pv)) {
    return(list(
      page_views = pv,
      total_hits = 0L,
      unique_ips = 0L,
      by_day = data.frame(),
      by_hour = data.frame(),
      by_dashboard = data.frame(),
      by_ip = data.frame(),
      by_device = data.frame(),
      recent = data.frame()
    ))
  }
  cutoff <- Sys.time() - as.difftime(days, units = "days")
  pv <- pv[!is.na(pv$time) & pv$time >= cutoff, , drop = FALSE]
  if (!nrow(pv)) {
    return(nginx_traffic_summary(df, days = days * 2))
  }

  by_day <- as.data.frame(table(format(pv$time, "%Y-%m-%d")))
  names(by_day) <- c("day", "hits")
  by_day$day <- as.Date(by_day$day)
  by_day <- by_day[order(by_day$day), ]

  by_hour <- as.data.frame(table(format(pv$time, "%H:00")))
  names(by_hour) <- c("hour", "hits")

  by_dashboard <- as.data.frame(table(pv$dashboard))
  names(by_dashboard) <- c("dashboard", "hits")
  by_dashboard <- by_dashboard[order(-by_dashboard$hits), ]

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
  by_ip <- merge(ip_tab, ip_last, by = "ip", all.x = TRUE)
  by_ip <- merge(by_ip, ip_dev, by = "ip", all.x = TRUE)
  by_ip <- by_ip[order(-by_ip$hits), ]

  by_device <- as.data.frame(table(pv$device))
  names(by_device) <- c("device", "hits")

  recent <- pv[order(pv$time, decreasing = TRUE), ]
  recent <- recent[seq_len(min(200L, nrow(recent))), c(
    "time", "ip", "dashboard", "path", "device", "status"
  )]

  list(
    page_views = pv,
    total_hits = nrow(pv),
    unique_ips = length(unique(pv$ip)),
    by_day = by_day,
    by_hour = by_hour,
    by_dashboard = by_dashboard,
    by_ip = by_ip,
    by_device = by_device,
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
