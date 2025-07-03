#!/bin/bash

# ==============================================================================
# Sitemap Scraper with Date Filter (v4 - Universal Awk)
#
# Description:
#   This script discovers and downloads URLs from a website's sitemap(s) that
#   have been created or updated within a specific number of days. It uses
#   a highly portable awk syntax to ensure compatibility across different
#   systems, including Linux and macOS.
#
# Usage:
#   ./sitemap_scraper.sh [OPTIONS] <WEBSITE_URL>
#
# Options:
#   -d, --days N   (Optional) Scrape URLs modified in the last N days.
#                  Defaults to 1 (the last 24 hours).
#
# Example (last 24 hours):
#   ./sitemap_scraper.sh https://www.google.com
#
# Example (last 30 days):
#   ./sitemap_scraper.sh -d 30 https://www.google.com
#
# ==============================================================================

# --- Configuration & Constants ---
USER_AGENT="Mozilla/5.0 (compatible; SitemapScraper/4.0; +https://github.com/your-repo)"

# --- Function Definitions ---

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Core function to process a sitemap URL.
process_sitemap() {
    local sitemap_url=$1
    log "Processing sitemap: $sitemap_url"

    local sitemap_content
    sitemap_content=$(curl -s -A "$USER_AGENT" -L "$sitemap_url")

    if [ -z "$sitemap_content" ]; then
        log "Warning: Could not fetch or content is empty for $sitemap_url. Skipping."
        return
    fi

    # Check if this is a sitemap index file (<sitemapindex>)
    if echo "$sitemap_content" | grep -q "<sitemapindex"; then
        log "Sitemap index found. Processing nested sitemaps..."

        # Use a highly portable awk script to parse the sitemap index
        echo "$sitemap_content" | awk -v cutoff_date="$CUTOFF_DATE" '
            BEGIN { RS = "</sitemap>" }
            {
                # Extract lastmod date if it exists
                lastmod = "";
                if (index($0, "<lastmod>")) {
                    temp_lastmod = $0;
                    sub(/.*<lastmod>/, "", temp_lastmod);
                    sub(/<\/lastmod>.*/, "", temp_lastmod);
                    lastmod = substr(temp_lastmod, 1, 10);
                }

                # Extract loc
                loc = "";
                if (index($0, "<loc>")) {
                    temp_loc = $0;
                    sub(/.*<loc>/, "", temp_loc);
                    sub(/<\/loc>.*/, "", temp_loc);
                    loc = temp_loc;
                }

                # Process if the sitemap is recent, or if it has no lastmod tag
                if (loc && (lastmod == "" || lastmod >= cutoff_date)) {
                    print loc;
                }
            }
        ' | while read -r nested_sitemap_url; do
            process_sitemap "$nested_sitemap_url"
        done

    else
        # This is a regular sitemap file (<urlset>)
        log "Extracting URLs from content sitemap..."

        # Use a highly portable awk script to parse the urlset
        echo "$sitemap_content" | awk -v cutoff_date="$CUTOFF_DATE" '
            BEGIN { RS = "</url>" }
            {
                # Extract lastmod date if it exists
                lastmod = "";
                if (index($0, "<lastmod>")) {
                    temp_lastmod = $0;
                    sub(/.*<lastmod>/, "", temp_lastmod);
                    sub(/<\/lastmod>.*/, "", temp_lastmod);
                    lastmod = substr(temp_lastmod, 1, 10);
                }

                # Extract loc
                loc = "";
                if (index($0, "<loc>")) {
                    temp_loc = $0;
                    sub(/.*<loc>/, "", temp_loc);
                    sub(/<\/loc>.*/, "", temp_loc);
                    loc = temp_loc;
                }

                # Add to output if the url is recent, or if it has no lastmod tag
                if (loc && (lastmod == "" || lastmod >= cutoff_date)) {
                    print loc;
                }
            }
        ' >> "$OUTPUT_FILE"
    fi
}

# --- Main Script Logic ---

# 1. Initialize Default Values
DAYS_AGO=1

# 2. Parse Command-Line Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--days)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                DAYS_AGO="$2"
                shift 2
            else
                error "Argument for $1 is missing or not a number"
            fi
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            WEBSITE_URL="$1"
            shift
            ;;
    esac
done

# 3. Validate Input
if [ -z "$WEBSITE_URL" ]; then
    echo "Usage: $0 [OPTIONS] <WEBSITE_URL>"
    echo "Example: $0 -d 30 https://www.example.com"
    exit 1
fi

# 4. Calculate Cutoff Date (OS-aware)
# This uses different flags for GNU date (Linux) and BSD date (macOS)
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    CUTOFF_DATE=$(date -v-${DAYS_AGO}d "+%Y-%m-%d")
else
    # Linux
    CUTOFF_DATE=$(date -d "$DAYS_AGO days ago" "+%Y-%m-%d")
fi

log "Filtering for URLs modified on or after $CUTOFF_DATE ($DAYS_AGO days)."

# 5. Initialize Variables
DOMAIN_NAME=$(echo "$WEBSITE_URL" | sed -E 's/https?:\/\/([^/]+).*/\1/')
if [ -z "$DOMAIN_NAME" ]; then
    error "Could not parse a valid domain name from the URL provided."
fi

ROBOTS_URL="${WEBSITE_URL%/}/robots.txt"
OUTPUT_FILE="${DOMAIN_NAME}_urls.txt"

# Create a fresh output file
> "$OUTPUT_FILE"

log "Starting sitemap discovery for: $WEBSITE_URL"
log "Output will be saved to: $OUTPUT_FILE"

# 6. Find Initial Sitemap URLs from robots.txt
log "Checking for sitemaps in $ROBOTS_URL..."
SITEMAP_URLS=$(curl -s -A "$USER_AGENT" -L "$ROBOTS_URL" | grep -i "Sitemap:" | awk '{print $2}')

# 7. Fallback if no sitemaps found in robots.txt
if [ -z "$SITEMAP_URLS" ]; then
    log "No sitemaps found in robots.txt. Trying default /sitemap.xml..."
    DEFAULT_SITEMAP_URL="${WEBSITE_URL%/}/sitemap.xml"
    http_status=$(curl -o /dev/null -s -w "%{http_code}" -A "$USER_AGENT" -L "$DEFAULT_SITEMAP_URL")
    if [ "$http_status" -eq 200 ]; then
        log "Found default sitemap at $DEFAULT_SITEMAP_URL"
        SITEMAP_URLS="$DEFAULT_SITEMAP_URL"
    else
        error "Could not find any sitemap references. Exiting."
    fi
fi

# 8. Process all found sitemap URLs
echo "$SITEMAP_URLS" | while read -r sitemap_url; do
    process_sitemap "$sitemap_url"
done

# 9. Finalize
# Sort and remove duplicate URLs from the output file
sort -u "$OUTPUT_FILE" -o "$OUTPUT_FILE"

URL_COUNT=$(wc -l < "$OUTPUT_FILE")

log "Scraping complete!"
log "Found $URL_COUNT unique URLs matching the date criteria."
log "Results saved in $OUTPUT_FILE"

exit 0
