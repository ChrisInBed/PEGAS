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

// triggerEventId is provided by configure_booster_core_stages.
global triggerEventArmed is false.
global triggerEventTarget is 0.
global triggerBoosterEngines is list().

function triggerEventCondition {
	// 1. never fires
	// return False.

	// 2. fires when one of the engines labeled as "booster" lost all thrust
	if (not (defined liftoffTime)) return false.
	if (ship:status <> "FLYING" AND ship:status <> "SUB_ORBITAL" AND ship:status <> "ORBITING") return false.
	for e in triggerBoosterEngines {
		if e:thrust < 1e-3 { return true. }
	}
	return false.
}

function triggerEventImmediately {
	if not triggerEventArmed { return. }
	if not triggerEventCondition() { return. }
	local currentEventId to sequence:find(triggerEventTarget).
	if currentEventId > eventPointer {
		sequence:remove(currentEventId).
		set triggerEventTarget["time"] to time:seconds - liftoffTime:seconds.
		set triggerEventId to eventPointer + 1.
		sequence:insert(triggerEventId, triggerEventTarget).
		buildFlightPlan(not (defined upfgInternal)).
	}
	set triggerEventArmed to false.
}

if ((defined triggerEventId) AND (defined sequence) AND triggerEventId >= 0 AND triggerEventId < sequence:length) {
	set triggerEventTarget to sequence[triggerEventId].
	local allEngines to list().
	list engines in allEngines.
	for e in allEngines {
		if e:tag:contains("booster") { triggerBoosterEngines:add(e). }
	}
	set triggerEventArmed to triggerBoosterEngines:length > 0.
	registerHook(triggerEventImmediately@, "passivePre").
	registerHook(triggerEventImmediately@, "activePre").
}
