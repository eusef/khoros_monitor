#!/bin/bash

# ==============================================================================
# Firecrawl Content Extractor
#
# Description:
#   This script reads a list of URLs from a text file, sends each URL to the
#   Firecrawl API to be scraped, and saves the returned Markdown content to
#   individual files.
#
# Dependencies:
#   - curl: For making API requests.
#   - jq: For parsing the JSON response from the API.
#     (e.g., 'brew install jq' or 'sudo apt-get install jq')
#
# Pre-requisites:
#   - A Firecrawl API key must be exported as an environment variable:
#     export FIRECRAWL_API_KEY="your_api_key_here"
#
# ==============================================================================

# --- Function Definitions ---

show_help() {
cat << EOF
Firecrawl Content Extractor

Description:
  Uses the Firecrawl API to scrape content from a list of URLs and saves
  the resulting Markdown to local files.

Usage:
  $0 -i <input_file> -o <output_directory>
  $0 -h | --help

Options:
  -i, --input <file>      Path to the input text file containing one URL per line.
  -o, --output <dir>      Path to the directory where Markdown files will be saved.
  -h, --help              Display this help message and exit.

Example:
  # Scrape all URLs from 'links.txt' and save them in the 'crawled_content' directory.
  $0 -i links.txt -o ./crawled_content
EOF
}

log() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Main Script Logic ---

# 1. Initialize Default Values
INPUT_FILE=""
OUTPUT_DIR=""

# 2. Check for Dependencies
if ! command -v curl &> /dev/null; then
    error "Dependency 'curl' could not be found. Please install it."
fi
if ! command -v jq &> /dev/null; then
    error "Dependency 'jq' could not be found. Please install it first. (e.g., 'brew install jq')"
fi

# 3. Check for API Key
if [ -z "$FIRECRAWL_API_KEY" ]; then
    error "FIRECRAWL_API_KEY environment variable is not set. Please export your API key."
fi

# 4. Parse Command-Line Arguments
if [ "$#" -eq 0 ]; then
    show_help
    exit 1
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            shift
            ;;
    esac
done

# 5. Validate Inputs
if [ -z "$INPUT_FILE" ]; then
    error "Input file not specified. Use -i <file> or -h for help."
fi
if ! [ -f "$INPUT_FILE" ]; then
    error "Input file not found at: $INPUT_FILE"
fi
if [ -z "$OUTPUT_DIR" ]; then
    error "Output directory not specified. Use -o <dir> or -h for help."
fi

# 6. Create Output Directory
mkdir -p "$OUTPUT_DIR"
log "Output will be saved to '$OUTPUT_DIR'"

# 7. Process URLs from input file
while IFS= read -r url || [[ -n "$url" ]]; do
    if [ -z "$url" ]; then
        continue
    fi

    log "Processing URL: $url"

    # Generate a clean filename from the URL slug
    slug=$(basename "$url")
    filename="${slug//[^a-zA-Z0-9-]/_}.md"
    output_path="$OUTPUT_DIR/$filename"

    # Construct the JSON payload for the API
    json_payload=$(printf '{"url": "%s"}' "$url")

    # Make the API call to Firecrawl
    response=$(curl -s -X POST "https://api.firecrawl.dev/v0/scrape" \
        -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload")

    # Check if the API call was successful and extract the markdown
    # The 'e' flag for jq exits with an error if the key is not found
    markdown_content=$(echo "$response" | jq -er '.data.markdown')

    if [ $? -eq 0 ]; then
        # Save the extracted markdown to the output file
        echo "$markdown_content" > "$output_path"
        log "Successfully created '$filename'"
    else
        # Extract and log the error message from the API if available
        error_message=$(echo "$response" | jq -r '.error // "Unknown API error"')
        log "Warning: Failed to process $url. API Response: $error_message"
    fi

done < "$INPUT_FILE"

log "Extraction complete."
exit 0
