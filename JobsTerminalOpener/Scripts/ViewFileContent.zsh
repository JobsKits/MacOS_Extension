#!/bin/zsh
# 脚本自述：
# - 脚本名称：用终端查看文件内容。
# - 核心用途：只读显示单个普通文件，超过阈值先在当前终端确认。
# - 影响范围：不执行文件、不修改原文件；不保存正文日志。
# - 运行提示：默认阈值 1 MiB；精确 YES 继续，回车 / EOF 取消，Ctrl+C 中止。
# shell: zsh

show_file_content_intro() {
  print -r -- '━━━━━━━━━━ 用终端查看文件内容 ━━━━━━━━━━'
  print -r -- '1、只读查看，不执行文件，不修改文件，不保存正文日志。'
  print -r -- '2、超过阈值先确认；二进制或未知编码另行确认后用十六进制显示。'
  print -r -- '3、回车 / EOF 取消确认；Ctrl+C 中止。普通小文本直接显示。'
}

# 系统 Perl 用安全标志打开同一文件句柄；不依赖第三方工具，不拼接或执行文件正文。
file_content_run() {
  /usr/bin/perl /dev/fd/3 "$@" 3<<'PERL'
use strict;
use warnings;
use utf8;
use Fcntl qw(:DEFAULT :mode);
use Encode qw(decode encode FB_DEFAULT FB_QUIET);
use IPC::Open2 qw(open2);
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';
$SIG{INT} = sub { exit 130 };
$SIG{HUP} = sub { exit 129 };
$SIG{TERM} = sub { exit 143 };

sub safe_text {
    my ($text, $metadata) = @_;
    $text =~ s/([\x00-\x08\x0b-\x1f\x7f-\x9f\x{202a}-\x{202e}\x{2066}-\x{2069}])/sprintf('\\x{%02X}', ord($1))/ge;
    $text =~ s/([\t\n])/sprintf('\\x{%02X}', ord($1))/ge if $metadata;
    return $text;
}
sub confirm {
    my ($message) = @_;
    print "$message\n";
    unless (-t STDIN) {
        print "已取消：当前没有可交互终端。\n";
        return 0;
    }
    print "输入 YES 继续；直接回车取消：";
    STDOUT->flush();
    my $answer = <STDIN>;
    unless (defined $answer) {
        print "\n已取消：输入已结束。\n";
        return 0;
    }
    $answer =~ s/\r?\n\z//;
    return 1 if $answer eq 'YES';
    print "已取消，没有读取文件正文。\n";
    return 0;
}
# 只剥离有效但尚未完整的 UTF-8 尾字节，避免采样边界或读取分块截断中文。
sub take_utf8_tail {
    my ($bytes) = @_;
    my $tail = '';
    if ($$bytes =~ s/((?:[\xc2-\xdf]|\xe0[\xa0-\xbf]?|[\xe1-\xec\xee\xef][\x80-\xbf]?|\xed[\x80-\x9f]?|\xf0(?:[\x90-\xbf][\x80-\xbf]?)?|[\xf1-\xf3](?:[\x80-\xbf]{1,2})?|\xf4(?:[\x80-\x8f][\x80-\xbf]?)?))\z//) {
        $tail = $1;
    }
    return $tail;
}
sub sample_is_text {
    my ($sample, $is_complete) = @_;
    take_utf8_tail(\$sample) unless $is_complete;
    my $text = decode('UTF-8', $sample, FB_QUIET);
    return 0 if length $sample;
    my $sample_bytes = encode('UTF-8', $text);
    my ($reader, $writer);
    my $pid = open2($reader, $writer, '/usr/bin/file', '-b', '--mime', '-');
    binmode $writer;
    print {$writer} $sample_bytes or die "样本识别写入失败：$!\n";
    close $writer or die "样本识别输入失败：$!\n";
    my $mime = <$reader> // '';
    close $reader;
    waitpid($pid, 0);
    die "文件样本识别失败。\n" if $? != 0;
    return $mime =~ /charset=(?:us-ascii|utf-8)\s*\z/;
}

my $limit = exists $ENV{JOBS_FILE_VIEWER_MAX_BYTES} ? $ENV{JOBS_FILE_VIEWER_MAX_BYTES} : '1048576';
unless ($limit =~ /\A[1-9][0-9]{0,18}\z/ &&
        (length($limit) < 19 || $limit le '9223372036854775807')) {
    die "✖ JOBS_FILE_VIEWER_MAX_BYTES 必须是 1 到 9223372036854775807 的十进制整数字节数。\n";
}
my $target = $ARGV[0] // '';
my @before = lstat($target);
unless (@ARGV == 1 && $target =~ m{\A/} && index($target, "\0") < 0 && @before && S_ISREG($before[2])) {
    die "✖ 请选择一个普通文件；不支持文件夹、链接或特殊文件。\n";
}
sysopen(my $file, $target, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) or die "✖ 无法只读打开文件：$!\n";
binmode $file;
my @metadata = stat($file);
die "✖ 已打开的目标不是普通文件。\n" unless @metadata && S_ISREG($metadata[2]);
my $size = $metadata[7];
print '文件：', safe_text(decode('UTF-8', $target, FB_DEFAULT), 1), "\n";
print "大小：$size 字节；确认阈值：$limit 字节\n";
if ($size > $limit) {
    exit 0 unless confirm('⚠ 文件超过确认阈值，继续可能需要较长时间并产生大量终端输出。');
}
my $sample_count = read($file, my $sample, $size < 8192 ? $size : 8192);
die "✖ 无法读取文件样本：$!\n" unless defined $sample_count;
seek($file, 0, 0) or die "✖ 无法复位文件读取位置：$!\n";
my $is_text = !$size || sample_is_text($sample, $sample_count >= $size);
if (!$is_text) {
    exit 0 unless confirm('⚠ 文件样本属于二进制或未知编码，继续将按十六进制显示。');
}
print $is_text ? "──── 文件内容（控制字符转义显示）────\n" : "──── 文件内容（十六进制）────\n";
my $remaining = $size;
my $pending = '';
my $offset = 0;
while ($remaining > 0) {
    my $count = read($file, my $chunk, $remaining < 8192 ? $remaining : 8192);
    die "✖ 读取文件失败：$!\n" unless defined $count;
    last unless $count;
    $remaining -= $count;
    if ($is_text) {
        my $bytes = $pending . $chunk;
        $pending = take_utf8_tail(\$bytes);
        print safe_text(decode('UTF-8', $bytes, FB_DEFAULT), 0);
    } else {
        for (my $index = 0; $index < length($chunk); $index += 16) {
            my $line = substr($chunk, $index, 16);
            my $hex = join(' ', map { sprintf('%02x', $_) } unpack('C*', $line));
            $line =~ s/[^\x20-\x7e]/./g;
            printf "%08x  %-47s  |%s|\n", $offset, $hex, $line;
            $offset += length($line);
        }
    }
}
print safe_text(decode('UTF-8', $pending, FB_DEFAULT), 0) if $is_text && length($pending);
print "\n──── 查看结束；最多读取打开时的 $size 字节 ────\n";
close $file or die "✖ 关闭文件失败：$!\n";
PERL
}

main() {
  show_file_content_intro
  setopt NO_NOMATCH PIPE_FAIL
  [[ -x /usr/bin/perl && -x /usr/bin/file ]] || { print -u2 -r -- '✖ 缺少系统 Perl 或 file 工具，已停止。'; return 1; }
  file_content_run "$@"
}

main "$@"
