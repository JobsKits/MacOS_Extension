#!/bin/zsh
# 脚本自述：
# - 脚本名称：修复 Dart 相对 import 为 package 引用。
# - 核心用途：按引用文件的位置解析相对 import，只转换实际指向本项目 lib 的引用。
# - 影响范围：选定 Flutter 项目内的普通 Dart 源码；跳过第三方、生成代码和符号链接。
# - 运行提示：先回车查看计划，再输入 YES 才备份并写入；--check / --dry-run 全程只读。
# shell: zsh

SCRIPT_DIR=""
SCRIPT_PATH=""
PROJECT_PATH=""
RUN_DIR=""
LOG_FILE=""
READ_ONLY=0
# 为内置自述提供红色标题、蓝色正文与纯文本回退。
intro_line() {
  local role="$1" message="$2" code="0;34"
  [[ "$role" == title ]] && code="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$code" "$message"
  else
    print -r -- "$message"
  fi
}
# 第一屏直接说明实际用途；只读检查和帮助入口不等待输入。
show_script_intro_and_wait() {
  local argument="" preview=0 answer="" project_value=0
  for argument in "$@"; do
    if (( project_value )); then
      project_value=0
      continue
    fi
    case "$argument" in
      --project) project_value=1 ;;
      --check|--dry-run|--help|-h) preview=1 ;;
    esac
  done
  intro_line title '修复 Dart 相对 import 为 package 引用'
  intro_line body '1、按每个 Dart 文件的位置解析 import，转换为 package:pubspec包名/lib内路径。'
  intro_line body '2、仅处理指向本项目 lib 的真实文件；跳过第三方、生成代码、链接和 export / part。'
  intro_line body '3、先显示逐条计划，输入 YES 才备份并写入；其它输入或 Ctrl+C 取消。'
  intro_line body '4、--check / --dry-run 不写项目、日志或备份；正常运行日志在系统临时目录。'
  (( preview )) && return 0
  [[ -t 0 ]] || { print -u2 -r -- '✖ 写入模式需要可交互终端；只读预览请使用 --check。'; exit 1; }
  IFS= read -r 'answer?已了解用途与范围，按回车继续查看计划；非空取消：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 集中初始化进程选项与脚本定位，不改用户环境或创建日志。
