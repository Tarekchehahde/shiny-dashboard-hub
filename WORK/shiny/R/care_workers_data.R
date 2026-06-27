# Care workers Thuringia — data loaders (interviews + organizations + analysis JSON)

CARE_THEME_COLORS <- c(
  "Transnational Recruitment" = "#6366f1",
  "Worker Suitability" = "#8b5cf6",
  "Pre-Arrival Expectations" = "#ec4899",
  "Extended Support" = "#10b981",
  "Qualification Mismatches" = "#f59e0b",
  "Adverse Outcomes" = "#ef4444",
  "Unknown" = "#64748b"
)

care_workers_data_dir <- function() {
  app_dir <- Sys.getenv("MASTR_CARE_WORKERS_DATA", "")
  if (nzchar(app_dir) && dir.exists(app_dir)) {
    return(normalizePath(app_dir, winslash = "/"))
  }
  candidates <- c(
    "data",
    file.path(getwd(), "data"),
    "/opt/mastr-shiny/WORK/shiny/apps/care_workers_thuringia/data"
  )
  for (p in candidates) {
    if (file.exists(file.path(p, "consolidated_interviews.csv"))) {
      return(normalizePath(p, winslash = "/"))
    }
  }
  stop("care_workers data directory not found", call. = FALSE)
}

care_workers_load_interviews <- function() {
  path <- file.path(care_workers_data_dir(), "consolidated_interviews.csv")
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  names(df) <- gsub("\\.", " ", names(df))
  if (!"Data Extract" %in% names(df) && "Data.Extract" %in% names(df)) {
    names(df)[names(df) == "Data.Extract"] <- "Data Extract"
  }
  df$Extract_Length <- nchar(df$`Data Extract`)
  df$Theme <- factor(df$Theme, levels = names(CARE_THEME_COLORS))
  df
}

care_workers_load_orgs <- function() {
  path <- file.path(care_workers_data_dir(), "Consolidated_lists.csv")
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  df <- df[!is.na(df$Latitude) & !is.na(df$Longitude), , drop = FALSE]
  df$Sector <- ifelse(grepl("^R", df$Schlüssel), "Health & social work",
    ifelse(grepl("^Q", df$Schlüssel), "Education",
      ifelse(grepl("^T", df$Schlüssel), "Advocacy & services", "Other")))
  df
}

care_workers_load_analysis <- function() {
  path <- file.path(care_workers_data_dir(), "analysis_data.json")
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

care_workers_theme_color <- function(theme) {
  out <- CARE_THEME_COLORS[as.character(theme)]
  out[is.na(out)] <- CARE_THEME_COLORS["Unknown"]
  unname(out)
}

care_workers_viz_links <- function() {
  list(
    list(
      file = "interview_insights_dashboard.html",
      title = "Interview insights",
      desc = "Theme radar, stakeholder profiles, coded entry explorer."
    ),
    list(
      file = "consolidated_dashboard.html",
      title = "Organizations map",
      desc = "59 Thuringia orgs — map, sector charts, WZ classification."
    ),
    list(
      file = "network_dashboard.html",
      title = "Network view",
      desc = "Relationships between organizations and service types."
    ),
    list(
      file = "quotations_by_theme.html",
      title = "Quotations by theme",
      desc = "Qualitative extracts grouped by research theme."
    ),
    list(
      file = "findings.html",
      title = "Key findings",
      desc = "Executive summary of recruitment pathways."
    ),
    list(
      file = "metadata_viewer.html",
      title = "Metadata viewer",
      desc = "Project structure and data dictionary."
    )
  )
}
