# iTerm2 Dynamic Worktree Profiles

Automatically create and switch iTerm2 profiles based on your current git worktree, making it visually easy to distinguish between different projects.

## What It Does

This script creates dynamic iTerm2 profiles for git worktrees with:

- **Automatic profile creation**: Unique iTerm2 profile for each worktree
- **Visual differentiation**: Assigns color presets and worktree name badges
- **Persistent color choices**: Remembers color assignments per worktree
- **Smart color selection**: Avoids reusing colors already assigned to other worktrees
- **Profile inheritance**: Merges with your default iTerm2 profile settings
- **Shell integration**: Automatically switches profiles when changing directories
- **Profile activation**: Immediately activates the profile using iTerm2's shell integration

## Requirements

- **macOS** - Uses macOS-specific commands
- **iTerm2** - Installed at `/Applications/iTerm.app`
- **Ruby 3.3.7** - Or any version that supports the standard library features used
- **git** - For worktree detection
- **iTerm2 Shell Integration** (optional) - For automatic profile switching

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/MihaiOnSoftware/directoryBasedProfiles.git
   cd directoryBasedProfiles
   ```

2. Make the script executable:
   ```bash
   chmod +x bin/iterm_worktree_profile.rb
   ```

3. (Optional) Add to your PATH or create an alias:
   ```bash
   # Add to ~/.zshrc or ~/.bashrc
   alias iterm-profile='/path/to/directoryBasedProfiles/bin/iterm_worktree_profile.rb'
   ```

## Usage

### Basic Usage

Run the script from within any git worktree:

```bash
./bin/iterm_worktree_profile.rb
```

This will:
1. Detect the current worktree
2. Generate or load a profile with a color preset
3. Create the profile in iTerm2's DynamicProfiles
4. Write a `.iterm_profile` marker file
5. Activate the profile (if shell integration is installed)

### Specify a Color Preset

```bash
./bin/iterm_worktree_profile.rb --preset "Solarized Dark"
```

Available presets:
- Solarized Dark
- Tango Dark
- Solarized Light
- Tango Light
- Pastel (Dark Background)
- Smoooooth

### Specify a Path

```bash
./bin/iterm_worktree_profile.rb /path/to/worktree
```

### Clear All Profiles

Remove all worktree profiles and configuration:

```bash
./bin/iterm_worktree_profile.rb --clear-all
```

## Shell Integration Setup

For automatic profile switching when changing directories:

1. Install iTerm2 Shell Integration:
   - iTerm2 menu → Install Shell Integration

2. Add the integration code to your shell:
   ```bash
   ./bin/iterm_worktree_profile.rb --generate-shell-integration >> ~/.zshrc
   ```

3. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

Now your iTerm2 profile will automatically switch when you `cd` into different worktrees.

## How It Works

1. **Profile Generation**: Creates a unique GUID based on worktree name (stable across runs)
2. **Color Assignment**:
   - First run: Randomly selects from 6 preferred presets
   - Subsequent runs: Reuses the saved color for that worktree
   - Avoids colors already assigned to other worktrees
3. **Profile Storage**: Stores profiles in `~/Library/Application Support/iTerm2/DynamicProfiles/worktrees.json`
4. **Configuration**: Saves color assignments in `~/.config/iterm_worktree_profile.json`
5. **Marker File**: Creates `.iterm_profile` in the worktree root containing the profile name
6. **Shell Integration**: Shell hook reads `.iterm_profile` and switches to that profile

## Development

### Running Tests

Install test dependencies:

```bash
bundle install
```

Run the test suite:

```bash
ruby test/iterm_worktree_profile_test.rb
```

The test suite includes:
- 100+ test cases covering all functionality
- Branch coverage tracking (requires >80% coverage)
- Comprehensive edge case testing
- No external dependencies (all I/O is mocked)

### Test Coverage

After running tests, view coverage report:

```bash
open coverage/index.html
```

## Files Created

- `~/Library/Application Support/iTerm2/DynamicProfiles/worktrees.json` - Dynamic profiles
- `~/.config/iterm_worktree_profile.json` - Color preset configuration
- `.iterm_profile` - Marker file in each worktree root

## Troubleshooting

### Profile not switching automatically

1. Verify iTerm2 Shell Integration is installed
2. Check that the shell integration code is in your `~/.zshrc`
3. Ensure you've restarted your shell or run `source ~/.zshrc`
4. Verify the `.iterm_profile` file exists in your worktree root

### Color preset not found

List available presets:
```bash
plutil -convert json -o - /Applications/iTerm.app/Contents/Resources/ColorPresets.plist | jq 'keys'
```

### Profile not appearing in iTerm2

iTerm2 reads DynamicProfiles on launch and periodically. Try:
1. Restarting iTerm2
2. Checking `~/Library/Application Support/iTerm2/DynamicProfiles/worktrees.json` exists

## License

MIT
