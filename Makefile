PROJECT     := MDSyndrome.xcodeproj
SCHEME      := MDSyndrome
DERIVED     := build/DerivedData
XCODEBUILD  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.PHONY: gen build test test-core test-app test-ui run lint clean dist perf

gen:
	xcodegen generate --quiet

build: gen
	$(XCODEBUILD) build

test-core:
	swift test --package-path Packages/MDKit

# xcodebuild does not pass its environment to the test host; TEST_RUNNER_ variables are the way in.
# Tests that must not run on CI read CI.
test-app: gen
	$(if $(CI),TEST_RUNNER_CI=$(CI) ,)$(XCODEBUILD) -only-testing:MDSyndromeTests test

# Drives the real app: takes over keyboard and mouse for about a minute.
test-ui: gen
	$(XCODEBUILD) -only-testing:MDSyndromeUITests test

test: lint test-core test-app

run: build
	open $(DERIVED)/Build/Products/Debug/MDSyndrome.app

# PRD NF-1: only WebRenderKit may import WebKit.
lint:
	@! grep -rlE --include='*.swift' '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*((public|package|internal|fileprivate|private)[[:space:]]+)?import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?WebKit([.[:space:]]|$$)' MDSyndrome Packages/MDKit/Sources | grep -v '/WebRenderKit/' || (echo "error: WebKit imported outside WebRenderKit" && false)

# Prints the parse time for a 1 MB document (NF-4), then the launch, idle CPU and memory sampler (NF-2, NF-5; needs `make build`).
perf:
	PERF=1 swift test -c release -Xswiftc -enable-testing --package-path Packages/MDKit --filter PerformanceReportTests 2>&1 | grep -E "PERF|error:"
	scripts/measure-launch.sh

# Universal Release build packaged as dist/MDSyndrome-<version>-macOS.zip + .dmg + SHA256SUMS.txt
#   make dist VERSION=1.2.3 [BUILD=42]
dist:
	scripts/package-release.sh $(or $(VERSION),0.0.0-dev) $(or $(BUILD),1)

clean:
	rm -rf build dist $(PROJECT) Packages/MDKit/.build
