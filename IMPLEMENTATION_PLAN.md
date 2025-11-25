# Implementation Plan: Add `-d` Delete Command

## Context

Add a `-d/--delete [path]` command that deletes the iTerm profile for a specified directory. The command should intelligently find which profile to delete by querying iTerm2 for the currently active profile.

## Approach

Start with the simplest implementation (explicit path argument) and progressively add intelligence (current directory default, iTerm query). Use the **SIMPLE/COMPLEX** splitting pattern to validate core functionality early, then layer on sophistication.

## Slices

### Slice 1: Delete by explicit path argument

**Goal**: Prove core deletion mechanism works

**Implementation**:
- Add `delete_profile(path)` class method
- Remove profile from `directories.json` by matching GUID (generated from path using existing `generate_stable_guid` method)
- Remove path entry from `iterm_directory_profile.json` config file
- Handle missing files gracefully (no error if files don't exist)
- Add `-d PATH` to CLI OptionParser (path is required in this slice)
- Print warning message if no profile found for the path
- Print success message if profile deleted

**Tests**:
- Profile deleted from `directories.json`
- Path entry deleted from `iterm_directory_profile.json`
- GUID matching works correctly (uses same logic as creation)
- No error when files don't exist
- Other profiles remain untouched after deletion
- CLI requires path argument with `-d` flag
- Appropriate messages printed for success and not-found cases

**Success criteria**: `iterm_directory_profile -d /some/path` successfully deletes the profile for that path

---

### Slice 2: Use current directory when path not provided

**Goal**: Make command convenient for the common case (deleting profile for current directory)

**Implementation**:
- Make path argument optional with `-d` flag
- Default to `Dir.pwd` when no path provided
- All slice 1 behavior maintained

**Tests**:
- Works with explicit path (all slice 1 tests still pass)
- Uses current directory when no path given
- CLI accepts `-d` with no argument
- Correct path used in both scenarios

**Success criteria**: `iterm_directory_profile -d` deletes profile for current directory

---

### Slice 3: Try iTerm query for active profile

**Goal**: Validate whether querying iTerm2 for the active profile works reliably

**Implementation**:
- Add `fetch_iterm_profile_name` class method
  - Use `it2profile -g` command (iTerm2's official utility)
  - Return profile name or nil if command fails
  - ~~Originally tried `ENV['ITERM_PROFILE']` but it doesn't update with Bound Hosts profiles~~
- Add `find_profile_path_by_name(profile_name)` method
  - Read existing profiles from `directories.json`
  - Find profile with matching "Name" field
  - Extract directory path from "Directory: /path" format
  - Return path or nil if no match found
- Modify delete CLI flow:
  - If path provided explicitly: use it
  - If no path: try iTerm query first, fall back to current directory
- Print which path was found and used (helpful for debugging)

**Tests**:
- `fetch_iterm_profile_name` calls `it2profile -g` and returns result
- Returns nil when command fails
- `find_profile_path_by_name` maps profile name to path correctly
- Handles "Directory: " prefix extraction
- Returns nil when profile name doesn't match any path
- Delete flow tries iTerm query before falling back to current dir
- All slice 2 tests still pass

**Success criteria**: Can query and use iTerm profile name to find which directory's profile to delete

**Findings from implementation**:
- ❌ `ENV['ITERM_PROFILE']` does NOT work - stays as "Default" even with active Bound Hosts profiles
- ✅ `it2profile -g` DOES work - correctly returns active profile name
- Research showed AppleScript also works but `it2profile -g` is simpler and official
- Slice 4 (parent walking) is NOT needed - iTerm query approach works reliably

---

### Slice 4: Walk parent directories (CONDITIONAL)

**Goal**: Alternative approach if iTerm query doesn't work reliably in Slice 3

**Implementation**:
- Add `find_profile_in_parents(starting_path)` method
  - Start at `starting_path`
  - Check if profile exists for current path
  - Walk up to parent directory
  - Repeat until profile found or filesystem root reached
  - Return matching path or nil
- Replace iTerm query logic with parent walking in delete flow
- Print which path was found and used

**Tests**:
- Finds profile at exact path
- Finds profile in parent directory
- Finds profile in grandparent directory
- Returns nil when no profile found in any parent
- Stops at filesystem root (doesn't infinite loop)
- Profile discovery works from subdirectories

**Success criteria**: Reliable profile discovery by walking parent directories

**Decision point**: After manual testing in Slice 3, decide whether to:
- **Keep Slice 3 approach** if `$ITERM_PROFILE` reliably reflects Bound Hosts switching
- **Implement Slice 4** if iTerm query proves unreliable

Only implement this slice if Slice 3 manual verification shows the iTerm query approach doesn't work for our use case.

---

### Slice 5: Update README documentation

**Goal**: Make delete feature discoverable and understandable

**Implementation**:
- Add "Delete a Profile" section under Usage
- Document `-d [PATH]` flag with examples
- Show both use cases: with explicit path and without
- Document intelligent discovery behavior (iTerm query OR parent walking, depending on what was implemented)
- Add to troubleshooting section if relevant (e.g., notes about `$ITERM_PROFILE` limitations)
- Update "Files Created" section to mention deletion affects both files

**Tests**: Manual review of README clarity and completeness

**Success criteria**: Clear, accurate documentation of delete functionality with practical examples

---

## Pattern Analysis

This plan follows the **SIMPLE/COMPLEX** pattern:
- **Slice 1**: Bare-bones delete with explicit path (proves core mechanism works)
- **Slice 2**: Convenience enhancement (current directory default)
- **Slice 3**: Intelligence layer (iTerm query)
- **Slice 4**: Alternative intelligence (conditional, only if Slice 3 fails)
- **Slice 5**: Documentation

Can stop after any slice and still have valuable, working functionality. Each slice validates one new concept before moving to the next.

## Execution Notes

- Use `/generic:tdd-slice` command to execute each slice
- This applies quality standards and commits incrementally (not as a final step)
- Each slice is independent and fully functional
- Manual verification in Slice 3 determines whether Slice 4 is needed
