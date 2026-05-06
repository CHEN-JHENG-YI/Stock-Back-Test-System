#!/usr/bin/env bash
# Build the C++ tree (CMake preset `dev`) and run all unit tests.
# Tracked in git; other *.sh remain ignored by default (.gitignore).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

verbose=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v | --verbose)
      verbose=1
      shift
      ;;
    -h | --help)
      echo "Usage: $0 [-v|--verbose] [-h|--help]"
      echo "  Runs: cmake --preset dev, cmake --build --preset dev, ctest --preset dev"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [-v|--verbose] [-h|--help]" >&2
      exit 1
      ;;
  esac
done

cmake --preset dev
cmake --build --preset dev

if [[ "${verbose}" -eq 1 ]]; then
  ctest --preset dev --verbose
else
  ctest --preset dev
fi
