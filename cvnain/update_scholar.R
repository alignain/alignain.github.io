library(httr2)
library(jsonlite)
library(yaml)

# -------------------------
# CHANGE THESE
# -------------------------

SERPAPI_KEY <- Sys.getenv("SERPAPI_KEY")

SCHOLAR_ID <- "7Db2EHMAAAAJ"

outfile <- "scholar_stats.yml"

# -------------------------

url <- request("https://serpapi.com/search.json") |>
  req_url_query(
    engine = "google_scholar_author",
    author_id = SCHOLAR_ID,
    api_key = SERPAPI_KEY
  )

result <- tryCatch(
  
  {
    req_perform(url) |>
      resp_body_json(simplifyVector = TRUE)
  },
  
  error = function(e) NULL
  
)

if(!is.null(result)){
  
  stats <- list(
    
    citations = result$cited_by$table[1]$citations,
    
    h_index = result$cited_by$table[2]$all,
    
    i10_index = result$cited_by$table[3]$all,
    
    updated = as.character(Sys.Date())
    
  )
  
  write_yaml(stats, outfile)
  
  message("Scholar stats updated.")
  
}else{
  
  message("Unable to update. Existing YAML retained.")
  
}