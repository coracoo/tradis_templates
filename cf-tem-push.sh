#!/bin/bash

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 子仓库(cloudflare)自动上传代码脚本 (SSH模式) ===${NC}"

# 0. 读取外部传入配置（用于后端自动化调用，避免交互）
GIT_SYNC_REPO_URL="${GIT_SYNC_REPO_URL:-}"
GIT_SYNC_COMMIT_MESSAGE="${GIT_SYNC_COMMIT_MESSAGE:-}"

# 1. 检查 git 环境
if ! command -v git &> /dev/null; then
    echo -e "${RED}错误: 未找到 git 命令，请先安装 git。${NC}"
    exit 1
fi

# 2. 初始化/检查仓库
if [ ! -d ".git" ]; then
    echo -e "${YELLOW}正在初始化 git 仓库...${NC}"
    git init
    git branch -M main
else
    echo -e "${GREEN}Git 仓库已存在。${NC}"
fi

# 3. 检查 .gitignore
if [ ! -f ".gitignore" ]; then
    echo -e "${RED}警告: 未找到 .gitignore 文件！建议先创建以避免上传垃圾文件。${NC}"
    echo -e "${YELLOW}正在尝试创建默认 .gitignore...${NC}"
    echo "node_modules/" >> .gitignore
    echo "dist/" >> .gitignore
    echo "*.log" >> .gitignore
fi

# 4. 添加文件并提交
echo -e "${YELLOW}正在添加文件到暂存区...${NC}"
git add .

status=$(git status --porcelain)
if [ -z "$status" ]; then
    echo -e "${GREEN}没有检测到新的更改，无需提交。${NC}"
else
    echo -e "${YELLOW}正在提交更改...${NC}"
    if [ -n "$GIT_SYNC_COMMIT_MESSAGE" ]; then
        mapfile -t _commit_lines <<< "$GIT_SYNC_COMMIT_MESSAGE"
        commit_args=()
        for _line in "${_commit_lines[@]}"; do
            _line="$(echo -n "$_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            if [ -n "$_line" ]; then
                commit_args+=(-m "$_line")
            fi
        done
        if [ ${#commit_args[@]} -eq 0 ]; then
            timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            git commit -m "Auto backup (cloudflare): $timestamp"
        else
            git commit "${commit_args[@]}"
        fi
    else
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        git commit -m "Auto backup (cloudflare): $timestamp"  # 备注加子仓库标识，便于区分
    fi
    echo -e "${GREEN}本地提交完成。${NC}"
fi

# 5. 配置远程仓库
current_remote=$(git remote get-url origin 2>/dev/null)
SSH_KEY_PATH="$HOME/.ssh/github/id_rsa"

if [ -f "$SSH_KEY_PATH" ]; then
    echo -e "${GREEN}检测到 SSH Key: $SSH_KEY_PATH${NC}"
    export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
else
    echo -e "${RED}警告: 未找到 SSH Key ($SSH_KEY_PATH)，将使用默认 SSH 配置。${NC}"
fi

if [ -z "$current_remote" ]; then
    echo -e "${YELLOW}未配置远程仓库 (origin)。${NC}"
    if [ -n "$GIT_SYNC_REPO_URL" ]; then
        git remote add origin "$GIT_SYNC_REPO_URL"
        echo -e "${GREEN}已添加远程仓库: $GIT_SYNC_REPO_URL${NC}"
    else
        echo -e "${RED}错误: 未提供远程仓库地址。请设置环境变量 GIT_SYNC_REPO_URL。${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}当前远程仓库: $current_remote${NC}"
    if [ -n "$GIT_SYNC_REPO_URL" ] && [ "$current_remote" != "$GIT_SYNC_REPO_URL" ]; then
        echo -e "${YELLOW}检测到指定远程仓库地址，正在更新 origin...${NC}"
        git remote set-url origin "$GIT_SYNC_REPO_URL"
        current_remote="$GIT_SYNC_REPO_URL"
        echo -e "${GREEN}origin 已更新为: $current_remote${NC}"
    fi
    if [[ "$current_remote" == https://* ]]; then
        echo -e "${YELLOW}检测到 HTTPS 协议，正在转换为 SSH 协议...${NC}"
        clean_url=$(echo "$current_remote" | sed -E 's/https?:\/\/(.*@)?//')
        ssh_url="git@${clean_url/\//:}"
        git remote set-url origin "$ssh_url"
        echo -e "${GREEN}已转换为 SSH 地址: $ssh_url${NC}"
    fi
fi

# 6. 推送代码
echo -e "${YELLOW}正在尝试通过 SSH 推送代码...${NC}"

if git push -u origin main; then
    echo -e "${GREEN}✅ 子仓库代码上传成功！${NC}"
    exit 0
else
    echo -e "${RED}❌ 推送失败。${NC}"
    echo -e "${YELLOW}=== 故障排查 ===${NC}"
    
    echo -e "${YELLOW}尝试拉取远程更改并变基 (git pull --rebase)...${NC}"
    if git pull origin main --rebase; then
        echo -e "${GREEN}合并成功，正在重试推送...${NC}"
        if git push -u origin main; then
            echo -e "${GREEN}✅ 子仓库代码上传成功！${NC}"
            exit 0
        fi
    else
        echo -e "${RED}自动合并失败。请手动解决冲突或检查 SSH 权限。${NC}"
        echo -e "提示: 确保您的公钥已添加到 GitHub 仓库的 Deploy Keys 或个人 SSH Keys 中。"
        if [ -f "${SSH_KEY_PATH}.pub" ]; then
             echo -e "公钥内容 ($SSH_KEY_PATH.pub):"
             cat "${SSH_KEY_PATH}.pub"
        fi
        exit 1
    fi
fi
