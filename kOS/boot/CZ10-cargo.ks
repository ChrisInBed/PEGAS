SWITCH TO 0.
CLEARSCREEN.
PRINT "Loading boot file: CZ-10...".
RUNPATH("0:/PEGASLib/stage_utils.ks").

// Parameter Settings
set config:IPU to 2000.
SET STEERINGMANAGER:ROLLTS TO 10.
LOCAL fairingMass to 202 * 2.
LOCAL towerMass to 0.
LOCAL BoosterInfo to lexicon(
	"massWet", 1230115,
	"massDry", 99231,
	"thrust", 19977100,
	"isp", 338.20,
	"throttleMinLevel", 0.637
).
LOCAL CoreInfo to lexicon(
	"massWet", 873490 + fairingMass + towerMass,
	"massDry", 308048 + fairingMass + towerMass,
	"thrust", 9988550,
	"isp", 338.20,
	"throttleMinLevel", 0.637
).
LOCAL EventInfo to lexicon(
	"throttleDownTime", 60,
	"throttleDownLevel", 0.64,
	"glim1", 3.5,
	"glim2", 3.5,
	"boosterSeparationDelay", 1,
	"coreThrottleUpDelay", 1.5
).
// Upper stage parameters, the CBC core stage will be automatically merged in afterwards
GLOBAL vehicle IS LIST(
	LEXICON(
		"name", "stage2",
		"massTotal", 258064,
		"massDry", 82498,
		"engines", LIST(LEXICON("isp", 352.30, "thrust", 2900e3)),
		"spoolup", 3.14,
		"staging", LEXICON(
						"jettison", TRUE,
						"waitBeforeJettison", 3,
						"ignition", TRUE,
						"waitBeforeIgnition", 1.5,
						"ullage", "none"
						)
	),
	LEXICON(
		"name", "stage3",
		"massTotal", 67000,
		"massDry", 7701,
		"engines", LIST(LEXICON("isp", 451, "thrust", 276324)),
		"spoolup", 1.60,
		"staging", LEXICON(
						"jettison", TRUE,
						"waitBeforeJettison", 5,
						"ignition", TRUE,
						"waitBeforeIgnition", 0.5,
						"ullage", "rcs",
						"ullageBurnDuration", 3,
						"postUllageBurn", 2
						)
	)
).
// Core-stage throttling and booster-separation events will be merged in afterwards
GLOBAL sequence IS LIST(
	LEXICON("time", -3, "type", "stage", "message", "Engine Start"),
	LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
	LEXICON("time", 220, "type", "jettison", "massLost", fairingMass + towerMass, "message", "jettison fairing and tower")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 20,
					"pitchOverAngle", 4,
					"upfgActivation", 125,
					"initialRoll", 90,
					"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"apoapsis", 200,
	"periapsis", 200,
	"payload", 18146  // Change to your payload mass in kg
).
// End Parameter Settings

SET usc_convergeFlags TO LIST().

LOCAL _initialStateConfig IS configure_booster_core_stages(
	BoosterInfo,
	CoreInfo,
	EventInfo,
	vehicle,
	sequence,
	controls,
	mission
).

PRINT "Loaded boot file: CZ-10!".
