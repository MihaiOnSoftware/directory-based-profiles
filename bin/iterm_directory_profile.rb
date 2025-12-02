#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'open3'
require 'digest'

class ItermDirectoryProfile
  PREFERRED_PRESETS = [
    'Solarized Dark',
    'Tango Dark',
    'Solarized Light',
    'Tango Light',
    'Pastel (Dark Background)',
    'Smoooooth'
  ].freeze

  ITERM_PREFS_PATH = File.expand_path('~/Library/Preferences/com.googlecode.iterm2.plist')
  COLOR_PRESETS_PATH = '/Applications/iTerm.app/Contents/Resources/ColorPresets.plist'
  CONFIG_DIR = File.expand_path('~/.config')
  CONFIG_FILE = File.join(CONFIG_DIR, 'iterm_directory_profile.json')
  DYNAMIC_PROFILES_DIR = File.expand_path('~/Library/Application Support/iTerm2/DynamicProfiles')
  DYNAMIC_PROFILES_FILE = File.join(DYNAMIC_PROFILES_DIR, 'directories.json')

  def initialize(
    default_guid_output:, bookmarks_output:, color_presets_output:, directory_path_output:, config_file_content:, existing_profiles_content:,
    path: nil,
    stdout: $stdout,
    stderr: $stderr
  )
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

  def run(preset_name: nil, git_branch_output: nil)
    display_name = get_display_name(git_branch_output)
    config = read_config

    config_preset = config[@path]
    preset = if config_preset && preset_name.nil?
               config_preset
             elsif !config_preset && preset_name.nil?
               select_random_preset(config.values)
             else
               preset_name
             end

    profile = generate_minimal_profile(display_name)
    default_profile = read_default_profile
    color_preset = load_color_preset(preset)
    merged_profile = merge_profiles(profile, default_profile, color_preset)
    write_dynamic_profile(merged_profile)

    config[@path] = preset
    write_config(config)

    @stdout.puts "Profile '#{profile['Name']}' created successfully!"
  end

  class << self
    def fetch_iterm_profile_name
      stdout, _stderr, status = Open3.capture3('it2profile', '-g')

      return stdout.strip if status.success?

      nil
    end

    def find_profile_path_by_name(profile_name:, existing_profiles_content:)
      profiles = parse_profiles_content(existing_profiles_content)
      profile = profiles.find { |p| p['Name'] == profile_name }
      return nil unless profile

      profile['Name'].sub('Directory: ', '')
    end

    def delete_profile(path:, existing_profiles_content:, config_file_content: nil)
      found = false

      if existing_profiles_content
        guid_to_delete = generate_stable_guid(path)
        existing_profiles = parse_profiles_content(existing_profiles_content)
        remaining_profiles = existing_profiles.reject { |p| p['Guid'] == guid_to_delete }

        found = existing_profiles.size != remaining_profiles.size

        profiles_data = { 'Profiles' => remaining_profiles }
        File.write(DYNAMIC_PROFILES_FILE, JSON.pretty_generate(profiles_data))
      end

      return found unless config_file_content

      config = JSON.parse(config_file_content)
      found ||= config.key?(path)
      config.delete(path)
      File.write(CONFIG_FILE, JSON.pretty_generate(config))

      found
    end

    def parse_profiles_content(content)
      return [] if content.nil?

      data = JSON.parse(content)
      data['Profiles'] || []
    end

    def generate_stable_guid(directory_name)
      hash = Digest::SHA256.hexdigest(directory_name)
      "#{hash[0..7]}-#{hash[8..11]}-#{hash[12..15]}-#{hash[16..19]}-#{hash[20..31]}".upcase
    end

    def clear_all_profiles
      File.delete(DYNAMIC_PROFILES_FILE) if File.exist?(DYNAMIC_PROFILES_FILE)
      File.delete(CONFIG_FILE) if File.exist?(CONFIG_FILE)
    end

    def run_cli(argv, stdout: $stdout, stderr: $stderr)
      options = {}
      preset_name = nil
      clear_all = false
      delete_path = nil

      OptionParser.new do |opts|
        opts.banner = 'Usage: iterm_directory_profile.rb [options] [path]'

        opts.on('-p', '--preset PRESET_NAME',
                'Color preset to use (default: saved config or random selection)') do |preset|
          preset_name = preset
        end

        opts.on('-d', '--delete [PATH]', 'Delete profile for specified path') do |path|
          if path
            delete_path = path
          else
            profile_name = fetch_iterm_profile_name
            if profile_name&.start_with?('Directory: ')
              existing_profiles_content = fetch_existing_profiles_content
              delete_path = find_profile_path_by_name(
                profile_name: profile_name,
                existing_profiles_content: existing_profiles_content
              )
            end
            delete_path ||= Dir.pwd
          end
        end

        opts.on('-c', '--clear-all', 'Clear all directory profiles') do
          clear_all = true
        end

        opts.on('-h', '--help', 'Show this help message') do
          stdout.puts opts
          return 0
        end
      end.parse!(argv)

      if delete_path
        existing_profiles_content = fetch_existing_profiles_content
        config_file_content = fetch_config_file_content
        found = delete_profile(
          path: delete_path,
          existing_profiles_content: existing_profiles_content,
          config_file_content: config_file_content
        )

        if found
          stdout.puts "Profile for '#{delete_path}' deleted successfully"
        else
          stdout.puts "No profile found for '#{delete_path}'"
        end

        return 0
      end

      if clear_all
        clear_all_profiles
        stdout.puts 'All directory profiles cleared'
        return 0
      end

      options[:path] = argv[0] unless argv.empty?

      io_results = {
        default_guid_output: fetch_default_guid_output,
        bookmarks_output: fetch_bookmarks_output,
        color_presets_output: fetch_color_presets_output,
        directory_path_output: fetch_directory_path_output,
        config_file_content: fetch_config_file_content,
        existing_profiles_content: fetch_existing_profiles_content
      }

      git_branch_output = fetch_git_branch_output

      begin
        new(**options.merge(io_results).merge(stdout: stdout, stderr: stderr)).run(preset_name: preset_name,
                                                                                   git_branch_output: git_branch_output)
        stdout.puts 'Dynamic profile created successfully'
        0
      rescue StandardError => e
        stdout.puts "Error: #{e.message}"
        1
      end
    end

    private

    def fetch_default_guid_output
      Open3.capture3(
        '/usr/libexec/PlistBuddy', '-c', "Print 'Default Bookmark Guid'", ITERM_PREFS_PATH
      )
    end

    def fetch_bookmarks_output
      Open3.capture3(
        "/usr/libexec/PlistBuddy -x -c \"Print 'New Bookmarks'\" #{ITERM_PREFS_PATH} | plutil -convert json -o - -"
      )
    end

    def fetch_color_presets_output
      Open3.capture3("plutil -convert json -o - #{COLOR_PRESETS_PATH}")
    end

    def fetch_directory_path_output
      Dir.pwd
    end

    def fetch_git_branch_output
      Open3.capture3('git', 'rev-parse', '--abbrev-ref', 'HEAD')
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

  def ensure_config_directory_exists!
    return if File.directory?(CONFIG_DIR)

    FileUtils.mkdir_p(CONFIG_DIR)
  end

  def generate_minimal_profile(display_name)
    profile_name = "Directory: #{@path}"
    badge_text = display_name
    guid = generate_stable_guid(@path)

    {
      'Name' => profile_name,
      'Guid' => guid,
      'Badge Text' => badge_text,
      'Bound Hosts' => ["#{@path}/*"],
      'Use Separate Colors for Light and Dark Mode' => false,
      'Rewritable' => true
    }
  end

  def generate_stable_guid(directory_name)
    self.class.generate_stable_guid(directory_name)
  end

  def get_display_name(git_branch_output)
    return @path if git_branch_output.nil?

    stdout, _stderr, status = git_branch_output

    if status.success? && !stdout.strip.empty?
      stdout.strip
    else
      @path
    end
  end

  def read_default_profile
    default_guid = read_default_guid
    bookmarks = read_bookmarks
    find_bookmark_by_guid(default_guid, bookmarks)
  end

  def read_default_guid
    stdout, _stderr, status = @default_guid_output

    raise StandardError, 'Unable to read default profile GUID from iTerm2 preferences' unless status.success?

    stdout.strip
  end

  def read_bookmarks
    stdout, _stderr, status = @bookmarks_output

    raise StandardError, 'Unable to read bookmarks from iTerm2 preferences' unless status.success?

    JSON.parse(stdout)
  end

  def find_bookmark_by_guid(target_guid, bookmarks)
    bookmark = bookmarks.find { |b| b['Guid'] == target_guid }

    raise StandardError, 'Default profile not found in iTerm2 bookmarks' unless bookmark

    bookmark
  end

  def load_color_preset(preset_name)
    raise StandardError, "ColorPresets.plist not found at #{COLOR_PRESETS_PATH}" unless File.exist?(COLOR_PRESETS_PATH)

    stdout, _stderr, status = @color_presets_output

    raise StandardError, 'Unable to read ColorPresets.plist' unless status.success?

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
      'Profiles' => merged_profiles
    }

    File.write(DYNAMIC_PROFILES_FILE, JSON.pretty_generate(profiles_data))
  end

  def read_existing_profiles
    self.class.parse_profiles_content(@existing_profiles_content)
  end

  def merge_with_existing_profiles(existing_profiles, new_profile)
    new_guid = new_profile['Guid']

    existing_without_duplicate = existing_profiles.reject { |p| p['Guid'] == new_guid }
    existing_without_duplicate + [new_profile]
  end

  def ensure_directory_exists!
    return if File.directory?(DYNAMIC_PROFILES_DIR)

    FileUtils.mkdir_p(DYNAMIC_PROFILES_DIR)
  end

  def detect_current_directory
    @directory_path_output || Dir.pwd
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'optparse'
  exit(ItermDirectoryProfile.run_cli(ARGV))
end
