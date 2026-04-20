#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage: build-schema.sh [-e stage|prod] [--install] [--test]

Options:
  -e, --env       Target environment: stage or prod (default: stage)
  --install       Install required tools (generate-v1-only-permissions, ksl)
  --test          Build test schema into _private/test-schema/{env}-schema.zed
  --stage-test    Shortcut: make init && make ksl-test-schema-stage
  -h, --help      Show this help message

Examples:
  scripts/build-schema.sh --install -e stage
  scripts/build-schema.sh -e prod
  scripts/build-schema.sh -e stage --test
  scripts/build-schema.sh --stage-test
EOF
}

ENVIRONMENT="stage"
DO_INSTALL=false
BUILD_TEST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env)
      ENVIRONMENT="${2:-}"
      shift 2
      ;;
    --install)
      DO_INSTALL=true
      shift 1
      ;;
    --test)
      BUILD_TEST=true
      shift 1
      ;;
    --stage-test)
      # Shortcut for: make init && make ksl-test-schema-stage
      ENVIRONMENT="stage"
      DO_INSTALL=true
      BUILD_TEST=true
      shift 1
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

case "$ENVIRONMENT" in
  stage|prod) ;;
  *) echo "ENV must be 'stage' or 'prod' (got '$ENVIRONMENT')" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if $DO_INSTALL; then
  echo "Installing required tools via 'make init'..."
  make -C "$REPO_ROOT" init | cat
fi

# Ensure Go bin paths are available for the current shell
export PATH="$HOME/go/bin:${GOPATH:-$HOME/go}/bin:$PATH"

# Verify required tools are present
for tool in generate-v1-only-permissions ksl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool '$tool' not found in PATH. Re-run with --install or add it to PATH." >&2
    exit 1
  fi
done

TARGET="ksl-schema-$ENVIRONMENT"
OUT_PATH="configs/$ENVIRONMENT/schemas/schema.zed"
if $BUILD_TEST; then
  TARGET="ksl-test-schema-$ENVIRONMENT"
  OUT_PATH="_private/test-schema/${ENVIRONMENT}-schema.zed"
fi

echo "Building schema for environment: $ENVIRONMENT (target: $TARGET)"
make -C "$REPO_ROOT" "$TARGET" | cat

if [[ -f "$REPO_ROOT/$OUT_PATH" ]]; then
  echo "Schema built: $REPO_ROOT/$OUT_PATH"
else
  echo "Expected output not found: $REPO_ROOT/$OUT_PATH" >&2
  exit 2
fi

echo "Done."


