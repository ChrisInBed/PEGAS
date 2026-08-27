GLOBAL vehicle IS LIST(
					LEXICON(
						//	This stage will be ignited upon UPFG activation.
						"name", "S-II",
						"massTotal", 713153,	//	kOS part upgrade
						"massFuel", 484820,
						"engines", LIST(LEXICON("isp", 424.50, "thrust", 5115457)),
						"spoolup", 2.94,
						"staging", LEXICON(
										"jettison", TRUE,
										"waitBeforeJettison", 0,
										"ignition", TRUE,
										"waitBeforeIgnition", 3,
										"ullage", "none"
										)
					),
					LEXICON(
						"name", "S-IVB",
						"massTotal", 186995,
						"massFuel", 125630,
						"engines", LIST(LEXICON("isp", 424.50, "thrust", 1023091)),
						"spoolup", 2.94,
						"staging", LEXICON(
										"jettison", TRUE,
										"waitBeforeJettison", 3,
										"ignition", TRUE,
										"waitBeforeIgnition", 3,
										"ullage", "none"
										)
					)
).
GLOBAL sequence IS LIST(
					LEXICON("time", -4.3, "type", "stage", "message", "F-1 ignition"),
					LEXICON("time", 0, "type", "stage", "message", "LIFTOFF"),
					LEXICON("time", 140, "type", "delegate", "function", "ShutEnginesDown", "message", "shutting down center engine"),
					LEXICON("time", 175, "type", "jettison", "massLost", 4161+3742, "message", "Jettison interstage and LES tower")
).
GLOBAL controls IS LEXICON(
					"launchTimeAdvance", 120,
					"verticalAscentTime", 25,
					"pitchOverAngle", 3,
					// "upfgActivation", 163
					"upfgActivationMass", 851000
).
GLOBAL mission IS LEXICON(
	"apoapsis", 200,
	"periapsis", 200,
	"payload", 0
).
// SET STEERINGMANAGER:ROLLTS TO 10.
SWITCH TO 0.
CLEARSCREEN.
PRINT "Loaded boot file: SaturnV!".