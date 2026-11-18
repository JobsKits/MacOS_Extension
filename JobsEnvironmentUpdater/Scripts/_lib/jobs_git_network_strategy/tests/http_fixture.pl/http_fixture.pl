#!/usr/bin/perl
# 由 【MacOS】integration.zsh/【MacOS】integration.zsh 启动的离线 HTTP 代理夹具：监听 loopback，转给临时仓库的 Git CGI。
# 它不转发公网请求、不读取用户代理配置，端口和请求记录只写测试临时目录。
use strict;
use warnings;
use IO::Socket::INET;
use IPC::Open3;
use Symbol qw(gensym);

my ($repository_root, $ports_file, $requests_file) = @ARGV;
die "fixture arguments missing\n" unless $requests_file && -d $repository_root;
my $listener = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1', LocalPort => 0,
    Listen => 8, ReuseAddr => 1, Proto => 'tcp',
) or die "cannot open loopback fixture\n";
my $unused = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp')
    or die "cannot reserve failed direct port\n";
my $direct_port = $unused->sockport;
close $unused;
open my $ports, '>', $ports_file or die "cannot write fixture ports\n";
print {$ports} $listener->sockport, "\n", $direct_port, "\n";
close $ports;
open my $requests, '>>', $requests_file or die "cannot write fixture requests\n";
select((select($requests), $| = 1)[0]);
$SIG{TERM} = sub { close $listener; exit 0; };

while (my $client = $listener->accept) {
    binmode $client;
    $client->autoflush(1);
    my $line = <$client>;
    unless (defined $line && $line =~ m{^([A-Z]+)\s+(\S+)\s+HTTP/1\.[01]}) {
        close $client;
        next;
    }
    my ($method, $target) = ($1, $2);
    my %headers;
    while (defined(my $header = <$client>)) {
        last if $header =~ /^\r?\n$/;
        if ($header =~ /^([^:]+):\s*(.*?)\r?\n$/) {
            $headers{lc $1} = $2;
        }
    }
    $target =~ s{^http://[^/]+}{};
    my ($path, $query) = split /\?/, $target, 2;
    print {$requests} "$method $path\n";
    if ($method eq 'HEAD' && $path eq '/') {
        print {$client} "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        close $client;
        next;
    }
    if (($headers{'transfer-encoding'} // '') ne '' || $path !~ m{^/remote\.git/}) {
        print {$client} "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        close $client;
        next;
    }
    print {$client} "HTTP/1.1 100 Continue\r\n\r\n" if ($headers{'expect'} // '') =~ /100-continue/i;
    my $length = $headers{'content-length'} // 0;
    my $body = '';
    while (length($body) < $length) {
        my $received = read $client, my $chunk, $length - length($body);
        last unless $received;
        $body .= $chunk;
    }
    local $ENV{GIT_PROJECT_ROOT} = $repository_root;
    local $ENV{GIT_HTTP_EXPORT_ALL} = '1';
    local $ENV{REMOTE_USER} = 'JobsFixture';
    local $ENV{REQUEST_METHOD} = $method;
    local $ENV{PATH_INFO} = $path;
    local $ENV{QUERY_STRING} = $query // '';
    local $ENV{CONTENT_TYPE} = $headers{'content-type'} // '';
    local $ENV{CONTENT_LENGTH} = $length;
    local $ENV{HTTP_GIT_PROTOCOL} = $headers{'git-protocol'} // '';
    my $error = gensym;
    my $pid = open3(my $input, my $output, $error, '/usr/bin/git', 'http-backend');
    binmode $input;
    binmode $output;
    print {$input} $body;
    close $input;
    my $response = do { local $/; <$output> } // '';
    my $errors = do { local $/; <$error> } // '';
    close $output;
    close $error;
    waitpid $pid, 0;
    my ($response_headers, $response_body) = split /\r?\n\r?\n/, $response, 2;
    $response_headers //= '';
    $response_body //= '';
    my $status = '200 OK';
    $status = $1 if $response_headers =~ s/^Status:\s*([^\r\n]+)\r?\n?//m;
    $response_headers =~ s/\r?\n/\r\n/g;
    print {$client} "HTTP/1.1 $status\r\n$response_headers\r\nContent-Length: ", length($response_body), "\r\nConnection: close\r\n\r\n$response_body";
    close $client;
}
