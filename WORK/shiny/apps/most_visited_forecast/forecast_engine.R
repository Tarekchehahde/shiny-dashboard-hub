# =============================================================================
# 4-month ensemble forecast for monthly MaStR Zubau (MW) by segment.
#
# Models (whatever succeeds on the series):
#   1. snaive              — last year's same month (seasonal naive)
#   2. seasonal_yoy        — same month × damped geometric YoY
#   3. month_trend         — per-calendar-month log-linear trend (damped)
#   4. ets                 — automatic Holt-Winters / ETS
#   5. sarima              — auto.arima with seasonal period 12
#   6. stlm                — STL decomposition + ETS on the seasonally adjusted series
#   7. nnetar              — neural-net autoregression (lag-12 seasonality)
#   8. rf_lags             — random forest on lag / calendar features (recursive)
#
# Production point forecast = inverse-MAPE² weighted average, then a
# regime stabilizer: German PV 2023–25 was a boom; Home/C&I already shrank
# in 2025. Unchecked ETS/trend keeps extrapolating that boom. After the
# ensemble we (1) spike-shrink one-off months, (2) continue recent YoY
# more when it is a decline than when it is growth, (3) clip explosive
# models. Grand Total is the sum of Home + C&I + Large Scale.
# =============================================================================

HORIZON <- 4L
CORE_SEGMENTS <- c("Home", "C&I", "Large Scale")
ALL_SEGMENTS <- c(CORE_SEGMENTS, "Grand Total")
MODEL_NAMES <- c("snaive", "robust_snaive", "anchor_damped", "seasonal_yoy",
                 "month_trend", "ets", "sarima", "stlm", "nnetar", "rf_lags")

.safe_mape <- function(actual, pred) {
  ok <- is.finite(actual) & is.finite(pred) & abs(actual) > 1
  if (!any(ok)) return(NA_real_)
  mean(abs(actual[ok] - pred[ok]) / abs(actual[ok]))
}

.safe_wmape <- function(actual, pred, w) {
  ok <- is.finite(actual) & is.finite(pred) & abs(actual) > 1 & is.finite(w)
  if (!any(ok)) return(NA_real_)
  ww <- w[ok]
  sum(ww * abs(actual[ok] - pred[ok]) / abs(actual[ok])) / sum(ww)
}

.trailing_yoy <- function(y, k) {
  n <- length(y)
  if (n < 2L * k) return(NA_real_)
  a <- sum(as.numeric(y[(n - k + 1L):n]))
  b <- sum(as.numeric(y[(n - 2L * k + 1L):(n - k)]))
  if (!is.finite(a) || !is.finite(b) || b <= 1) return(NA_real_)
  a / b
}

detect_regime <- function(y) {
  g6  <- .trailing_yoy(y, 6L)
  g12 <- .trailing_yoy(y, 12L)
  if (!is.finite(g6)) g6 <- 1
  if (!is.finite(g12)) g12 <- 1
  g <- 0.6 * g6 + 0.4 * g12
  g <- min(1.45, max(0.55, g))
  type <- if (g < 0.92) "decline" else if (g > 1.10) "growth" else "stable"
  list(g6 = g6, g12 = g12, g = g, type = type)
}

# Last year same month, but shrink one-off spikes (e.g. Large Scale Feb/Aug 2025).
.fc_robust_snaive <- function(y, h) {
  n <- length(y)
  if (n < 24L) return(.fc_snaive(y, h))
  out <- numeric(h)
  for (k in seq_len(h)) {
    last <- if (n - 12L + k >= 1L) as.numeric(y[n - 12L + k]) else as.numeric(y[n])
    prev <- numeric(0)
    for (lag in 2:3) {
      idx <- n - lag * 12L + k
      if (idx >= 1L) prev <- c(prev, as.numeric(y[idx]))
    }
    prev <- prev[is.finite(prev) & prev > 1]
    if (length(prev) && is.finite(last) && last > 1.4 * stats::median(prev)) {
      last <- 0.65 * stats::median(prev) + 0.35 * last
    }
    out[k] <- max(last, 0)
  }
  out
}

