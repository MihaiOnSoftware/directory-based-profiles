#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/bin/iterm_directory_profile.rb"
TARGET_NAME="iterm_directory_profile"
LOCAL_BIN="$HOME/.local/bin"
TARGET_FILE="$LOCAL_BIN/$TARGET_NAME"
ZSHRC="$HOME/.zshrc"

# Ensure source file exists
if [ ! -f "$SOURCE_FILE" ]; then
  echo "Error: Source file not found: $SOURCE_FILE"
  exit 1
fi

# Ensure .local/bin exists
mkdir -p "$LOCAL_BIN"

# Create symlink
if [ -L "$TARGET_FILE" ] || [ -f "$TARGET_FILE" ]; then
  echo "Removing existing file: $TARGET_FILE"
  rm "$TARGET_FILE"
fi

ln -s "$SOURCE_FILE" "$TARGET_FILE"
echo "Created symlink: $TARGET_FILE -> $SOURCE_FILE"

# Add to PATH in .zshrc if not already present
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$ZSHRC" 2>/dev/null; then
  echo '' >> "$ZSHRC"
  echo '# User binaries' >> "$ZSHRC"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$ZSHRC"
  echo "Added ~/.local/bin to PATH in $ZSHRC"
  echo "Run: source ~/.zshrc"
else
  echo "~/.local/bin already in PATH"
fi

echo ""
echo "Installation complete!"
echo "Run 'source ~/.zshrc' or start a new shell to use: $TARGET_NAME"
