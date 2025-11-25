# Refactoring Plan: Slim Down Constructor

## Goal

Move creation-specific parameters from constructor to `run` method, keeping all tests passing at each step.

**Current constructor (line 26):**
```ruby
def initialize(
  default_guid_output:, bookmarks_output:, color_presets_output:,
  directory_path_output:, git_branch_output:, config_file_content:,
  existing_profiles_content:, preset_name: nil,
  path: nil, stdout: $stdout, stderr: $stderr
)
```

**Target:**
```ruby
def initialize(path:, existing_profiles_content:, config_file_content:,
               stdout: $stdout, stderr: $stderr)

def run(default_guid_output:, bookmarks_output:, color_presets_output:,
        directory_path_output:, git_branch_output:, preset_name: nil)
```

**Why:** This will make it easy to add a `delete` method later that only needs the constructor parameters, not the creation-specific I/O data.

---

## Slice 0: Rename test helper from create_instance to run_script

**Goal:** Make test helper call both `new` and `run` so we only update it during refactor

**Implementation:**
- No production code changes

**Tests:**
- Find `create_instance` helper (around line 1396)
- Rename to `run_script`
- Change implementation to:
  ```ruby
  def run_script(**overrides)
    ItermDirectoryProfile.new(**default_io_results.merge(overrides)).run
  end
  ```
- Find/replace all `create_instance(...).run` with `run_script(...)`
- Keep any `create_instance(...)` without `.run` as-is (if any exist)

**Success criteria:**
- Helper renamed and calls both `new` and `run`
- All test call sites updated
- All tests green

---

## Slice 1: Make preset_name a run parameter

**Goal:** Move `preset_name` from constructor to run method

**Implementation:**
- Remove `preset_name` parameter from constructor
- Add `preset_name: nil` parameter to run method
- Change `run` to use parameter instead of `@preset_name`
- Update line 52: `if config_preset && preset_name.nil?`
- Update line 54: `elsif !config_preset && preset_name.nil?`
- Update line 56: `else preset_name`

**Tests:**
- Update `run_script` helper to pass `preset_name` to `run` instead of constructor
- No changes to test call sites!
- All tests pass

**Success criteria:**
- `preset_name` not in constructor
- Only helper updated, test call sites unchanged
- All tests green

---

## Slice 2: Make git_branch_output a run parameter

**Goal:** Move `git_branch_output` from constructor to run

**Implementation:**
- Remove `@git_branch_output` instance variable
- Add `git_branch_output:` parameter to `run`
- Change `get_display_name` to accept `git_branch_output` parameter
- Update `run` line 48 to pass parameter: `get_display_name(git_branch_output)`

**Tests:**
- Update `run_script` helper to pass `git_branch_output` to `run` instead of constructor
- No changes to test call sites!
- All tests pass

**Success criteria:**
- `git_branch_output` not in constructor
- `get_display_name(git_branch_output)` takes parameter
- All tests green

---

## Slice 3: Make color_presets_output a run parameter

**Goal:** Move `color_presets_output` from constructor to run

**Implementation:**
- Remove `@color_presets_output` instance variable
- Add `color_presets_output:` parameter to `run`
- Change `load_color_preset(preset_name)` to `load_color_preset(preset_name, color_presets_output)`
- Update method to use parameter instead of `@color_presets_output` (line 337)
- Update `run` line 62 to pass parameter

**Tests:**
- Update `run_script` helper to pass `color_presets_output` to `run` instead of constructor
- No changes to test call sites!
- All tests pass

**Success criteria:**
- `color_presets_output` not in constructor
- `load_color_preset` takes parameter
- All tests green

---

## Slice 4: Make bookmarks_output a run parameter

**Goal:** Move `bookmarks_output` from constructor to run

**Implementation:**
- Remove `@bookmarks_output` instance variable
- Add `bookmarks_output:` parameter to `run`
- Change `read_bookmarks` to accept parameter
- Update `read_default_profile` to accept `bookmarks_output` parameter
- Thread through from `run` line 61

**Tests:**
- Update `run_script` helper to pass `bookmarks_output` to `run` instead of constructor
- No changes to test call sites!
- All tests pass

**Success criteria:**
- `bookmarks_output` not in constructor
- Methods take parameters
- All tests green

---

## Slice 5: Make default_guid_output a run parameter

**Goal:** Move `default_guid_output` from constructor to run

**Implementation:**
- Remove `@default_guid_output` instance variable
- Add `default_guid_output:` parameter to `run`
- Change `read_default_guid` to accept parameter
- Thread through `read_default_profile` to `run` line 61

**Tests:**
- Update `run_script` helper to pass `default_guid_output` to `run` instead of constructor
- No changes to test call sites!
- All tests pass

**Success criteria:**
- `default_guid_output` not in constructor
- Methods take parameters
- All tests green

---

## Slice 6: Handle directory_path_output

**Goal:** Decide what to do with `directory_path_output`

**Implementation:**
- Check usage: line 385 `detect_current_directory` uses it
- Line 44: called during initialization if path is nil
- Options:
  - Keep in constructor (used for initialization)
  - Make it a default value in constructor: `path: nil` becomes `path: Dir.pwd`
  - Pass explicitly when path might be nil

**Tests:**
- Depends on decision
- All tests pass

**Success criteria:**
- Clear decision on placement
- All tests green

---

## Slice 7: Update run_cli to match new signature

**Goal:** CLI calls new and run with correct signatures

**Implementation:**
- Update `run_cli` (around line 206) to split constructor args from run args
- Constructor gets: `path`, `existing_profiles_content`, `config_file_content`, `stdout`, `stderr`
- Run gets: `default_guid_output`, `bookmarks_output`, `color_presets_output`, `git_branch_output`, `preset_name`

**Tests:**
- CLI tests still pass
- All tests pass

**Success criteria:**
- `run_cli` uses new signature
- All tests green

---

## Summary

**Key insight:** Renaming `create_instance` to `run_script` and having it call both `new` and `run` means:
- Only update the helper as we move params
- Test call sites don't change
- Much easier refactor!

**Result:**
- Constructor: `path`, `existing_profiles_content`, `config_file_content`, I/O handles
- Run: All creation-specific data
- Ready for delete in future

**Pattern:** Horizontal refactoring - each slice keeps all tests passing

**Expected outcome:**
- Lightweight constructor that works for any operation
- `run` method takes creation-specific data
- Future `delete` method can use same constructor with minimal data
