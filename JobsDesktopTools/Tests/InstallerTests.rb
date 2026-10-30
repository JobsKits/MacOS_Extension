# frozen_string_literal: true
# 使用真实配置发布与临时文件，系统登记和构建由函数替身承接。
require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'json'
require 'digest'

class DesktopInstallerTests < Minitest::Test
  ROOT = File.expand_path('..', __dir__)
  MANAGER = File.join(ROOT, 'Scripts/ManageDesktopTools.zsh')

  def test_first_install_migrates_only_enabled_legacy_leaves
    run_checks(<<~'ZSH')
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      extension_is_enabled() { [[ "$1" == com.jobs.androidsimulatorrepairer.findersync ]]; }
      read_configuration && plan_configuration && publish_configuration || exit 1
      [[ "$(<"$CONFIG_PATH")" == ios-simulator-create,android-simulator-repair ]] || exit 2
      [[ ! -e "$MARKER_PATH" ]] || exit 3
    ZSH
  end

  def test_existing_selection_is_preserved_without_remigrating_closed_leaves
    run_checks(<<~'ZSH')
      print -nr -- hidden-files-toggle > "$CONFIG_PATH"
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      extension_is_enabled() { return 0; }
      read_configuration && plan_configuration && publish_configuration || exit 1
      [[ "$(<"$CONFIG_PATH")" == ios-simulator-create,hidden-files-toggle ]] || exit 2
    ZSH
  end

  def test_failed_retirement_restores_original_configuration
    run_checks(<<~'ZSH')
      print -nr -- hidden-files-toggle > "$CONFIG_PATH"
      /bin/chmod 640 "$CONFIG_PATH"
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      build_and_verify() { return 0; }
      register_and_verify() { return 0; }
      retire_legacy() { return 7; }
      read_configuration && plan_configuration || exit 1
      if install_features; then exit 2; fi
      rollback_transaction
      [[ "$(<"$CONFIG_PATH")" == hidden-files-toggle ]] || exit 3
      [[ "$(/usr/bin/stat -f %Lp "$CONFIG_PATH")" == 640 ]] || exit 4
      [[ ! -e "$MARKER_PATH" ]] || exit 5
    ZSH
  end

  def test_registration_failure_publishes_nothing_and_keeps_legacy_state
    run_checks(<<~'ZSH')
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      build_and_verify() { print -r -- build >> "$TRANSACTION_DIR/calls"; return 0; }
      register_and_verify() { print -r -- register >> "$TRANSACTION_DIR/calls"; return 7; }
      retire_legacy() { print -r -- retire >> "$TRANSACTION_DIR/calls"; return 0; }
      read_configuration && plan_configuration || exit 1
      if install_features; then exit 2; fi
      [[ ! -e "$CONFIG_PATH" && ! -e "$MARKER_PATH" ]] || exit 3
      [[ "$(<"$TRANSACTION_DIR/calls")" == $'build\nregister' ]] || exit 4
    ZSH
  end

  def test_failure_after_migration_marker_publication_restores_both_files
    [false, true].each do |had_marker|
      run_checks(<<~ZSH)
        #{had_marker ? 'print -nr -- previous > "$MARKER_PATH"' : ':'}
        OPERATION=install
        REQUESTED=(ios-simulator-create)
        build_and_verify() { return 0; }
        register_and_verify() { return 0; }
        retire_legacy() { return 0; }
        functions[real_publish_marker]="$functions[publish_marker]"
        publish_marker() { real_publish_marker || return 1; return 7; }
        read_configuration && plan_configuration || exit 1
        if install_features; then exit 2; fi
        [[ "$(<"$MARKER_PATH")" == 1 ]] || exit 3
        rollback_transaction
        [[ ! -e "$CONFIG_PATH" ]] || exit 4
        #{had_marker ? '[[ "$(<"$MARKER_PATH")" == previous ]] || exit 5' : '[[ ! -e "$MARKER_PATH" ]] || exit 5'}
      ZSH
    end
  end

  def test_external_configuration_edit_is_preserved
    run_checks(<<~'ZSH')
      print -nr -- hidden-files-toggle > "$CONFIG_PATH"
      OPERATION=install
      REQUESTED=(ios-simulator-create)
      read_configuration && plan_configuration || exit 1
      print -nr -- harmony-simulator-create > "$CONFIG_PATH"
      if publish_configuration; then exit 2; fi
      [[ "$(<"$CONFIG_PATH")" == harmony-simulator-create ]] || exit 3
    ZSH
  end

  def test_partial_uninstall_keeps_other_leaf_and_last_uninstall_disables_aggregate
    run_checks(<<~'ZSH')
      print -nr -- ios-simulator-create,hidden-files-toggle > "$CONFIG_PATH"
      OPERATION=uninstall
      REQUESTED=(ios-simulator-create)
      disable_aggregate_extension() { print -r -- disable >> "$TRANSACTION_DIR/calls"; }
      retire_legacy() { return 0; }
      read_configuration && plan_configuration && uninstall_features || exit 1
      [[ "$(<"$CONFIG_PATH")" == hidden-files-toggle && ! -e "$TRANSACTION_DIR/calls" ]] || exit 2
      CONFIG_PUBLISHED=0
      REQUESTED=(hidden-files-toggle)
      read_configuration && plan_configuration && uninstall_features || exit 3
      [[ ! -s "$CONFIG_PATH" && "$(<"$TRANSACTION_DIR/calls")" == disable ]] || exit 4
    ZSH
  end

  def test_malformed_configuration_never_becomes_default_all
    ["ios-simulator-create\n", 'unknown', 'ios-simulator-create,', 'ios-simulator-create,,hidden-files-toggle', 'hidden-files-toggle,hidden-files-toggle'].each do |value|
      run_checks('if read_configuration; then exit 1; fi', configuration: value)
    end
  end

  def test_temporary_root_accepts_both_trailing_slash_forms
    ['', '/'].each do |suffix|
      run_checks(<<~ZSH)
        TMPDIR="$1#{suffix}"
        prepare_context install hidden-files-toggle --non-interactive || exit 1
        [[ "$LOG_FILE" == "$1/JobsDesktopToolsInstall.log" ]] || exit 2
        CONFIG_DIR="$1/temporary-config"
        CONFIG_PATH="$CONFIG_DIR/EnabledFeatures.txt"
        MARKER_PATH="$CONFIG_DIR/MigrationVersion.txt"
        LOCK_PATH="$CONFIG_DIR/.manager-lock"
        initialize_runtime
        [[ "$TRANSACTION_DIR" == "$1"/JobsDesktopToolsTransaction.* ]] || exit 3
        TRANSACTION_COMMITTED=1
      ZSH
    end
  end

  def test_bundled_sources_match_manifest_and_canonical_sources
    JSON.parse(File.read(File.join(ROOT, 'SourceManifest.json'))).each do |record|
      target = File.join(ROOT, record.fetch('target'))
      source = File.expand_path(record.fetch('source'), ROOT)
      assert_equal record.fetch('sha256'), Digest::SHA256.file(target).hexdigest, target
      assert_equal File.binread(source), File.binread(target), source
    end
  end

  def test_total_installer_deduplicates_six_leaves_into_one_project
    installer = File.join(ROOT, '../Scripts/ManageFinderExtensions.zsh')
    run_checks(<<~'ZSH', source: installer)
      parse_feature_selection ios-simulator-create,android-simulator-create,harmony-simulator-create,android-simulator-repair,harmony-simulator-repair,hidden-files-toggle,ios-simulator-create || exit 1
      [[ "${(j:,:)SELECTED_KEYS}" == desktop-tools && ${#SELECTED_FUNCTION_IDS} == 6 ]] || exit 2
      [[ "${FEATURE_PROJECT_DIR[desktop-tools]}" == JobsDesktopTools ]] || exit 3
      [[ "${FEATURE_EXTENSION_ID[desktop-tools]}" == com.jobs.desktoptools.findersync ]] || exit 4
    ZSH
  end

  private

  def run_checks(checks, configuration: nil, source: MANAGER)
    Dir.mktmpdir('jobs-desktop-installer-') do |directory|
      source_text = File.read(source).sub(/^main "\$@"\s*\z/, '')
      fixture = File.join(directory, 'fixture.zsh')
      setup = <<~'ZSH'
        setopt NO_NOMATCH PIPE_FAIL
        CONFIG_DIR="$1/config"
        CONFIG_PATH="$CONFIG_DIR/EnabledFeatures.txt"
        MARKER_PATH="$CONFIG_DIR/MigrationVersion.txt"
        TRANSACTION_DIR="$1/transaction"
        LOG_FILE="$1/fixture.log"
        /bin/mkdir -p "$CONFIG_DIR" "$TRANSACTION_DIR"
        extension_is_enabled() { return 1; }
      ZSH
      FileUtils.mkdir_p(File.join(directory, 'config'))
      File.write(File.join(directory, 'config/EnabledFeatures.txt'), configuration) unless configuration.nil?
      File.write(fixture, source_text + "\n" + setup + checks)
      output, status = Open3.capture2e({'NO_COLOR' => '1'}, '/bin/zsh', '-f', fixture, directory)
      assert status.success?, "#{output}\n#{checks}"
    end
  end
end
