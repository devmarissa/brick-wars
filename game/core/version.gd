class_name CoreVersion
extends RefCounted
## What core calls itself, so a pack can say which core it was built against.
##
## Every `pack.json` carries `core_version` as a semver range (`FORMAT-SPEC` §9, §11), and
## a range is worth nothing without a number to test it against. This is that number.
##
## The scheme: `0.<milestone>.<fix>`. C0 was 0.0, this is C1, and 1.0.0 is the first
## version core promises not to break. Tying it to the build order rather than to a release
## calendar means a pack author who reads "requires core 0.4" can look at BUILD-ORDER.md
## and know exactly which capabilities that implies, which is more use than a date.
##
## The minor number goes up when a milestone lands. It is the thing to remember to bump.

const VERSION := "0.1.0"

## The milestone this version corresponds to, for error messages that would otherwise be
## three digits and no context.
const MILESTONE := "C1"


## For messages: "core 0.1.0 (C1)".
static func described() -> String:
	return "core %s (%s)" % [VERSION, MILESTONE]
