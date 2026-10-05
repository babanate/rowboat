# Rowboat developer tasks. Works with the Xcode command line tools alone.
TESTING_PLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
PLUGIN_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS),)

.PHONY: build test run app clean dump

build:
	swift build

test:
	swift test $(PLUGIN_FLAGS)

run: build
	.build/debug/Rowboat

app:
	scripts/build-app.sh

dump: build
	.build/debug/Rowboat --dump $(APP)

clean:
	rm -rf .build dist
