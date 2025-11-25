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

### Delete a Profile

Remove the iTerm2 profile for a specific directory:

```bash
# Delete profile for current directory
iterm_directory_profile -d

# Delete profile for specific path
iterm_directory_profile -d /path/to/directory
```

The delete command intelligently determines which profile to remove:
1. If you provide a path explicitly, it deletes that directory's profile
2. If no path is given, it queries iTerm2 for your currently active profile using `it2profile -g`
3. If iTerm2 returns a valid directory profile, it deletes that profile
4. Otherwise, it falls back to deleting the profile for your current directory

This means you can run `iterm_directory_profile -d` from any location, and it will delete the profile that's currently active in your iTerm2 window, regardless of what directory you're in.

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

- `~/Library/Application Support/iTerm2/DynamicProfiles/directories.json` - Dynamic profiles (modified by create and delete operations)
- `~/.config/iterm_directory_profile.json` - Color preset configuration (modified by create and delete operations)
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

### Delete command doesn't find the right profile

If `iterm_directory_profile -d` deletes the wrong profile or can't find a profile:

1. **Check what iTerm2 thinks is the active profile**:
   ```bash
   it2profile -g
   ```
   This shows the profile name iTerm2 currently reports. The delete command uses this to find which directory's profile to remove.

2. **Profile name doesn't match a directory**: If iTerm2 reports "Default" or another non-directory profile name, the delete command falls back to using your current directory. Make sure you're in the directory whose profile you want to delete, or provide the path explicitly:
   ```bash
   iterm_directory_profile -d /path/to/directory
   ```

3. **Profile deleted but iTerm2 still shows colors**: iTerm2 may cache the profile. Try:
   - Opening a new tab or window
   - Restarting iTerm2
   - The profile is removed from `directories.json` but iTerm2 needs to reload

## License

MIT
