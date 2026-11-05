# frozen_string_literal: true
# Jobs：仅使用临时 App 夹具，系统签名与登记全部由函数替身承接。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

class AppDeploymentTests < Minitest::Test
  LIBRARY = File.expand_path('../../Scripts/【MacOS】AppDeployment.zsh/【MacOS】AppDeployment.zsh', __dir__)
  APP_ID = 'com.jobs.fixture'
  EXTENSION = 'JobsFixtureFinder.appex'
  EXTENSION_ID = 'com.jobs.fixture.findersync'

  def setup
    @temporary = Dir.mktmpdir('Jobs App部署 ')
    @root = File.realpath(@temporary)
    @applications = File.join(@root, '应用 程序')
    @derived = File.join(@root, '编译 产物', 'work', 'JobsFixtureDerivedData')
    @built = File.join(@derived, 'Build/Products/Debug/JobsFixture.app')
    @container = File.join(@applications, 'Jobs自定义右键菜单.app')
    @deployed = File.join(@container, 'Contents/Applications/JobsFixture.app')
    FileUtils.mkdir_p(@applications)
    make_container
    make_app(@built, 'new')
  end

  def teardown
    FileUtils.remove_entry(@temporary) if File.exist?(@temporary)
  end

  def test_default_build_mode_and_install_uninstall_are_unchanged
    shell(<<~'ZSH')
      unset JOBS_FINDER_INSTALL_LOCATION
      [[ "$(jobs_deployment_app_path "$BUILT")" == "$BUILT" ]] || exit 1
      jobs_deployment_install "$TEST_ROOT/missing/JobsFixture.app" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_uninstall "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      jobs_deployment_commit && jobs_deployment_rollback || exit 4
      [[ -d "$BUILT" && ! -e "$CALLS" ]] || exit 5
    ZSH
  end

  def test_complete_app_is_copied_and_commit_releases_backup_and_lock
    shell(<<~'ZSH')
      [[ "$(jobs_deployment_app_path "$BUILT")" == "$DEPLOYED" ]] || exit 1
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ -d "$DEPLOYED/Contents/PlugIns/$EXTENSION" && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 3
      jobs_deployment_commit || exit 4
      [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 5
    ZSH
    assert_equal 'new', File.read(resource(@deployed))
    assert_equal File.binread(resource(@built)), File.binread(resource(@deployed))
    assert File.directory?(@derived), '默认不请求清理时必须保留构建产物'
    assert_empty Dir.glob(File.join(@applications, '.JobsFinderDeployment.*'))
  end

  def test_deployed_bundle_keeps_resources_after_source_is_removed
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    FileUtils.remove_entry(@derived)
    assert_equal 'new', File.read(resource(@deployed))
    assert File.executable?(File.join(@deployed, 'Contents/PlugIns', EXTENSION, 'Contents/MacOS/FixtureExtension'))
    deployed_host = File.join(@deployed, 'Contents/MacOS/FixtureHost')
    output, error, result = Open3.capture3([deployed_host, deployed_host])
    assert result.success?, "部署宿主执行失败：#{error}"
    assert_equal 'new', output
  end

  def test_owned_app_is_replaced_then_rollback_restores_original_file_and_active_build
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == new ]] || exit 2
      jobs_deployment_retire_other_copies "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      jobs_deployment_rollback || exit 4
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old ]] || exit 5
      /usr/bin/grep -F "register:$BUILT" "$CALLS" >/dev/null || exit 6
      /usr/bin/grep -F "unregister:$BUILT" "$CALLS" >/dev/null || exit 7
    ZSH
    assert_empty Dir.glob(File.join(@applications, '.JobsFinderDeployment.*'))
  end

  def test_registration_failure_on_first_application_install_restores_build_registration
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_retire_other_copies "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_rollback || exit 3
      [[ ! -e "$DEPLOYED" && -d "$BUILT" ]] || exit 4
      /usr/bin/grep -F "register:$BUILT" "$CALLS" >/dev/null || exit 5
    ZSH
  end

  def test_copy_failure_keeps_previous_application
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_copy_app() { /bin/mkdir "$2"; print partial > "$2/partial"; return 7; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ "$?" == 7 ]] || exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 3
    ZSH
  end

  def test_bad_staging_signature_does_not_replace_previous_application
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_verify_signature() { [[ "$1" != */staging.app ]]; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 2
    ZSH
  end

  def test_failed_final_move_restores_previous_application
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_verify_signature() { [[ "$1" != */staging.app ]] || /bin/rm -r -- "$1"; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 2
    ZSH
  end

  def test_foreign_same_name_application_is_never_overwritten_or_uninstalled
    make_app(@deployed, 'foreign', app_id: 'com.other.fixture')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == foreign && ! -e "$CALLS" ]] || exit 3
    ZSH
  end

  def test_symlink_destination_and_linked_applications_parent_are_rejected
    File.symlink(@built, @deployed)
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1; [[ -L "$DEPLOYED" && -d "$BUILT" ]] || exit 2')
    File.symlink(@applications, File.join(@root, 'linked-apps'))
    shell(<<~'ZSH')
      JOBS_FINDER_APPLICATIONS_DIR="$TEST_ROOT/linked-apps"
      jobs_deployment_app_path "$BUILT" && exit 1
      JOBS_FINDER_APPLICATIONS_DIR=/
      jobs_deployment_app_path "$BUILT" && exit 2
      return 0
    ZSH
  end

  def test_external_resource_link_is_rejected_before_publication
    File.write(File.join(@root, 'outside.zsh'), 'external')
    File.symlink(File.join(@root, 'outside.zsh'), File.join(@built, 'Contents/Resources/link.zsh'))
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1; [[ ! -e "$DEPLOYED" ]] || exit 2')
  end

  def test_exact_location_matching_and_other_enabled_detection
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_matches_path "$DEPLOYED" "$BUILT" || exit 1
      jobs_deployment_matches_path "$DEPLOYED/Contents/PlugIns/$EXTENSION" "$BUILT" || exit 2
      jobs_deployment_matches_path "$BUILT/Contents/PlugIns/$EXTENSION" "$BUILT" && exit 3
      jobs_deployment_matches_path "$DEPLOYED.backup" "$BUILT" && exit 4
      jobs_deployment_matches_path "$DEPLOYED/Contents/PlugIns/extra/$EXTENSION" "$BUILT" && exit 5
      jobs_deployment_has_other_enabled "$DEPLOYED" "$EXTENSION_ID" || exit 6
      jobs_deployment_has_other_enabled "$BUILT" "$EXTENSION_ID" && exit 7
      jobs_deployment_selected_exists "$BUILT" || exit 8
      return 0
    ZSH
  end

  def test_uninstall_removes_only_selected_application_and_never_build_copy
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_uninstall "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$DEPLOYED" && -d "$BUILT" ]] || exit 3
      [[ "$(<"$CALLS")" == "unregister:$DEPLOYED" ]] || exit 4
    ZSH
  end

  def test_build_switch_retirement_can_restore_application_registration
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 5
      jobs_deployment_retire_other_copies "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_rollback || exit 2
      [[ -d "$DEPLOYED" && -d "$BUILT" ]] || exit 3
      /usr/bin/grep -F "register:$DEPLOYED" "$CALLS" >/dev/null || exit 4
      /usr/bin/grep -F "unregister:$BUILT" "$CALLS" >/dev/null || exit 6
    ZSH
  end

  def test_build_install_rollback_without_retirement_restores_original_application
    make_app(@deployed, 'old')
    set_active(@deployed)
    shell(<<~'ZSH')
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_rollback || exit 2
      [[ "$(<"$CALLS")" == $'unregister:'"$BUILT"$'\nregister:'"$DEPLOYED" ]] || exit 3
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old ]] || exit 4
    ZSH
  end

  def test_registration_restore_failure_keeps_original_file_and_backup_transaction_for_retry
    make_app(@deployed, 'old')
    set_active(@built)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      jobs_deployment_register_restored_app() { return 7; }
      jobs_deployment_rollback && exit 2
      [[ "$(<"$DEPLOYED/Contents/Resources/业务.zsh")" == old && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 3
      jobs_deployment_register_restored_app() { return 0; }
      jobs_deployment_rollback || exit 4
      [[ -z "$JOBS_DEPLOYMENT_TRANSACTION_DIR" ]] || exit 5
    ZSH
  end

  def test_enabled_metadata_parser_and_query_error_are_not_treated_as_disabled
    shell(<<~'ZSH')
      fixture_pluginkit() {
        print -r -- '+ com.jobs.fixture.findersync(1.0)'
        print -r -- "    Path = $BUILT/Contents/PlugIns/$EXTENSION"
        print -r -- '- com.jobs.fixture.findersync(1.0)'
        print -r -- "    Path = $DEPLOYED/Contents/PlugIns/$EXTENSION"
      }
      functions[jobs_deployment_enabled_extension_paths]="$functions[jobs_deployment_enabled_extension_paths_original]"
      [[ -n "$functions[jobs_deployment_enabled_extension_paths]" ]] || exit 1
      functions[jobs_deployment_enabled_extension_paths]="${functions[jobs_deployment_enabled_extension_paths]//\/usr\/bin\/pluginkit/fixture_pluginkit}"
      [[ "$(jobs_deployment_enabled_extension_paths "$EXTENSION_ID")" == "$BUILT/Contents/PlugIns/$EXTENSION" ]] || exit 2
      jobs_deployment_has_other_enabled "$DEPLOYED" "$EXTENSION_ID" || exit 3
      fixture_pluginkit() { return 9; }
      jobs_deployment_has_other_enabled "$DEPLOYED" "$EXTENSION_ID" && exit 4
      [[ "$?" == 2 ]] || exit 5
    ZSH
  end

  def test_internal_relative_resources_are_copied_and_commit_detects_concurrent_target_swap
    File.symlink('业务.zsh', File.join(@built, 'Contents/Resources/internal.zsh'))
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ -L "$DEPLOYED/Contents/Resources/internal.zsh" && "$(<"$DEPLOYED/Contents/Resources/internal.zsh")" == new ]] || exit 2
      /bin/mv "$DEPLOYED" "$TEST_ROOT/concurrent.app"
      /bin/mkdir "$DEPLOYED"
      jobs_deployment_commit && exit 3
      [[ -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR" && -d "$TEST_ROOT/concurrent.app" ]] || exit 4
    ZSH
  end

  def test_rollback_preserves_concurrent_replacement_and_retains_backup
    make_app(@deployed, 'old')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      /bin/mv "$DEPLOYED" "$TEST_ROOT/moved.app"
      /bin/mkdir "$DEPLOYED"
      print concurrent > "$DEPLOYED/concurrent"
      jobs_deployment_rollback && exit 2
      [[ -f "$DEPLOYED/concurrent" && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR/previous.app" ]] || exit 3
    ZSH
  end

  def test_invalid_location_and_repeated_uncommitted_install_are_rejected
    shell(<<~'ZSH')
      JOBS_FINDER_INSTALL_LOCATION=invalid
      jobs_deployment_app_path "$BUILT" && exit 1
      JOBS_FINDER_INSTALL_LOCATION=applications
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      jobs_deployment_commit || exit 4
    ZSH
  end

  def test_single_combined_container_is_created_with_fixed_name_and_identity
    FileUtils.remove_entry(@container)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      [[ "$(jobs_deployment_container_path)" == "$CONTAINER" ]] || exit 2
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$CONTAINER/Contents/Info.plist")" == Jobs自定义右键菜单 ]] || exit 3
    ZSH
    assert_equal ['Jobs自定义右键菜单.app'], Dir.children(@applications)
  end

  def test_successful_commit_migrates_only_selected_owned_top_level_application
    legacy = File.join(@applications, 'JobsFixture.app')
    other = File.join(@applications, 'JobsOther.app')
    make_app(legacy, 'legacy')
    make_app(other, 'other')
    set_active(legacy)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      [[ ! -e "${CONTAINER:h}/JobsFixture.app" && -d "${CONTAINER:h}/JobsOther.app" && -d "$DEPLOYED" ]] || exit 2
    ZSH
    assert_equal 'other', File.read(resource(other))
  end

  def test_failed_commit_restores_migrated_top_level_application_and_original_registration
    legacy = File.join(@applications, 'JobsFixture.app')
    make_app(legacy, 'legacy')
    set_active(legacy)
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      functions[original_release]="$functions[jobs_deployment_release_transaction]"
      jobs_deployment_release_transaction() { return 7; }
      jobs_deployment_commit && exit 2
      [[ ! -e "${CONTAINER:h}/JobsFixture.app" && -d "$JOBS_DEPLOYMENT_TRANSACTION_DIR/legacy.app" ]] || exit 3
      functions[jobs_deployment_release_transaction]="$functions[original_release]"
      jobs_deployment_rollback || exit 4
      [[ "$(<"${CONTAINER:h}/JobsFixture.app/Contents/Resources/业务.zsh")" == legacy ]] || exit 5
      /usr/bin/grep -F "register:${CONTAINER:h}/JobsFixture.app" "$CALLS" >/dev/null || exit 6
    ZSH
  end

  def test_unknown_top_level_application_is_retained_when_combined_host_is_installed
    legacy = File.join(@applications, 'JobsFixture.app')
    make_app(legacy, 'foreign', app_id: 'com.other.fixture')
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    assert_equal 'foreign', File.read(resource(legacy))
    assert File.directory?(@deployed)
  end

  def test_foreign_container_and_container_symlink_are_rejected
    File.write(File.join(@container, 'Contents/Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.other.manager</string></dict></plist>')
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1; [[ ! -e "$DEPLOYED" ]] || exit 2')
    FileUtils.remove_entry(@container)
    File.symlink(@built, @container)
    shell('jobs_deployment_app_path "$BUILT" && exit 1; [[ -L "$CONTAINER" ]] || exit 2')
  end

  def test_uninstall_keeps_sibling_host_and_removes_container_after_last_host
    make_app(@deployed, 'old')
    sibling = File.join(File.dirname(@deployed), 'JobsOther.app')
    make_app(sibling, 'other')
    shell(<<~'ZSH')
      jobs_deployment_uninstall "$DEPLOYED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ -d "$CONTAINER/Contents/Applications/JobsOther.app" && -d "$CONTAINER" ]] || exit 2
      jobs_deployment_uninstall "$CONTAINER/Contents/Applications/JobsOther.app" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 3
      [[ ! -e "$CONTAINER" ]] || exit 4
    ZSH
  end

  def test_outer_signing_preserves_signed_child_entitlements_and_verifies_complete_container
    extension_bundle = File.join(@built, 'Contents/PlugIns', EXTENSION)
    FileUtils.cp('/usr/bin/true', File.join(extension_bundle, 'Contents/MacOS/FixtureExtension'))
    File.chmod(0o755, File.join(extension_bundle, 'Contents/MacOS/FixtureExtension'))
    entitlements = File.join(@root, 'fixture-entitlements.plist')
    File.write(entitlements, '<plist version="1.0"><dict><key>com.jobs.fixture</key><true/></dict></plist>')
    [
      ['/usr/bin/codesign', '--force', '--sign', '-', '--entitlements', entitlements, extension_bundle],
      ['/usr/bin/codesign', '--force', '--sign', '-', @built]
    ].each do |command|
      output, error, result = Open3.capture3(*command)
      assert result.success?, "临时夹具签名失败：#{output}#{error}"
    end
    before, = Open3.capture3('/usr/bin/codesign', '-d', '--entitlements', ':-', extension_bundle)
    shell(<<~'ZSH')
      functions[jobs_deployment_verify_signature]="$functions[jobs_deployment_verify_signature_original]"
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      /usr/bin/codesign --verify --deep --strict "$CONTAINER" || exit 2
    ZSH
    after, error, result = Open3.capture3('/usr/bin/codesign', '-d', '--entitlements', ':-', File.join(@deployed, 'Contents/PlugIns', EXTENSION))
    assert result.success?, error
    assert_includes after, 'com.jobs.fixture'
    assert_equal before, after
  end

  def test_cleanup_removes_only_committed_derived_root_and_deployed_host_still_runs
    sibling = File.join(File.dirname(@derived), 'JobsOtherDerivedData')
    FileUtils.mkdir_p(sibling)
    File.write(File.join(sibling, 'keep'), 'sibling')
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$DERIVED" && -d "$DEPLOYED" ]] || exit 3
    ZSH
    assert_equal 'sibling', File.read(File.join(sibling, 'keep'))
    host = File.join(@deployed, 'Contents/MacOS/FixtureHost')
    output, error, result = Open3.capture3([host, host])
    assert result.success?, error
    assert_equal 'new', output
  end

  def test_cleanup_rejects_uncommitted_build_mode_and_unrelated_roots
    shell(<<~'ZSH')
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      jobs_deployment_commit || exit 4
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      for rejected in "$TEST_ROOT" "${DERIVED:h}" "$CONTAINER" "$TEST_ROOT/编译 产物" /; do
        jobs_deployment_cleanup_build_products "$BUILT" "$rejected" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 5
      done
      JOBS_FINDER_INSTALL_LOCATION=build
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 6
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 7
    ZSH
  end

  def test_cleanup_requires_exact_active_target_and_no_old_registered_source_or_process
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      print -r -- "$BUILT/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/registered.txt"
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      /bin/rm "$TEST_ROOT/registered.txt"
      jobs_deployment_source_is_running() { return 0; }
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 5
    ZSH
  end

  def test_cleanup_rejects_linked_parent_and_restores_root_when_a_process_appears
    shell(<<~'ZSH')
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      parent_dir="${DERIVED:h}"
      /bin/mv "$parent_dir" "$parent_dir.moved"
      /bin/ln -s "$parent_dir.moved" "$parent_dir"
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      /bin/rm "$parent_dir"
      /bin/mv "$parent_dir.moved" "$parent_dir"
      process_checks=0
      jobs_deployment_source_is_running() { (( process_checks += 1 )); (( process_checks > 1 )); }
      jobs_deployment_cleanup_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 4
    ZSH
  end

  def test_unregister_is_idempotent_only_when_failed_remove_has_no_remaining_exact_record
    shell(<<~'ZSH')
      functions[jobs_deployment_unregister_app]="$functions[jobs_deployment_unregister_app_original]"
      jobs_deployment_remove_extension_path() { return 7; }
      jobs_deployment_registered_extension_paths_for_bundle() { return 0; }
      jobs_deployment_unregister_host_path() { print -r -- "host:$1" >> "$CALLS"; }
      jobs_deployment_unregister_app "$BUILT" "$EXTENSION" || exit 1
      [[ "$(<"$CALLS")" == "host:$BUILT" ]] || exit 2
      /bin/rm "$CALLS"
      jobs_deployment_registered_extension_paths_for_bundle() { print -r -- "$BUILT/Contents/PlugIns/$EXTENSION"; }
      jobs_deployment_unregister_app "$BUILT" "$EXTENSION" && exit 3
      [[ ! -e "$CALLS" ]] || exit 4
      jobs_deployment_registered_extension_paths_for_bundle() { return 9; }
      jobs_deployment_unregister_app "$BUILT" "$EXTENSION" && exit 5
      [[ ! -e "$CALLS" ]] || exit 6
    ZSH
  end

  def test_outer_signature_is_prepared_before_registration_and_commit_does_not_resign
    shell(<<~'ZSH')
      sign_count=0
      jobs_deployment_sign_container() { (( sign_count += 1 )); print -r -- sign >> "$CALLS"; }
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ "$sign_count" == 1 && "$JOBS_DEPLOYMENT_PREPARED_REGISTRATION" == 1 ]] || exit 2
      print -r -- register >> "$CALLS"
      jobs_deployment_prepare_registration || exit 3
      jobs_deployment_commit || exit 4
      [[ "$sign_count" == 1 && "$(<"$CALLS")" == $'sign\nregister' ]] || exit 5
    ZSH
  end

  def test_app_management_signature_denial_returns_77_and_emits_responsible_app_marker
    shell(<<~'ZSH')
      setopt ERR_EXIT
      exec 2> "$TEST_ROOT/policy-error.log"
      JOBS_FINDER_RESPONSIBLE_APP='FixtureManager.app'
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_codesign_container() { print -u2 -r -- "$1: Operation not permitted"; return 1; }
      denied_result=0
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || denied_result=$?
      [[ "$denied_result" == 77 && -d "$DERIVED" && ! -e "$DEPLOYED" ]] || exit 1
      /usr/bin/grep -F $'JOBS_MANAGER_BLOCKED\tapp-management\t77' "$TEST_ROOT/policy-error.log" >/dev/null || exit 2
      /usr/bin/grep -F FixtureManager.app "$TEST_ROOT/policy-error.log" >/dev/null || exit 3
    ZSH
  end

  def test_app_management_marker_writes_only_precreated_private_control_flag
    shell(<<~'ZSH')
      control_dir="$TEST_ROOT/JobsFinderControl.12345678"
      /bin/mkdir -m 700 "$control_dir"
      JOBS_FINDER_BLOCKED_FILE="$control_dir/app-management.blocked"
      : > "$JOBS_FINDER_BLOCKED_FILE"
      /bin/chmod 600 "$JOBS_FINDER_BLOCKED_FILE"
      JOBS_FINDER_RESPONSIBLE_APP=FixtureManager.app
      blocked_result=0
      jobs_deployment_error 'Fixture.app: Operation not permitted' || blocked_result=$?
      [[ "$blocked_result" == 77 && "$(<"$JOBS_FINDER_BLOCKED_FILE")" == app-management ]] || exit 1
      jobs_deployment_error 'Fixture.app: Operation not permitted' || blocked_result=$?
      [[ "$(<"$JOBS_FINDER_BLOCKED_FILE")" == app-management ]] || exit 2
      [[ "$(/usr/bin/stat -f %Lp "$JOBS_FINDER_BLOCKED_FILE")" == 600 ]] || exit 3
    ZSH
  end

  def test_app_management_marker_rejects_wrong_paths_links_permissions_and_missing_flag
    shell(<<~'ZSH')
      safe_dir="$TEST_ROOT/JobsFinderControl.12345678"
      /bin/mkdir -m 700 "$safe_dir"
      flag="$safe_dir/app-management.blocked"
      : > "$flag"
      /bin/chmod 600 "$flag"
      JOBS_FINDER_RESPONSIBLE_APP=FixtureManager.app
      deny() { jobs_deployment_error 'Fixture.app: Operation not permitted' || true; }
      JOBS_FINDER_BLOCKED_FILE="$safe_dir/missing.blocked"
      deny
      [[ ! -e "$JOBS_FINDER_BLOCKED_FILE" ]] || exit 1
      JOBS_FINDER_BLOCKED_FILE="$safe_dir/other"
      print -nr -- untouched > "$JOBS_FINDER_BLOCKED_FILE"
      /bin/chmod 600 "$JOBS_FINDER_BLOCKED_FILE"
      deny
      [[ "$(<"$JOBS_FINDER_BLOCKED_FILE")" == untouched ]] || exit 2
      JOBS_FINDER_BLOCKED_FILE="$flag"
      /bin/chmod 644 "$flag"
      deny
      [[ ! -s "$flag" ]] || exit 3
      /bin/chmod 600 "$flag"
      /bin/chmod 755 "$safe_dir"
      deny
      [[ ! -s "$flag" ]] || exit 4
      /bin/chmod 700 "$safe_dir"
      /bin/mv "$flag" "$safe_dir/original"
      /bin/ln -s "$safe_dir/original" "$flag"
      deny
      [[ ! -s "$safe_dir/original" ]] || exit 5
      /bin/rm "$flag"
      /bin/ln "$safe_dir/original" "$flag"
      deny
      [[ ! -s "$safe_dir/original" ]] || exit 6
      /bin/rm "$flag"
      JOBS_FINDER_BLOCKED_FILE="$flag"
      deny
      [[ ! -e "$flag" ]] || exit 7
      /bin/mv "$safe_dir" "$TEST_ROOT/wrong-name"
      JOBS_FINDER_BLOCKED_FILE="$TEST_ROOT/wrong-name/app-management.blocked"
      : > "$JOBS_FINDER_BLOCKED_FILE"
      /bin/chmod 600 "$JOBS_FINDER_BLOCKED_FILE"
      deny
      [[ ! -s "$JOBS_FINDER_BLOCKED_FILE" ]] || exit 8
    ZSH
  end

  def test_other_signature_failure_keeps_its_error_code_without_app_management_marker
    shell(<<~'ZSH')
      exec 2> "$TEST_ROOT/signature-error.log"
      functions[jobs_deployment_sign_container]="$functions[jobs_deployment_sign_container_original]"
      jobs_deployment_codesign_container() { print -u2 -r -- 'bundle format unrecognized'; return 9; }
      failed_result=0
      jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || failed_result=$?
      [[ "$failed_result" == 9 && -d "$DERIVED" && ! -e "$DEPLOYED" ]] || exit 1
      /usr/bin/grep -F JOBS_MANAGER_BLOCKED "$TEST_ROOT/signature-error.log" >/dev/null && exit 2
      return 0
    ZSH
  end

  def test_independent_cleanup_in_fresh_worker_does_not_need_an_install_receipt
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    set_active(@deployed)
    shell(<<~'ZSH')
      (( ${#JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]} == 0 )) || exit 1
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 2
      [[ ! -e "$DERIVED" && -d "$DEPLOYED" ]] || exit 3
      (( ${#JOBS_DEPLOYMENT_COMMITTED_RECEIPT[@]} == 0 )) || exit 4
    ZSH
    host = File.join(@deployed, 'Contents/MacOS/FixtureHost')
    output, error, result = Open3.capture3([host, host])
    assert result.success?, error
    assert_equal 'new', output
  end

  def test_independent_cleanup_missing_or_empty_source_is_noop
    FileUtils.remove_entry(@derived)
    shell('jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1')
    FileUtils.mkdir_p(@derived)
    shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" || exit 1
      [[ -d "$DERIVED" ]] || exit 2
    ZSH
  end

  def test_independent_cleanup_rejects_unsigned_or_unregistered_target_and_bad_scope
    shell('jobs_deployment_install "$BUILT" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && jobs_deployment_commit || exit 1')
    shell(<<~'ZSH')
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 1
      print -r -- "$DEPLOYED/Contents/PlugIns/$EXTENSION" > "$TEST_ROOT/active.txt"
      jobs_deployment_verify_signature() { return 8; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 2
      jobs_deployment_verify_signature() { return 0; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "${DERIVED:h}" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 3
      jobs_deployment_source_is_running() { return 0; }
      jobs_deployment_cleanup_existing_build_products "$BUILT" "$DERIVED" "$APP_ID" "$EXTENSION" "$EXTENSION_ID" && exit 4
      [[ -d "$DERIVED" && -d "$DEPLOYED" ]] || exit 5
    ZSH
  end

  private

  def make_container
    FileUtils.mkdir_p(File.join(@container, 'Contents/Applications'))
    FileUtils.mkdir_p(File.join(@container, 'Contents/MacOS'))
    File.write(File.join(@container, 'Contents/Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.jobs.finderextensions.manager</string><key>CFBundleExecutable</key><string>JobsFinderExtensions</string><key>CFBundleName</key><string>Jobs自定义右键菜单</string></dict></plist>')
    executable = File.join(@container, 'Contents/MacOS/JobsFinderExtensions')
    File.write(executable, "#!/bin/zsh\nexit 0\n")
    File.chmod(0o755, executable)
  end

  def resource(app)
    File.join(app, 'Contents/Resources/业务.zsh')
  end

  def make_app(app, content, app_id: APP_ID)
    [[app, app_id, 'FixtureHost'], [File.join(app, 'Contents/PlugIns', EXTENSION), EXTENSION_ID, 'FixtureExtension']].each do |bundle, identifier, executable|
      FileUtils.mkdir_p(File.join(bundle, 'Contents/MacOS'))
      File.write(File.join(bundle, 'Contents/Info.plist'), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{identifier}</string><key>CFBundleExecutable</key><string>#{executable}</string><key>CFBundlePackageType</key><string>#{executable == 'FixtureHost' ? 'APPL' : 'XPC!'}</string><key>CFBundleVersion</key><string>1</string></dict></plist>
      XML
      program = File.join(bundle, 'Contents/MacOS', executable)
      body = if executable == 'FixtureHost'
               <<~'SH'
                 #!/bin/sh
                 resource_dir=$(CDPATH= cd "$(dirname "$0")/../Resources" && pwd) || exit 1
                 exec /bin/cat "$resource_dir/业务.zsh"
               SH
             else
               "#!/bin/sh\nexit 0\n"
             end
      File.write(program, body)
      File.chmod(0o755, program)
    end
    FileUtils.mkdir_p(File.dirname(resource(app)))
    File.write(resource(app), content)
  end

  def set_active(app)
    File.write(File.join(@root, 'active.txt'), File.join(app, 'Contents/PlugIns', EXTENSION) + "\n")
  end

  def shell(body)
    script = <<~'ZSH'
      source "$1" || exit 90
      TEST_ROOT="$2"
      BUILT="$3"
      DEPLOYED="$4"
      CALLS="$TEST_ROOT/calls"
      DERIVED="${BUILT%/Build/Products/Debug/JobsFixture.app}"
      CONTAINER="${DEPLOYED%/Contents/Applications/JobsFixture.app}"
      APP_ID=com.jobs.fixture
      EXTENSION=JobsFixtureFinder.appex
      EXTENSION_ID=com.jobs.fixture.findersync
      functions[jobs_deployment_enabled_extension_paths_original]="$functions[jobs_deployment_enabled_extension_paths]"
      functions[jobs_deployment_verify_signature_original]="$functions[jobs_deployment_verify_signature]"
      functions[jobs_deployment_sign_container_original]="$functions[jobs_deployment_sign_container]"
      functions[jobs_deployment_unregister_app_original]="$functions[jobs_deployment_unregister_app]"
      jobs_deployment_verify_signature() { return 0; }
      jobs_deployment_sign_container() { return 0; }
      jobs_prepare_combined_manager_resources() { return 0; }
      jobs_deployment_enabled_extension_paths() { [[ ! -f "$TEST_ROOT/active.txt" ]] || /bin/cat "$TEST_ROOT/active.txt"; return 0; }
      jobs_deployment_registered_extension_paths() { if [[ -f "$TEST_ROOT/registered.txt" ]]; then /bin/cat "$TEST_ROOT/registered.txt"; else jobs_deployment_enabled_extension_paths "$1"; fi; }
      jobs_deployment_source_is_running() { return 1; }
      jobs_deployment_unregister_app() { print -r -- "unregister:$1" >> "$CALLS"; }
      jobs_deployment_register_restored_app() { print -r -- "register:$1" >> "$CALLS"; }
    ZSH
    output, error, result = Open3.capture3(
      { 'JOBS_FINDER_INSTALL_LOCATION' => 'applications', 'JOBS_FINDER_APPLICATIONS_DIR' => @applications },
      '/bin/zsh', '-f', '-c', script + body, 'AppDeploymentTests', LIBRARY, @root, @built, @deployed
    )
    assert result.success?, "exit=#{result.exitstatus}\nstdout=#{output}\nstderr=#{error}\n#{body}"
  end
end
