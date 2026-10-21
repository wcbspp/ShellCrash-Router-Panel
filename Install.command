#!/bin/sh
cd -- "$(dirname -- "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
 printf '%s\n' '电脑未找到 Python 3。请先从 https://www.python.org/downloads/ 安装 Python 3.9 或更新版本。'
 result=1
else
 python3 start.py "$@"
 result=$?
fi
printf '\n按回车关闭窗口。'
read -r answer
exit "$result"
