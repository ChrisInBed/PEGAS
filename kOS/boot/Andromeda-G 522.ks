GLOBAL controls IS LEXICON(
	"verticalAscentTime", 12,	//	8.25s for all
	"pitchOverAngle", 3.5,
	"upfgActivation", 130,
	"launchTimeAdvance", 60,
	"initialRoll", 90,
	"disableThrustWatchdog", TRUE
).
GLOBAL mission IS LEXICON(
	"payload", 9706+326,
	"periapsis", 200,
	"apoapsis", 200
	//"inclination", 36.4,
	//"direction", "north",
	//"LAN", 58.4
).
SWITCH TO 0.
CLEARSCREEN.
PRINT "Loading boot file: Andromeda-G 522...".
RUNPATH("0:/PEGASLib/stage_utils.ks").
set config:IPU to 600.
// SET STEERINGMANAGER:ROLLTS TO 10.
LOCAL fairingMass to 3180.	//	2780, 3180, 3580, 3980
LOCAL towerMass to 0.
LOCAL BoosterInfo to lexicon(
	"massWet", 648494,
	"massDry", 52452,
	"thrust", 10715840,
	"isp", 335.08,
	"throttleMinLevel", 0.5,
	"engineLabel", "booster"
).
LOCAL CoreInfo to lexicon(
	"massWet", 189580 + fairingMass + towerMass,
	"massDry", 40569 + fairingMass + towerMass,
	"thrust", 2678960,
	"isp", 335.08,
	"throttleMinLevel", 0.5,
	"engineLabel", "core"
).
LOCAL EventInfo to lexicon(
	"throttleDownTime", 30,
	"throttleDownLevel", 0.505,
	"glim1", 4.5,
	"glim2", 4.5,
	"boosterSeparationDelay", -3.1,
	"coreThrottleUpDelay", -1.5
	// "boosterSeparationDelay", 1,
	// "coreThrottleUpDelay", 2
).
// DECLARE GLOBAL BoosterStagingType IS "DefaultBoosterStaging".
// To issue several separation commands instead, replace the line above with:
DECLARE GLOBAL BoosterStagingType IS "ConsecutiveBoosterStaging".
DECLARE GLOBAL BoosterStagingArgs IS LEXICON("stagingNumber", 1, "timeInterval", 0.3, "sepDelay", 0.3).
// Upper stage parameters, the CBC core stage will be automatically merged in afterwards
GLOBAL vehicle IS LIST(
	LEXICON(
		"name", "Argo-4E",
		"massTotal", 24988,
		"massDry", 3321,
		"engines", LIST(LEXICON("isp", 465.5, "thrust", 110100)),
		"spoolup", 4.92,
		"staging", LEXICON(
						"jettison", TRUE,
						"waitBeforeJettison", 0,
						"ignition", TRUE,
						"waitBeforeIgnition", 1,
						"ullage", "rcs",
						"ullageBurnDuration", 3,
						"postUllageBurn", 4
						)
	)
).
GLOBAL sequence IS LIST(
	LEXICON("time", -4.4, "type", "stage", "message", "Main Engines ignition"),
	LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
	LEXICON("time", 210, "type", "jettison", "massLost", fairingMass, "message", "Fairing jettison")
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

PRINT "Loaded boot file: Andromeda-G 522!".