// Build the PEGAS logical stages for a booster-core vehicle whose core is
// throttled down before booster burnout. See architecture.md for the model.
//
// boosterInfo and coreInfo contain:
//   massWet, massDry, thrust, isp, throttleMinLevel
// eventInfo contains:
//   throttleDownTime, throttleDownLevel, glim1, glim2
FUNCTION make_throttle_stage_config {
	PARAMETER boosterInfo.
	PARAMETER coreInfo.
	PARAMETER eventInfo.
	PARAMETER payloadMass.

	LOCAL boosterWetMass IS boosterInfo["massWet"].
	LOCAL boosterDryMass IS boosterInfo["massDry"].
	LOCAL boosterThrust IS boosterInfo["thrust"].
	LOCAL boosterIsp IS boosterInfo["isp"].
	LOCAL boosterMinThrottle IS boosterInfo["throttleMinLevel"].

	LOCAL coreWetMass IS coreInfo["massWet"] + payloadMass.
	LOCAL coreDryMass IS coreInfo["massDry"] + payloadMass.
	LOCAL coreThrust IS coreInfo["thrust"].
	LOCAL coreIsp IS coreInfo["isp"].
	LOCAL coreMinThrottle IS coreInfo["throttleMinLevel"].

	LOCAL throttleDownTime IS eventInfo["throttleDownTime"].
	LOCAL throttleDownLevel IS eventInfo["throttleDownLevel"].
	LOCAL glim1 IS eventInfo["glim1"].
	LOCAL glim2 IS eventInfo["glim2"].

	LOCAL boosterExhaustVelocity IS boosterIsp * CONSTANT:g0.
	LOCAL coreExhaustVelocity IS coreIsp * CONSTANT:g0.
	LOCAL boosterFullFlow IS boosterThrust / boosterExhaustVelocity.
	LOCAL coreFullFlow IS coreThrust / coreExhaustVelocity.
	LOCAL unthrottledBoosterBurnoutTime IS
		(boosterWetMass - boosterDryMass) / boosterFullFlow.
	PRINT "[stage-utils] Building booster-core profile.".
	PRINT "[stage-utils] Full-thrust booster burnout: T+"
		+ ROUND(unthrottledBoosterBurnoutTime, 3) + " s".

	LOCAL throttledCoreThrust IS coreThrust * throttleDownLevel.
	LOCAL throttledStageMaxThrust IS boosterThrust + throttledCoreThrust.
	LOCAL throttledStageMinThrust IS
		boosterThrust * boosterMinThrottle
		+ coreThrust * coreMinThrottle.
	LOCAL throttledStageMinThrottle IS
		throttledStageMinThrust / throttledStageMaxThrust.

	LOCAL gstatus IS "ok".
	LOCAL jettisonTime IS 0.
	LOCAL coreMassAtJettison IS 0.
	LOCAL fullStageEndTime IS throttleDownTime.
	LOCAL throttleDownStageConfig IS LEXICON().

	IF unthrottledBoosterBurnoutTime <= throttleDownTime {
		// There is no core-throttled booster phase to describe.
		SET gstatus TO "no_core_throttling".
		PRINT "[stage-utils] Booster burnout precedes core throttle-down.".
		SET jettisonTime TO unthrottledBoosterBurnoutTime.
		SET fullStageEndTime TO jettisonTime.
		SET coreMassAtJettison TO coreWetMass - coreFullFlow * jettisonTime.
	} ELSE {
		PRINT "[stage-utils] Core throttle-down: T+"
			+ ROUND(throttleDownTime, 3) + " s at "
			+ ROUND(100 * throttleDownLevel, 3) + "%".
		LOCAL boosterMassAtThrottleDown IS
			boosterWetMass - boosterFullFlow * throttleDownTime.
		LOCAL coreMassAtThrottleDown IS
			coreWetMass - coreFullFlow * throttleDownTime.
		LOCAL totalMassAtThrottleDown IS
			boosterMassAtThrottleDown + coreMassAtThrottleDown.

		LOCAL throttledStageFullFlow IS
			boosterFullFlow + coreFullFlow * throttleDownLevel.
		LOCAL gLimitAcceleration IS glim1 * CONSTANT:g0.
		LOCAL gLimitStartMass IS throttledStageMaxThrust / gLimitAcceleration.
		LOCAL gLimitStartTime IS throttleDownTime
			+ (totalMassAtThrottleDown - gLimitStartMass)
			/ throttledStageFullFlow.
		SET gLimitStartTime TO MAX(gLimitStartTime, throttleDownTime).

		IF gLimitStartTime >= unthrottledBoosterBurnoutTime {
			// The boosters remain at full thrust for their entire burn.
			PRINT "[stage-utils] glim1 is not reached before booster burnout.".
			SET jettisonTime TO unthrottledBoosterBurnoutTime.
			SET coreMassAtJettison TO coreMassAtThrottleDown
				- coreFullFlow * throttleDownLevel
				* (jettisonTime - throttleDownTime).
		} ELSE {
			PRINT "[stage-utils] Constant-g phase 1 begins: T+"
				+ ROUND(gLimitStartTime, 3) + " s".
			LOCAL timeBeforeConstantG IS gLimitStartTime - throttleDownTime.
			LOCAL boosterMassAtConstantG IS boosterMassAtThrottleDown
				- boosterFullFlow * timeBeforeConstantG.
			LOCAL coreMassAtConstantG IS coreMassAtThrottleDown
				- coreFullFlow * throttleDownLevel * timeBeforeConstantG.
			LOCAL totalMassAtConstantG IS
				boosterMassAtConstantG + coreMassAtConstantG.

			// T(u) = thrustSlope*u + thrustFloor.
			LOCAL thrustSlope IS
				boosterThrust * (1 - boosterMinThrottle)
				+ coreThrust * (throttleDownLevel - coreMinThrottle).
			LOCAL thrustFloor IS throttledStageMinThrust.
			// -massDot(u) = flowSlope*u + flowFloor.
			LOCAL boosterFlowSlope IS
				boosterThrust * (1 - boosterMinThrottle)
				/ boosterExhaustVelocity.
			LOCAL boosterFlowFloor IS
				boosterThrust * boosterMinThrottle
				/ boosterExhaustVelocity.
			LOCAL coreFlowSlope IS
				coreThrust * (throttleDownLevel - coreMinThrottle)
				/ coreExhaustVelocity.
			LOCAL coreFlowFloor IS
				coreThrust * coreMinThrottle
				/ coreExhaustVelocity.
			LOCAL flowSlope IS boosterFlowSlope + coreFlowSlope.
			LOCAL flowFloor IS boosterFlowFloor + coreFlowFloor.

			// Under constant g, massDot = -alpha*M - beta.
			LOCAL alpha IS flowSlope * gLimitAcceleration / thrustSlope.
			LOCAL beta IS flowFloor - flowSlope * thrustFloor / thrustSlope.
			LOCAL shiftedMass IS totalMassAtConstantG + beta / alpha.
			// Booster mass derivative is -p*M-r in constant-g flight.
			LOCAL p IS boosterFlowSlope * gLimitAcceleration / thrustSlope.
			LOCAL _r IS
				boosterFlowFloor - boosterFlowSlope * thrustFloor / thrustSlope.

			// The ideal requested main throttle reaches zero at this mass.
			LOCAL throttleFloorMass IS thrustFloor / gLimitAcceleration.
			LOCAL timeToThrottleFloor IS 0.
			LOCAL totalMassAtThrottleFloor IS totalMassAtConstantG.
			LOCAL boosterMassAtThrottleFloor IS boosterMassAtConstantG.
			IF totalMassAtConstantG > throttleFloorMass {
				SET timeToThrottleFloor TO LN(
					shiftedMass / (throttleFloorMass + beta / alpha)
				) / alpha.
				SET totalMassAtThrottleFloor TO throttleFloorMass.
				SET boosterMassAtThrottleFloor TO boosterMassAtConstantG
					- p / alpha * shiftedMass
					* (1 - CONSTANT:E ^ (-alpha * timeToThrottleFloor))
					+ (p * beta / alpha - _r) * timeToThrottleFloor.
			}
			PRINT "[stage-utils] Ideal throttle floor: T+"
				+ ROUND(gLimitStartTime + timeToThrottleFloor, 3)
				+ " s, booster mass "
				+ ROUND(boosterMassAtThrottleFloor, 3) + " kg" AT(0, 22).

			IF boosterMassAtThrottleFloor > boosterDryMass {
				// Constant g cannot be held. Continue at ideal main throttle u=0.
				SET gstatus TO "overload1".
				PRINT "[stage-utils] glim1 overload; simulating at u=0.".
				LOCAL minimumThrottleBurnTime IS
					(boosterMassAtThrottleFloor - boosterDryMass)
					/ boosterFlowFloor.
				SET jettisonTime TO gLimitStartTime
					+ timeToThrottleFloor + minimumThrottleBurnTime.
				LOCAL totalMassAtJettison IS totalMassAtThrottleFloor
					- flowFloor * minimumThrottleBurnTime.
				SET coreMassAtJettison TO totalMassAtJettison - boosterDryMass.
			} ELSE {
				// Solve mB(tau) = boosterDryMass with safeguarded Newton steps.
				LOCAL lowerTime IS 0.
				LOCAL upperTime IS timeToThrottleFloor.
				LOCAL rootTime IS (lowerTime + upperTime) / 2.
				FROM { LOCAL iteration IS 0. }
				UNTIL iteration >= 32
				STEP { SET iteration TO iteration + 1. }
				DO {
					LOCAL expTerm IS CONSTANT:E ^ (-alpha * rootTime).
					LOCAL totalMassAtRoot IS shiftedMass * expTerm - beta / alpha.
					LOCAL boosterMassAtRoot IS boosterMassAtConstantG
						- p / alpha * shiftedMass * (1 - expTerm)
						+ (p * beta / alpha - _r) * rootTime.
					LOCAL massError IS boosterMassAtRoot - boosterDryMass.
					PRINT "[stage-utils] Newton " + (iteration + 1)
						+ ": dt=" + ROUND(rootTime, 6)
						+ " s, dm=" + ROUND(massError, 3) + " kg".

					IF ABS(massError) <= 0.001
						OR upperTime - lowerTime <= 0.000001 {
						BREAK.
					}
					IF massError > 0 {
						SET lowerTime TO rootTime.
					} ELSE {
						SET upperTime TO rootTime.
					}

					LOCAL massDerivative IS -p * totalMassAtRoot - _r.
					LOCAL nextTime IS rootTime - massError / massDerivative.
					IF nextTime <= lowerTime OR nextTime >= upperTime {
						SET nextTime TO (lowerTime + upperTime) / 2.
					}
					SET rootTime TO nextTime.
				}

				SET jettisonTime TO gLimitStartTime + rootTime.
				LOCAL finalExpTerm IS CONSTANT:E ^ (-alpha * rootTime).
				LOCAL totalMassAtJettison IS
					shiftedMass * finalExpTerm - beta / alpha.
				SET coreMassAtJettison TO totalMassAtJettison - boosterDryMass.
			}
		}
	}

	LOCAL boosterMassAtFullStageEnd IS
		boosterWetMass - boosterFullFlow * fullStageEndTime.
	LOCAL coreMassAtFullStageEnd IS
		coreWetMass - coreFullFlow * fullStageEndTime.
	LOCAL fullStageConfig IS LEXICON(
		"name", "full thrust",
		"massTotal", boosterWetMass + coreWetMass - payloadMass,
		"massDry", boosterMassAtFullStageEnd + coreMassAtFullStageEnd - payloadMass,
		"engines", LIST(
			LEXICON("isp", boosterIsp, "thrust", boosterThrust),
			LEXICON("isp", coreIsp, "thrust", coreThrust)
		),
		"staging", LEXICON(
			"jettison", FALSE,
			"ignition", FALSE
		)
	).

	IF gstatus <> "no_core_throttling" {
		SET throttleDownStageConfig TO LEXICON(
			"name", "throttle down",
			"massTotal", fullStageConfig["massDry"],
			"massDry", boosterDryMass + coreMassAtJettison - payloadMass,
			"gLim", glim1,
			"minThrottle", throttledStageMinThrottle,
			"engines", LIST(
				LEXICON("isp", boosterIsp, "thrust", boosterThrust),
				LEXICON("isp", coreIsp, "thrust", throttledCoreThrust)
			),
			"staging", LEXICON(
				"jettison", FALSE,
				"ignition", FALSE
			)
		).
	}

	LOCAL throttleUpStageConfig IS LEXICON(
		"name", "throttle up",
		"massTotal", coreMassAtJettison - payloadMass,
		"massDry", coreDryMass - payloadMass,
		"gLim", glim2,
		"minThrottle", coreMinThrottle,
		"engines", LIST(
			LEXICON("isp", coreIsp, "thrust", coreThrust)
		),
		"staging", LEXICON(
			"jettison", FALSE,
			"ignition", FALSE
		)
	).

	// Predict core burnout/separation after booster jettison. First check
	// whether full thrust reaches glim2 before dry mass, then check whether the
	// limit remains achievable above the physical minimum throttle.
	LOCAL coreFullBurnTime IS
		(coreMassAtJettison - coreDryMass) / coreFullFlow.
	LOCAL coreGLimitAcceleration IS glim2 * CONSTANT:g0.
	LOCAL coreGLimitMass IS coreThrust / coreGLimitAcceleration.
	LOCAL coreGLimitStart IS
		MAX(0, (coreMassAtJettison - coreGLimitMass) / coreFullFlow).
	LOCAL coreBurnDuration IS coreFullBurnTime.

	IF coreGLimitStart >= coreFullBurnTime {
		PRINT "[stage-utils] Core does not reach glim2 before separation.".
	} ELSE {
		LOCAL coreMassAtGLimit IS
			coreMassAtJettison - coreFullFlow * coreGLimitStart.
		LOCAL coreThrottleFloorMass IS
			coreThrust * coreMinThrottle / coreGLimitAcceleration.
		PRINT "[stage-utils] Core reaches glim2 at T+"
			+ ROUND(jettisonTime + coreGLimitStart, 3) + " s".

		IF coreMassAtGLimit <= coreThrottleFloorMass {
			// Even minimum throttle is already above glim2 at throttle-up.
			SET coreBurnDuration TO
				(coreMassAtJettison - coreDryMass)
				/ (coreFullFlow * coreMinThrottle).
			PRINT "[stage-utils] Core cannot maintain glim2 at throttle-up;"
				+ " simulating the full burn at minimum throttle.".
		} ELSE IF coreDryMass >= coreThrottleFloorMass {
			// The core reaches dry mass before the throttle floor.
			SET coreBurnDuration TO coreGLimitStart
				+ coreIsp / glim2
				* LN(coreMassAtGLimit / coreDryMass).
			PRINT "[stage-utils] Core maintains glim2 through separation.".
		} ELSE {
			// Constant g ends at minimum throttle; finish at constant min thrust.
			LOCAL timeToCoreThrottleFloor IS coreIsp / glim2
				* LN(coreMassAtGLimit / coreThrottleFloorMass).
			LOCAL coreMinimumThrottleBurnTime IS
				(coreThrottleFloorMass - coreDryMass)
				/ (coreFullFlow * coreMinThrottle).
			SET coreBurnDuration TO coreGLimitStart
				+ timeToCoreThrottleFloor + coreMinimumThrottleBurnTime.
			PRINT "[stage-utils] Core reaches minimum throttle before separation;"
				+ " simulating the remaining burn at minimum thrust.".
		}
	}
	LOCAL coreSeperationTime IS jettisonTime + coreBurnDuration.
	PRINT "[stage-utils] Result: " + gstatus
		+ ", booster jettison T+" + ROUND(jettisonTime, 3)
		+ " s, core separation T+" + ROUND(coreSeperationTime, 3) + " s".

	RETURN LEXICON(
		"fullStage", fullStageConfig,
		"throttleDownStage", throttleDownStageConfig,
		"throttleUpStage", throttleUpStageConfig,
		"status", gstatus,
		"jettisonMass", boosterDryMass,
		"throttleDownTime", throttleDownTime,
		"jettisonTime", jettisonTime,
		"coreSeperationTime", coreSeperationTime
	).
}

