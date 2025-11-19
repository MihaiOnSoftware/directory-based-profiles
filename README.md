# iTerm2 Directory-Based Profiles

Automatically create and switch iTerm2 profiles based on your current directory, making it visually easy to distinguish between different projects and directories.

## What It Does

This script creates dynamic iTerm2 profiles for directories with:

- **Automatic profile creation**: Unique iTerm2 profile for each directory
- **Visual differentiation**: Assigns color presets and directory/branch name badges
- **Persistent color choices**: Remembers color assignments per directory
- **Smart color selection**: Avoids reusing colors already assigned to other directories
- **Profile inheritance**: Merges with your default iTerm2 profile settings
- **Native automatic switching**: Uses iTerm2's "Bound Hosts" feature for seamless profile switching
- **Git branch badges**: Shows git branch name in badge when available, falls back to directory path

## Requirements

- **macOS** - Uses macOS-specific commands
- **iTerm2** - Installed at `/Applications/iTerm.app`
- **Ruby** - Any version with standard library support
- **git** (optional) - For git branch badge display

## Installation

Run the installation script to set up the command:

```bash
./install.sh
```

This will:
1. Create a symlink at `~/.local/bin/iterm_directory_profile`
2. Add `~/.local/bin` to your PATH in `~/.zshrc` (if not already present)

After installation, reload your shell:

```bash
source ~/.zshrc
```

Or start a new shell session.

## Usage

### Basic Usage

Run the command from within any directory:

```bash
iterm_directory_profile
```

This will:
1. Detect the current directory
2. Generate or load a profile with a color preset
3. Create the profile in iTerm2's DynamicProfiles
4. Register the directory path as a "Bound Host" for automatic switching

### Specify a Color Preset

```bash
iterm_directory_profile --preset "Solarized Dark"
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
iterm_directory_profile /path/to/directory
```

### Clear All Profiles

Remove all directory profiles and configuration:

```bash
iterm_directory_profile --clear-all
```

## Automatic Profile Switching

After creating a profile for a directory, iTerm2 will automatically switch to that profile when you `cd` into that directory. This works through iTerm2's native "Bound Hosts" feature, which monitors your current working directory.

No additional shell integration or configuration is required beyond running the `iterm_directory_profile` command once for each directory you want to track.

## How It Works

1. **Profile Generation**: Creates a unique GUID based on directory path (stable across runs)
2. **Color Assignment**:
   - First run: Randomly selects from 6 preferred presets
   - Subsequent runs: Reuses the saved color for that directory
   - Avoids colors already assigned to other directories
3. **Profile Storage**: Stores profiles in `~/Library/Application Support/iTerm2/DynamicProfiles/directories.json`
4. **Configuration**: Saves color assignments in `~/.config/iterm_directory_profile.json`
5. **Bound Hosts**: Registers the directory path in the profile's "Bound Hosts" field
6. **Automatic Switching**: iTerm2 monitors your current directory and activates the matching profile automatically
7. **Badge Display**: Shows git branch name in badge if in a git repository, otherwise shows directory path

## Development

### Running Tests

Install test dependencies:

```bash
bundle install
```

Run the test suite:

```bash
ruby test/iterm_directory_profile_test.rb
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

- `~/Library/Application Support/iTerm2/DynamicProfiles/directories.json` - Dynamic profiles
- `~/.config/iterm_directory_profile.json` - Color preset configuration
- `~/.local/bin/iterm_directory_profile` - Symlink to the script (created by install.sh)

## Troubleshooting

### Profile not switching automatically

1. Ensure you've run `iterm_directory_profile` in the directory at least once
2. Check that the profile exists in `~/Library/Application Support/iTerm2/DynamicProfiles/directories.json`
3. Verify that iTerm2 is monitoring your working directory (this is enabled by default)
4. Try restarting iTerm2 to reload the dynamic profiles

### Color preset not found

List available presets:
```bash
plutil -convert json -o - /Applications/iTerm.app/Contents/Resources/ColorPresets.plist | jq 'keys'
```

### Profile not appearing in iTerm2

iTerm2 reads DynamicProfiles on launch and periodically. Try:
1. Restarting iTerm2
2. Checking `~/Library/Application Support/iTerm2/DynamicProfiles/directories.json` exists
3. Verifying the JSON file is valid with `cat ~/Library/Application\ Support/iTerm2/DynamicProfiles/directories.json | jq`

## License

MIT