initialize_runtime() {
  local script_source="${(%):-%x}"
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_DIR="$(cd "$(dirname "$script_source")" && pwd)"
  SCRIPT_PATH="${SCRIPT_DIR}/${script_source:t}"
}
# 展示可直接用于菜单派发或终端检查的参数。
show_usage() {
  print -r -- "用法：zsh '$SCRIPT_PATH' --project <Flutter项目根目录> [--check | --dry-run]"
  print -r -- '无参数时可输入或拖入一个项目目录；直接回车采用调用时的当前目录。'
  print -r -- '--check / --dry-run：只读列出转换计划，存在待转换项也返回 0。'
  print -r -- '返回码：0=完成、无需转换或取消；1=校验/执行失败；2=参数错误。'
}
# 解析明确项目路径，避免菜单入口误用脚本所在目录。
parse_arguments() {
  while (( $# )); do
    case "$1" in
      --project)
        (( $# >= 2 )) && [[ -n "$2" ]] || { print -u2 -r -- '✖ --project 缺少目录。'; exit 2; }
        [[ -z "$PROJECT_PATH" ]] || { print -u2 -r -- '✖ 每次只接受一个项目。'; exit 2; }
        PROJECT_PATH="$2"
        shift 2
        ;;
      --check|--dry-run) READ_ONLY=1; shift ;;
      --help|-h) show_usage; exit 0 ;;
      *) print -u2 -r -- "✖ 未知参数：$1"; show_usage; exit 2 ;;
    esac
  done
}
# 还原 Terminal 拖入的单一路径，只解除 Shell 引号与转义而不执行文本。
resolve_project_input() {
  local raw="" word=""
  local -a words=()
  if [[ -z "$PROJECT_PATH" ]]; then
    if (( READ_ONLY )); then
      PROJECT_PATH="$PWD"
    else
      IFS= read -r 'raw?输入或拖入 Flutter 根目录；直接回车使用当前目录：' || exit 0
      if [[ -z "$raw" ]]; then
        PROJECT_PATH="$PWD"
      elif [[ -d "$raw" ]]; then
        PROJECT_PATH="$raw"
      else
        words=( ${(z)raw} )
        (( ${#words} == 1 )) || { print -u2 -r -- '✖ 请只输入一个项目目录。'; exit 1; }
        word="${(Q)words[1]}"
        PROJECT_PATH="$word"
      fi
    fi
  fi
  [[ -d "$PROJECT_PATH" && ! -L "$PROJECT_PATH" ]] || { print -u2 -r -- '✖ 项目目录不存在或本身是符号链接。'; exit 1; }
}
# 仅验证系统已有 Perl，不联网或引入包管理器、Flutter SDK。
check_environment() {
  [[ -x /usr/bin/perl ]] && /usr/bin/perl -e 'use Cwd; use File::Find; use File::Temp; exit 0' || {
    print -u2 -r -- '✖ 系统 Perl 不可用，请先修复系统工具；脚本未安装任何依赖。'
    exit 1
  }
}
# 在确认用途后建立独立纯文本运行日志，只读入口不创建文件。
prepare_run_log() {
  (( READ_ONLY )) && return 0
  RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-flutter-imports.XXXXXX")" || exit 1
  LOG_FILE="$RUN_DIR/imports.log"
  print -r -- "日志：$LOG_FILE"
}
# 内嵌词法与文件处理引擎，使独立脚本和菜单资源使用同一实现。
run_import_engine() {
  /usr/bin/perl - "$PROJECT_PATH" "$READ_ONLY" "$RUN_DIR" 3<&0 <<'PERL'
use strict;
use warnings;
use Encode qw(decode FB_CROAK);
use JSON::PP ();
$| = 1;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Find;
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_EXCL);

my ($project, $read_only, $run_dir) = @ARGV;
my (@plans, @stages, @committed);
my ($scanned, $protected, $changes) = (0, 0, 0);
# 让路径与源码片段保持单行纯文本，不把控制字符带进终端或日志。
sub display {
    my ($text) = @_;
    $text =~ s/([\x00-\x1f\x7f])/sprintf('\\x%02X', ord($1))/ge;
    return $text;
}
# 二进制读取保留原有编码、BOM 与换行，后续只替换 URI 区间。
sub read_bytes {
    my ($path) = @_;
    open my $handle, '<:raw', $path or die "无法读取 " . display($path) . ": $!\n";
    local $/;
    my $data = <$handle>;
    close $handle or die "无法关闭 " . display($path) . ": $!\n";
    return defined $data ? $data : '';
}
# 目录名边界同时用于扫描与目标 URI 校验。
sub excluded_name {
    return $_[0] =~ /\A(?:\.git|node_modules|Pods|PodsManual|ManualBy.*Pods\@Pods|\.dart_tool|build|DerivedData|\.fvm|\.pub-cache|\.gradle|\.symlinks|vendor|vendors|third[_ -]?party|external|generated)\z/i;
}
# 常见 Dart 生成文件由其生成器维护。
sub generated_name {
    return $_[0] =~ /(?:\.(?:g|freezed|mocks|gen)\.dart|generated_plugin_registrant\.dart)\z/i;
}
# 检查规范化路径的每一级，既不遍历链接，也不把链接目标当成本项目源码。
sub regular_project_path {
    my ($path, $root) = @_;
    return 0 if -l $root || !-d $root;
    return 0 unless index($path, "$root/") == 0;
    my $walk = $root;
    for my $part (split m{/}, substr($path, length($root) + 1)) {
        return 0 if excluded_name($part);
        $walk .= "/$part";
        return 0 if -l $walk;
    }
    return -f $path;
}
# 解析器取自现有 Finder Flutter 识别逻辑，不执行 YAML 或工程代码。
sub trim {
  my ($source) = @_;
  $source =~ s/^\s+|\s+$//g;
  return $source;
}
# 只寻找引号和 flow 容器之外的分隔符；# 还必须位于空白之后。
sub delimiter {
  my ($source, $wanted, $comments) = @_;
  my @characters = split //, $source;
  my ($quote, $depth, $escaped) = ('', 0, 0);
  for (my $index = 0; $index < @characters; $index++) {
    my $current = $characters[$index];
    if (length $quote) {
      if ($quote eq '"' && $current eq '\\' && !$escaped) {
        $escaped = 1;
        next;
      }
      if ($current eq $quote && !$escaped) {
        if ($quote eq "'" && $index + 1 < @characters && $characters[$index + 1] eq "'") {
          $index++;
          next;
        }
        $quote = '';
      }
      $escaped = 0;
    } elsif ($current eq '"' || $current eq "'") {
      $quote = $current;
    } elsif ($current eq $wanted && $depth == 0) {
      return $index if !$comments || $index == 0 || $characters[$index - 1] =~ /\s/;
    } elsif ($current eq '{' || $current eq '[') {
      $depth++;
    } elsif ($current eq '}' || $current eq ']') {
      $depth--;
    }
  }
  return undef;
}
# 解码普通值和单双引号标量；不支持 YAML 标签、锚点或执行型扩展。
sub scalar_value {
  my $source = trim($_[0]);
  return undef if !length $source;
  if (substr($source, 0, 1) eq '"') {
    my $value = eval { JSON::PP->new->allow_nonref->decode($source) };
    return undef if $@ || !defined($value) || ref($value);
    return $value;
  }
  if (substr($source, 0, 1) eq "'") {
    return undef if length($source) < 2 || substr($source, -1) ne "'";
    my $body = substr($source, 1, length($source) - 2);
    my $unpaired = $body;
    $unpaired =~ s/''//g;
    return undef if $unpaired =~ /'/;
    $body =~ s/''/'/g;
    return $body;
  }
  return undef if $source =~ /[{}\[\],:#&*!|>"']/;
  return $source;
}
# 解析一行或一个 flow 成员的键值，忽略引号外的尾注释。
sub mapping_pair {
  my ($source) = @_;
  my $hash = delimiter($source, '#', 1);
  $source = trim(substr($source, 0, $hash)) if defined $hash;
  my $colon = delimiter($source, ':', 0);
  return undef if !defined $colon;
  my $key = scalar_value(substr($source, 0, $colon));
  return undef if !defined($key) || !length($key);
  return [$key, trim(substr($source, $colon + 1))];
}
# 解析单行花括号映射，重复键或缺值一律拒绝。
sub flow_mapping {
  my $source = trim($_[0]);
  return undef if substr($source, 0, 1) ne '{' || substr($source, -1) ne '}';
  my $remaining = trim(substr($source, 1, length($source) - 2));
  my %result;
  while (length $remaining) {
    my $comma = delimiter($remaining, ',', 0);
    my $part = defined($comma) ? substr($remaining, 0, $comma) : $remaining;
    my $pair = mapping_pair($part);
    return undef if !defined($pair) || exists($result{$pair->[0]}) || !length($pair->[1]);
    $result{$pair->[0]} = $pair->[1];
    last if !defined $comma;
    $remaining = trim(substr($remaining, $comma + 1));
  }
  return \%result;
}
# 按缩进定位唯一 dependencies → flutter → sdk，与菜单的保守识别规则一致。
sub declares_flutter_sdk {
  my ($text) = @_;
  return 0 if index($text, "\0") >= 0;
  $text =~ s/\r\n/\n/g;
  my @entries;
  for my $line (split /\n/, $text, -1) {
    $line =~ s/^\x{FEFF}//;
    my ($spaces) = $line =~ /^( *)/;
    my $indent = length($spaces);
    my $trimmed = trim($line);
    next if !length($trimmed) || substr($trimmed, 0, 1) eq '#';
    my ($prefix) = $line =~ /^(\s*)/;
    return 0 if $trimmed eq '---' || $trimmed eq '...' || $prefix =~ /\t/;
    my $pair = mapping_pair(substr($line, $indent));
    push @entries, [$indent, defined($pair) ? @$pair : ('', '')];
  }
  my @roots = grep { $entries[$_][0] == 0 && $entries[$_][1] eq 'dependencies' } 0 .. $#entries;
  return 0 if @roots != 1;
  my $root = $roots[0];
  if (length $entries[$root][2]) {
    my $dependencies = flow_mapping($entries[$root][2]);
    return 0 if !defined($dependencies) || !exists($dependencies->{flutter});
    my $flutter = flow_mapping($dependencies->{flutter});
    return 0 if !defined($flutter) || !exists($flutter->{sdk});
    return (scalar_value($flutter->{sdk}) // '') eq 'flutter';
  }
  my $end = $root + 1;
  $end++ while $end < @entries && $entries[$end][0] != 0;
  return 0 if $end == $root + 1;
  my @children = @entries[$root + 1 .. $end - 1];
  my $dependency_indent = $children[0][0];
  for my $entry (@children) {
    $dependency_indent = $entry->[0] if $entry->[0] < $dependency_indent;
  }
  return 0 if $dependency_indent <= 0;
  my @flutter_positions = grep { $children[$_][0] == $dependency_indent && $children[$_][1] eq 'flutter' } 0 .. $#children;
  return 0 if @flutter_positions != 1;
  my $flutter_index = $flutter_positions[0];
  if (length $children[$flutter_index][2]) {
    my $flutter = flow_mapping($children[$flutter_index][2]);
    return 0 if !defined($flutter) || !exists($flutter->{sdk});
    return (scalar_value($flutter->{sdk}) // '') eq 'flutter';
  }
  my $flutter_end = $flutter_index + 1;
  $flutter_end++ while $flutter_end < @children && $children[$flutter_end][0] > $dependency_indent;
  return 0 if $flutter_end == $flutter_index + 1;
  my @fields = @children[$flutter_index + 1 .. $flutter_end - 1];
  my $sdk_indent = $fields[0][0];
  for my $entry (@fields) {
    $sdk_indent = $entry->[0] if $entry->[0] < $sdk_indent;
  }
  return 0 if $sdk_indent <= $dependency_indent;
  my @sdk = grep { $_->[0] == $sdk_indent && $_->[1] eq 'sdk' } @fields;
  return @sdk == 1 && (scalar_value($sdk[0][2]) // '') eq 'flutter';
}

# 校验唯一包名及 dependencies.flutter.sdk，解析规则与 Finder 项目门禁保持一致。
sub project_metadata {
    my ($root) = @_;
    die "项目根目录不能是符号链接。\n" if -l $root;
    $root = abs_path($root) or die "项目目录不存在。\n";
    die "需要普通 pubspec.yaml 与 lib/，链接项目不处理。\n"
        unless -f "$root/pubspec.yaml" && !-l "$root/pubspec.yaml" && -d "$root/lib" && !-l "$root/lib";
    die "pubspec.yaml 过大，拒绝解析。\n" if -s "$root/pubspec.yaml" > 1_048_576;
    my $yaml = read_bytes("$root/pubspec.yaml");
    my $decode_copy = $yaml;
    my $text = eval { decode('UTF-8', $decode_copy, FB_CROAK) };
    die "pubspec.yaml 不是有效 UTF-8。\n" if $@ || !defined $text;
    $text =~ s/^\x{FEFF}//;
    my @names;
    for my $line (split /\n/, $text) {
        next if $line =~ /^\s/;
        my $pair = mapping_pair($line);
        push @names, scalar_value($pair->[1]) if defined $pair && $pair->[0] eq 'name';
    }
    die "pubspec.yaml 需要唯一有效 name（小写字母、数字、下划线）。\n"
        unless @names == 1 && defined($names[0]) && $names[0] =~ /\A[a-z_][a-z0-9_]*\z/;
    die "不是可识别的 Flutter 项目：dependencies.flutter.sdk 需要声明为 flutter。\n"
        unless declares_flutter_sdk($text);
    return ($root, $names[0], $yaml);
}
# 跳过可嵌套块注释；未闭合时拒绝改写整个文件。
sub skip_comment {
    my ($text, $position) = @_;
    if (substr($text, $position, 2) eq '//') {
        my $end = index($text, "\n", $position + 2);
        return $end < 0 ? length($text) : $end;
    }
    my ($depth, $cursor) = (1, $position + 2);
    while ($cursor < length($text)) {
        my $pair = substr($text, $cursor, 2);
        if ($pair eq '/*') { $depth++; $cursor += 2; }
        elsif ($pair eq '*/') { $depth--; $cursor += 2; return $cursor unless $depth; }
        else { $cursor++; }
    }
    die "块注释未闭合";
}
# 识别普通、原始和三引号字符串入口。
sub string_at {
    my ($text, $position) = @_;
    return 1 if substr($text, $position, 1) =~ /['"]/;
    return substr($text, $position, 2) =~ /^r['"]/;
}
# 插值表达式里的字符串与注释仍然必须作为整体跳过。
sub skip_interpolation {
    my ($text, $cursor) = @_;
    my $depth = 1;
    while ($cursor < length($text)) {
        my $pair = substr($text, $cursor, 2);
        if ($pair eq '//' || $pair eq '/*') { $cursor = skip_comment($text, $cursor); }
        elsif (string_at($text, $cursor)) { my $string = scan_string($text, $cursor); $cursor = $string->{end}; }
        elsif (substr($text, $cursor, 1) eq '{') { $depth++; $cursor++; }
        elsif (substr($text, $cursor, 1) eq '}') { $depth--; $cursor++; return $cursor unless $depth; }
        else { $cursor++; }
    }
    die "字符串插值未闭合";
}
# 返回字符串内容的字节区间，保留原始引号、前缀和外围格式。
sub scan_string {
    my ($text, $position) = @_;
    my $raw = substr($text, $position, 1) eq 'r';
    my $quote_position = $position + ($raw ? 1 : 0);
    my $quote = substr($text, $quote_position, 1);
    my $width = substr($text, $quote_position, 3) eq $quote x 3 ? 3 : 1;
    my $delimiter = $quote x $width;
    my $start = $quote_position + $width;
    my $cursor = $start;
    while ($cursor < length($text)) {
        if (substr($text, $cursor, $width) eq $delimiter) {
            return { kind => 'string', start => $start, stop => $cursor, end => $cursor + $width,
                     value => substr($text, $start, $cursor - $start), raw => $raw };
        }
        my $character = substr($text, $cursor, 1);
        if (!$raw && $character eq '\\') { $cursor += 2; }
        elsif (!$raw && substr($text, $cursor, 2) eq '${') { $cursor = skip_interpolation($text, $cursor + 2); }
        else { $cursor++; }
    }
    die "字符串未闭合";
}
# 词法扫描只暴露真正的 token，防止注释、字符串中的 import 文本被替换。
sub tokenize {
    my ($text) = @_;
    my (@tokens, $cursor);
    $cursor = substr($text, 0, 3) eq "\xef\xbb\xbf" ? 3 : 0;
    while ($cursor < length($text)) {
        my $pair = substr($text, $cursor, 2);
        my $character = substr($text, $cursor, 1);
        if ($character =~ /\s/) { $cursor++; }
        elsif ($pair eq '//' || $pair eq '/*') { $cursor = skip_comment($text, $cursor); }
        elsif (string_at($text, $cursor)) { my $token = scan_string($text, $cursor); push @tokens, $token; $cursor = $token->{end}; }
        elsif ($character =~ /[A-Za-z_\$]/) {
            my $start = $cursor++;
            $cursor++ while $cursor < length($text) && substr($text, $cursor, 1) =~ /[A-Za-z0-9_\$]/;
            push @tokens, { kind => 'word', value => substr($text, $start, $cursor - $start), start => $start, end => $cursor };
        } else {
            push @tokens, { kind => 'punct', value => $character, start => $cursor, end => ++$cursor };
        }
    }
    return \@tokens;
}
# 在声明头部检查生成标记及明确的第三方作者，普通无作者业务源码可进入计划。
sub protection_reason {
    my ($path, $text) = @_;
    return '生成文件名' if generated_name($path);
    my $header = '';
    my $cursor = substr($text, 0, 3) eq "\xef\xbb\xbf" ? 3 : 0;
    while ($cursor < length($text)) {
        if (substr($text, $cursor, 1) =~ /\s/) { $cursor++; next; }
        my $pair = substr($text, $cursor, 2);
        last unless $pair eq '//' || $pair eq '/*';
        my $end = skip_comment($text, $cursor);
        $header .= substr($text, $cursor, $end - $cursor) . "\n";
        $cursor = $end;
    }
    return '生成代码标记' if $header =~ /GENERATED CODE|DO NOT (?:MODIFY|EDIT)|Generated by/i;
    for my $line (split /\n/, $header) {
        if ($line =~ /(?:created\s+by|\bauthors?\s*:|\@author\b|copyright)/i && $line !~ /\bJobs\b/i) {
            return '明确的其他作者或版权声明';
        }
    }
    return '';
}
# 相对 URI 以引用文件为基准消解点段，只有实际位于本项目 lib 的普通文件才转换。
sub package_uri {
    my ($uri, $source, $root, $name) = @_;
    return if $uri eq '' || $uri =~ /^[A-Za-z][A-Za-z0-9+.-]*:/;
    return if $uri =~ m{^[\\/]|[\\\$%?#\x00-\x20\x7f]};
    my @parts;
    for my $part (split m{/}, dirname($source) . "/$uri") {
        next if $part eq '' || $part eq '.';
        if ($part eq '..') { return unless @parts; pop @parts; }
        else { push @parts, $part; }
    }
    my $target = '/' . join('/', @parts);
    return unless index($target, "$root/lib/") == 0;
    return unless regular_project_path($target, $root) && !generated_name($target);
    my $suffix = substr($target, length("$root/lib/"));
    return unless $suffix =~ /\.dart\z/;
    return "package:$name/$suffix";
}
# 从 import 指令提取默认 URI 与 if 条件 URI，不处理 export / part 或条件比较字符串。
sub import_replacements {
    my ($text, $path, $root, $name) = @_;
    my $tokens = tokenize($text);
    my (@replacements, $depth);
    $depth = 0;
    for (my $index = 0; $index < @$tokens; $index++) {
        my $token = $tokens->[$index];
        if ($token->{kind} eq 'punct') {
            $depth++ if $token->{value} =~ /^[{(\[]$/;
            $depth-- if $token->{value} =~ /^[})\]]$/;
        }
        next unless $depth == 0 && $token->{kind} eq 'word' && $token->{value} eq 'import';
        my $cursor = $index + 1;
        next unless $cursor < @$tokens && $tokens->[$cursor]{kind} eq 'string';
        my @uris = ($tokens->[$cursor++]);
        my $terminated = 0;
        while ($cursor < @$tokens) {
            my $part = $tokens->[$cursor];
            if ($part->{kind} eq 'punct' && $part->{value} eq ';') { $terminated = 1; last; }
            if ($part->{kind} eq 'word' && $part->{value} eq 'if') {
                $cursor++;
                last unless $cursor < @$tokens && $tokens->[$cursor]{value} eq '(';
                my $parentheses = 1;
                while (++$cursor < @$tokens && $parentheses) {
                    my $condition = $tokens->[$cursor];
                    if ($condition->{kind} eq 'punct') {
                        $parentheses++ if $condition->{value} eq '(';
                        $parentheses-- if $condition->{value} eq ')';
                    }
                }
                last unless !$parentheses && $cursor < @$tokens && $tokens->[$cursor]{kind} eq 'string';
                push @uris, $tokens->[$cursor];
            }
            $cursor++;
        }
        next unless $terminated;
        for my $uri (@uris) {
            my $replacement = package_uri($uri->{value}, $path, $root, $name);
            next unless defined $replacement;
            my $line = 1 + (substr($text, 0, $uri->{start}) =~ tr/\n/\n/);
            push @replacements, { %$uri, replacement => $replacement, line => $line };
        }
        $index = $cursor;
    }
    return \@replacements;
}
# 扫描仅保存计划与原始字节；此阶段不写入任何项目文件。
sub build_plan {
    my ($root, $name) = @_;
    my @files;
    File::Find::find({ no_chdir => 1, wanted => sub {
        my $path = $File::Find::name;
        return if $path eq $root;
        my $relative = substr($path, length($root) + 1);
        if (-l $path) { $protected++; return; }
        if (-d $path) {
            if (excluded_name($_ =~ m{([^/]+)\z} ? $1 : $_) || -e "$path/pubspec.yaml") {
                $File::Find::prune = 1;
                $protected++;
                print '跳过目录：', display($relative), "（第三方/构建目录或嵌套包）\n";
            }
            return;
        }
        push @files, $path if -f $path && $path =~ /\.dart\z/;
    } }, $root);
    for my $path (sort @files) {
        $scanned++;
        my $relative = substr($path, length($root) + 1);
        my @stat = lstat($path);
        if (!regular_project_path($path, $root) || $stat[3] > 1) {
            $protected++;
            print '跳过文件：', display($relative), "（链接或不在扫描范围）\n";
            next;
        }
        my $text = read_bytes($path);
        my ($reason, $replacements);
        my $valid = eval { $reason = protection_reason($path, $text); $replacements = import_replacements($text, $path, $root, $name) unless $reason; 1 };
        if (!$valid || $reason) {
            $protected++;
            print '跳过文件：', display($relative), '（', display($reason || $@), "）\n";
            next;
        }
        next unless @$replacements;
        my $updated = $text;
        for my $edit (reverse @$replacements) {
            substr($updated, $edit->{start}, $edit->{stop} - $edit->{start}, $edit->{replacement});
        }
        push @plans, { path => $path, relative => $relative, original => $text, updated => $updated,
                       stat => \@stat, replacements => $replacements };
        for my $edit (@$replacements) {
            print '计划 ', display($relative), ':', $edit->{line}, '：', display($edit->{value}), ' → ', display($edit->{replacement}), "\n";
            $changes++;
        }
    }
}
# 写前复检文件身份、内容与目录边界，发现并发变化就停止。
sub verify_original {
    my ($record, $root) = @_;
    my @now = lstat($record->{path});
    die '文件身份已变化：' . display($record->{relative}) . "\n"
        unless @now && regular_project_path($record->{path}, $root) && $now[0] == $record->{stat}[0] && $now[1] == $record->{stat}[1] && $now[3] == 1;
    die '文件内容已变化：' . display($record->{relative}) . "\n" unless read_bytes($record->{path}) eq $record->{original};
}
# 用同目录临时文件承载完整结果，rename 以单文件原子方式替换。
sub stage_bytes {
    my ($record, $bytes) = @_;
    my ($handle, $stage) = tempfile('.jobs-imports-XXXXXX', DIR => dirname($record->{path}), UNLINK => 0);
    push @stages, $stage;
    binmode $handle;
    print {$handle} $bytes or die "无法写入临时文件：$!\n";
    close $handle or die "无法关闭临时文件：$!\n";
    chmod($record->{stat}[2] & 07777, $stage) == 1 or die "无法保留文件权限：$!\n";
    return $stage;
}
# 批量备份全部原文后才写第一份源码；中途失败仅回滚仍等于本次结果的文件。
sub apply_plan {
    my ($root, $yaml) = @_;
    my $ok = eval {
        die "pubspec.yaml 或 lib 已变化，请重新预览。\n" unless !-l "$root/pubspec.yaml" && -f "$root/pubspec.yaml" && !-l "$root/lib" && -d "$root/lib" && read_bytes("$root/pubspec.yaml") eq $yaml;
        verify_original($_, $root) for @plans;
        for my $record (@plans) {
            my $backup = "$run_dir/backup/$record->{relative}";
            make_path(dirname($backup), { mode => 0700 });
            sysopen my $handle, $backup, O_WRONLY | O_CREAT | O_EXCL, 0600 or die "无法创建备份：$!\n";
            binmode $handle;
            print {$handle} $record->{original} or die "无法写入备份：$!\n";
            close $handle or die "无法关闭备份：$!\n";
            $record->{stage} = stage_bytes($record, $record->{updated});
        }
        verify_original($_, $root) for @plans;
        for my $record (@plans) {
            verify_original($record, $root);
            rename($record->{stage}, $record->{path}) or die '无法替换 ' . display($record->{relative}) . ": $!\n";
            push @committed, $record;
        }
        1;
    };
    my $failure = $@;
    unless ($ok) {
        for my $record (reverse @committed) {
            my $restored = eval {
                die "文件又被修改，保留当前版本" unless regular_project_path($record->{path}, $root) && read_bytes($record->{path}) eq $record->{updated};
                my $stage = stage_bytes($record, $record->{original});
                rename($stage, $record->{path}) or die "$!";
                1;
            };
            print '警告：需要从备份人工恢复 ', display($record->{relative}), '：', display($@), "\n" unless $restored;
        }
    }
    unlink $_ for grep { -f $_ && !-l $_ } @stages;
    die $failure unless $ok;
    print "✔ 已转换 ", scalar(@plans), " 个文件、$changes 处 import。\n";
    print '备份：', display("$run_dir/backup"), "\n";
}
# 编排只读计划、精确确认与持久化，异常统一返回失败状态。
sub run {
    my ($root, $name, $yaml) = project_metadata($project);
    print '项目：', display($root), "\n包名：$name\n";
    build_plan($root, $name);
    print "摘要：扫描 $scanned 个 Dart 文件；保护 $protected 项；待转换 ", scalar(@plans), " 个文件、$changes 处 import。\n";
    if ($read_only) { print "只读检查结束，未创建日志、备份或改写文件。\n"; return; }
    if (!@plans) { print "✔ 无需转换。\n"; return; }
    print "确认范围：仅应用以上计划；备份保存在本次日志目录。\n";
    print "输入 YES 后回车执行；其它输入或输入结束取消：";
    open my $confirmation, '<&=3' or die "无法读取确认输入。\n";
    my $answer = <$confirmation>;
    if (!defined $answer || $answer !~ /^YES\r?\n\z/) { print "\n已取消，未写入源码或备份。\n"; return; }
    print "\n";
    local $SIG{INT} = sub { die "用户中断，停止写入。\n" };
    local $SIG{TERM} = sub { die "进程终止，停止写入。\n" };
    local $SIG{HUP} = sub { die "终端关闭，停止写入。\n" };
    apply_plan($root, $yaml);
}
my $success = eval { run(); 1 };
unless ($success) { print STDERR '✖ ', display($@), "\n"; exit 1; }
PERL
}
# 统一传递引擎退出码，正常模式同时保存终端业务输出。
run_business() {
  local result=0
  if (( READ_ONLY )); then
    run_import_engine
    result=$?
  else
    run_import_engine 2>&1 | /usr/bin/tee -a "$LOG_FILE"
    result=$?
    print -r -- "日志：$LOG_FILE"
  fi
  exit "$result"
}
# 主入口只编排高层步骤，所有文件操作都留在确认后的业务函数中。
main() {
  show_script_intro_and_wait "$@" # 先说明用途，普通运行等待回车确认。
  initialize_runtime # 设置本进程选项并定位脚本。
  parse_arguments "$@" # 区分项目参数与只读检查入口。
  resolve_project_input # 接收明确项目目录或拖入路径。
  check_environment # 验证已有系统 Perl，不安装依赖。
  prepare_run_log # 正常模式创建独立日志，只读模式保持零写入。
  run_business # 展示计划，输入 YES 后备份并转换。
}

main "$@"
