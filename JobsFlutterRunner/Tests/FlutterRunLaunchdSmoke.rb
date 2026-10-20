# Created by Jobs on 2026年10月20日，星期二.
# 隔离集成验证：只创建临时 launchd 任务与假 Flutter，不注册 Finder、不构建业务项目。
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'digest'
require 'json'
require 'timeout'

runtime = File.expand_path('../Scripts/RunFlutterProject.zsh', __dir__)
temporary = File.realpath(Dir.mktmpdir('jobs-flutter-launchd-'))
project = File.join(temporary, "项目 空格 ' $(literal)")
home = File.join(temporary, 'home')
bin = File.join(temporary, 'bin')
FileUtils.mkdir_p([project, home, bin])
FileUtils.mkdir_p(File.join(project, 'android'))
File.write(File.join(project, 'pubspec.yaml'), "name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n")
mock = File.join(bin, 'flutter')
File.write(mock, <<~'ZSH')
  #!/bin/zsh
  case "$1" in
    --version) print '{"frameworkVersion":"fixture"}'; exit 0 ;;
    devices) print '[{"id":"mock-device","name":"模拟设备","targetPlatform":"android-arm64","supported":true}]'; exit 0 ;;
    run)
      [[ "$*" == 'run --machine -d mock-device' ]] || exit 71
      print '[{"event":"app.start","params":{"appId":"smoke-app"}}]'
      while true; do
        if IFS= read -r -t 1 message; then
          if [[ "$message" == *'app.stop'* ]]; then
            print 'SMOKE_STOPPED'
            exit 0
          fi
          [[ "$message" != *'app.restart'* ]] || print 'SMOKE_RELOADED'
        fi
        print 'SMOKE_HEARTBEAT'
      done
      ;;
    *) exit 72 ;;
  esac
ZSH
FileUtils.chmod(0o700, mock)
digest = Digest::SHA256.hexdigest(project + "\0mock-device")
label = "com.jobs.flutterrunner.#{digest}"
target = "gui/#{Process.uid}/#{label}"
session = File.join(home, 'Library/Application Support/JobsFlutterRunner/sessions', digest)
environment = { 'HOME' => home, 'PATH' => "#{bin}:/usr/bin:/bin:/usr/sbin:/sbin", 'NO_COLOR' => '1' }

begin
  out, err, result = Open3.capture3(environment, '/bin/zsh', runtime, '--project', project, stdin_data: "\n1\nd\n")
  raise "启动入口失败：#{out}\n#{err}" unless result.success?
  raise '任务未注册到 launchd' unless system('/bin/launchctl', 'print', target, out: File::NULL, err: File::NULL)
  30.times do
    break if File.exist?(File.join(session, 'run.log')) && File.read(File.join(session, 'run.log')).include?('SMOKE_HEARTBEAT')
    sleep 0.1
  end
  before = File.size(File.join(session, 'run.log'))
  sleep 1.2
  raise '入口退出后后台日志未继续增长' unless File.size(File.join(session, 'run.log')) > before
  # HUP 对应关闭终端的断连；只终止本次日志入口，launchd 持有的 worker 必须继续。
  Open3.popen3(environment, '/bin/zsh', runtime, '--project', project) do |input, output, errors, process|
    captured = ''
    reader = Thread.new { captured << output.read }
    input.write("\n1\n")
    input.flush
    sleep 2.5
    Process.kill('HUP', process.pid)
    input.close
    Timeout.timeout(10) { process.value; reader.join }
    raise "HUP 入口异常：#{captured}\n#{errors.read}" unless process.value.success?
  end
  before = File.size(File.join(session, 'run.log'))
  sleep 1.2
  raise '终端 HUP 后后台日志未继续增长' unless File.size(File.join(session, 'run.log')) > before
  # 模拟 worker 意外崩溃，没有 exitcode 标记时也必须允许重新启动。
  raise '无法注入隔离 worker 崩溃' unless system('/bin/launchctl', 'kill', 'SIGKILL', target)
  30.times do
    current, = Open3.capture2('/bin/launchctl', 'print', target)
    break unless current.match?(/^\s*pid = [1-9]/)
    sleep 0.1
  end
  out, err, result = Open3.capture3(environment, '/bin/zsh', runtime, '--project', project, stdin_data: "\n1\nd\n")
  raise "失效任务无法重启：#{out}\n#{err}" unless result.success? && out.include?('后台任务已提交')
  sleep 0.5
  out, err, result = Open3.capture3(environment, '/bin/zsh', runtime, '--project', project, stdin_data: "\n1\nr\ns\n")
  raise "重连 / 停止失败：#{out}\n#{err}" unless result.success?
  raw = File.read(File.join(session, 'run.log'))
  raise '热重载协议未到达 Flutter' unless raw.include?('SMOKE_RELOADED')
  raise '停止协议未到达 Flutter' unless raw.include?('SMOKE_STOPPED')
  raise '退出码记录错误' unless File.read(File.join(session, 'exitcode')).strip == '0'
  raise '停止后 launchd 任务仍存在' if system('/bin/launchctl', 'print', target, out: File::NULL, err: File::NULL)
  puts 'PASS: launchd 托管、退出及 HUP 后存活、日志增长、崩溃后重启、重连、热重载和停止；特殊路径按数据传递。'
ensure
  system('/bin/launchctl', 'bootout', target, out: File::NULL, err: File::NULL)
  FileUtils.remove_entry(temporary)
end
