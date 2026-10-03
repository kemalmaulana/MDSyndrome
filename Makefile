PROJECT     := MDSyndrome.xcodeproj
SCHEME      := MDSyndrome
DERIVED     := build/DerivedData
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: gen build test test-core test-app test-ui run lint clean

gen:
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) build

test-core:
	swift test --package-path Packages/MDKit

test-app: gen
	$(XCODEBUILD) -only-testing:MDSyndromeTests test

# Drives the real app: takes over keyboard and mouse for about a minute.
test-ui: gen
	$(XCODEBUILD) -only-testing:MDSyndromeUITests test

test: lint test-core test-app

run: build
	open $(DERIVED)/Build/Products/Debug/MDSyndrome.app

# PRD NF-1: only WebRenderKit may import WebKit.
lint:
	@! grep -rl --include='*.swift' -E '^import WebKit' MDSyndrome Packages/MDKit/Sources | grep -v '/WebRenderKit/' || (echo "error: WebKit imported outside WebRenderKit" && false)

clean:
	rm -rf build $(PROJECT) Packages/MDKit/.build
