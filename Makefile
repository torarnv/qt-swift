export CONFIGURATION ?= debug

build:
	@swift build -c $$CONFIGURATION

check:
	@swift test -c $$CONFIGURATION

lint:
	@swift format lint --recursive .
	@swiftlint

format:
	@swift format format --in-place --recursive .
	@swiftlint --fix
