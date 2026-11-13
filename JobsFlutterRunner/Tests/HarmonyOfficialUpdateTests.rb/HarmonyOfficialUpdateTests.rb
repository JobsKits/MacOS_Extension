# Created by Jobs on 2026年11月12日，星期四.
# 只用临时文件模拟 HTTP；实际系统 JXA 解析，绝不下载 SDK、读取 Cookie 或启动设备。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

class HarmonyOfficialUpdateTests < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  HELPER = ENV.fetch('JOBS_HARMONY_OFFICIAL_TEST_HELPER', File.join(ROOT, 'Scripts/SimulatorCreators/【MacOS】模拟器启动环境.zsh/Resources/【MacOS】鸿蒙官方更新.zsh/【MacOS】鸿蒙官方更新.zsh'))

  def setup
    @temporary = Dir.mktmpdir('harmony-official-update-')
    @prefix = File.join(@temporary, 'operation 中文 log')
    @receipt = File.join(@temporary, 'receipt.json')
    File.write(@receipt, '')
    @version_file = File.join(@temporary, 'version.txt')
    File.write(@version_file, '6.1.1.280')
    @public = File.join(@temporary, 'public.json')
    @catalog = File.join(@temporary, 'catalog.json')
    @download = File.join(@temporary, 'download.json')
    @trace = File.join(@temporary, 'trace')
    @build = '6.1.1.300'
    @name = "commandline-tools-mac-#{`uname -m`.strip == 'arm64' ? 'arm64-' : 'x64-'}#{@build}.zip"
    @platform = `uname -m`.strip == 'arm64' ? 3 : 2
    @release = {code: 0, value: {status: '4', lang: 'en', fileName: 'deveco-studio-new-features-611', content: {content: <<~HTML}}}
      <h4>DevEco Studio 6.1.1 Release (6.1.1.300)</h4>
      <table><tr><td>HarmonyOS Emulator</td><td>6.1.1.999</td></tr></table>
      <table><tr><td>Command Line</td><td>6.1.1.300</td></tr></table>
      <h4>DevEco Studio 6.1.1 Beta1 (6.1.1.900)</h4>
      <table><tr><td>Command Line</td><td>6.1.1.900</td></tr></table>
    HTML
    @package = {sdkId: 'sdk-id', packageId: 'package-id', packageName: @name, packageSize: 12345, sha256: 'a' * 64}
    @entry = {versionId: 'version-id', versionName: 'Command Line Tools 6.1.1 Release', buildVersion: @build, packageList: [@package]}
    @catalog_data = {code: '00000', value: {toolName: 'Command Line Tools', versionTypeList: [{osType: @platform, versionList: [@entry]}]}}
    @download_data = {code: '00000', value: {downloadUrl: "https://appfile-cn.dbankcdn.com/packages/#{@name}?signature=fixture"}}
    write_fixtures
    @env = {'MOCK_HELPER' => HELPER, 'MOCK_LOG' => @prefix, 'MOCK_RECEIPT' => @receipt, 'MOCK_CURRENT' => '6.1.1.280',
            'MOCK_VERSION_FILE' => @version_file, 'MOCK_PUBLIC' => @public, 'MOCK_CATALOG' => @catalog, 'MOCK_DOWNLOAD' => @download,
            'MOCK_TRACE' => @trace, 'MOCK_HTTP' => '200', 'MOCK_CURL_EXIT' => '0', 'MOCK_FIRST_FAILURE' => '0',
            'MOCK_FIRST_HTTP' => '000', 'MOCK_FIRST_EXIT' => '28', 'MOCK_BACKOFF_EXIT' => '0'}
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def write_fixtures
    File.write(@public, JSON.generate(@release))
    File.write(@catalog, JSON.generate(@catalog_data))
    File.write(@download, JSON.generate(@download_data))
  end

  def execute(environment = {})
    script = <<~'ZSH'
      setopt NO_NOMATCH PIPE_FAIL
      LOG_FILE="$MOCK_LOG"
      log() { print -r -- "$*"; }
      run_bounded() {
        local seconds="$1" output="$2" argument="" destination="" payload=""
        shift 2
        if [[ "$1" == /usr/bin/curl ]]; then
          while (( $# )); do
            argument="$1"; shift
            case "$argument" in
              --output) destination="$1"; shift ;;
              --data-binary) payload="${1#@}"; shift ;;
            esac
          done
          print -r -- "$payload" >> "$MOCK_TRACE"
          if [[ "$MOCK_FIRST_FAILURE" == 1 && ! -f "$MOCK_LOG.failed-once" ]]; then
            : > "$MOCK_LOG.failed-once"
            print -n -r -- "$MOCK_FIRST_HTTP" > "$output"
            return "$MOCK_FIRST_EXIT"
          fi
          case "$payload" in
            *.release.request) /bin/cp "$MOCK_PUBLIC" "$destination" ;;
            *.catalog.request) /bin/cp "$MOCK_CATALOG" "$destination" ;;
            *.download.request) /bin/cp "$MOCK_DOWNLOAD" "$destination" ;;
            *) return 98 ;;
          esac
          print -n -r -- "$MOCK_HTTP" > "$output"
          return "$MOCK_CURL_EXIT"
        fi
        "$@" > "$output" 2>&1
      }
      source "$MOCK_HELPER"
      jobs_sim_harmony_official_backoff() {
        print -r -- "$1" >> "$MOCK_LOG.backoff"
        return "$MOCK_BACKOFF_EXIT"
      }
      jobs_sim_harmony_official_update "$MOCK_CURRENT" "$MOCK_RECEIPT" "$MOCK_VERSION_FILE"
    ZSH
    output, status = Open3.capture2e(@env.merge(environment), '/bin/zsh', '-c', script)
    [output, status.exitstatus]
  end

  def test_current_release_uses_public_clt_row_without_download_auth_or_emulator_version
    File.write(@version_file, "6.1.1.300\n")
    output, status = execute('MOCK_CURRENT' => '6.1.1.300')
    assert_equal 0, status, output
    receipt = JSON.parse(File.read(@receipt))
    assert_equal 'ready', receipt['state']
    assert_equal '6.1.1.300', receipt['version']
    assert_equal 1, File.readlines(@trace).length
    refute File.exist?(@prefix + '.harmony-official.catalog.request')
  end

  def test_verified_positive_path_returns_size_hash_and_official_matching_url
    output, status = execute
    assert_equal 0, status, output
    receipt = JSON.parse(File.read(@receipt))
    assert_equal 'update', receipt['state']
    assert_equal @name, receipt['packageName']
    assert_equal 12345, receipt['size']
    assert_equal 'a' * 64, receipt['sha256']
    assert_equal @download_data[:value][:downloadUrl], receipt['url']
    request = JSON.parse(File.read(@prefix + '.harmony-official.download.request'))
    assert_equal({versionId: 'version-id', sdkId: 'sdk-id', packageId: 'package-id'}, JSON.parse(request['reqJson'], symbolize_names: true))
  end

  def test_nested_service_wrapper_and_signed_query_remain_data
    File.write(@catalog, JSON.generate(returnCode: '0', resJson: JSON.generate(@catalog_data)))
    url = "https://appfile-cn.dbankcdn.com/packages/#{@name}?signature=a%2Fb%2Bc&expires=123"
    File.write(@download, JSON.generate(returnCode: 0, resJson: JSON.generate(code: '00000', value: {downloadUrl: url})))
    output, status = execute
    assert_equal 0, status, output
    assert_equal url, JSON.parse(File.read(@receipt))['url']
  end

  def test_zero_size_or_duplicate_release_records_are_incomplete_metadata
    @package[:packageSize] = 0
    File.write(@catalog, JSON.generate(@catalog_data))
    output, status = execute
    assert_equal 67, status, output
    assert_empty File.read(@receipt)
    @package[:packageSize] = 12345
    @catalog_data[:value][:versionTypeList][0][:versionList] << @entry.dup
    File.write(@catalog, JSON.generate(@catalog_data))
    output, status = execute
    assert_equal 67, status, output
    assert_empty File.read(@receipt)
  end

  def test_authentication_html_and_http_fail_closed_without_receipt
    [{returnCode: '90910011', description: 'X-HD-CSRF is missing'}, '<html>login</html>'].each do |response|
      File.write(@catalog, response.is_a?(String) ? response : JSON.generate(response))
      output, status = execute
      assert_equal 67, status, output
      assert_empty File.read(@receipt)
      assert_includes output, '未下载固定旧版'
    end
    output, status = execute('MOCK_HTTP' => '401')
    assert_equal 67, status, output
    assert_empty File.read(@receipt)
    assert_includes output, 'HTTP=401'
  end

  def test_beta_only_stale_catalog_wrong_architecture_or_bad_hash_never_becomes_ready
    [lambda { @entry[:versionName] = 'Command Line Tools 6.1.1 Beta2' },
     lambda { @entry[:buildVersion] = '6.1.1.280'; @package[:packageName] = @name.sub('.300', '.280') },
     lambda { @catalog_data[:value][:versionTypeList][0][:osType] = 1 },
     lambda { @package[:sha256] = 'invalid' }].each do |mutate|
      original = JSON.parse(JSON.generate(@catalog_data), symbolize_names: true)
      mutate.call
      File.write(@catalog, JSON.generate(@catalog_data))
      output, status = execute
      assert_equal 67, status, output
      assert_empty File.read(@receipt)
      @catalog_data = original
      @entry = @catalog_data[:value][:versionTypeList][0][:versionList][0]
      @package = @entry[:packageList][0]
    end
  end

  def test_invalid_download_source_filename_or_outer_error_is_rejected
    ['http://appfile-cn.dbankcdn.com/' + @name, 'https://example.com/' + @name,
     'https://appfile-cn.dbankcdn.com/wrong.zip', 'https://appfile-cn.dbankcdn.com/' + @name + '#fragment'].each do |url|
      File.write(@download, JSON.generate(code: '00000', value: {downloadUrl: url}))
      output, status = execute
      assert_equal 67, status, output
      assert_empty File.read(@receipt)
    end
    File.write(@catalog, JSON.generate(returnCode: '90910011', resJson: JSON.generate(@catalog_data)))
    output, status = execute
    assert_equal 67, status, output
  end

  def test_public_document_structure_and_local_version_provenance_are_required
    File.write(@public, JSON.generate(@release).sub('Command Line', 'Emulator'))
    output, status = execute('MOCK_CURRENT' => '6.1.1.300')
    assert_equal 67, status, output
    assert_empty File.read(@receipt)
    write_fixtures
    File.delete(@trace)
    output, status = execute('MOCK_VERSION_FILE' => File.join(@temporary, 'missing'))
    assert_equal 67, status, output
    refute File.exist?(@trace)
  end

  def test_cancellation_is_preserved_and_never_retried_or_treated_as_authentication
    [130, 143].each do |code|
      File.write(@trace, '')
      output, status = execute('MOCK_CURL_EXIT' => code.to_s)
      assert_equal code, status, output
      assert_equal 1, File.readlines(@trace).length
      assert_empty File.read(@receipt)
    end
  end

  def test_transport_timeout_503_and_429_retry_then_recover_without_replaying_download
    File.write(@version_file, '6.1.1.300')
    [[28, '000'], [0, '503'], [0, '429']].each do |code, http|
      File.write(@receipt, '')
      File.write(@trace, '')
      File.delete(@prefix + '.failed-once') if File.exist?(@prefix + '.failed-once')
      output, status = execute('MOCK_CURRENT' => '6.1.1.300', 'MOCK_FIRST_FAILURE' => '1', 'MOCK_FIRST_EXIT' => code.to_s, 'MOCK_FIRST_HTTP' => http)
      assert_equal 0, status, output
      assert_equal 'ready', JSON.parse(File.read(@receipt))['state']
      assert_equal 2, File.readlines(@trace).length
      assert_includes output, '自动重试'
      refute File.exist?(@prefix + '.harmony-official.catalog.request')
    end
  end

  def test_cancel_during_transport_backoff_stops_before_another_request
    [130, 143].each do |code|
      File.write(@trace, '')
      File.delete(@prefix + '.failed-once') if File.exist?(@prefix + '.failed-once')
      output, status = execute('MOCK_FIRST_FAILURE' => '1', 'MOCK_BACKOFF_EXIT' => code.to_s)
      assert_equal code, status, output
      assert_equal 1, File.readlines(@trace).length
      assert_empty File.read(@receipt)
    end
  end
end
