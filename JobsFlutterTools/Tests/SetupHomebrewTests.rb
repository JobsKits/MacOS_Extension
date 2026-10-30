# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 假Homebrew及隔离TTY覆盖依赖链，不联网、不安装、不改用户启动文件。
require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'pty'
require 'tmpdir'

class SetupHomebrewTests < Minitest::Test
  SOURCE = File.expand_path('../Scripts/Tools/SetupHomebrew.zsh', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-setup-brew-'))
    @prefix = File.join(@root, 'brew')
    FileUtils.mkdir_p(File.join(@prefix, 'bin'))
    @brew = File.join(@prefix, 'bin/brew')
    File.write(@brew, <<~'SH')
      #!/bin/zsh
      [[ "$HB_TEST_BAD" != 1 ]] || exit 42
      case "$1" in --prefix) print -r -- "$HB_TEST_PREFIX" ;; --version) print Homebrew-fixture ;; config) print fixture ;; *) exit 41 ;; esac
    SH
    FileUtils.chmod(0o755, @brew)
    @env = { 'HB_TEST_SOURCE' => SOURCE, 'HB_TEST_PREFIX' => @prefix, 'HB_TEST_BREW' => @brew,
             'HB_TEST_TRACE' => File.join(@root, 'trace'), 'HB_TEST_BAD' => nil,
             'HOME' => @root, 'JOBS_HOMEBREW_BIN' => @brew, 'PATH' => '/usr/bin:/bin' }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def prefix
    <<~'SH'
      source "$HB_TEST_SOURCE"
      PE_RUN_DIR="$HOME"
      pe_log() { print -r -- "$*"; }
      pe_event() { print -r -- "$*" >> "$HB_TEST_TRACE"; }
    SH
  end

  def run_tty(body)
    text = +''
    result = nil
    PTY.spawn(@env, '/bin/zsh', '-c', prefix + body + '; code=$?; print "RESULT:$code"; exit "$code"') do |reader, _writer, pid|
      begin
        reader.each_line { |line| text << line }
      rescue Errno::EIO
        nil
      ensure
        Process.wait(pid)
        result = $CHILD_STATUS || $?
      end
    end
    [text, result]
  end

  def test_healthy_chain_reuses_brew_and_only_changes_current_path
    out, err, result = Open3.capture3(@env, '/bin/zsh', '-c', prefix + 'pe_prepare_homebrew && print -r -- "BREW:$PJ_BREW|$PJ_BREW_PREFIX"')
    assert result.success?, out + err
    assert_includes out, "BREW:#{@brew}|#{@prefix}"
    assert_includes File.read(@env['HB_TEST_TRACE']), 'succeeded'
    refute File.exist?(File.join(@root, '.zprofile'))
  end

  def test_missing_leaf_installs_once_then_verifies
    out, result = run_tty(<<~'SH')
      hb_setup_find() { return 1; }
      hb_setup_prerequisites() { return 0; }
      hb_setup_choose_mode() { HB_SETUP_MODE=user; }
      hb_setup_install_user() { print install >> "$HB_TEST_TRACE"; HB_SETUP_BREW="$HB_TEST_BREW"; }
      pe_prepare_homebrew
    SH
    assert result.success?, out
    assert_equal 1, File.read(@env['HB_TEST_TRACE']).lines.count { |line| line.strip == 'install' }
    assert_includes out, 'RESULT:0'
  end

  def test_missing_clt_stops_all_lower_layers
    out, result = run_tty(<<~'SH')
      hb_setup_find() { return 1; }
      hb_setup_prerequisites() { return 3; }
      hb_setup_choose_mode() { print unexpected-choice >> "$HB_TEST_TRACE"; }
      hb_setup_install_user() { print unexpected-install >> "$HB_TEST_TRACE"; }
      pe_prepare_homebrew
    SH
    assert_equal 3, result.exitstatus, out
    refute_includes File.read(@env['HB_TEST_TRACE']), 'unexpected'
  end

  def test_install_failure_does_not_switch_routes_or_activate
    out, result = run_tty(<<~'SH')
      hb_setup_find() { return 1; }
      hb_setup_prerequisites() { return 0; }
      hb_setup_choose_mode() { HB_SETUP_MODE=system; }
      hb_setup_install_system() { return 41; }
      hb_setup_install_user() { print unexpected-fallback >> "$HB_TEST_TRACE"; }
      hb_setup_activate() { print unexpected-activate >> "$HB_TEST_TRACE"; }
      pe_prepare_homebrew
    SH
    assert_equal 41, result.exitstatus, out
    refute_includes File.read(@env['HB_TEST_TRACE']), 'unexpected'
  end

  def test_post_install_failed_health_check_is_not_success
    out, result = run_tty(<<~'SH')
      hb_setup_find() { return 1; }
      hb_setup_prerequisites() { return 0; }
      hb_setup_choose_mode() { HB_SETUP_MODE=user; }
      hb_setup_install_user() { HB_SETUP_BREW="$HB_TEST_BREW"; export HB_TEST_BAD=1; }
      pe_prepare_homebrew
    SH
    refute result.success?, out
    refute_includes File.read(@env['HB_TEST_TRACE']), 'succeeded'
  end

  def test_source_only_does_not_execute_or_write
    _, err, result = Open3.capture3(@env, '/bin/zsh', '-c', 'source "$HB_TEST_SOURCE"')
    assert result.success?, err
    refute File.exist?(@env['HB_TEST_TRACE'])
    refute File.exist?(File.join(@root, '.zprofile'))
  end
end
