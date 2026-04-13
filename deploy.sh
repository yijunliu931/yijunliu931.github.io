#!/bin/bash
# ============================================
# Yijun's Portfolio - GitHub Pages 一键部署脚本
# ============================================
# 使用方法：
#   1. 确保你已安装 git 并登录了 GitHub
#   2. 在终端中 cd 到这个文件夹
#   3. 运行: chmod +x deploy.sh && ./deploy.sh
# ============================================

set -e

REPO_NAME="yijunliu.github.io"
GITHUB_USER=""

echo ""
echo "🚀 Yijun's Portfolio - GitHub Pages 部署工具"
echo "============================================="
echo ""

# 获取 GitHub 用户名
read -p "请输入你的 GitHub 用户名: " GITHUB_USER

if [ -z "$GITHUB_USER" ]; then
    echo "❌ 用户名不能为空"
    exit 1
fi

REPO_NAME="${GITHUB_USER}.github.io"

echo ""
echo "📋 部署信息:"
echo "   仓库名: ${REPO_NAME}"
echo "   网址:   https://${REPO_NAME}"
echo ""
read -p "确认部署？(y/n): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "已取消"
    exit 0
fi

# 检查是否已经是 git 仓库
if [ -d ".git" ]; then
    echo "⚠️  检测到已有 git 仓库，将直接推送更新..."
else
    echo "📁 初始化 Git 仓库..."
    git init
    git branch -M main
fi

# 添加并提交文件
echo "📦 添加文件..."
git add index.html
git commit -m "Deploy portfolio site" 2>/dev/null || echo "   (没有新的更改需要提交)"

# 设置远程仓库
if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
else
    git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
fi

echo ""
echo "⚠️  接下来需要你在 GitHub 上创建仓库（如果还没有的话）:"
echo ""
echo "   1. 打开 https://github.com/new"
echo "   2. Repository name 填: ${REPO_NAME}"
echo "   3. 选择 Public"
echo "   4. 不要勾选 Add README"
echo "   5. 点击 Create repository"
echo ""
read -p "创建好了？按 Enter 继续推送..."

echo "🚀 推送到 GitHub..."
git push -u origin main

echo ""
echo "✅ 部署完成！"
echo ""
echo "🌐 你的网站将在 1-2 分钟内上线:"
echo "   https://${GITHUB_USER}.github.io"
echo ""
echo "💡 以后更新网站只需要:"
echo "   git add . && git commit -m '更新内容' && git push"
echo ""
