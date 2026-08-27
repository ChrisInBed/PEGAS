declare global CoreThrottleDown to {
	local myengs to list().
	list engines in myengs.
	for e in myengs {
		if e:tag:contains("core") { set e:thrustlimit to CoreThrottleTarget. }
	}
}.
declare global CoreThrottleUp to {
	local myengs to list().
	list engines in myengs.
	for e in myengs {
		if e:tag:contains("core") { set e:thrustlimit to 100. }
	}
}.

declare global ShutEnginesDown to {
	local myengs to list().
	list engines in myengs.
	for e in myengs {
		if e:tag:contains("shutdown") { e:shutdown(). }
	}
}.

declare global delegateTable to lexicon(
    "CoreThrottleDown", CoreThrottleDown,
    "CoreThrottleUp", CoreThrottleUp,
	"ShutEnginesDown", ShutEnginesDown
).

for _s in sequence {
    if (_s["type"] = "delegate") {
        set _s["function"] to delegateTable[_s["function"]].
    }
}.