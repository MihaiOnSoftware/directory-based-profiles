# typed: false
# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../bin/iterm_directory_profile'

describe ItermDirectoryProfile do
  let(:dynamic_profiles_dir) { File.expand_path('~/Library/Application Support/iTerm2/DynamicProfiles') }
  let(:dynamic_profiles_file) { File.join(dynamic_profiles_dir, 'directories.json') }
  let(:iterm_prefs_path) { File.expand_path('~/Library/Preferences/com.googlecode.iterm2.plist') }

  let(:success_status) do
    mock.tap do |status|
      status.stubs(:success?).returns(true)
    end
  end

  let(:failure_status) do
    mock.tap do |status|
      status.stubs(:success?).returns(false)
    end
  end

  before do
    require 'open3'

    @written_files = {}

    File.stubs(:exist?).returns(false)
    color_presets_path = '/Applications/iTerm.app/Contents/Resources/ColorPresets.plist'
    File.stubs(:exist?).with(color_presets_path).returns(true)

    Open3.stubs(:capture3).raises('Unmocked Open3.capture3 call')
    File.stubs(:read).raises('Unmocked File.read call')
    File.stubs(:write).with do |path, content|
      @written_files[path] = content
      true
    end.returns(100)
    File.stubs(:directory?).raises('Unmocked File.directory? call')
    FileUtils.stubs(:mkdir_p).raises('Unmocked FileUtils.mkdir_p call')
    ItermDirectoryProfile.any_instance.stubs(:system).returns(true)
  end

  describe 'basic profile creation' do
    before do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations
    end

    it 'generates profile with unique guid' do
      create_instance(path: '/tmp/project', existing_profiles_content: nil).run

      guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']
      assert_valid_guid_format(guid)
    end

    it 'writes to correct dynamic profiles location' do
      create_instance(path: '/tmp/project', existing_profiles_content: nil).run

      assert(@written_files.key?(dynamic_profiles_file), "Should write to #{dynamic_profiles_file}")
    end

    it 'writes profile with required fields and correct structure' do
      create_instance(
        path: '/tmp/project',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]

      expected_guid = generate_expected_guid('/tmp/project')
      expected_profile = {
        'Name' => 'Directory: /tmp/project',
        'Guid' => expected_guid,
        'Badge Text' => '/tmp/project',
        'Bound Hosts' => ['/tmp/project/*'],
        'Use Separate Colors for Light and Dark Mode' => false,
        'Rewritable' => true
      }
      assert_profile_structure(profile, expected_profile)
    end

    it 'creates directory if missing' do
      stub_directory_exists(dynamic_profiles_dir, false)

      FileUtils.expects(:mkdir_p).with(dynamic_profiles_dir)

      create_instance(path: '/tmp/project', existing_profiles_content: nil).run
    end

    it 'overwrites existing file' do
      first_write_json = JSON.generate({ 'Profiles' => [{ 'Name' => 'Test', 'Guid' => 'TEST-GUID' }] })

      create_instance(path: '/tmp/project', existing_profiles_content: nil).run
      assert(@written_files.key?(dynamic_profiles_file), 'Should write file on first run')

      create_instance(path: '/tmp/project', existing_profiles_content: first_write_json).run
      assert(@written_files.key?(dynamic_profiles_file), 'Should write file on second run')
    end
  end

  describe 'default profile and bookmark inheritance' do
    before do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations
    end

    it 'reads default profile guid from preferences' do
      create_instance(
        path: '/tmp/project',
        default_guid_output: ["TEST-GUID-1234\n", '', success_status],
        bookmarks_output: [JSON.generate([{ 'Guid' => 'TEST-GUID-1234', 'Name' => 'Default' }]), '', success_status],
        existing_profiles_content: nil
      ).run

      Open3.expects(:capture3).never
    end

    it 'reads bookmark from preferences as json' do
      bookmark_data = {
        'Guid' => 'ABC-123',
        'Name' => 'My Profile',
        'Columns' => 120,
        'Rows' => 40,
        'Background Color' => { 'Red Component' => 0.1 }
      }

      create_instance(
        path: '/tmp/project',
        default_guid_output: ["ABC-123\n", '', success_status],
        bookmarks_output: [JSON.generate([bookmark_data]), '', success_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert(profile['Name'].start_with?('Directory: '), "Profile name should start with 'Directory: '")
      assert_valid_guid_format(profile['Guid'])
      assert_profile_inherits_properties(profile, {
                                           'Columns' => 120,
                                           'Rows' => 40,
                                           'Background Color' => { 'Red Component' => 0.1 }
                                         })
    end

    it 'finds profile by guid when multiple bookmarks exist' do
      bookmarks = [
        { 'Guid' => 'PROFILE-1', 'Name' => 'First', 'Columns' => 80 },
        { 'Guid' => 'PROFILE-2', 'Name' => 'Second', 'Columns' => 120 },
        { 'Guid' => 'PROFILE-3', 'Name' => 'Third', 'Columns' => 160 }
      ]

      create_instance(
        path: '/tmp/project',
        default_guid_output: ["PROFILE-2\n", '', success_status],
        bookmarks_output: [JSON.generate(bookmarks[0..1]), '', success_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_equal 120, profile['Columns']
    end

    it 'merges settings into existing profile preserving name and guid' do
      bookmark_data = {
        'Guid' => 'DEFAULT-123',
        'Name' => 'Default Profile Name',
        'Columns' => 100,
        'Rows' => 30,
        'Font' => 'Monaco',
        'Background Color' => { 'Red Component' => 0.5 }
      }

      create_instance(
        path: '/tmp/project',
        default_guid_output: ["DEFAULT-123\n", '', success_status],
        bookmarks_output: [JSON.generate([bookmark_data]), '', success_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert(profile['Name'].start_with?('Directory: '), "Profile name should start with 'Directory: '")
      assert_valid_guid_format(profile['Guid'])
      assert_profile_has_new_guid_and_name(profile, 'DEFAULT-123')
      assert_profile_properties(profile, {
                                  'Columns' => 100,
                                  'Rows' => 30,
                                  'Font' => 'Monaco',
                                  'Background Color' => { 'Red Component' => 0.5 }
                                })
    end
  end

  describe 'error handling' do
    before do
      setup_basic_directory
    end

    it 'handles missing preferences file' do
      assert_raises_with_message(StandardError, /Unable to read default profile GUID/) do
        create_instance(
          path: '/tmp/project',
          default_guid_output: ['', 'file not found', failure_status]
        ).run
      end
    end

    it 'handles default profile not found in bookmarks' do
      bookmarks = [
        { 'Guid' => 'OTHER-1' },
        { 'Guid' => 'OTHER-2' }
      ]

      assert_raises_with_message(StandardError, /Default profile not found/) do
        create_instance(
          path: '/tmp/project',
          default_guid_output: ["MISSING-GUID\n", '', success_status],
          bookmarks_output: [JSON.generate(bookmarks), '', success_status]
        ).run
      end
    end

    it 'handles bookmark count read failure' do
      assert_raises_with_message(StandardError, /Unable to read bookmarks/) do
        create_instance(
          path: '/tmp/project',
          default_guid_output: ["TEST-GUID\n", '', success_status],
          bookmarks_output: ['', 'error reading', failure_status]
        ).run
      end
    end

    it 'handles bookmark read failure at index' do
      error = assert_raises(StandardError) do
        create_instance(
          path: '/tmp/project',
          git_branch_output: ['', 'fatal: not a git repository', failure_status],
          default_guid_output: ["TEST-GUID\n", '', success_status],
          bookmarks_output: ['invalid json', '', success_status]
        ).run
      end
      assert(error.message.include?('unexpected'))
    end
  end

  describe 'color presets' do
    let(:color_presets_path) { '/Applications/iTerm.app/Contents/Resources/ColorPresets.plist' }

    before do
      stub_config_file_operations
    end

    it 'loads preset from color presets plist' do
      preset_data = {
        'Ansi 0 Color' => { 'Red Component' => 0.0 },
        'Foreground Color' => { 'Blue Component' => 0.5 }
      }

      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      presets_with_data = default_io_results[:color_presets_output][0]
      presets_hash = JSON.parse(presets_with_data)
      presets_hash['Solarized Dark'] = preset_data

      create_instance(
        preset_name: 'Solarized Dark',
        path: '/tmp/project',
        existing_profiles_content: nil,
        color_presets_output: [JSON.generate(presets_hash), '', success_status]
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_color_components(profile, preset_data)
    end

    it 'applies preset colors to profile' do
      default_profile = {
        'Guid' => 'DEFAULT-GUID',
        'Name' => 'Default',
        'Columns' => 120,
        'Font' => 'Monaco'
      }

      preset_colors = {
        'Background Color' => { 'Red Component' => 0.1, 'Green Component' => 0.2 },
        'Foreground Color' => { 'Blue Component' => 0.9 }
      }

      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      presets_with_data = default_io_results[:color_presets_output][0]
      presets_hash = JSON.parse(presets_with_data)
      presets_hash['Tango Dark'] = preset_colors

      create_instance(
        preset_name: 'Tango Dark',
        path: '/tmp/project',
        default_guid_output: ["DEFAULT-GUID\n", '', success_status],
        bookmarks_output: [JSON.generate([default_profile]), '', success_status],
        existing_profiles_content: nil,
        color_presets_output: [JSON.generate(presets_hash), '', success_status]
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_profile_properties(profile, { 'Columns' => 120, 'Font' => 'Monaco' })
      assert_color_components(profile, preset_colors)
    end

    it 'raises error when preset does not exist' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      presets_hash = { 'Solarized Dark' => {}, 'Tango Dark' => {} }

      assert_raises_with_message(StandardError, /Color preset 'NonExistent' not found/) do
        create_instance(
          preset_name: 'NonExistent',
          path: '/tmp/project',
          color_presets_output: [JSON.generate(presets_hash), '', success_status]
        ).run
      end
    end

    it 'raises error when color presets plist not found' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations
      File.expects(:exist?).with(color_presets_path).returns(false)

      assert_raises_with_message(StandardError, /ColorPresets.plist not found/) do
        create_instance(
          preset_name: 'Solarized Dark',
          path: '/tmp/project'
        ).run
      end
    end

    it 'raises error when color presets plist cannot be read' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      assert_raises_with_message(StandardError, /Unable to read ColorPresets.plist/) do
        create_instance(
          preset_name: 'Solarized Dark',
          path: '/tmp/project',
          color_presets_output: ['', 'plutil failed', failure_status]
        ).run
      end
    end

    it 'uses solarized dark by default' do
      preset_data = { 'Background Color' => { 'Red Component' => 0.0 } }

      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      presets_with_data = default_io_results[:color_presets_output][0]
      presets_hash = JSON.parse(presets_with_data)
      presets_hash['Solarized Dark'] = preset_data

      create_instance(
        path: '/tmp/project',
        existing_profiles_content: nil,
        color_presets_output: [JSON.generate(presets_hash), '', success_status]
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_equal({ 'Red Component' => 0.0 }, profile['Background Color'])
    end

    it 'accepts custom preset via cli' do
      preset_data = { 'Background Color' => { 'Red Component' => 1.0 } }

      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      presets_with_data = default_io_results[:color_presets_output][0]
      presets_hash = JSON.parse(presets_with_data)
      presets_hash['Smoooooth'] = preset_data

      create_instance(
        preset_name: 'Smoooooth',
        path: '/tmp/project',
        existing_profiles_content: nil,
        color_presets_output: [JSON.generate(presets_hash), '', success_status]
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_equal({ 'Red Component' => 1.0 }, profile['Background Color'])
    end
  end

  describe 'path argument' do
    before do
      stub_config_file_operations
    end

    it 'accepts path argument and uses it in profile naming and badge text' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      create_instance(
        path: '/Users/test/myworktree',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_valid_directory_profile(profile, '/Users/test/myworktree')
    end

    it 'uses full path when git is not available for both profile name and badge text' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      create_instance(
        path: '/Users/test/myproject/src',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_valid_directory_profile(profile, '/Users/test/myproject/src')
    end
  end

  describe 'stable GUID generation' do
    before do
      stub_config_file_operations
    end

    it 'generates same guid for same worktree name' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      create_instance(
        path: '/Users/test/trees/sameworktree/src',
        existing_profiles_content: nil
      ).run

      first_guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']

      create_instance(
        path: '/Users/test/trees/sameworktree/src',
        existing_profiles_content: nil
      ).run

      second_guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']

      assert_equal(first_guid, second_guid)
    end

    it 'generates different guids for different worktree names' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      create_instance(
        path: '/Users/test/directory1',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      first_guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']

      create_instance(
        path: '/Users/test/directory2',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      second_guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']

      refute_equal(first_guid, second_guid)
    end
  end

  describe 'auto-detect worktree' do
    before do
      stub_config_file_operations
    end

    it 'detects worktree from current directory' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations

      create_instance(
        directory_path_output: '/Users/test/myworktree',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_valid_directory_profile(profile, '/Users/test/myworktree')
    end
  end

  describe 'git branch naming' do
    before do
      stub_config_file_operations
    end

    it 'uses path for profile name and branch name for badge when git is available' do
      stub_directory_exists(dynamic_profiles_dir, true)

      create_instance(
        path: '/Users/test/myproject',
        git_branch_output: ["feature/awesome-feature\n", '', success_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_equal('Directory: /Users/test/myproject', profile['Name'])
      assert_equal('feature/awesome-feature', profile['Badge Text'])
    end

    it 'falls back to directory name when git branch command fails' do
      stub_directory_exists(dynamic_profiles_dir, true)

      create_instance(
        path: '/Users/test/myproject',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        existing_profiles_content: nil
      ).run

      profile = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      assert_equal('Directory: /Users/test/myproject', profile['Name'])
      assert_equal('/Users/test/myproject', profile['Badge Text'])
    end

    it 'generates different GUIDs for different paths even on same branch' do
      stub_directory_exists(dynamic_profiles_dir, true)

      create_instance(
        path: '/Users/test/project1',
        git_branch_output: ["feature-branch\n", '', success_status],
        existing_profiles_content: nil
      ).run

      first_guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']

      create_instance(
        path: '/Users/test/project2',
        git_branch_output: ["feature-branch\n", '', success_status],
        existing_profiles_content: nil
      ).run

      second_guid = JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']

      refute_equal(first_guid, second_guid, 'Different paths should generate different GUIDs even on same branch')
    end
  end

  describe 'preset configuration' do
    let(:config_dir) { File.expand_path('~/.config') }
    let(:config_file) { File.join(config_dir, 'iterm_directory_profile.json') }

    def stub_profile_operations_without_config
      expect_default_guid('DEFAULT-GUID')
      expect_bookmark_count(1)
      expect_bookmark_at_index(0, { 'Guid' => 'DEFAULT-GUID' })
    end

    it 'selects from preferred presets when no saved config and default preset' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      Array.any_instance.stubs(:sample).returns('Smoooooth')

      create_instance(
        path: '/tmp/project',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        config_file_content: nil,
        existing_profiles_content: nil
      ).run

      parsed_config = JSON.parse(@written_files[config_file])
      assert_equal('Smoooooth', parsed_config['/tmp/project'], 'Should save the selected preset')
    end

    it 'uses saved preset when preset_name is nil and config exists' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      config_data = { '/Users/test/testworktree' => 'Tango Dark' }
      ItermDirectoryProfile.any_instance.stubs(:write_config)

      preset_data = { 'Background Color' => { 'Red Component' => 0.5 } }
      presets_with_data = default_io_results[:color_presets_output][0]
      presets_hash = JSON.parse(presets_with_data)
      presets_hash['Tango Dark'] = preset_data

      create_instance(
        preset_name: nil,
        path: '/Users/test/testworktree',
        git_branch_output: ['', 'not a git repo', failure_status],
        config_file_content: JSON.generate(config_data),
        existing_profiles_content: nil,
        color_presets_output: [JSON.generate(presets_hash), '', success_status]
      ).run

      parsed = JSON.parse(@written_files[dynamic_profiles_file])
      profile = parsed['Profiles'][0]
      assert_equal({ 'Red Component' => 0.5 }, profile['Background Color'])
    end

    it 'selects random preset when preset_name is nil and no config exists' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      Array.any_instance.stubs(:sample).returns('Tango Light')

      create_instance(
        preset_name: nil,
        path: '/tmp/randomproject',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        config_file_content: nil,
        existing_profiles_content: nil
      ).run

      parsed_config = JSON.parse(@written_files[config_file])
      assert_equal('Tango Light', parsed_config['/tmp/randomproject'], 'Should save the randomly selected preset')
    end

    it 'uses explicit preset when preset_name is non-nil even if config exists' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      config_data = { 'explicitworktree' => 'Old Preset' }

      written_config = nil
      ItermDirectoryProfile.any_instance.stubs(:write_config).tap do |stub|
        stub.with do |config|
          written_config = JSON.pretty_generate(config)
          true
        end
      end

      preset_data = { 'Background Color' => { 'Red Component' => 1.0 } }
      presets_with_data = default_io_results[:color_presets_output][0]
      presets_hash = JSON.parse(presets_with_data)
      presets_hash['Smoooooth'] = preset_data

      create_instance(
        preset_name: 'Smoooooth',
        path: '/Users/test/explicitworktree',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        config_file_content: JSON.generate(config_data),
        existing_profiles_content: nil,
        color_presets_output: [JSON.generate(presets_hash), '', success_status]
      ).run

      parsed = JSON.parse(@written_files[dynamic_profiles_file])
      profile = parsed['Profiles'][0]
      assert_equal({ 'Red Component' => 1.0 }, profile['Background Color'])

      parsed_config = JSON.parse(written_config)
      assert_equal('Smoooooth', parsed_config['/Users/test/explicitworktree'])
    end

    it 'avoids presets already assigned to other worktrees when selecting randomly' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      existing_config = {
        'worktree1' => 'Solarized Dark',
        'worktree2' => 'Tango Dark'
      }

      Array.any_instance.stubs(:sample).returns('Solarized Light')

      create_instance(
        path: '/tmp/new_worktree',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        config_file_content: JSON.generate(existing_config),
        existing_profiles_content: nil
      ).run

      parsed_config = JSON.parse(@written_files[config_file])
      assigned_preset = parsed_config['/tmp/new_worktree']

      assert_equal('Solarized Light', assigned_preset, 'Should assign an available preset')
    end

    it 'falls back to preferred presets when all six are already assigned' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      existing_config = {
        'worktree1' => 'Solarized Dark',
        'worktree2' => 'Tango Dark',
        'worktree3' => 'Solarized Light',
        'worktree4' => 'Tango Light',
        'worktree5' => 'Pastel (Dark Background)',
        'worktree6' => 'Smoooooth'
      }

      Array.any_instance.stubs(:sample).returns('Solarized Dark')

      create_instance(
        path: '/tmp/new_worktree',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        config_file_content: JSON.generate(existing_config),
        existing_profiles_content: nil
      ).run

      parsed_config = JSON.parse(@written_files[config_file])
      assigned_preset = parsed_config['/tmp/new_worktree']

      assert_equal('Solarized Dark', assigned_preset, 'Should fall back to a preferred preset')
    end

    it 'loads config when it exists' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      config_data = { 'worktree1' => 'Tango Dark' }
      ItermDirectoryProfile.any_instance.stubs(:write_config)

      create_instance(
        path: '/Users/test/trees/worktree1/src',
        config_file_content: JSON.generate(config_data),
        existing_profiles_content: nil
      ).run
    end

    it 'saves config after successful run' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      written_config = nil
      ItermDirectoryProfile.any_instance.stubs(:write_config).tap do |stub|
        stub.with do |config|
          written_config = JSON.pretty_generate(config)
          true
        end
      end

      create_instance(
        path: '/Users/test/worktree2',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        preset_name: 'Tango Dark',
        config_file_content: nil,
        existing_profiles_content: nil
      ).run

      parsed_config = JSON.parse(written_config)
      assert_equal('Tango Dark', parsed_config['/Users/test/worktree2'])
    end

    it 'creates config directory if missing' do
      stub_directory_exists(dynamic_profiles_dir, true)

      File.expects(:directory?).with(config_dir).returns(false)
      FileUtils.expects(:mkdir_p).with(config_dir)

      Array.any_instance.stubs(:sample).returns('Solarized Dark')

      create_instance(
        path: '/Users/test/trees/worktree3/src',
        config_file_content: nil,
        existing_profiles_content: nil
      ).run
    end

    it 'updates preset in config when different preset provided' do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_directory_exists(config_dir, true)

      config_data = { 'worktree5' => 'Old Preset' }

      written_config = nil
      ItermDirectoryProfile.any_instance.stubs(:write_config).tap do |stub|
        stub.with do |config|
          written_config = JSON.pretty_generate(config)
          true
        end
      end

      create_instance(
        path: '/Users/test/worktree5',
        git_branch_output: ['', 'fatal: not a git repository', failure_status],
        preset_name: 'New Preset',
        config_file_content: JSON.generate(config_data),
        existing_profiles_content: nil
      ).run

      parsed_config = JSON.parse(written_config)
      assert_equal('New Preset', parsed_config['/Users/test/worktree5'])
    end
  end

  describe 'delete profile' do
    before do
      stub_directory_exists(dynamic_profiles_dir, true)
      stub_config_file_operations
    end

    it 'uses same guid generation logic as profile creation' do
      create_instance(path: '/tmp/test-project', existing_profiles_content: nil).run

      ItermDirectoryProfile.delete_profile(
        path: '/tmp/test-project',
        existing_profiles_content: @written_files[dynamic_profiles_file]
      )

      remaining_profiles = JSON.parse(@written_files[dynamic_profiles_file])
      assert_equal([], remaining_profiles['Profiles'])
    end

    it 'removes profile from directories.json by path' do
      guid_to_delete = generate_expected_guid('/tmp/project1')
      guid_to_keep = generate_expected_guid('/tmp/project2')

      existing_content = JSON.generate({
                                         'Profiles' => [
                                           {
                                             'Name' => 'Directory: /tmp/project1',
                                             'Guid' => guid_to_delete,
                                             'Badge Text' => '/tmp/project1',
                                             'Bound Hosts' => ['/tmp/project1/*']
                                           },
                                           {
                                             'Name' => 'Directory: /tmp/project2',
                                             'Guid' => guid_to_keep,
                                             'Badge Text' => '/tmp/project2',
                                             'Bound Hosts' => ['/tmp/project2/*']
                                           }
                                         ]
                                       })

      ItermDirectoryProfile.delete_profile(
        path: '/tmp/project1',
        existing_profiles_content: existing_content
      )

      expected_structure = {
        'Profiles' => [
          {
            'Name' => 'Directory: /tmp/project2',
            'Guid' => guid_to_keep,
            'Badge Text' => '/tmp/project2',
            'Bound Hosts' => ['/tmp/project2/*']
          }
        ]
      }

      assert_equal(expected_structure, JSON.parse(@written_files[dynamic_profiles_file]))
    end

    it 'removes path entry from config when config exists' do
      existing_config_content = JSON.generate({
                                                '/tmp/project1' => 'Solarized Dark',
                                                '/tmp/project2' => 'Tango Dark'
                                              })

      ItermDirectoryProfile.delete_profile(
        path: '/tmp/project1',
        existing_profiles_content: nil,
        config_file_content: existing_config_content
      )

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      expected_config = { '/tmp/project2' => 'Tango Dark' }

      assert_equal(expected_config, JSON.parse(@written_files[config_file]))
    end

    it "succeeds when files don't exist" do
      ItermDirectoryProfile.delete_profile(
        path: '/tmp/project1',
        existing_profiles_content: nil,
        config_file_content: nil
      )

      assert_equal({}, @written_files)
    end
  end

  describe 'fetch_iterm_profile_name' do
    it 'reads ITERM_PROFILE environment variable when set' do
      ENV.stubs(:[]).with('ITERM_PROFILE').returns('Directory: /test/project')

      result = ItermDirectoryProfile.fetch_iterm_profile_name

      assert_equal('Directory: /test/project', result)
    end
  end

  describe 'CLI' do
    before do
      stub_config_file_operations
    end

    it 'handles errors gracefully' do
      stub_directory_exists(dynamic_profiles_dir, true)

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      File.stubs(:exist?).with(config_file).returns(false)
      File.stubs(:exist?).with(dynamic_profiles_file).returns(false)

      require 'open3'
      failure_status = mock.tap { |status| status.stubs(:success?).returns(false) }
      Open3.stubs(:capture3).returns(['', 'PlistBuddy error', failure_status])

      output = StringIO.new
      exit_code = ItermDirectoryProfile.run_cli([], stdout: output)

      assert_cli_error(exit_code, output)
    end

    it 'handles help flag' do
      output = StringIO.new
      exit_code = ItermDirectoryProfile.run_cli(['--help'], stdout: output)

      assert_cli_help(exit_code, output)
    end

    it 'handles --preset option' do
      stub_directory_exists(dynamic_profiles_dir, true)
      ItermDirectoryProfile.any_instance.unstub(:write_config)

      config_dir = File.expand_path('~/.config')
      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      stub_directory_exists(config_dir, true)
      File.stubs(:exist?).with(config_file).returns(false)
      File.stubs(:exist?).with(dynamic_profiles_file).returns(false)

      all_presets = {
        'Solarized Dark' => {},
        'Tango Dark' => {},
        'Tango Light' => {}
      }

      require 'open3'
      Open3.stubs(:capture3).with('/usr/libexec/PlistBuddy', '-c', "Print 'Default Bookmark Guid'",
                                  anything).returns(["DEFAULT-GUID\n", '', success_status])
      Open3.stubs(:capture3).with("plutil -convert json -o - #{ItermDirectoryProfile::COLOR_PRESETS_PATH}").returns([
                                                                                                                      JSON.generate(all_presets), '', success_status
                                                                                                                    ])
      Open3.stubs(:capture3).with("/usr/libexec/PlistBuddy -x -c \"Print 'New Bookmarks'\" #{ItermDirectoryProfile::ITERM_PREFS_PATH} | plutil -convert json -o - -").returns([
                                                                                                                                                                                JSON.generate([{ 'Guid' => 'DEFAULT-GUID' }]), '', success_status
                                                                                                                                                                              ])
      Open3.stubs(:capture3).with('git', 'rev-parse', '--abbrev-ref',
                                  'HEAD').returns(['', 'fatal: not a git repository', failure_status])

      output = StringIO.new
      exit_code = ItermDirectoryProfile.run_cli(['--preset', 'Tango Dark', '/tmp/test-path'], stdout: output)

      assert_equal(0, exit_code)
      assert_match(/Profile.*created successfully/, output.string)

      JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]
      saved_config = @written_files[config_file]
      assert(saved_config, 'Config file should be written')
      assert_equal('Tango Dark', JSON.parse(saved_config)['/tmp/test-path'])
    end

    it 'handles --clear-all flag' do
      output = StringIO.new

      File.expects(:exist?).with(dynamic_profiles_file).returns(true)
      File.expects(:delete).with(dynamic_profiles_file)

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      File.expects(:exist?).with(config_file).returns(true)
      File.expects(:delete).with(config_file)

      exit_code = ItermDirectoryProfile.run_cli(['--clear-all'], stdout: output)

      assert_equal(0, exit_code, 'CLI should exit successfully')
      assert_match(/All directory profiles cleared/, output.string)
    end

    it "handles --clear-all when files don't exist" do
      output = StringIO.new

      File.expects(:exist?).with(dynamic_profiles_file).returns(false)
      File.expects(:delete).with(dynamic_profiles_file).never

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      File.expects(:exist?).with(config_file).returns(false)
      File.expects(:delete).with(config_file).never

      exit_code = ItermDirectoryProfile.run_cli(['--clear-all'], stdout: output)

      assert_equal(0, exit_code, 'CLI should exit successfully')
      assert_match(/All directory profiles cleared/, output.string)
    end

    it 'handles -d flag with path argument' do
      guid_to_delete = generate_expected_guid('/tmp/test-project')

      existing_profiles = JSON.generate({
                                          'Profiles' => [
                                            {
                                              'Name' => 'Directory: /tmp/test-project',
                                              'Guid' => guid_to_delete,
                                              'Badge Text' => '/tmp/test-project',
                                              'Bound Hosts' => ['/tmp/test-project/*']
                                            }
                                          ]
                                        })

      existing_config = JSON.generate({
                                        '/tmp/test-project' => 'Solarized Dark'
                                      })

      File.stubs(:exist?).with(dynamic_profiles_file).returns(true)
      File.stubs(:read).with(dynamic_profiles_file).returns(existing_profiles)

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      File.stubs(:exist?).with(config_file).returns(true)
      File.stubs(:read).with(config_file).returns(existing_config)

      output = StringIO.new
      exit_code = ItermDirectoryProfile.run_cli(['-d', '/tmp/test-project'], stdout: output)

      assert_equal(0, exit_code, 'CLI should exit successfully')
      assert_match(/deleted/, output.string)

      assert(@written_files.key?(dynamic_profiles_file), 'Should write updated profiles')
      remaining_profiles = JSON.parse(@written_files[dynamic_profiles_file])
      assert_equal([], remaining_profiles['Profiles'], 'Profile should be removed')

      assert(@written_files.key?(config_file), 'Should write updated config')
      remaining_config = JSON.parse(@written_files[config_file])
      refute(remaining_config.key?('/tmp/test-project'), 'Config entry should be removed')
    end

    it 'prints warning when deleting non-existent profile' do
      File.stubs(:exist?).with(dynamic_profiles_file).returns(false)

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      File.stubs(:exist?).with(config_file).returns(false)

      output = StringIO.new
      exit_code = ItermDirectoryProfile.run_cli(['-d', '/tmp/non-existent'], stdout: output)

      assert_equal(0, exit_code, 'CLI should exit successfully')
      assert_match(/No profile found/, output.string)
    end

    it 'uses current directory path when -d has no argument' do
      test_dir = '/test/current/dir'
      Dir.stubs(:pwd).returns(test_dir)

      guid_to_delete = generate_expected_guid(test_dir)

      existing_profiles = JSON.generate({
                                          'Profiles' => [
                                            {
                                              'Name' => "Directory: #{test_dir}",
                                              'Guid' => guid_to_delete,
                                              'Badge Text' => test_dir,
                                              'Bound Hosts' => ["#{test_dir}/*"]
                                            }
                                          ]
                                        })

      existing_config = JSON.generate({
                                        test_dir => 'Solarized Dark'
                                      })

      File.stubs(:exist?).with(dynamic_profiles_file).returns(true)
      File.stubs(:read).with(dynamic_profiles_file).returns(existing_profiles)

      config_file = File.expand_path('~/.config/iterm_directory_profile.json')
      File.stubs(:exist?).with(config_file).returns(true)
      File.stubs(:read).with(config_file).returns(existing_config)

      output = StringIO.new
      ItermDirectoryProfile.run_cli(['-d'], stdout: output)

      assert(@written_files.key?(dynamic_profiles_file), 'Should write updated profiles')
      remaining_profiles = JSON.parse(@written_files[dynamic_profiles_file])
      assert_equal([], remaining_profiles['Profiles'], 'Profile should be removed from current directory')

      assert(@written_files.key?(config_file), 'Should write updated config')
      remaining_config = JSON.parse(@written_files[config_file])
      refute(remaining_config.key?(test_dir), 'Config entry should be removed for current directory')
    end
  end

  private

  def setup_basic_directory
    stub_directory_exists(dynamic_profiles_dir, true)
  end

  def setup_basic_environment
    setup_basic_directory
    stub_default_profile
  end

  def setup_basic_environment_multiple_times(times)
    stub_directory_exists(dynamic_profiles_dir, true)
    stub_default_profile_multiple_times(times)
  end

  def run_and_get_guid(path)
    setup_basic_environment
    create_instance(path: path).run
    JSON.parse(@written_files[dynamic_profiles_file])['Profiles'][0]['Guid']
  end

  def stub_config_file_operations
    ItermDirectoryProfile.any_instance.stubs(:read_config).returns({})
    ItermDirectoryProfile.any_instance.stubs(:write_config)
    Array.any_instance.stubs(:sample).returns('Solarized Dark')
  end

  def stub_git_worktree_detection_success(path = '/tmp/project')
    require 'open3'

    success_status = mock.tap { |status| status.stubs(:success?).returns(true) }

    Open3.stubs(:capture3)
         .with('git', 'rev-parse', '--show-toplevel')
         .returns([path, '', success_status])
  end

  def assert_color_components(profile, expected_colors)
    expected_colors.each do |color_key, expected_value|
      assert_equal(expected_value, profile[color_key], "Expected #{color_key} to match")
    end
  end

  def assert_profile_properties(profile, expected_properties)
    expected_properties.each do |key, expected_value|
      assert_equal(expected_value, profile[key], "Expected #{key} to match")
    end
  end

  def assert_profile_structure(profile, expected_profile)
    assert_equal(expected_profile, profile)
  end

  def assert_profile_inherits_properties(profile, expected_properties)
    assert_profile_properties(profile, expected_properties)
  end

  def assert_profile_has_new_guid_and_name(profile, original_guid)
    refute_equal(original_guid, profile['Guid'])
  end

  def assert_raises_with_message(exception_class, message_pattern, &block)
    error = assert_raises(exception_class, &block)
    assert_match(message_pattern, error.message)
  end

  def stub_directory_exists(path, exists)
    File.stubs(:directory?).with(path).returns(exists)
  end

  def expect_default_guid(guid)
    require 'open3'
    iterm_prefs_path = File.expand_path('~/Library/Preferences/com.googlecode.iterm2.plist')

    guid_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <string>#{guid}</string>
      </plist>
    XML

    success_status = mock.tap { |status| status.stubs(:success?).returns(true) }

    Open3.expects(:capture3)
         .with('/usr/libexec/PlistBuddy', '-c', "Print 'Default Bookmark Guid'", iterm_prefs_path)
         .returns([guid_xml, '', success_status])
  end

  def expect_bookmark_count(count)
    iterm_prefs_path = File.expand_path('~/Library/Preferences/com.googlecode.iterm2.plist')
    count_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <integer>#{count}</integer>
      </plist>
    XML

    success_status = mock.tap { |status| status.stubs(:success?).returns(true) }

    Open3.expects(:capture3)
         .with('/usr/libexec/PlistBuddy', '-c', "Print 'New Bookmarks'", iterm_prefs_path)
         .returns([count_xml, '', success_status])
  end

  def expect_bookmark_at_index(index, bookmark_data)
    require 'json'
    require 'open3'
    iterm_prefs_path = File.expand_path('~/Library/Preferences/com.googlecode.iterm2.plist')

    bookmark_json = JSON.generate(bookmark_data)

    success_status = mock.tap { |status| status.stubs(:success?).returns(true) }

    Open3.expects(:capture3)
         .with("/usr/libexec/PlistBuddy -x -c \"Print 'New Bookmarks:#{index}'\" #{iterm_prefs_path} | plutil -convert json -o - -")
         .returns([bookmark_json, '', success_status])
  end

  def expect_color_preset(preset_name, preset_data)
    require 'json'
    require 'open3'

    color_presets_path = '/Applications/iTerm.app/Contents/Resources/ColorPresets.plist'
    File.expects(:exist?).with(color_presets_path).returns(true)

    plist_data = {
      preset_name => preset_data
    }

    success_status = mock.tap { |status| status.stubs(:success?).returns(true) }

    Open3.expects(:capture3)
         .with("plutil -convert json -o - #{color_presets_path}")
         .returns([JSON.generate(plist_data), '', success_status])
  end

  def assert_valid_directory_profile(profile_data, directory_name)
    assert_valid_guid_format(profile_data['Guid'])
    assert(profile_data['Name'].include?(directory_name),
           "Profile name should include directory name '#{directory_name}'")
    assert_equal(directory_name, profile_data['Badge Text'])
  end

  def assert_cli_success(exit_code, output)
    assert_equal(0, exit_code, 'CLI should exit successfully')
    assert(output.string.include?('successfully'), 'CLI should output success message')
  end

  def assert_cli_error(exit_code, output)
    assert_equal(1, exit_code, 'CLI should exit with error code 1')
    assert(output.string.include?('Error'), 'CLI should output error message')
  end

  def assert_cli_help(exit_code, output)
    assert_equal(0, exit_code, 'CLI should exit successfully')
    assert(output.string.include?('Usage'), 'CLI should display usage information')
  end

  def assert_valid_guid_format(guid)
    assert_match(/\A[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\z/, guid,
                 'GUID should match UUID format')
  end

  def generate_expected_guid(worktree_name)
    require 'digest'
    hash = Digest::SHA256.hexdigest(worktree_name)
    "#{hash[0..7]}-#{hash[8..11]}-#{hash[12..15]}-#{hash[16..19]}-#{hash[20..31]}".upcase
  end

  def default_io_results
    all_presets = {
      'Solarized Dark' => {},
      'Tango Dark' => {},
      'Solarized Light' => {},
      'Tango Light' => {},
      'Pastel (Dark Background)' => {},
      'Smoooooth' => {},
      'New Preset' => {}
    }
    {
      default_guid_output: ["DEFAULT-GUID\n", '', success_status],
      bookmarks_output: [JSON.generate([{ 'Guid' => 'DEFAULT-GUID' }]), '', success_status],
      color_presets_output: [JSON.generate(all_presets), '', success_status],
      directory_path_output: '/tmp/test_directory',
      git_branch_output: ["main\n", '', success_status],
      config_file_content: '{}',
      existing_profiles_content: nil
    }
  end

  def create_instance(**overrides)
    ItermDirectoryProfile.new(**default_io_results.merge(overrides))
  end

  def stub_default_profile
    stub_config_file_operations
    stub_git_worktree_detection_success
    expect_default_guid('DEFAULT-GUID')
    expect_bookmark_count(1)
    expect_bookmark_at_index(0, { 'Guid' => 'DEFAULT-GUID' })
    expect_color_preset('Solarized Dark', {})
  end

  def stub_default_profile_for_presets
    stub_git_worktree_detection_success
    expect_default_guid('DEFAULT-GUID')
    expect_bookmark_count(1)
    expect_bookmark_at_index(0, { 'Guid' => 'DEFAULT-GUID' })
  end

  def stub_default_profile_multiple_times(times)
    require 'open3'

    stub_config_file_operations

    guid = 'DEFAULT-GUID'

    success_status_git = mock.tap { |status| status.stubs(:success?).returns(true) }
    Open3.stubs(:capture3)
         .with('git', 'rev-parse', '--show-toplevel')
         .returns(['/tmp/test_worktree', '', success_status_git])
         .times(times)
    guid_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <string>#{guid}</string>
      </plist>
    XML

    count_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <integer>1</integer>
      </plist>
    XML

    bookmark_json = JSON.generate({ 'Guid' => guid })

    Open3.stubs(:capture3)
         .with('/usr/libexec/PlistBuddy', '-c', "Print 'Default Bookmark Guid'", iterm_prefs_path)
         .returns([guid_xml, '', success_status])
         .times(times)

    Open3.stubs(:capture3)
         .with('/usr/libexec/PlistBuddy', '-c', "Print 'New Bookmarks'", iterm_prefs_path)
         .returns([count_xml, '', success_status])
         .times(times)

    Open3.stubs(:capture3)
         .with("/usr/libexec/PlistBuddy -x -c \"Print 'New Bookmarks:0'\" #{iterm_prefs_path} | plutil -convert json -o - -")
         .returns([bookmark_json, '', success_status])
         .times(times)

    color_presets_path = '/Applications/iTerm.app/Contents/Resources/ColorPresets.plist'
    File.stubs(:exist?).with(color_presets_path).returns(true)
    Open3.stubs(:capture3)
         .with("plutil -convert json -o - #{color_presets_path}")
         .returns([JSON.generate({ 'Solarized Dark' => {} }), '', success_status])
         .times(times)
  end
end
