set -e  # Exit on error

# Find the closest ancestor directory containing a .stuff folder
find_repo_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.stuff" ]]; then
      echo "$dir/.stuff"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "Error: No .stuff directory found in any ancestor." >&2
  exit 1
}

# https://stackoverflow.com/a/246128
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

export STUFF_BASE_DIR="$SCRIPT_DIR"
export STUFF_REPO_DIR="$(find_repo_root)"
export STUFF_CONFIG_FILE="$STUFF_REPO_DIR/stuff.yaml"
export STUFF_SOURCE_DIR="$(dirname "$STUFF_REPO_DIR")"
export STUFF_COMPILED_DIR="$STUFF_SOURCE_DIR/.stuff-compiled"

#rm -rf "$STUFF_COMPILED_DIR"
mkdir -p "$STUFF_COMPILED_DIR"

if [[ ! -f "$STUFF_CONFIG_FILE" ]]; then
  echo "Error: stuff.yaml not found in .stuff directory." >&2
  exit 1
fi

export STUFF_VERSION=$(yq ".stuff" "$STUFF_CONFIG_FILE")
if [[ "$STUFF_VERSION" != "0.1.0" ]]; then
  echo "Error: stuff.yaml must contain `stuff: '0.1.0'`, got $STUFF_VERSION" >&2
  exit 1
fi

COMMAND="$1"
SUBCOMMAND="$2"
TARGET="$3"

