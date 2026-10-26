APP_NAME := PicPress
BUILD    := .build
DIST     := dist

.PHONY: all app cli icon test snapshot run dmg clean help

all: app ## 构建 App 和 CLI

app: ## 构建 dist/PicPress.app
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

dmg: app ## 打包成 dist/PicPress.dmg
	@rm -rf "$(BUILD)/dmg" && mkdir -p "$(BUILD)/dmg"
	@cp -R "$(DIST)/$(APP_NAME).app" "$(BUILD)/dmg/"
	@ln -s /Applications "$(BUILD)/dmg/Applications"
	@hdiutil create -quiet -volname "$(APP_NAME)" -srcfolder "$(BUILD)/dmg" \
		-ov -format UDZO "$(DIST)/$(APP_NAME).dmg"
	@echo "✓ $(DIST)/$(APP_NAME).dmg"

clean: ## 清理构建产物
	@rm -rf "$(BUILD)" "$(DIST)"
	@echo "✓ cleaned"

help: ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
