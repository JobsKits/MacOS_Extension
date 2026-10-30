# frozen_string_literal: true
# Jobs：临时缓存与真实 Java FileLock，假 Wrapper 验证预置协议，不联网或调用 Gradle。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'digest'
require 'json'
require 'timeout'
require 'shellwords'

class WrapperDistributionCacheTests < Minitest::Test
  LIBRARY = File.expand_path('../Scripts/Tools/WrapperDistributionCache.zsh', __dir__)
  URL = 'https://services.gradle.org/distributions/gradle-8.14-bin.zip'
  def setup
    @root = File.realpath(Dir.mktmpdir('jobs-wrapper-cache-'))
    @project = File.join(@root, "工程 ' $ literal")
    @user_home = File.join(@root, 'Gradle Home')
    @wrapper = File.join(@project, 'android/gradle/wrapper')
    FileUtils.mkdir_p(@wrapper)
    @properties = File.join(@wrapper, 'gradle-wrapper.properties')
    File.write(@properties, "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14-bin.zip\n")
    File.write(File.join(@wrapper, 'gradle-wrapper.jar'), 'fake wrapper fixture')
    @archive = File.join(@root, 'verified.zip')
    File.write(@archive, 'verified distribution fixture')
    @sha = Digest::SHA256.file(@archive).hexdigest
    @java_home = Open3.capture2('/usr/libexec/java_home')[0].strip
    assert File.executable?(File.join(@java_home, 'bin/javac')), 'native JDK is required for FileLock tests'
    @env = {'HOME' => @root, 'GRADLE_USER_HOME' => @user_home, 'PATH' => '/usr/bin:/bin',
            'GRADLE_OPTS' => '', 'JAVA_OPTS' => '', 'JAVA_TOOL_OPTIONS' => '', 'JDK_JAVA_OPTIONS' => '', '_JAVA_OPTIONS' => ''}
  end
  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end
  def run_library(code, *args, env: {})
    script = <<~'ZSH'
      source "$1"
      PE_RUN_DIR="$2"
      PE_LOG_FILE="$2/cache-test.log"
      pe_log() { print -r -- "$1"; }
      pe_run_logged() { "$@"; }
      shift 2
    ZSH
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', script + code, 'fixture', LIBRARY, @root, *args)
  end
  def prepare
    run_library('wd_prepare_zip "$@"', @project, URL, @sha, @archive, @java_home)
  end
  def expected_zip
    hash = Digest::MD5.hexdigest(URL).to_i(16).to_s(36)
    File.join(@user_home, 'wrapper/dists/gradle-8.14-bin', hash, 'gradle-8.14-bin.zip')
  end
  def assert_success(result)
    assert result[2].success?, result[0] + result[1]
  end
  def test_unsigned_md5_base36_matches_gradle_path_assembler_vector
    result = run_library('wd_url_hash "$1"', URL)
    assert_success(result)
    assert_equal Digest::MD5.hexdigest(URL).to_i(16).to_s(36), result[0]
    assert_equal '36906f4932b15760a9815022152d6425', Digest::MD5.hexdigest(URL)
  end
  def test_standard_cache_stages_verified_zip_without_forging_ok_then_fake_wrapper_reuses_it
    result = prepare
    assert_success(result)
    assert_equal File.binread(@archive), File.binread(expected_zip)
    refute File.exist?(expected_zip + '.ok')
    # The fake Wrapper refuses to "download" when the expected ZIP is absent.
    wrapper = File.join(@project, 'android/gradlew')
    File.write(wrapper, <<~'SH')
      #!/bin/sh
      test "$1" = --version || exit 91
      test -f "$EXPECTED_WRAPPER_ZIP" || exit 92
      test ! -f "$EXPECTED_WRAPPER_ZIP.ok" || exit 93
      printf 'Gradle 8.14 (cached ZIP; no download)\n'
    SH
    out, err, state = Open3.capture3(@env.merge('EXPECTED_WRAPPER_ZIP' => expected_zip), '/bin/sh', wrapper, '--version')
    assert state.success?, out + err
    assert_includes out, 'no download'
    assert_success(prepare)
  end
  def test_project_bases_and_distinct_zip_path_match_real_android_working_directory
    File.open(@properties, 'a') { |f| f.write("distributionBase=PROJECT\ndistributionPath=custom/dists\nzipStoreBase=PROJECT\nzipStorePath=custom/zips\n") }
    result = run_library('wd_resolve_layout "$@"; print -r -- "$WD_DISTRIBUTION_PATH"; print -r -- "$WD_ZIP_PATH"', @project, URL)
    assert_success(result)
    hash = Digest::MD5.hexdigest(URL).to_i(16).to_s(36)
    assert_equal [File.join(@project, 'android/custom/dists/gradle-8.14-bin', hash),
                  File.join(@project, 'android/custom/zips/gradle-8.14-bin', hash, 'gradle-8.14-bin.zip')], result[0].lines.map(&:strip)
    refute Dir.exist?(@user_home)
  end
  def test_unknown_or_escaping_layout_and_jvm_overrides_stop_without_creating_cache
    ["zipStoreBase=UNKNOWN\n", "zipStorePath=../escape\n", "zipStorePath=/absolute\n", "distributionBase=PROJECT\ndistributionBase=GRADLE_USER_HOME\n"].each do |text|
      File.write(@properties, text)
      out, err, state = prepare
      refute state.success?, out + err
      refute Dir.exist?(@user_home)
    end
    File.write(@properties, '')
    out, err, state = run_library('wd_prepare_zip "$@"', @project, URL, @sha, @archive, @java_home, env: {'GRADLE_OPTS' => '-Dgradle.user.home=/other'})
    refute state.success?, out + err
    refute Dir.exist?(@user_home)
  end
  def test_existing_mismatched_zip_partial_and_symlinks_are_preserved
    FileUtils.mkdir_p(File.dirname(expected_zip))
    File.write(expected_zip, 'other data')
    refute prepare[2].success?
    assert_equal 'other data', File.read(expected_zip)
    File.unlink(expected_zip)
    File.write(expected_zip + '.part', 'in-flight data')
    refute prepare[2].success?
    assert_equal 'in-flight data', File.read(expected_zip + '.part')
    refute File.exist?(expected_zip)
    File.unlink(expected_zip + '.part')
    File.symlink(@archive, expected_zip)
    refute prepare[2].success?
    assert File.symlink?(expected_zip)
    assert_equal @sha, Digest::SHA256.file(@archive).hexdigest
  end
  def test_marker_alone_does_not_skip_verified_zip_needed_for_broken_distribution_recovery
    FileUtils.mkdir_p(File.dirname(expected_zip))
    File.write(expected_zip + '.ok', '')
    assert_success(prepare)
    assert_equal File.binread(@archive), File.binread(expected_zip)
    assert_equal '', File.read(expected_zip + '.ok')
  end
  def test_function_scoped_source_preserves_resolved_paths_for_its_caller
    result = run_library('load_library() { source "$1"; }; load_library "$1"; wd_resolve_layout "$2" "$3"; print -r -- "$WD_ZIP_PATH"', LIBRARY, @project, URL)
    assert_success(result)
    assert_equal expected_zip, result[0].strip
  end
  def test_missing_wrapper_or_changed_source_never_publishes_zip
    File.unlink(File.join(@wrapper, 'gradle-wrapper.jar'))
    refute prepare[2].success?
    refute File.exist?(expected_zip)
    File.write(File.join(@wrapper, 'gradle-wrapper.jar'), 'fake')
    File.write(@archive, 'changed since SHA verification')
    refute prepare[2].success?
    refute File.exist?(expected_zip)
  end
  def test_actual_java_file_lock_blocks_publication_and_preserves_in_flight_state
    FileUtils.mkdir_p(File.dirname(expected_zip))
    java = <<~'JAVA'
      import java.nio.file.*; import java.nio.channels.*;
      public class HoldWrapperLock { public static void main(String[] a) throws Exception {
        try(FileChannel c=FileChannel.open(Paths.get(a[0]),StandardOpenOption.CREATE,StandardOpenOption.WRITE); FileLock l=c.lock()) {
          System.out.println("LOCKED"); System.out.flush(); System.in.read();
        }
      }}
    JAVA
    File.write(File.join(@root, 'HoldWrapperLock.java'), java)
    out, err, state = Open3.capture3(File.join(@java_home, 'bin/javac'), File.join(@root, 'HoldWrapperLock.java'))
    assert state.success?, out + err
    Open3.popen3(File.join(@java_home, 'bin/java'), '-cp', @root, 'HoldWrapperLock', expected_zip + '.lck') do |input, output, error, wait|
      assert_equal "LOCKED\n", Timeout.timeout(10) { output.gets }
      result = prepare
      refute result[2].success?, result[0] + result[1]
      assert_includes result[1], 'currently locked'
      refute File.exist?(expected_zip)
      input.write("\n"); input.close
      assert wait.value.success?, error.read
    end
  end
end
