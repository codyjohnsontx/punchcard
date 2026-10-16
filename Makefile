.PHONY: build test app run zip clean

# With only the Command Line Tools, SwiftPM passes the directory holding
# Testing.framework as -I instead of -F and adds no rpath, so plain `swift test`
# cannot import Swift Testing and runs nothing. Add the missing flags there.
CLT := /Library/Developer/CommandLineTools
CLT_FRAMEWORKS := $(CLT)/Library/Developer/Frameworks
TEST_FLAGS := $(if $(filter $(CLT)/%,$(shell xcrun --show-sdk-path 2>/dev/null)),-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS))

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	scripts/build-app.sh

run:
	swift run Punchcard

zip:
	scripts/build-app.sh --zip

clean:
	rm -rf .build dist