case "$COMMAND" in
  generate-typedefs)
    pushd "$STUFF_REPO_DIR" >/dev/null
    shift # remove "generate-typedefs" from $@
    NAMESPACE="$(yq -r ".scope" "$STUFF_CONFIG_FILE").$(yq -r ".name" "$STUFF_CONFIG_FILE")"
    ytt -f "$STUFF_BASE_DIR/convert-typedefs.ytt.yaml" --data-values-file "$STUFF_REPO_DIR/typedefs.jtd.yaml" --data-value namespace="$NAMESPACE" \
        | yq -o=json - \
        | jtd-codegen - --root-name root "$@"
    popd >/dev/null
    exit 0
    ;;
  validate|test)
    CMD=$(yq -r ".$COMMAND" "$STUFF_CONFIG_FILE")
    echo "Running: $CMD"
    eval "$CMD"
    ;;
  refresh|discard)
    # 1. Check if manifest exists
    MANIFEST_FILE="$STUFF_SOURCE_DIR/.stuff-manifest.yaml"
    if [[ ! -f "$MANIFEST_FILE" ]]; then
      echo "No manifest file found, nothing to refresh" >&2
      exit 0
    fi

    # 2. Verify manifest is a list
    if ! yq 'type == "seq"' "$MANIFEST_FILE" >/dev/null 2>&1; then
      echo "Error: Manifest file must be a list" >&2
      exit 1
    fi

    # 3. Find entry with path "."
    ENTRY_TYPE=$(yq -r '.[] | select(.path == ".") | .type' "$MANIFEST_FILE")
    ENTRY_NAME=$(yq -r '.[] | select(.path == ".") | .name' "$MANIFEST_FILE")

    if [[ -z "$ENTRY_TYPE" || -z "$ENTRY_NAME" ]]; then
      echo "No root entry found in manifest" >&2
      exit 0
    fi

    if [[ "$COMMAND" == "refresh" && "$ENTRY_TYPE" == "view" ]]; then
      echo "Error: Views cannot be refreshed" >&2
      exit 1
    fi
    if [[ "$ENTRY_TYPE" != "morph" && "$ENTRY_TYPE" != "view" ]]; then
      echo "Error: Invalid type '$ENTRY_TYPE' in manifest" >&2
      exit 1
    fi

    # 4. Execute appropriate save command
    if [[ "$COMMAND" == "refresh" ]]; then
      export STUFF_OP_DIR="$STUFF_SOURCE_DIR"
      CMD=$(yq -r ".morphs.$ENTRY_NAME.save" "$STUFF_CONFIG_FILE")
      echo "Running: $CMD"
      eval "$CMD"
    else
      echo "Discarding manifested morph or view."
    fi

    # For now, only clean up on an explicit discard command.
    # This might be changed in the future to also happen on a refresh.
    if [[ "$COMMAND" == "discard" ]]; then

      # 5. Remove the entry and clean up if empty
      yq -iy 'del(.[] | select(.path == "."))' "$MANIFEST_FILE"
      if [[ $(yq -r 'length' "$MANIFEST_FILE") == 0 ]]; then
        rm "$MANIFEST_FILE"
      fi

      # 6. Clean up source directory
      echo "Cleaning up source directory:"
      echo "$STUFF_SOURCE_DIR"
      find "$STUFF_SOURCE_DIR" -maxdepth 1 -type f -not -name ".*" -exec rm {} \;
      find "$STUFF_SOURCE_DIR" -maxdepth 1 -type d -not -name ".*" -exec rm -r {} \;

    fi
    ;;
  load-all)
    MORPHS=$(yq -r ".morphs | keys | .[]" "$STUFF_CONFIG_FILE")
    for MORPH in $MORPHS; do
      CMD=$(yq -r ".morphs.$MORPH.load" "$STUFF_CONFIG_FILE")
      echo "Running: $CMD"
      eval "$CMD"
    done
    exit 0
    VIEWS=$(yq -r ".views | keys | .[]" "$STUFF_CONFIG_FILE")
    for VIEW in $VIEWS; do
      CMD=$(yq -r ".views.$VIEW.load" "$STUFF_CONFIG_FILE")
      echo "Running: $CMD"
      eval "$CMD"
    done
    ;;
  morph|view)
    if [[ -z "$SUBCOMMAND" || (-z "$TARGET" && "$SUBCOMMAND" != "load-all" && "$SUBCOMMAND" != "realize") ]]; then
      echo "Usage: stuff $COMMAND {load|save|realize} <name> | stuff $COMMAND load-all" >&2
      exit 1
    fi
    if [[ "$COMMAND" == "morph" && "$SUBCOMMAND" =~ ^(load|save)$ ]]; then
      export STUFF_OP_DIR="$STUFF_COMPILED_DIR/morphs/$TARGET"
      CMD=$(yq -r ".morphs.$TARGET.$SUBCOMMAND" "$STUFF_CONFIG_FILE")
    elif [[ "$COMMAND" == "morph" && "$SUBCOMMAND" == "manifest" ]]; then
      MANIFEST_FILE="$STUFF_SOURCE_DIR/.stuff-manifest.yaml"
      if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo "[]" > "$MANIFEST_FILE"
      fi
      if ! yq 'type == "seq"' "$MANIFEST_FILE" >/dev/null 2>&1; then
        echo "[]" > "$MANIFEST_FILE"
      fi
      if [[ $(yq -r '.[] | select(.path == ".") | .path' "$MANIFEST_FILE") == "." ]]; then
        echo "Error: An entry with path '.' already exists in manifest, please discard first" >&2
        exit 1
      fi
      # yq -iy 'del(.[] | select(.path == "."))' "$MANIFEST_FILE"
      yq -iy '. += [{"path": ".", "type": "morph", "name": "'"$TARGET"'"}]' "$MANIFEST_FILE"
      export STUFF_OP_DIR="$STUFF_SOURCE_DIR"
      CMD=$(yq -r ".morphs.$TARGET.load" "$STUFF_CONFIG_FILE")
    elif [[ "$COMMAND" == "view" && "$SUBCOMMAND" == "load" ]]; then
      export STUFF_OP_DIR="$STUFF_COMPILED_DIR/views/$TARGET"
      CMD=$(yq -r ".views.$TARGET.$SUBCOMMAND" "$STUFF_CONFIG_FILE")
    elif [[ "$COMMAND" == "view" && "$SUBCOMMAND" == "manifest" ]]; then
      MANIFEST_FILE="$STUFF_SOURCE_DIR/.stuff-manifest.yaml"
      if [[ ! -f "$MANIFEST_FILE" ]]; then
        echo "[]" > "$MANIFEST_FILE"
      fi
      if ! yq 'type == "seq"' "$MANIFEST_FILE" >/dev/null 2>&1; then
        echo "[]" > "$MANIFEST_FILE"
      fi
      if [[ $(yq -r '.[] | select(.path == ".") | .path' "$MANIFEST_FILE") == "." ]]; then
        echo "Error: An entry with path '.' already exists in manifest, please discard first" >&2
        exit 1
      fi
      # yq -iy 'del(.[] | select(.path == "."))' "$MANIFEST_FILE"
      yq -iy '. += [{"path": ".", "type": "view", "name": "'"$TARGET"'"}]' "$MANIFEST_FILE"
      export STUFF_OP_DIR="$STUFF_SOURCE_DIR"
      CMD=$(yq -r ".views.$TARGET.load" "$STUFF_CONFIG_FILE")
    elif [[ "$COMMAND" == "morph" && "$SUBCOMMAND" == "load-all" ]]; then
      MORPHS=$(yq -r ".morphs | keys | .[]" "$STUFF_CONFIG_FILE")
      for MORPH in $MORPHS; do
        CMD=$(yq -r ".morphs.$MORPH.load" "$STUFF_CONFIG_FILE")
        echo "Running: $CMD"
        eval "$CMD"
      done
      exit 0
    elif [[ "$COMMAND" == "view" && "$SUBCOMMAND" == "load-all" ]]; then
      VIEWS=$(yq -r ".views | keys | .[]" "$STUFF_CONFIG_FILE")
      for VIEW in $VIEWS; do
        CMD=$(yq -r ".views.$VIEW.load" "$STUFF_CONFIG_FILE")
        echo "Running: $CMD"
        eval "$CMD"
      done
      exit 0
    else
      echo "Invalid command." >&2
      exit 1
    fi
    echo "Running: $CMD"
    eval "$CMD"
    ;;
  *)
    echo "Usage: stuff {generate-typedefs|validate|test|refresh|discard|load-all|morph|view}" >&2
    exit 1
    ;;
esac
