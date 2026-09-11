// Live booster-separation strategies.
//
// A staging callback is a short, non-blocking state-machine step. It returns
// FALSE while it still needs to be called and TRUE only after its complete
// staging sequence has finished. The recurring trigger below inverts that
// value because returning TRUE from a kOS trigger preserves the trigger.

GLOBAL _boosterStagingEngines IS LIST().

FUNCTION _hasBurnout {
	FOR eng IN _boosterStagingEngines {
		IF eng:IGNITION and eng:FLAMEOUT {
			RETURN TRUE.
		}
	}
	RETURN FALSE.
}

FUNCTION _deactivateEngines {
	FOR eng IN _boosterStagingEngines {
		eng:shutdown().
	}
}

// Default booster staging strategy: wait for burnout, then stage once.
GLOBAL _defaultStagingActive IS FALSE.
FUNCTION DefaultBoosterStagingCallback {
	IF ((NOT _defaultStagingActive) AND _hasBurnout()) {
		_deactivateEngines().
		SET _defaultStagingActive TO TRUE.
	}
	IF (_defaultStagingActive AND STAGE:READY) {
		LOCAL actualSeparationTime IS TIME:SECONDS - liftoffTime:SECONDS.
		STAGE.
		pushUIMessage("Booster separation at T+"
			+ ROUND(actualSeparationTime, 3) + " s").
		RETURN TRUE.
	}

	RETURN FALSE.
}

// Consecutive booster staging strategy: wait for burnout, then stage up to N times with a time interval.
GLOBAL _consecutiveMaxStagingNumber IS 3.
GLOBAL _consecutiveTimeInterval IS 0.3.
GLOBAL _consecutiveStagingActive IS FALSE.
GLOBAL _consecutiveStagingNumber IS 0.
GLOBAL _consecutiveLastStagingTime IS TIME:SECONDS.
FUNCTION ConsecutiveBoosterStagingCallback {
	IF ((NOT _consecutiveStagingActive) AND _hasBurnout()) {
		_deactivateEngines().
		SET _consecutiveStagingActive TO TRUE.
		// Make the first command eligible immediately; timeInterval applies
		// between consecutive staging commands.
		SET _consecutiveLastStagingTime TO TIME:SECONDS - _consecutiveTimeInterval.
	}
	LOCAL currentTime IS TIME:SECONDS.
	IF (_consecutiveStagingActive AND STAGE:READY AND (currentTime - _consecutiveLastStagingTime) >= _consecutiveTimeInterval) {
		STAGE.
		SET _consecutiveStagingNumber TO _consecutiveStagingNumber + 1.
		SET _consecutiveLastStagingTime TO currentTime.
		IF _consecutiveStagingNumber >= _consecutiveMaxStagingNumber {
			pushUIMessage("Booster separation complete ("
				+ _consecutiveStagingNumber + " stages) at T+"
				+ ROUND(currentTime - liftoffTime:SECONDS, 3) + " s").
		}
	}
	RETURN _consecutiveStagingNumber >= _consecutiveMaxStagingNumber.
}


// Entry point for the booster staging addon. A valid mode is enabled only when
// its complete configuration and at least one matching engine are available.
GLOBAL _StagingCallback IS DefaultBoosterStagingCallback@.
GLOBAL _boosterStagingConfigured IS FALSE.
GLOBAL _boosterStagingConfigError IS "".
SET addonEnabled TO FALSE.
IF (DEFINED BoosterStagingType) {
	IF (BoosterStagingType = "DefaultBoosterStaging") {
		SET _StagingCallback TO DefaultBoosterStagingCallback@.
		SET _boosterStagingConfigured TO TRUE.
	} ELSE IF (BoosterStagingType = "ConsecutiveBoosterStaging") {
		IF NOT (DEFINED BoosterStagingArgs) {
			SET _boosterStagingConfigError TO "BoosterStagingArgs is undefined".
		} ELSE IF NOT BoosterStagingArgs:ISTYPE("Lexicon") {
			SET _boosterStagingConfigError TO "BoosterStagingArgs must be a lexicon".
		} ELSE IF NOT BoosterStagingArgs:HASKEY("stagingNumber") OR NOT BoosterStagingArgs:HASKEY("timeInterval") {
			SET _boosterStagingConfigError TO "BoosterStagingArgs requires stagingNumber and timeInterval".
		} ELSE IF NOT BoosterStagingArgs["stagingNumber"]:ISTYPE("Scalar") OR NOT BoosterStagingArgs["timeInterval"]:ISTYPE("Scalar") {
			SET _boosterStagingConfigError TO "stagingNumber and timeInterval must be scalars".
		} ELSE IF BoosterStagingArgs["stagingNumber"] < 1
			OR BoosterStagingArgs["stagingNumber"] <> ROUND(BoosterStagingArgs["stagingNumber"], 0)
			OR BoosterStagingArgs["timeInterval"] < 0 {
			SET _boosterStagingConfigError TO "stagingNumber must be a positive integer and timeInterval must be non-negative".
		} ELSE {
			SET _StagingCallback TO ConsecutiveBoosterStagingCallback@.
			SET _consecutiveMaxStagingNumber TO BoosterStagingArgs["stagingNumber"].
			SET _consecutiveTimeInterval TO BoosterStagingArgs["timeInterval"].
			SET _boosterStagingConfigured TO TRUE.
		}
	} ELSE {
		SET _boosterStagingConfigError TO "unknown BoosterStagingType '" + BoosterStagingType + "'".
	}
}

IF _boosterStagingConfigured {
	IF NOT (DEFINED BoosterEngineLabel) {
		SET _boosterStagingConfigured TO FALSE.
		SET _boosterStagingConfigError TO "BoosterEngineLabel is undefined".
	} ELSE {
		LOCAL allEngines IS LIST().
		LIST ENGINES IN allEngines.
		FOR eng IN allEngines {
			IF eng:TAG:CONTAINS(BoosterEngineLabel) {
				_boosterStagingEngines:ADD(eng).
			}
		}
		IF _boosterStagingEngines:LENGTH = 0 {
			SET _boosterStagingConfigured TO FALSE.
			SET _boosterStagingConfigError TO "no engine tag contains '" + BoosterEngineLabel + "'".
		}
	}
}

IF _boosterStagingConfigured {
	SET addonEnabled TO TRUE.
	SET addonName TO BoosterStagingType.
	WHEN (TRUE) THEN {
		RETURN NOT _StagingCallback().
	}
} ELSE IF _boosterStagingConfigError:LENGTH > 0 {
	pushUIMessage("Booster staging: " + _boosterStagingConfigError
		+ "; using timed staging.", 10, PRIORITY_HIGH).
}
