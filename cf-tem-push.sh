#!/bin/bash

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== 子仓库(cloudflare)自动上传代码脚本 (SSH模式) ===${NC}"

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

# 3. 检查 .gitignore（关键修改：删除父仓库的忽略项）
if [ ! -f ".gitignore" ]; then
    echo -e "${RED}警告: 未找到 .gitignore 文件！建议先创建以避免上传垃圾文件。${NC}"
    echo -e "${YELLOW}正在尝试创建默认 .gitignore...${NC}"
    echo "node_modules/" >> .gitignore
    echo "dist/" >> .gitignore
    echo "*.log" >> .gitignore
    # 删掉原脚本的 docker-manager-backend（子仓库无需忽略这个）
    # 可根据子仓库需求添加忽略项，比如：echo "temp/" >> .gitignore
fi

# 4. 添加文件并提交
echo -e "${YELLOW}正在添加文件到暂存区...${NC}"
git add .

status=$(git status --porcelain)
if [ -z "$status" ]; then
    echo -e "${GREEN}没有检测到新的更改，无需提交。${NC}"
else
    echo -e "${YELLOW}正在提交更改...${NC}"
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    git commit -m "Auto backup (cloudflare): $timestamp"  # 备注加子仓库标识，便于区分
    echo -e "${GREEN}本地提交完成。${NC}"
fi

# 5. 配置远程仓库 (自动转换为 SSH)
current_remote=$(git remote get-url origin 2>/dev/null)

# 关键：确认 SSH_KEY_PATH 与父仓库一致（父仓库能用，说明这个路径是对的）
SSH_KEY_PATH="$HOME/.ssh/github/id_rsa"

if [ -f "$SSH_KEY_PATH" ]; then
    echo -e "${GREEN}检测到 SSH Key: $SSH_KEY_PATH${NC}"
    # 设置 GIT_SSH_COMMAND 环境变量，指定 key 文件
    export GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
else
    echo -e "${RED}警告: 未找到 SSH Key ($SSH_KEY_PATH)，将使用默认 SSH 配置。${NC}"
fi

if [ -z "$current_remote" ]; then
    echo -e "${YELLOW}未配置远程仓库 (origin)。${NC}"
    echo -e "请输入您的 GitHub 子仓库地址 (格式: git@github.com:user/子仓库名.git)"
    read -p "地址: " repo_url
    
    if [ -n "$repo_url" ]; then
        git remote add origin "$repo_url"
        echo -e "${GREEN}已添加远程仓库: $repo_url${NC}"
    else
        echo -e "${RED}未输入地址，跳过推送步骤。${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}当前远程仓库: $current_remote${NC}"
    # 检查是否为 HTTPS，如果是则尝试转换为 SSH
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
    
    # 检查是否因为远程有更新
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