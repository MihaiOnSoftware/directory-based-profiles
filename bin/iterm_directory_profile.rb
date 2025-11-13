#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "digest"

class ItermDirectoryProfile
  PREFERRED_PRESETS = [
    "Solarized Dark",
    "Tango Dark",
    "Solarized Light",
    "Tango Light",
    "Pastel (Dark Background)",
    "Smoooooth",
  ].freeze

  ITERM_PREFS_PATH = File.expand_path("~/Library/Preferences/com.googlecode.iterm2.plist")
  COLOR_PRESETS_PATH = "/Applications/iTerm.app/Contents/Resources/ColorPresets.plist"
  CONFIG_DIR = File.expand_path("~/.config")
  CONFIG_FILE = File.join(CONFIG_DIR, "iterm_directory_profile.json")
  DYNAMIC_PROFILES_DIR = File.expand_path("~/Library/Application Support/iTerm2/DynamicProfiles")
  DYNAMIC_PROFILES_FILE = File.join(DYNAMIC_PROFILES_DIR, "directories.json")
  PROFILE_MARKER_PATH = ".iterm_profile"

  def initialize(
    preset_name: nil,
    path: nil,
    default_guid_output:,
    bookmarks_output:,
    color_presets_output:,
    directory_path_output:,
    config_file_content:,
    existing_profiles_content:,
    stdout: $stdout,
    stderr: $stderr
  )
    @preset_name = preset_name
    @path = path
    @default_guid_output = default_guid_output
    @bookmarks_output = bookmarks_output
    @color_presets_output = color_presets_output
    @directory_path_output = directory_path_output
    @config_file_content = config_file_content
    @existing_profiles_content = existing_profiles_content
    @stdout = stdout
    @stderr = stderr

    @path ||= detect_current_directory if path.nil?
  end

  def run
    directory_name = extract_directory_name(@path)
    config = read_config

    config_preset = config[directory_name]
    preset = if config_preset && @preset_name.nil?
      config_preset
    elsif !config_preset && @preset_name.nil?
      select_random_preset(config.values)
    else
      @preset_name
    end

    profile = generate_minimal_profile
    default_profile = read_default_profile
    color_preset = load_color_preset(preset)
    merged_profile = merge_profiles(profile, default_profile, color_preset)
    write_dynamic_profile(merged_profile)

    config[directory_name] = preset
    write_config(config)

    write_profile_marker(profile["Name"])
    activate_profile(profile["Name"])

    check_shell_integration_setup(directory_name)
  end

  class << self
    def generate_shell_integration_code
      <<~SHELL
        # iTerm2 directory profile switching
        function iterm_set_directory_profile() {
          local marker_file=".iterm_profile"
          if [[ -f "$marker_file" ]]; then
            local profile_name=$(cat "$marker_file")
            it2profile -s "$profile_name"
          fi
        }

        # Hook to run on directory change
        function chpwd_iterm_directory() {
          iterm_set_directory_profile
        }
        chpwd_functions+=(chpwd_iterm_directory)

        # Run on shell load
        iterm_set_directory_profile
      SHELL
    end

    def clear_all_profiles
      File.delete(DYNAMIC_PROFILES_FILE) if File.exist?(DYNAMIC_PROFILES_FILE)
      File.delete(CONFIG_FILE) if File.exist?(CONFIG_FILE)
    end

    def run_cli(argv, stdout: $stdout, stderr: $stderr)
      options = {}
      generate_shell_integration = false
      clear_all = false

      OptionParser.new do |opts|
        opts.banner = "Usage: iterm_directory_profile.rb [options] [path]"

        opts.on("-p", "--preset PRESET_NAME", "Color preset to use (default: saved config or random selection)") do |preset|
          options[:preset_name] = preset
        end

        opts.on("-g", "--generate-shell-integration", "Generate shell integration code") do
          generate_shell_integration = true
        end

        opts.on("-c", "--clear-all", "Clear all directory profiles") do
          clear_all = true
        end

        opts.on("-h", "--help", "Show this help message") do
          stdout.puts opts
          return 0
        end
      end.parse!(argv)

      if generate_shell_integration
        stdout.puts generate_shell_integration_code
        return 0
      end

      if clear_all
        clear_all_profiles
        stdout.puts "All directory profiles cleared"
        return 0
      end

      options[:path] = argv[0] unless argv.empty?

      io_results = {
        default_guid_output: fetch_default_guid_output,
        bookmarks_output: fetch_bookmarks_output,
        color_presets_output: fetch_color_presets_output,
        directory_path_output: fetch_directory_path_output,
        config_file_content: fetch_config_file_content,
        existing_profiles_content: fetch_existing_profiles_content,
      }

      begin
        new(**options.merge(io_results).merge(stdout: stdout, stderr: stderr)).run
        stdout.puts "Dynamic profile created successfully"
        0
      rescue StandardError => e
        stdout.puts "Error: #{e.message}"
        1
      end
    end

    private

    def fetch_default_guid_output
      Open3.capture3(
        "/usr/libexec/PlistBuddy", "-c", "Print 'Default Bookmark Guid'", ITERM_PREFS_PATH
      )
    end

    def fetch_bookmarks_output
      Open3.capture3(
        "/usr/libexec/PlistBuddy -x -c \"Print 'New Bookmarks'\" #{ITERM_PREFS_PATH} | plutil -convert json -o - -",
      )
    end

    def fetch_color_presets_output
      Open3.capture3("plutil -convert json -o - #{COLOR_PRESETS_PATH}")
    end

    def fetch_directory_path_output
      Dir.pwd
    end

    def fetch_config_file_content
      File.exist?(CONFIG_FILE) ? File.read(CONFIG_FILE) : nil
    end

    def fetch_existing_profiles_content
      File.exist?(DYNAMIC_PROFILES_FILE) ? File.read(DYNAMIC_PROFILES_FILE) : nil
    end
  end

  private

  def select_random_preset(used_presets)
    available_presets = PREFERRED_PRESETS - used_presets
    (available_presets.empty? ? PREFERRED_PRESETS : available_presets).sample
  end

  def read_config
    return {} if @config_file_content.nil?

    JSON.parse(@config_file_content)
  end

  def write_config(config)
    ensure_config_directory_exists!
    File.write(CONFIG_FILE, JSON.pretty_generate(config))
  end

  def write_profile_marker(profile_name)
    marker_file = File.join(@path, PROFILE_MARKER_PATH)
    File.write(marker_file, profile_name)
  end

  def activate_profile(profile_name)
    marker_file = File.join(@path, PROFILE_MARKER_PATH)
    return unless File.exist?(marker_file)

    system("it2profile", "-s", profile_name)
  end

  def ensure_config_directory_exists!
    return if File.directory?(CONFIG_DIR)

    FileUtils.mkdir_p(CONFIG_DIR)
  end

  def generate_minimal_profile
    directory_name = extract_directory_name(@path)
    profile_name = "Directory: #{directory_name}"
    badge_text = directory_name
    guid = generate_stable_guid(directory_name)

    {
      "Name" => profile_name,
      "Guid" => guid,
      "Badge Text" => badge_text,
      "Use Separate Colors for Light and Dark Mode" => false,
      "Rewritable" => true,
    }
  end

  def generate_stable_guid(directory_name)
    hash = Digest::SHA256.hexdigest(directory_name)
    "#{hash[0..7]}-#{hash[8..11]}-#{hash[12..15]}-#{hash[16..19]}-#{hash[20..31]}".upcase
  end

  def extract_directory_name(path)
    File.basename(path)
  end

  def read_default_profile
    default_guid = read_default_guid
    bookmarks = read_bookmarks
    find_bookmark_by_guid(default_guid, bookmarks)
  end

  def read_default_guid
    stdout, _stderr, status = @default_guid_output

    unless status.success?
      raise StandardError, "Unable to read default profile GUID from iTerm2 preferences"
    end

    stdout.strip
  end

  def read_bookmarks
    stdout, _stderr, status = @bookmarks_output

    unless status.success?
      raise StandardError, "Unable to read bookmarks from iTerm2 preferences"
    end

    JSON.parse(stdout)
  end

  def find_bookmark_by_guid(target_guid, bookmarks)
    bookmark = bookmarks.find { |b| b["Guid"] == target_guid }

    unless bookmark
      raise StandardError, "Default profile not found in iTerm2 bookmarks"
    end

    bookmark
  end

  def load_color_preset(preset_name)
    unless File.exist?(COLOR_PRESETS_PATH)
      raise StandardError, "ColorPresets.plist not found at #{COLOR_PRESETS_PATH}"
    end

    stdout, _stderr, status = @color_presets_output

    unless status.success?
      raise StandardError, "Unable to read ColorPresets.plist"
    end

    presets = JSON.parse(stdout)

    unless presets.key?(preset_name)
      raise StandardError, "Color preset '#{preset_name}' not found in ColorPresets.plist"
    end

    presets[preset_name]
  end

  def merge_profiles(base_profile, default_profile, color_preset)
    default_profile.merge(color_preset).merge(base_profile)
  end

  def write_dynamic_profile(profile)
    ensure_directory_exists!

    existing_profiles = read_existing_profiles
    merged_profiles = merge_with_existing_profiles(existing_profiles, profile)

    profiles_data = {
      "Profiles" => merged_profiles,
    }

    File.write(DYNAMIC_PROFILES_FILE, JSON.pretty_generate(profiles_data))
  end

  def read_existing_profiles
    return [] if @existing_profiles_content.nil?

    data = JSON.parse(@existing_profiles_content)
    data["Profiles"] || []
  end

  def merge_with_existing_profiles(existing_profiles, new_profile)
    new_guid = new_profile["Guid"]

    existing_without_duplicate = existing_profiles.reject { |p| p["Guid"] == new_guid }
    existing_without_duplicate + [new_profile]
  end

  def ensure_directory_exists!
    return if File.directory?(DYNAMIC_PROFILES_DIR)

    FileUtils.mkdir_p(DYNAMIC_PROFILES_DIR)
  end

  def check_shell_integration_setup(directory_name)
    profile_name = "Directory: #{directory_name}"

    unless shell_integration_installed?
      @stderr.puts(<<~MESSAGE)

        Note: Profile '#{profile_name}' created successfully!

        To enable automatic profile switching:
          1. Install iTerm2 Shell Integration: iTerm2 > Install Shell Integration
          2. Run: #{File.expand_path(__FILE__)} --generate-shell-integration >> ~/.zshrc
          3. Restart your shell or run: source ~/.zshrc
      MESSAGE
      return
    end

    @stdout.puts("Profile '#{profile_name}' created successfully!")
  end

  def shell_integration_installed?
    system("zsh", "-c", "type iterm_set_directory_profile", out: File::NULL, err: File::NULL)
  end

  def detect_current_directory
    @directory_path_output || Dir.pwd
  end
end

if __FILE__ == $PROGRAM_NAME
  require "optparse"
  exit(ItermDirectoryProfile.run_cli(ARGV))
end