// Insert an event without disturbing the order of existing events at the same
// time. The caller must provide a sequence that is already time-ordered.
FUNCTION _stage_utils_insert_timed_event {
	PARAMETER targetSequence.
	PARAMETER newEvent.

	LOCAL insertAt IS targetSequence:LENGTH.
	FROM { LOCAL eventIndex IS 0. }
	UNTIL eventIndex >= targetSequence:LENGTH
	STEP { SET eventIndex TO eventIndex + 1. }
	DO {
		IF newEvent["time"] < targetSequence[eventIndex]["time"] {
			SET insertAt TO eventIndex.
			BREAK.
		}
	}

	IF insertAt = targetSequence:LENGTH {
		targetSequence:ADD(newEvent).
	} ELSE {
		targetSequence:INSERT(insertAt, newEvent).
	}
	PRINT "[stage-utils] Inserted " + newEvent["message"]
		+ " at T+" + ROUND(newEvent["time"], 3) + " s".
}

// Calculate the booster/core profile, prepend only stages still burning when
// UPFG activates, and merge the generated events into an ordered sequence.
FUNCTION configure_booster_core_stages {
	PARAMETER boosterInfo.
	PARAMETER coreInfo.
	PARAMETER eventInfo.
	PARAMETER targetVehicle.
	PARAMETER targetSequence.
	PARAMETER controlInfo.
	PARAMETER missionInfo.

	LOCAL stageConfig IS
		make_throttle_stage_config(boosterInfo, coreInfo, eventInfo, missionInfo["payload"]).
	LOCAL massActivation IS controlInfo:HASKEY("upfgActivationMass").
	LOCAL gstatus IS stageConfig["status"].
	LOCAL jettisonTime IS stageConfig["jettisonTime"].
	LOCAL fullStageEndTime IS stageConfig["throttleDownTime"].
	IF gstatus = "no_core_throttling" {
		SET fullStageEndTime TO jettisonTime.
	}

	LOCAL coreStage IS stageConfig["throttleUpStage"].
	LOCAL coreStageEndTime IS stageConfig["coreSeperationTime"].
	LOCAL includeFullStage IS FALSE.
	LOCAL includeThrottleStage IS FALSE.
	LOCAL includeCoreStage IS FALSE.

	IF massActivation {
		LOCAL activationMass IS controlInfo["upfgActivationMass"].
		LOCAL payloadMass IS missionInfo["payload"].
		SET includeFullStage TO stageConfig["fullStage"]["massDry"] + payloadMass < activationMass.
		IF gstatus <> "no_core_throttling" {
			SET includeThrottleStage TO stageConfig["throttleDownStage"]["massDry"] + payloadMass < activationMass.
		}
		SET includeCoreStage TO coreStage["massDry"] + payloadMass < activationMass.
		PRINT "[stage-utils] UPFG activation mass: " + ROUND(activationMass, 3) + " kg".
	} ELSE {
		LOCAL upfgActivation IS controlInfo["upfgActivation"].
		SET includeFullStage TO fullStageEndTime > upfgActivation.
		SET includeThrottleStage TO jettisonTime > upfgActivation.
		SET includeCoreStage TO coreStageEndTime > upfgActivation.
		PRINT "[stage-utils] UPFG activation: T+" + ROUND(upfgActivation, 3) + " s".
	}
	LOCAL prependIndex IS 0.
	IF includeFullStage {
		targetVehicle:INSERT(prependIndex, stageConfig["fullStage"]).
		SET prependIndex TO prependIndex + 1.
		PRINT "[stage-utils] Prepended full-thrust stage.".
	} ELSE {
		PRINT "[stage-utils] Skipped full-thrust stage; already complete.".
	}

	IF gstatus <> "no_core_throttling" {
		IF includeThrottleStage {
			targetVehicle:INSERT(prependIndex, stageConfig["throttleDownStage"]).
			SET prependIndex TO prependIndex + 1.
			PRINT "[stage-utils] Prepended throttled booster/core stage.".
		} ELSE {
			PRINT "[stage-utils] Skipped throttled stage; already complete.".
		}
	}

	IF includeCoreStage {
		targetVehicle:INSERT(prependIndex, coreStage).
		PRINT "[stage-utils] Prepended core-only stage; predicted end T+"
			+ ROUND(coreStageEndTime, 3) + " s".
	} ELSE {
		PRINT "[stage-utils] Skipped core-only stage; already complete.".
	}

	LOCAL boosterSeparationDelay IS 0.
	IF eventInfo:HASKEY("boosterSeparationDelay") {
		SET boosterSeparationDelay TO eventInfo["boosterSeparationDelay"].
	}
	LOCAL coreThrottleUpDelay IS boosterSeparationDelay.
	IF eventInfo:HASKEY("coreThrottleUpDelay") {
		SET coreThrottleUpDelay TO eventInfo["coreThrottleUpDelay"].
	}

	IF gstatus <> "no_core_throttling" {
		_stage_utils_insert_timed_event(targetSequence, LEXICON(
			"time", stageConfig["throttleDownTime"],
			"type", "delegate",
			"function", "CoreThrottleDown",
			"message", "Core stage throttle down"
		)).
	}
	_stage_utils_insert_timed_event(targetSequence, LEXICON(
		"time", jettisonTime + boosterSeparationDelay,
		"type", "jettison",
		"massLost", stageConfig["jettisonMass"],
		"message", "booster separation"
	)).
	IF gstatus <> "no_core_throttling" {
		_stage_utils_insert_timed_event(targetSequence, LEXICON(
			"time", jettisonTime + coreThrottleUpDelay,
			"type", "delegate",
			"function", "CoreThrottleUp",
			"message", "Core stage throttle up"
		)).
	}

	RETURN stageConfig.
}
