APP_NAME := PicPress
BUILD    := .build
DIST     := dist

.PHONY: all app cli icon test snapshot run sign cert dmg notarize release doctor clean help

all: app ## 构建 App 和 CLI（自动签名）

app: ## 构建 dist/PicPress.app（自动用最合适的证书签名）
	@./scripts/build.sh

cli: app ## 同 app（CLI 一起构建）

icon: ## 重新生成 Resources/AppIcon.icns
	@./scripts/make-icon.sh

test: ## 运行集成测试
	@./scripts/test.sh

snapshot: ## 把主窗口离屏渲染成 PNG（检查界面用）
	@./scripts/snapshot.sh

run: app ## 构建并打开 App
	@open "$(DIST)/$(APP_NAME).app"

sign: app ## 重新签名现有构建并打印 Gatekeeper 结论
	@./scripts/sign.sh

cert: ## 没有 Apple 开发者证书时，生成本机自签名证书（身份稳定）
	@./scripts/make-cert.sh

dmg: app ## 打包成 dist/PicPress.dmg（含签名）
	@./scripts/package.sh

notarize: ## 公证 App 和 DMG（需要 Developer ID 证书 + 凭据）
	@./scripts/notarize.sh

release: app ## 签名 + 公证 + 钉票据，产出任何人都能直接打开的 dmg
	@./scripts/notarize.sh

doctor: ## 体检：签名身份、Hardened Runtime、Gatekeeper、隐私授权
	@./scripts/doctor.sh

clean: ## 清理构建产物
	@rm -rf "$(BUILD)" "$(DIST)"
	@echo "✓ cleaned"

help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