# Continue recent YoY, but believe declines more than continued boom.
.fc_anchor_damped <- function(y, h) {
  n <- length(y)
  if (n < 24L) return(.fc_snaive(y, h))
  reg <- detect_regime(y)
  base <- .fc_robust_snaive(y, h)
  lambda <- switch(reg$type, decline = 0.85, growth = 0.25, 0.45)
  out <- base * (1 + lambda * (reg$g - 1))
  # Winter months keep falling faster in the Home/C&I cooldown.
  if (identical(reg$type, "decline")) {
    start <- stats::start(y)
    last_m <- ((start[2] - 1L + n - 1L) %% 12L) + 1L
    for (k in seq_len(h)) {
      m <- ((last_m + k - 1L) %% 12L) + 1L
      if (m %in% c(1L, 2L, 12L)) out[k] <- out[k] * 0.90
    }
  }
  pmax(out, 0)
}

.add_months <- function(year, month, k) {
  tot <- as.integer(year) * 12L + (as.integer(month) - 1L) + as.integer(k)
  list(year = tot %/% 12L, month = tot %% 12L + 1L)
}

.ym_index <- function(year, month) as.integer(year) * 12L + (as.integer(month) - 1L)

# Drop the current calendar month (always incomplete) and a trailing stub
# month whose MW is < 45% of the same-month median — typical MaStR lag.
last_complete_cursor <- function(d, today = Sys.Date()) {
  if (!nrow(d)) return(NULL)
  cy <- as.integer(format(today, "%Y"))
  cm <- as.integer(format(today, "%m"))
  d <- d[!(d$year > cy | (d$year == cy & d$month >= cm)), ]
  if (!nrow(d)) return(NULL)

  last_idx <- NULL
  for (seg in unique(d$segment)) {
    ds <- d[d$segment == seg, ]
    ds <- ds[order(ds$year, ds$month), ]
    if (!nrow(ds)) next
    last <- ds[nrow(ds), ]
    same <- ds$mw[ds$month == last$month & ds$year < last$year]
    drop_last <- length(same) >= 3L && is.finite(last$mw) &&
      last$mw < 0.45 * stats::median(same)
    end_i <- .ym_index(last$year, last$month) - if (drop_last) 1L else 0L
    last_idx <- if (is.null(last_idx)) end_i else min(last_idx, end_i)
  }
  if (is.null(last_idx)) return(NULL)
  list(year = last_idx %/% 12L, month = last_idx %% 12L + 1L, idx = last_idx)
}

.to_monthly_ts <- function(dd) {
  dd <- dd[order(dd$year, dd$month), ]
  if (nrow(dd) < 24L) return(NULL)
  y <- dd$mw
  y[!is.finite(y)] <- 0
  y[y < 0] <- 0
  stats::ts(y, start = c(dd$year[1], dd$month[1]), frequency = 12)
}

# ----- individual models (return numeric vector of length h, or NULL) --------

.fc_snaive <- function(y, h) {
  n <- length(y)
  if (n < 12L) return(NULL)
  as.numeric(utils::tail(y, 12L)[seq_len(h)])
}

.fc_seasonal_yoy <- function(y, h) {
  n <- length(y)
  if (n < 24L) return(.fc_snaive(y, h))
  # Only the latest YoY — a 3-year geometric mean keeps the 2022–24 boom alive.
  g <- .trailing_yoy(y, 12L)
  if (!is.finite(g)) g <- 1
  lambda <- if (g >= 1) 0.25 else 0.80
  g_d <- 1 + lambda * (g - 1)
  base <- .fc_robust_snaive(y, h)
  pmax(base * g_d, 0)
}

