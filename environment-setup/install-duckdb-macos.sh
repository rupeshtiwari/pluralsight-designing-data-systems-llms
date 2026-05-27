#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; exit 1; }

echo "=================================="
echo " DuckDB macOS installer"
echo "=================================="
echo ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This script is for macOS only."
fi

echo "Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is required. Install it from https://brew.sh/ and rerun this script."
fi
pass "Homebrew found: $(brew --version | head -1)"

echo ""
echo "Checking DuckDB CLI..."
if ! command -v duckdb >/dev/null 2>&1; then
  warn "DuckDB CLI not found. Installing DuckDB..."
  brew install duckdb
else
  pass "DuckDB already installed: $(duckdb --version 2>&1 | head -1)"
fi

echo ""
echo "Validating DuckDB..."
duckdb --version >/dev/null
pass "DuckDB command works: $(duckdb --version 2>&1 | head -1)"

echo ""
echo "Testing DuckDB query..."
duckdb :memory: "SELECT 'duckdb_ready' AS status;" >/tmp/duckdb_test_output.txt
cat /tmp/duckdb_test_output.txt

echo ""
pass "DuckDB is installed and ready."
echo ""
echo "Example usage:"
echo "  duckdb --version"
echo "  duckdb data/northwind.duckdb"
echo ""
echo "Note:"
echo "  If the course app is running, do not manually open data/northwind.duckdb."
echo "  The app may hold a file lock. Use course demo scripts instead."
