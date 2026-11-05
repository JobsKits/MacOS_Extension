# Created by Jobs. Catalog retry fixtures never execute sdkmanager or install components.
require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'shellwords'

class AndroidRepairCatalogRetryTests < Minitest::Test
  TOOLS = File.expand_path('../../Scripts/Tools', __dir__)
  def fixture(cancel: false)
    Dir.mktmpdir('jobs-android-repair-catalog-') do |tmp|
      source = File.read(File.join(TOOLS, 'RepairAndroidSdk.zsh'))
      line = source.lines.find { |v| v.start_with?('catalog=') }
      refute_nil line
      body = <<~SH
        source #{File.join(TOOLS, 'AndroidSdkSupport.zsh').shellescape}
        LOG_FILE=#{File.join(tmp, 'sdk.log').shellescape}
        fixture_count=#{File.join(tmp, 'count').shellescape}
        JOBS_SDK_RETRY_DELAY=0 JOBS_SDK_RETRY_MAX_DELAY=1
        ANDROID_SIM_SDKMANAGER=/fixture/sdkmanager
        ANDROID_SIM_SDK=/fixture/sdk
        ANDROID_SIM_SDK_PROXY=()
        android_timed() {
          local count=0
          [[ ! -f "$fixture_count" ]] || count=$(<"$fixture_count")
          (( count++ )); print "$count" > "$fixture_count"
          if [[ #{cancel ? '1' : '0'} == 1 ]]; then return 130; fi
          if (( count==1 )); then print 'Warning: Failed to download repository; invalid-failed-package'; return 0; fi
          print -r -- $'platforms;android-34 | 3 | Android SDK Platform 34\nbuild-tools;34.0.0 | 34.0.0 | Android SDK Build-Tools'
        }
        #{line}
        print -r -- "$catalog"
        print BUSINESS
      SH
      out, err, status = Open3.capture3('/bin/zsh', '-f', '-c', body)
      assert File.exist?(File.join(tmp, 'count')), err+out
      yield out, err, status, File.read(File.join(tmp, 'count')).strip
    end
  end
  def test_failed_exit_zero_catalog_retries_and_only_success_stdout_is_parsed
    fixture do |out, err, status, count|
      assert status.success?, err
      assert_equal '2', count
      assert_includes out, 'platforms;android-34'
      refute_includes out, 'invalid-failed-package'
      assert_includes err, 'Failed to download'
    end
  end
  def test_user_cancel_130_stops_before_following_business
    fixture(cancel: true) do |out, err, status, count|
      assert_equal 130, status.exitstatus, err
      assert_equal '1', count
      refute_includes out, 'BUSINESS'
    end
  end
end