.fc_month_trend <- function(y, h, start) {
  n <- length(y)
  if (n < 36L) return(.fc_seasonal_yoy(y, h))
  yr0 <- start[1]
  mo0 <- start[2]
  years <- yr0 + (seq_len(n) - 1L + (mo0 - 1L)) %/% 12L
  months <- ((mo0 - 1L + seq_len(n) - 1L) %% 12L) + 1L
  last_y <- years[n]
  last_m <- months[n]
  out <- numeric(h)
  for (k in seq_len(h)) {
    tgt <- .add_months(last_y, last_m, k)
    idx <- which(months == tgt$month)
    mw <- as.numeric(y[idx])
    yy <- years[idx]
    ok <- is.finite(mw) & mw > 1
    if (sum(ok) < 4L) {
      out[k] <- if (sum(ok)) stats::median(mw[ok]) else as.numeric(y[n])
      next
    }
    fit <- tryCatch(
      stats::lm(log(mw[ok]) ~ yy[ok]),
      error = function(e) NULL)
    if (is.null(fit) || anyNA(stats::coef(fit))) {
      out[k] <- stats::median(mw[ok])
      next
    }
    b <- stats::coef(fit)
    raw <- exp(as.numeric(b[1] + b[2] * tgt$year))
    recent <- utils::tail(mw[ok], 3L)
    blend <- exp(mean(log(pmax(recent, 1))))
    growth <- as.numeric(b[2])
    # damp extreme slopes (solar boom years)
    if (is.finite(growth) && abs(growth) > log(1.35)) {
      raw <- 0.4 * raw + 0.6 * blend
    } else {
      raw <- 0.7 * raw + 0.3 * blend
    }
    out[k] <- raw
  }
  out
}

