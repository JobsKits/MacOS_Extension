"""Jobs 测试专用源码定位；发布夹具仍保留原平铺资源名。"""

from pathlib import Path
import re

def source_script(path):
    """优先接受发布文件，仅对缺失路径尝试明确的源码同名包装。"""
    path = Path(path)
    if path.is_file() and not path.is_symlink():
        return path
    names = [path.name]
    if path.suffix in {".zsh", ".command", ".sh"} and not path.name.startswith("【MacOS"):
        names.append(("【MacOS@Xcode】" if path.name == "EnableFinderExtension.zsh" else "【MacOS】") + path.name)
    candidates = [path.parent / name / name for name in names]
    matches = [p for p in candidates if p.is_file() and not p.is_symlink() and not p.parent.is_symlink()]
    if len(matches) != 1:
        raise FileNotFoundError(f"无法唯一定位源码：{path}；候选：{matches}")
    return matches[0]

def shell_library(source):
    """只剥离文件末尾的入口调用，避免测试 source 时执行安装器。"""
    calls = list(re.finditer(r'(?m)^(?:main|manager_main) "\$@"[^\n]*$', source))
    if not calls or source[calls[-1].end():].strip():
        raise ValueError("缺少可验证的文件末尾入口调用")
    return source[:calls[-1].start()]
