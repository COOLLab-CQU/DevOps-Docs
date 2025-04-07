#!/bin/bash

# ==============================================================================
# Script to update a specific section in /etc/hosts from a remote source.
#
# Downloads hosts content from a URL, identifies a block marked by specific
# comments, and replaces or appends this block in the system's /etc/hosts file.
#
# Requires root privileges (sudo) to modify /etc/hosts.
# Requires curl to download the file.
# ==============================================================================

# --- Configuration ---
HOSTS_URL="https://cdn.jsdelivr.net/gh/COOLLab-CQU/DevOps-Docs/hosts"
HOSTS_FILE="/etc/hosts" # System hosts file path
TMP_DOWNLOAD=$(mktemp)  # Temporary file for download
TMP_HOSTS=$(mktemp)     # Temporary file for building the new hosts content
START_MARKER="# <-- COOL-LAB HOSTS BEGIN -->"
END_MARKER="# <-- COOL-LAB HOSTS END -->"
# Escape markers for sed patterns
START_MARKER_ESCAPED=$(printf '%s\n' "$START_MARKER" | sed 's:[][\\/.^$*]:\\&:g')
END_MARKER_ESCAPED=$(printf '%s\n' "$END_MARKER" | sed 's:[][\\/.^$*]:\\&:g')

# --- Cleanup Function ---
# Ensures temporary files are removed on exit, error, or interrupt.
cleanup() {
  rm -f "$TMP_DOWNLOAD" "$TMP_HOSTS"
}
trap cleanup EXIT INT TERM HUP

# --- Helper Functions ---
log_error() {
  echo "[ERROR] $1" >&2
}

log_info() {
  echo "[INFO] $1"
}

# --- Main Script Logic ---

# 1. Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
  log_error "This script must be run as root (e.g., using sudo)."
  exit 1
fi

# 2. Check if curl is installed
if ! command -v curl &> /dev/null; then
    log_error "'curl' command not found. Please install curl."
    exit 1
fi

# 3. Download the remote hosts file content
log_info "Downloading hosts content from $HOSTS_URL..."
if ! curl -fsSL --connect-timeout 10 --max-time 30 "$HOSTS_URL" -o "$TMP_DOWNLOAD"; then
  log_error "Failed to download hosts file from $HOSTS_URL."
  exit 1
fi
log_info "Download successful."

# 4. Extract the relevant block from the downloaded file
log_info "Extracting COOL-LAB hosts block..."
# Use awk for more robust block extraction
COOL_LAB_BLOCK=$(awk "/^${START_MARKER_ESCAPED}$/{f=1; print; next} /^${END_MARKER_ESCAPED}$/{print; f=0; next} f" "$TMP_DOWNLOAD")

# Check if the block was actually found in the downloaded content
if [[ -z "$COOL_LAB_BLOCK" ]]; then
    log_error "Could not find the block between '$START_MARKER' and '$END_MARKER' in the downloaded file."
    log_error "Please check the content at $HOSTS_URL."
    exit 1
fi
# Ensure the block ends with a newline if it doesn't already
[[ "$COOL_LAB_BLOCK" != *$'\n' ]] && COOL_LAB_BLOCK+=$'\n'

log_info "Block extracted successfully."

# 5. Check if the block already exists in the system hosts file
log_info "Checking system hosts file: $HOSTS_FILE"
if grep -q -F "$START_MARKER" "$HOSTS_FILE"; then
  log_info "Existing COOL-LAB hosts block found. Replacing it."
  # Use sed to delete the existing block and write to the temporary hosts file
  # Explanation of sed command:
  # /^START_MARKER_ESCAPED$/,/^END_MARKER_ESCAPED$/d -> Delete lines from start marker to end marker (inclusive)
  if ! sed "/^${START_MARKER_ESCAPED}$/,/^${END_MARKER_ESCAPED}$/d" "$HOSTS_FILE" > "$TMP_HOSTS"; then
      log_error "Failed to process the existing hosts file ($HOSTS_FILE)."
      exit 1
  fi
else
  log_info "COOL-LAB hosts block not found. Appending new block."
  # Copy the existing hosts file content to the temporary file
  if ! cat "$HOSTS_FILE" > "$TMP_HOSTS"; then
       log_error "Failed to read the existing hosts file ($HOSTS_FILE)."
       exit 1
  fi
  # Ensure there's a newline before appending if the file doesn't end with one
  if [[ $(tail -c1 "$TMP_HOSTS" | wc -l) -eq 0 ]]; then
      echo "" >> "$TMP_HOSTS" # Add a newline if the file doesn't end with one
  fi
fi

# 6. Append the new block to the temporary hosts file
log_info "Adding the downloaded block..."
# Use printf to preserve newlines in the block correctly
if ! printf '%s' "$COOL_LAB_BLOCK" >> "$TMP_HOSTS"; then
    log_error "Failed to append the new block to the temporary hosts file."
    exit 1
fi

# 7. Replace the system hosts file with the updated content
# Optional: Create a backup first
backup_file="${HOSTS_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
log_info "Backing up current hosts file to $backup_file..."
if ! cp "$HOSTS_FILE" "$backup_file"; then
    log_error "Failed to create backup file $backup_file. Aborting update."
    exit 1
fi
log_info "Backup created."

log_info "Updating system hosts file: $HOSTS_FILE..."
# Use cat and redirect to preserve permissions/ownership better than mv when using sudo
if ! cat "$TMP_HOSTS" > "$HOSTS_FILE"; then
    log_error "Failed to write updated content to $HOSTS_FILE."
    log_error "You might need to restore from the backup: $backup_file"
    exit 1
fi

log_info "Hosts file updated successfully!"
exit 0