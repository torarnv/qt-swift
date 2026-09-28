build:
	@swift build

check:
	@swift test

lint:
	@swift format lint --recursive .
	@swiftlint

format:
	@swift format format --in-place --recursive .
	@swiftlint --fix
