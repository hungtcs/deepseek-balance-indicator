UUID := deepseek-balance-indicator@hungtcs.dev
VERSION := $(shell sed -n 's/.*"version-name": "\(.*\)".*/\1/p' metadata.json)
DIST := dist
ZIP := $(DIST)/$(UUID).shell-extension.zip
DEV_DIR := $(DIST)/dev/$(UUID)
SCHEMA := schemas/org.gnome.shell.extensions.deepseek-balance-indicator.gschema.xml

.PHONY: all pack install uninstall enable disable prefs dev-bundle dev-session test test-shell check clean

all: pack

# 只把运行时需要的东西打进 zip：metadata.json、extension.js、prefs.js、
# stylesheet.css 和 --schema 都由 gnome-extensions pack 自动处理，
# 其余模块和图标通过 --extra-source 显式列出。
pack:
	rm -rf $(DIST)
	mkdir -p $(DIST)
	gnome-extensions pack --force --out-dir=$(DIST) \
		--extra-source=client.js \
		--extra-source=indicator.js \
		--extra-source=icons \
		--extra-source=stylesheet.css \
		--schema=$(SCHEMA) \
		.
	# GNOME Shell 50.5 的 gnome-extensions install 遇到 zip 里的目录条目会
	# 报 “Can’t recursively copy directory”。pack 生成的 zip 带目录条目，
	# 删掉后安装正常；schema 由安装器解压后自动编译。
	zip -qd $(ZIP) '*/'
	@echo "==> $(ZIP) (v$(VERSION))"

# 未打包的开发目录：dist/dev/<uuid>/，由 dev-session.sh 软链进临时数据目录。
# 和 zip 不同，它带编译好的 schema，直接给 GSettings / gsettings 用。
dev-bundle:
	rm -rf $(DEV_DIR)
	mkdir -p $(DEV_DIR)/schemas
	cp metadata.json extension.js prefs.js client.js indicator.js stylesheet.css $(DEV_DIR)/
	cp -r icons $(DEV_DIR)/
	cp $(SCHEMA) $(DEV_DIR)/schemas/
	glib-compile-schemas $(DEV_DIR)/schemas
	@echo "==> $(DEV_DIR)"

# 启动嵌套 GNOME Shell 窗口（--devkit），不影响当前登录的桌面设置。
dev-session: dev-bundle
	./dev-session.sh

install: pack
	gnome-extensions install --force $(ZIP)
	@echo "==> 已安装。若顶栏没有立即出现，注销重新登录后运行："
	@echo "    gnome-extensions enable $(UUID)"

uninstall:
	-gnome-extensions disable $(UUID)
	-gnome-extensions uninstall $(UUID)

enable:
	gnome-extensions enable $(UUID)

disable:
	gnome-extensions disable $(UUID)

prefs:
	gnome-extensions prefs $(UUID)

# 纯 JS 单元测试：不需要 Shell，也不需要显示器。
test:
	gjs -m tests/client.test.js

# 无头 GNOME Shell 内的集成测试：需要 gnome-shell-test-tool。
test-shell: pack
	./tests/run-shell-test.sh

check: test test-shell

clean:
	rm -rf $(DIST)