.fc_ets <- function(y, h) {
  if (!requireNamespace("forecast", quietly = TRUE) || length(y) < 36L) return(NULL)
  lam <- if (min(as.numeric(y), na.rm = TRUE) > 1) "auto" else NULL
  fit <- tryCatch(forecast::ets(y, lambda = lam, biasadj = !is.null(lam)),
                  error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  fc <- tryCatch(forecast::forecast(fit, h = h, level = 80),
                 error = function(e) NULL)
  if (is.null(fc)) return(NULL)
  list(mean = pmax(as.numeric(fc$mean), 0),
       lo = pmax(as.numeric(fc$lower[, 1]), 0),
       hi = pmax(as.numeric(fc$upper[, 1]), 0))
}

.fc_sarima <- function(y, h) {
  if (!requireNamespace("forecast", quietly = TRUE) || length(y) < 36L) return(NULL)
  lam <- if (min(as.numeric(y), na.rm = TRUE) > 1) "auto" else NULL
  fit <- tryCatch(
    forecast::auto.arima(y, seasonal = TRUE, stepwise = TRUE,
                         approximation = TRUE, allowdrift = TRUE,
                         lambda = lam, biasadj = !is.null(lam)),
    error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  fc <- tryCatch(forecast::forecast(fit, h = h, level = 80),
                 error = function(e) NULL)
  if (is.null(fc)) return(NULL)
  list(mean = pmax(as.numeric(fc$mean), 0),
       lo = pmax(as.numeric(fc$lower[, 1]), 0),
       hi = pmax(as.numeric(fc$upper[, 1]), 0))
}

.fc_stlm <- function(y, h) {
  if (!requireNamespace("forecast", quietly = TRUE) || length(y) < 36L) return(NULL)
  fit <- tryCatch(forecast::stlm(y, s.window = "periodic", robust = TRUE),
                  error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  fc <- tryCatch(forecast::forecast(fit, h = h, level = 80),
                 error = function(e) NULL)
  if (is.null(fc)) return(NULL)
  list(mean = pmax(as.numeric(fc$mean), 0),
       lo = pmax(as.numeric(fc$lower[, 1]), 0),
       hi = pmax(as.numeric(fc$upper[, 1]), 0))
}

.fc_nnetar <- function(y, h) {
  if (!requireNamespace("forecast", quietly = TRUE) || length(y) < 36L) return(NULL)
  lam <- if (min(as.numeric(y), na.rm = TRUE) > 1) "auto" else NULL
  set.seed(42)
  fit <- tryCatch(
    forecast::nnetar(y, P = 1, repeats = 8, lambda = lam, scale.inputs = TRUE),
    error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  fc <- tryCatch(forecast::forecast(fit, h = h, PI = FALSE),
                 error = function(e) NULL)
  if (is.null(fc) || is.null(fc$mean)) return(NULL)
  .as_fc(pmax(as.numeric(fc$mean), 0))
}

.fc_rf_lags <- function(y, h, start) {
  if (!requireNamespace("randomForest", quietly = TRUE) || length(y) < 48L) return(NULL)
  n <- length(y)
  yr0 <- start[1]; mo0 <- start[2]
  months <- ((mo0 - 1L + seq_len(n) - 1L) %% 12L) + 1L
  t_idx <- seq_len(n)
  lag1 <- c(NA, y[-n])
  lag12 <- c(rep(NA, 12L), y[seq_len(n - 12L)])
  lag24 <- c(rep(NA, 24L), y[seq_len(n - 24L)])
  yoy <- y / pmax(lag12, 1)
  dat <- data.frame(
    y = as.numeric(y),
    month = months,
    m_sin = sin(2 * pi * months / 12),
    m_cos = cos(2 * pi * months / 12),
    t = t_idx,
    lag1 = as.numeric(lag1),
    lag12 = as.numeric(lag12),
    lag24 = as.numeric(lag24),
    yoy = as.numeric(yoy)
  )
  train <- dat[complete.cases(dat), ]
  if (nrow(train) < 24L) return(NULL)
  fit <- tryCatch(
    randomForest::randomForest(y ~ ., data = train, ntree = 250L, mtry = 3L),
    error = function(e) NULL)
  if (is.null(fit)) return(NULL)

  hist <- as.numeric(y)
  out <- numeric(h)
  for (k in seq_len(h)) {
    nn <- length(hist)
    last_ym <- .add_months(yr0, mo0, nn - 1L)
    tgt <- .add_months(last_ym$year, last_ym$month, 1L)
    m <- tgt$month
    nd <- data.frame(
      month = m,
      m_sin = sin(2 * pi * m / 12),
      m_cos = cos(2 * pi * m / 12),
      t = nn + 1L,
      lag1 = hist[nn],
      lag12 = if (nn >= 12L) hist[nn - 11L] else hist[nn],
      lag24 = if (nn >= 24L) hist[nn - 23L] else hist[max(1L, nn - 11L)],
      yoy = hist[nn] / max(if (nn >= 12L) hist[nn - 11L] else hist[nn], 1)
    )
    pred <- tryCatch(as.numeric(stats::predict(fit, newdata = nd)),
                     error = function(e) NA_real_)
    if (!is.finite(pred)) pred <- hist[nn]
    pred <- max(pred, 0)
    out[k] <- pred
    hist <- c(hist, pred)
  }
  out
}

.as_fc <- function(mean, lo = NULL, hi = NULL) {
  if (is.null(mean) || !length(mean) || all(!is.finite(mean))) return(NULL)
  mean <- pmax(as.numeric(mean), 0)
  if (is.null(lo) || length(lo) != length(mean) || any(!is.finite(lo))) {
    lo <- pmax(mean * 0.72, 0)
  }
  if (is.null(hi) || length(hi) != length(mean) || any(!is.finite(hi))) {
    hi <- mean * 1.32
  }
  list(mean = mean, lo = pmax(as.numeric(lo), 0), hi = pmax(as.numeric(hi), mean))
}

.unwrap <- function(res) {
  if (is.null(res)) return(NULL)
  if (is.list(res) && !is.null(res$mean)) return(.as_fc(res$mean, res$lo, res$hi))
  .as_fc(res)
}

run_models <- function(y, h, start, include_slow = TRUE) {
  out <- list(
    snaive        = .unwrap(.fc_snaive(y, h)),
    robust_snaive = .unwrap(.fc_robust_snaive(y, h)),
    anchor_damped = .unwrap(.fc_anchor_damped(y, h)),
    seasonal_yoy  = .unwrap(.fc_seasonal_yoy(y, h)),
    month_trend   = .unwrap(.fc_month_trend(y, h, start)),
    ets           = .unwrap(.fc_ets(y, h)),
    sarima        = .unwrap(.fc_sarima(y, h)),
    stlm          = .unwrap(.fc_stlm(y, h))
  )
  if (isTRUE(include_slow)) {
    out$nnetar  <- .unwrap(.fc_nnetar(y, h))
    out$rf_lags <- .unwrap(.fc_rf_lags(y, h, start))
  }
  out
}

holdout_weights <- function(y, start, h_prod = HORIZON) {
  n <- length(y)
  h_hold <- if (n >= 60L) 12L else if (n >= 42L) 6L else 0L
  if (h_hold < 4L) {
    w <- setNames(rep(1, length(MODEL_NAMES)), MODEL_NAMES)
    return(list(weights = w / sum(w),
                mape = setNames(rep(NA_real_, length(w)), names(w)),
                h_hold = 0L))
  }
  y_tr <- stats::ts(utils::head(as.numeric(y), n - h_hold),
                    start = start, frequency = 12)
  actual <- utils::tail(as.numeric(y), h_hold)
  fitted <- suppressWarnings(run_models(y_tr, h_hold, start, include_slow = FALSE))
  recency <- seq(0.55, 1.45, length.out = h_hold)
  mape <- vapply(names(fitted), function(nm) {
    m <- fitted[[nm]]
    if (is.null(m)) return(NA_real_)
    .safe_wmape(actual, m$mean, recency)
  }, numeric(1))
  mape[!is.finite(mape) | mape <= 0] <- NA_real_
  # drop models that are > 2.8× the best MAPE
  best <- min(mape, na.rm = TRUE)
  if (is.finite(best)) {
    mape[mape > 2.2 * best] <- NA_real_
  }
  w <- 1 / (mape + 0.03)^2
  w[!is.finite(w)] <- 0
  if (sum(w) <= 0) w[is.finite(mape)] <- 1
  if (sum(w) <= 0) w[] <- 1
  med_mape <- stats::median(mape[is.finite(mape)], na.rm = TRUE)
  avg_w <- mean(w[w > 0], na.rm = TRUE)
  if (!is.finite(avg_w) || avg_w <= 0) avg_w <- 1
  prior <- if (is.finite(med_mape)) 1 / (med_mape * 1.15 + 0.03)^2 else avg_w
  w <- c(w, nnetar = prior, rf_lags = prior * 0.85)
  w <- w / sum(w)
  mape <- c(mape, nnetar = NA_real_, rf_lags = NA_real_)
  list(weights = w, mape = mape, h_hold = h_hold)
}

ensemble_from_models <- function(models, weights) {
  keep <- intersect(names(models), names(weights))
  keep <- keep[vapply(keep, function(nm) !is.null(models[[nm]]), logical(1))]
  if (!length(keep)) return(NULL)
  w <- weights[keep]
  w <- w / sum(w)
  h <- length(models[[keep[1]]]$mean)
  mean <- numeric(h)
  lo <- numeric(h)
  hi <- numeric(h)
  for (nm in keep) {
    mean <- mean + w[[nm]] * models[[nm]]$mean
    lo   <- lo   + w[[nm]] * models[[nm]]$lo
    hi   <- hi   + w[[nm]] * models[[nm]]$hi
  }
  # widen band by cross-model disagreement
  stack <- do.call(rbind, lapply(keep, function(nm) models[[nm]]$mean))
  disagree <- apply(stack, 2, stats::sd)
  disagree[!is.finite(disagree)] <- 0
  lo <- pmax(lo - 0.35 * disagree, 0)
  hi <- hi + 0.35 * disagree
  list(mean = pmax(mean, 0), lo = pmax(lo, 0), hi = pmax(hi, mean),
       weights = w, models = models[keep])
}

.clip_to_anchor <- function(x, anchor, lo_mult, hi_mult) {
  lo <- lo_mult * anchor
  hi <- hi_mult * anchor
  pmin(pmax(x, lo), hi)
}

stabilize_ensemble <- function(ens, y, h) {
  if (is.null(ens) || length(y) < 24L) return(ens)
  reg <- detect_regime(y)
  anchor <- .fc_anchor_damped(y, h)
  snaive <- .fc_robust_snaive(y, h)
  if (identical(reg$type, "decline")) {
    w_anchor <- 0.72
    mean <- (1 - w_anchor) * ens$mean + w_anchor * anchor
    mean <- .clip_to_anchor(mean, snaive, 0.58, 1.08)
    lo <- .clip_to_anchor((1 - w_anchor) * ens$lo + w_anchor * anchor * 0.82,
                          snaive, 0.52, 1.08)
    hi <- .clip_to_anchor((1 - w_anchor) * ens$hi + w_anchor * anchor * 1.18,
                          snaive, 0.58, 1.20)
  } else if (identical(reg$type, "growth")) {
    # Still rising (Large Scale): do not pull toward last year — that caps
    # genuine new levels. Only shrink months where last year was a spike.
    w_anchor <- 0
    mean <- ens$mean
    raw <- .fc_snaive(y, h)
    spiked <- is.finite(raw) & is.finite(snaive) & raw > 1.4 * snaive
    if (any(spiked)) {
      mean[spiked] <- 0.55 * mean[spiked] + 0.45 * snaive[spiked]
    }
    lo <- ens$lo
    hi <- ens$hi
  } else {
    w_anchor <- 0.45
    mean <- (1 - w_anchor) * ens$mean + w_anchor * anchor
    mean <- .clip_to_anchor(mean, snaive, 0.62, 1.15)
    lo <- .clip_to_anchor((1 - w_anchor) * ens$lo + w_anchor * anchor * 0.85,
                          snaive, 0.58, 1.15)
    hi <- .clip_to_anchor((1 - w_anchor) * ens$hi + w_anchor * anchor * 1.15,
                          snaive, 0.62, 1.22)
  }
  ens$mean <- pmax(mean, 0)
  ens$lo <- pmax(pmin(lo, ens$mean), 0)
  ens$hi <- pmax(hi, ens$mean)
  ens$regime <- reg
  ens$w_anchor <- w_anchor
  ens
}

forecast_one_segment <- function(dd, h = HORIZON) {
  y <- .to_monthly_ts(dd)
  if (is.null(y)) return(NULL)
  start <- stats::start(y)
  wt <- holdout_weights(y, start, h)
  models <- suppressWarnings(run_models(y, h, start))
  reg <- detect_regime(y)
  w <- wt$weights
  # Log-linear month trend keeps the 2022–24 boom; kill it in a cooldown.
  if (identical(reg$type, "decline") && "month_trend" %in% names(w)) {
    w[["month_trend"]] <- 0
  }
  if (sum(w, na.rm = TRUE) > 0) w <- w / sum(w)
  ens <- ensemble_from_models(models, w)
  if (is.null(ens)) return(NULL)
  ens <- stabilize_ensemble(ens, y, h)
  last <- dd[nrow(dd), ]
  horizon <- lapply(seq_len(h), function(k) .add_months(last$year, last$month, k))
  list(
    segment = dd$segment[1],
    last_complete = list(year = last$year, month = last$month),
    horizon_year = vapply(horizon, `[[`, integer(1), "year"),
    horizon_month = vapply(horizon, `[[`, integer(1), "month"),
    mean = ens$mean,
    lo = ens$lo,
    hi = ens$hi,
    weights = ens$weights,
    mape = wt$mape[names(ens$weights)],
    h_hold = wt$h_hold,
    models = ens$models,
    regime = ens$regime,
    history = dd
  )
}

seasonal_profile <- function(dd) {
  # Share of annual MW by calendar month, last up to 5 complete years.
  years <- sort(unique(dd$year))
  if (length(years) >= 2L) years <- years[-length(years)]
  years <- utils::tail(years, 5L)
  x <- dd[dd$year %in% years, ]
  if (!nrow(x)) return(NULL)
  ann <- x |>
    dplyr::group_by(year) |>
    dplyr::summarise(tot = sum(mw, na.rm = TRUE), .groups = "drop")
  x |>
    dplyr::left_join(ann, by = "year") |>
    dplyr::filter(tot > 1) |>
    dplyr::group_by(month) |>
    dplyr::summarise(share = mean(mw / tot, na.rm = TRUE),
                     mw_typ = stats::median(mw, na.rm = TRUE),
                     .groups = "drop")
}

yoy_recent <- function(dd) {
  dd <- dd[order(dd$year, dd$month), ]
  n <- nrow(dd)
  if (n < 24L) return(NA_real_)
  last12 <- sum(dd$mw[(n - 11L):n], na.rm = TRUE)
  prev12 <- sum(dd$mw[(n - 23L):(n - 12L)], na.rm = TRUE)
  if (prev12 <= 1) return(NA_real_)
  last12 / prev12 - 1
}

# Align all core segments, freeze training at Dec of the previous calendar
# year, forecast that year, then build Grand Total as the sum (coherent).
pad_monthly <- function(d) {
  if (!nrow(d)) return(d)
  d$year <- as.integer(d$year)
  d$month <- as.integer(d$month)
  out <- list()
  for (seg in unique(d$segment)) {
    ds <- d[d$segment == seg, ]
    ds <- ds[order(ds$year, ds$month), ]
    i0 <- .ym_index(ds$year[1], ds$month[1])
    i1 <- .ym_index(ds$year[nrow(ds)], ds$month[nrow(ds)])
    grid <- lapply(i0:i1, function(i) {
      list(year = i %/% 12L, month = i %% 12L + 1L)
    })
    g <- dplyr::bind_rows(grid)
    g$segment <- seg
    joined <- dplyr::left_join(g, ds, by = c("segment", "year", "month"))
    joined$mw[is.na(joined$mw)] <- 0
    joined$units[is.na(joined$units)] <- 0
    out[[seg]] <- joined
  }
  dplyr::bind_rows(out)
}

force_end <- function(d, year, month) {
  end_i <- .ym_index(year, month)
  d <- d[.ym_index(d$year, d$month) <= end_i, ]
  if (!nrow(d)) return(d)
  extra <- lapply(unique(d$segment), function(seg) {
    data.frame(year = as.integer(year), month = as.integer(month),
               segment = seg, mw = 0, units = 0)
  })
  d <- dplyr::bind_rows(d, extra)
  d <- dplyr::distinct(d, segment, year, month, .keep_all = TRUE)
  pad_monthly(d)
}

# Months older than (current calendar month − 2) are used only to *score*
# the frozen model. They never enter training. The last two calendar months
# plus the current month stay MaStR-preliminary (Nachmeldung).
.score_through_idx <- function(today = Sys.Date()) {
  cy <- as.integer(format(today, "%Y"))
  cm <- as.integer(format(today, "%m"))
  .ym_index(cy, cm) - 2L
}

# Frozen calendar-year model: train on complete years through Dec of (year-1),
# forecast all 12 months of `year`. Target-year Ist is overlay only.
backtest_calendar_year <- function(d, year = 2026L, today = Sys.Date()) {
  year <- as.integer(year)
  train <- force_end(pad_monthly(d[d$year < year, ]), year - 1L, 12L)
  if (!nrow(train)) return(NULL)
  actuals <- d[d$year == year, ]
  score_idx <- .score_through_idx(today)

  out <- list()
  for (seg in CORE_SEGMENTS) {
    ds <- train[train$segment == seg, ]
    ds <- ds[order(ds$year, ds$month), ]
    if (!nrow(ds)) next
    fc <- tryCatch(forecast_one_segment(ds, h = 12L), error = function(e) NULL)
    if (is.null(fc)) next
    act <- actuals[actuals$segment == seg, ]
    act <- act[order(act$month), ]
    actual <- rep(NA_real_, 12L)
    if (nrow(act)) {
      m <- as.integer(act$month)
      ok_m <- m >= 1L & m <= 12L
      actual[m[ok_m]] <- act$mw[ok_m]
    }
    overlay <- is.finite(actual)
    known <- overlay & (.ym_index(year, seq_len(12L)) <= score_idx)
    err <- fc$mean - actual
    ape <- ifelse(known & actual > 1, abs(err) / actual, NA_real_)
    model_mape <- NULL
    if (!is.null(fc$models) && any(known)) {
      model_mape <- vapply(fc$models, function(m) {
        if (is.null(m) || is.null(m$mean)) return(NA_real_)
        .safe_mape(actual[known], m$mean[known])
      }, numeric(1))
    }
    out[[seg]] <- list(
      segment = seg,
      year = year,
      month = seq_len(12L),
      pred = fc$mean,
      lo = fc$lo,
      hi = fc$hi,
      actual = actual,
      err = err,
      ape = ape,
      known = known,
      overlay = overlay,
      mape = if (any(is.finite(ape))) mean(ape, na.rm = TRUE) else NA_real_,
      mae  = if (any(known)) mean(abs(err[known]), na.rm = TRUE) else NA_real_,
      bias = if (any(known)) mean(err[known], na.rm = TRUE) else NA_real_,
      n_known = sum(known),
      model_mape = model_mape,
      holdout_mape = fc$mape,
      weights = fc$weights,
      regime = fc$regime,
      history = ds
    )
  }
  if (!length(out)) return(NULL)

  gt_pred <- Reduce(`+`, lapply(out, `[[`, "pred"))
  gt_lo   <- Reduce(`+`, lapply(out, `[[`, "lo"))
  gt_hi   <- Reduce(`+`, lapply(out, `[[`, "hi"))
  gt_known <- Reduce(`&`, lapply(out, `[[`, "known"))
  gt_act_raw <- rep(NA_real_, 12L)
  if (nrow(actuals)) {
    tot <- actuals |>
      dplyr::group_by(month) |>
      dplyr::summarise(mw = sum(mw, na.rm = TRUE), .groups = "drop")
    gt_act_raw[tot$month] <- tot$mw
  }
  gt_overlay <- is.finite(gt_act_raw)
  gt_err <- gt_pred - gt_act_raw
  gt_ape <- ifelse(gt_known & is.finite(gt_act_raw) & gt_act_raw > 1,
                   abs(gt_err) / gt_act_raw, NA_real_)
  hist_gt <- train |>
    dplyr::group_by(year, month) |>
    dplyr::summarise(mw = sum(mw, na.rm = TRUE),
                     units = sum(units, na.rm = TRUE),
                     .groups = "drop") |>
    dplyr::mutate(segment = "Grand Total") |>
    dplyr::arrange(year, month)
  out[["Grand Total"]] <- list(
    segment = "Grand Total",
    year = year,
    month = seq_len(12L),
    pred = gt_pred,
    lo = gt_lo,
    hi = gt_hi,
    actual = gt_act_raw,
    err = gt_err,
    ape = gt_ape,
    known = gt_known,
    overlay = gt_overlay,
    mape = if (any(is.finite(gt_ape))) mean(gt_ape, na.rm = TRUE) else NA_real_,
    mae  = if (any(gt_known)) mean(abs(gt_err[gt_known]), na.rm = TRUE) else NA_real_,
    bias = if (any(gt_known)) mean(gt_err[gt_known], na.rm = TRUE) else NA_real_,
    n_known = sum(gt_known),
    model_mape = NULL,
    holdout_mape = NULL,
    weights = NULL,
    history = hist_gt,
    coherent = TRUE
  )
  list(
    year = year,
    train_end = list(year = year - 1L, month = 12L),
    known_through = list(year = score_idx %/% 12L, month = score_idx %% 12L + 1L),
    score_through_idx = score_idx,
    segments = out
  )
}

# Slice the frozen year-ahead forecast into the remaining months shown as
# the 4-month outlook. Training data and 12-month predictions are unchanged.
outlook_from_backtest <- function(bt, h = HORIZON, today = Sys.Date()) {
  if (is.null(bt) || !length(bt$segments)) return(NULL)
  cy <- as.integer(bt$year)
  cm <- as.integer(format(today, "%m"))
  if (as.integer(format(today, "%Y")) != cy) cm <- 1L
  idx <- seq.int(cm, min(12L, cm + as.integer(h) - 1L))
  out <- list()
  for (seg in names(bt$segments)) {
    x <- bt$segments[[seg]]
    overlay <- data.frame(
      year = cy,
      month = x$month,
      mw = x$actual,
      known = x$known,
      overlay = if (!is.null(x$overlay)) x$overlay else is.finite(x$actual)
    )
    overlay <- overlay[is.finite(overlay$mw), ]
    out[[seg]] <- list(
      segment = seg,
      last_complete = bt$train_end,
      train_end = bt$train_end,
      frozen_year = cy,
      horizon_year = rep(cy, length(idx)),
      horizon_month = idx,
      mean = x$pred[idx],
      lo = x$lo[idx],
      hi = x$hi[idx],
      year_mean = x$pred,
      year_lo = x$lo,
      year_hi = x$hi,
      weights = x$weights,
      mape = x$holdout_mape,
      history = x$history,
      overlay = overlay,
      coherent = isTRUE(x$coherent)
    )
  }
  out
}

forecast_all_segments <- function(d, h = HORIZON, today = Sys.Date()) {
  cy <- as.integer(format(today, "%Y"))
  bt <- backtest_calendar_year(d, year = cy, today = today)
  outlook_from_backtest(bt, h = h, today = today)
}
