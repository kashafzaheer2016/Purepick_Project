#!/usr/bin/env bash
# run_tests.sh — PurePick test runner
#
# Usage:
#   ./run_tests.sh              # run all tests
#   ./run_tests.sh unit         # unit tests only (fast, no DB)
#   ./run_tests.sh api          # API endpoint tests
#   ./run_tests.sh integration  # DB integration tests
#   ./run_tests.sh coverage     # full run with HTML coverage report
#   ./run_tests.sh fast         # unit + api, skip slow/integration

set -e
cd "$(dirname "$0")/backend"

export DJANGO_SETTINGS_MODULE=purepick_core.settings.test

case "${1:-all}" in
  unit)
    echo "Running unit tests..."
    pytest tests/ -m unit -v
    ;;
  api)
    echo "Running API endpoint tests..."
    pytest tests/ -m api -v
    ;;
  integration)
    echo "Running integration tests..."
    pytest tests/ -m integration -v
    ;;
  slow)
    echo "Running slow tests (ML model load)..."
    pytest tests/ -m slow -v -s
    ;;
  fast)
    echo "Running fast tests (unit + api)..."
    pytest tests/ -m "unit or api" -v
    ;;
  coverage)
    echo "Running full test suite with coverage..."
    pytest tests/ \
      --cov=purepick_core \
      --cov=scanner \
      --cov=skin_analysis \
      --cov-report=html:coverage_html \
      --cov-report=term-missing \
      --cov-fail-under=70 \
      -v
    echo ""
    echo "Coverage report: backend/coverage_html/index.html"
    ;;
  all|*)
    echo "Running all tests (excluding slow)..."
    pytest tests/ -m "not slow" -v
    ;;
esac
