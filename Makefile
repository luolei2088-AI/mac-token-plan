APP_NAME = mac-token-plan
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: run build release app clean

run:
	swift run

build:
	swift build

release:
	swift build -c release

app: release
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
