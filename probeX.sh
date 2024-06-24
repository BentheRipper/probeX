#!/bin/bash

# Default values for options
OUTPUT_FILE=""
FILTER_STATUS_CODES=()
FILTER_PORTS=(80 443)
declare -A SEEN_SUBDOMAINS

# Function to display usage
usage() {
    echo -e "\033[31mUsage: $0 [-o output_file] [-s status_codes] [-p ports] <subdomains_file>\033[0m"
    echo -e "  -o output_file       Save output to a file"
    echo -e "  -s status_codes      Filter by status codes (comma-separated, e.g., 200,301,404)"
    echo -e "  -p ports             Filter by ports (comma-separated, e.g., 80,443)"
    exit 1
}

# Parse command-line arguments
while getopts ":o:s:p:" opt; do
    case ${opt} in
        o)
            OUTPUT_FILE="$OPTARG"
            ;;
        s)
            IFS=',' read -r -a FILTER_STATUS_CODES <<< "$OPTARG"
            ;;
        p)
            IFS=',' read -r -a FILTER_PORTS <<< "$OPTARG"
            ;;
        \?)
            usage
            ;;
    esac
done
shift $((OPTIND -1))

# Check if a subdomains file is provided
if [[ -z "$1" ]]; then
    usage
fi

SUBDOMAINS_FILE="$1"

# Check if the subdomains file exists
if [[ ! -f "$SUBDOMAINS_FILE" ]]; then
    echo -e "\033[31mSubdomains file ($SUBDOMAINS_FILE) not found!\033[0m"
    exit 1
fi

# Function to probe a single subdomain
probe_subdomain() {
    local subdomain=$1
    local sources=$2
    local port=$3
    local protocol=$4
    echo -e "\033[36mProbing ${protocol}://${subdomain}:${port} (Sources: ${sources})...\033[0m"
    status_code=$(curl -o /dev/null -s -w "%{http_code}\n" "${protocol}://${subdomain}:${port}")
    
    # Filter by status codes if specified
    if [[ ${#FILTER_STATUS_CODES[@]} -gt 0 && ! " ${FILTER_STATUS_CODES[@]} " =~ " ${status_code} " ]]; then
        return
    fi

    case $status_code in
        200)
            result="\033[32m${protocol}://${subdomain}:${port} is live (Status code: ${status_code})\033[0m"
            ;;
        301|302)
            result="\033[33m${protocol}://${subdomain}:${port} is redirected (Status code: ${status_code})\033[0m"
            ;;
        403)
            result="\033[35m${protocol}://${subdomain}:${port} is forbidden (Status code: ${status_code})\033[0m"
            ;;
        404)
            result="\033[31m${protocol}://${subdomain}:${port} not found (Status code: ${status_code})\033[0m"
            ;;
        *)
            result="\033[37m${protocol}://${subdomain}:${port} returned status code ${status_code}\033[0m"
            ;;
    esac
    
    echo -e "$result"
    
    # Save to output file if specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "${protocol}://${subdomain}:${port} (Status code: ${status_code}) - Sources: ${sources}" >> "$OUTPUT_FILE"
    fi
}

# Read the subdomains file and probe each subdomain
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        # Extract subdomain and sources
        subdomain=$(echo "$line" | awk -F',' '{print $1}')
        sources=$(echo "$line" | awk -F',' '{print substr($0, index($0,$2))}')
        sources=${sources:1:-1}  # Remove the surrounding brackets
        sources=$(echo "$sources" | tr ',' ' ')  # Replace commas with spaces

        # Check for duplicates
        if [[ -n "${SEEN_SUBDOMAINS[$subdomain]}" ]]; then
            echo -e "\033[33mWarning: Duplicate subdomain found: ${subdomain} (Sources: ${sources})\033[0m"
            continue
        fi
        SEEN_SUBDOMAINS[$subdomain]=1

        for port in "${FILTER_PORTS[@]}"; do
            if [[ $port -eq 80 ]]; then
                probe_subdomain "$subdomain" "$sources" "$port" "http"
            elif [[ $port -eq 443 ]]; then
                probe_subdomain "$subdomain" "$sources" "$port" "https"
            else
                # For non-standard ports, try both http and https
                probe_subdomain "$subdomain" "$sources" "$port" "http"
                probe_subdomain "$subdomain" "$sources" "$port" "https"
            fi
        done
    fi
done < "$SUBDOMAINS_FILE"
