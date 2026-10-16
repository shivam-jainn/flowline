# StepIt developer entry points. Run `make` for the default target (build).
.PHONY: all build test check-arch serve demo automate bundle dmg clean

all: build

build:
	swift build

test:
	swift test

check-arch:
	Scripts/ci/check_architecture.sh

serve:
	swift run stepit serve

demo:
	swift run stepit demo

automate:
	swift run stepit automate

bundle:
	Scripts/release/bundle_app.sh

dmg:
	Scripts/release/create_dmg.sh

clean:
	rm -rf .build dist
