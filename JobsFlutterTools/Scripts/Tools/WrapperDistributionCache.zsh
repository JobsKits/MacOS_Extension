#!/bin/zsh
# 只供 source：将可信 Gradle ZIP 预置到真实 Wrapper 缓存；不伪造 .ok 或执行项目脚本。
# 路径算法依据 Gradle PathAssembler：固定发行包名 / URL 的 MD5 无符号整数 base36。
# https://github.com/gradle/gradle/blob/master/platforms/core-runtime/wrapper-shared/src/main/java/org/gradle/wrapper/PathAssembler.java

typeset -g WD_ZIP_PATH="" WD_DISTRIBUTION_PATH="" WD_URL_HASH=""
# 使用系统核心模块复现 Wrapper 的 URL 散列，不把 MD5 当作内容校验。
wd_url_hash() {
    /usr/bin/perl -MDigest::MD5=md5_hex -MMath::BigInt -e '
        my $v=Math::BigInt->from_hex("0x".md5_hex($ARGV[0]));
        my $out=""; my @alphabet=(0..9,"a".."z");
        while (!$v->is_zero()) { my $r=$v->copy()->bmod(36)->numify(); $out=$alphabet[$r].$out; $v->bdiv(36); }
        print length($out) ? $out : "0";
    ' "$1"
}
# 只允许 Wrapper 的两个已知基准和安全相对目录，不猜测特殊属性语法。
wd_resolve_layout() {
    local project="$1" url="$2" wrapper="$1/android/gradle/wrapper/gradle-wrapper.properties"
    local rows="" configured_url="" key="" value="" base="" segment="" root="" gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
    local distribution_base=GRADLE_USER_HOME distribution_path=wrapper/dists zip_base=GRADLE_USER_HOME zip_path=wrapper/dists
    [[ "$project" == /* && -f "$wrapper" && ! -L "$wrapper" ]] || return 1
    [[ "$url" =~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._~/%+-]+$' ]] || { pe_log '✖ Wrapper缓存只支持无凭据的ASCII HTTPS固定URL。'; return 1; }
    [[ "$gradle_home" == /* && ! -L "${gradle_home%/}" ]] || { pe_log '✖ GRADLE_USER_HOME须为绝对普通目录路径，不能是链接。'; return 1; }
    for value in "${GRADLE_OPTS:-}" "${JAVA_OPTS:-}" "${JAVA_TOOL_OPTIONS:-}" "${JDK_JAVA_OPTIONS:-}" "${_JAVA_OPTIONS:-}"; do
        [[ "$value" != *'-Dgradle.user.home'* && "$value" != *'-Duser.home'* ]] || { pe_log '✖ JVM参数另行覆盖Gradle缓存基准，请先移除本次冲突参数；未猜测缓存位置。'; return 1; }
    done
    rows="$(/usr/bin/perl -ne '
        s/\r?\n$//; next if /^\s*[#!]/;
        if (/^\s*(distributionUrl|distributionBase|distributionPath|zipStoreBase|zipStorePath)\s*[=:]\s*(.*?)\s*$/) {
            die "duplicate wrapper cache key\n" if $seen{$1}++; my ($key,$value)=($1,$2); $value =~ s/\\:/:/g if $key eq "distributionUrl"; print "$key\t$value\n";
        }
    ' "$wrapper")" || return 1
    if [[ -n "$rows" ]]; then
        while IFS=$'\t' read -r key value; do
            case "$key" in
                distributionUrl) configured_url="$value" ;;
                distributionBase) distribution_base="$value" ;;
                distributionPath) distribution_path="$value" ;;
                zipStoreBase) zip_base="$value" ;;
                zipStorePath) zip_path="$value" ;;
            esac
        done <<< "$rows"
    fi
    [[ "$configured_url" == "$url" ]] || { pe_log '✖ Wrapper URL在准备期间变化或无法解析，未写入缓存。'; return 1; }
    for base in "$distribution_base" "$zip_base"; do
        [[ "$base" == GRADLE_USER_HOME || "$base" == PROJECT ]] || { pe_log "✖ 不支持Wrapper缓存基准：$base；未写入缓存。"; return 1; }
    done
    for value in "$distribution_path" "$zip_path"; do
        [[ "$value" =~ '^[A-Za-z0-9_. /-]+$' && "$value" != /* && "$value" != */ && "$value" != *'//'* ]] || { pe_log '✖ Wrapper缓存目录须为普通相对路径；特殊转义/变量/绝对路径需人工处理。'; return 1; }
        for segment in "${(@s:/:)value}"; do
            [[ -n "$segment" && "$segment" != . && "$segment" != .. ]] || { pe_log '✖ Wrapper缓存相对目录含越界/空段，已停止。'; return 1; }
        done
    done
    WD_URL_HASH="$(wd_url_hash "$url")" || return 1
    [[ "$WD_URL_HASH" =~ '^[0-9a-z]+$' ]] || return 1
    root="${url:t:r}/$WD_URL_HASH"
    [[ "$distribution_base" != PROJECT ]] || base="$project/android"
    [[ "$distribution_base" != GRADLE_USER_HOME ]] || base="$gradle_home"
    WD_DISTRIBUTION_PATH="$base/$distribution_path/$root"
    [[ "$zip_base" != PROJECT ]] || base="$project/android"
    [[ "$zip_base" != GRADLE_USER_HOME ]] || base="$gradle_home"
    WD_ZIP_PATH="$base/$zip_path/$root/${url:t}"
    # 固定本次Wrapper进程的缓存根，避免Java默认user.home与Shell HOME差异。
    export GRADLE_USER_HOME="$gradle_home"
}
# 编译最小本机助手，用与 Wrapper 相同的 Java FileLock 互斥，避免另一构建的在途缓存被覆盖。
wd_write_locked_zip() {
    local java_home="$1" archive="$2" sha="$3" helper=""
    [[ -x "$java_home/bin/java" && -x "$java_home/bin/javac" ]] || return 1
    helper="$(/usr/bin/mktemp -d "$PE_RUN_DIR/wrapper-cache-helper.XXXXXX")" || return 1
    /bin/cat > "$helper/JobsWrapperCache.java" <<'JAVA'
import java.io.*;
import java.nio.channels.*;
import java.nio.file.*;
import java.security.*;
import static java.nio.file.LinkOption.NOFOLLOW_LINKS;
public final class JobsWrapperCache {
    static void regular(Path p) throws Exception {
        if (!Files.isRegularFile(p, NOFOLLOW_LINKS) || ((Number)Files.getAttribute(p,"unix:nlink",NOFOLLOW_LINKS)).intValue()!=1) throw new IOException("Not a regular single-link cache file: "+p);
    }
    static String hash(Path p) throws Exception {
        regular(p); MessageDigest d=MessageDigest.getInstance("SHA-256");
        try (InputStream in=Files.newInputStream(p)) { byte[] b=new byte[65536]; int n; while ((n=in.read(b))!=-1) d.update(b,0,n); }
        StringBuilder out=new StringBuilder(); for(byte b:d.digest()) out.append(String.format("%02x",b&255)); return out.toString();
    }
    static void parents(Path p) throws Exception {
        Path current=p.getRoot();
        for(Path part:p) { current=current.resolve(part); if(Files.exists(current,NOFOLLOW_LINKS)) { if(!Files.isDirectory(current,NOFOLLOW_LINKS)) throw new IOException("Cache parent is not a plain directory: "+current); } else Files.createDirectory(current); }
    }
    public static void main(String[] args) throws Exception {
        Path source=Paths.get(args[0]), target=Paths.get(args[1]), distribution=Paths.get(args[3]); String expected=args[2];
        if(!hash(source).equals(expected)) throw new IOException("Source ZIP SHA256 changed");
        parents(target.getParent()); parents(distribution);
        Path lock=Paths.get(target+".lck"), partial=Paths.get(target+".part"), marker=Paths.get(target+".ok");
        if(Files.exists(lock,NOFOLLOW_LINKS)) regular(lock);
        try(FileChannel channel=FileChannel.open(lock,StandardOpenOption.CREATE,StandardOpenOption.WRITE,NOFOLLOW_LINKS)) {
            regular(lock); FileLock lease=channel.tryLock(); if(lease==null) throw new IOException("Wrapper cache is currently locked by another build");
            try {
                if(Files.exists(marker,NOFOLLOW_LINKS)) { regular(marker); System.out.println("Wrapper marker exists; keeping a verified ZIP for recovery if extracted files are damaged: "+distribution); }
                if(Files.exists(partial,NOFOLLOW_LINKS)) throw new IOException("Wrapper has an in-progress or interrupted .part; preserving it: "+partial);
                if(Files.exists(target,NOFOLLOW_LINKS)) { if(!hash(target).equals(expected)) throw new IOException("Existing Wrapper ZIP checksum differs; preserving it: "+target); System.out.println("Reusing verified Wrapper ZIP: "+target); return; }
                Path staging=Files.createTempFile(target.getParent(),".jobs-gradle-",".tmp");
                try { Files.copy(source,staging,StandardCopyOption.REPLACE_EXISTING); if(!hash(staging).equals(expected)) throw new IOException("Staged ZIP checksum mismatch"); Files.move(staging,target); }
                finally { Files.deleteIfExists(staging); }
                System.out.println("Published verified ZIP to actual Wrapper cache: "+target);
            } finally { lease.release(); }
        }
    }
}
JAVA
    pe_run_logged "$java_home/bin/javac" -d "$helper" "$helper/JobsWrapperCache.java" || return $?
    pe_run_logged "$java_home/bin/java" -cp "$helper" JobsWrapperCache "$archive" "$WD_ZIP_PATH" "$sha" "$WD_DISTRIBUTION_PATH"
}
# 预置实际 Wrapper ZIP；调用方随后以选定Java有界运行项目Wrapper --version完成校验解压。
wd_prepare_zip() {
    local project="$1" url="$2" sha="$3" archive="$4" java_home="$5"
    [[ "$sha" =~ '^[0-9a-fA-F]{64}$' && -f "$archive" && ! -L "$archive" && -n "$PE_RUN_DIR" ]] || return 1
    [[ -f "$project/android/gradle/wrapper/gradle-wrapper.jar" && ! -L "$project/android/gradle/wrapper/gradle-wrapper.jar" ]] || { pe_log '✖ 缺少普通gradle-wrapper.jar，无法验证后续项目Wrapper复用；请先恢复项目Wrapper文件。'; return 1; }
    wd_resolve_layout "$project" "$url" || return $?
    pe_log "➤ 实际Wrapper ZIP：$WD_ZIP_PATH；解压目标：$WD_DISTRIBUTION_PATH；不伪造.ok。"
    wd_write_locked_zip "$java_home" "$archive" "${sha:l}"
}
