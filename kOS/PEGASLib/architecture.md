# Booster-core stage profile

`make_throttle_stage_config` converts a parallel booster/core burn into the three
logical stages expected by PEGAS. The first stage represents the initial
full-thrust burn, the second represents the core-throttled booster burn, and the
third represents the core after booster separation. PEGAS creates the
constant-acceleration virtual stages associated with `gLim`; the helper still
has to predict booster burnout explicitly so that UPFG's separation timeline
and predicted core mass remain internally consistent.

## Inputs and result

`boosterInfo` and `coreInfo` are lexicons with these fields:

| Field | Units | Meaning |
| --- | --- | --- |
| `massWet` | kg | Initial configured mass of the engine group and everything assigned to it, excluding the PEGAS payload |
| `massDry` | kg | Configured mass remaining when that engine group runs out of propellant, excluding the PEGAS payload |
| `thrust` | N | Maximum vacuum thrust |
| `isp` | s | Vacuum specific impulse |
| `throttleMinLevel` | 0-1 | Physical engine throttle at KSP main throttle zero |
| `engineLabel` | string | Substring used to identify engines belonging to this group by their KSP part tag |

`engineLabel` does not participate in the mass or burnout calculation. The helper
publishes the values as the globals `BoosterEngineLabel` and `CoreEngineLabel` so
runtime delegates and other add-ons can identify the two engine groups. The
generated core throttle delegates currently consume `CoreEngineLabel`;
the live booster-staging add-on consumes `BoosterEngineLabel`.

`make_throttle_stage_config` takes `payloadMass` as its fourth argument. The
payload must not already be included in `coreInfo["massWet"]` or
`coreInfo["massDry"]`. The helper adds it to both core masses for its internal
flight prediction, so payload changes the g-load and throttle history without
changing the available core propellant. Pass zero when no payload is defined.

`eventInfo` contains `throttleDownTime` in seconds, `throttleDownLevel` as the
core's physical throttle after throttling down, and the acceleration limits
`glim1` and `glim2` in multiples of standard gravity. The optional
`boosterSeparationDelay` and `coreThrottleUpDelay` fields are offsets from
predicted booster burnout. They default to zero and the separation delay,
respectively. With live booster staging, `boosterSeparationDelay` calibrates
only the time at which UPFG applies the predicted booster mass loss; it does not
delay the physical staging command.

The returned lexicon has `fullStage`, `throttleDownStage`, and
`throttleUpStage`; `status`; `jettisonMass`; `throttleDownTime`; and
`jettisonTime`; and `coreSeperationTime`. The jettison time is measured from
liftoff and is the predicted instant at which booster mass reaches `massDry`.
`coreSeperationTime` is the predicted core dry-mass time after accounting for
`glim2` and minimum throttle. Neither value includes a mechanical separation
delay. `throttleDownTime` always echoes the requested event time, including
when `no_core_throttling` cancels that event.

Every `massTotal` and `massDry` in the three returned PEGAS stage lexicons
excludes payload mass. PEGAS's normal vehicle setup adds `mission["payload"]`
to each guided stage afterwards. Payload therefore participates exactly once
in both the helper's physical prediction and PEGAS's runtime vehicle model.

The statuses are:

- `ok`: the requested profile is feasible through booster burnout.
- `no_core_throttling`: the boosters burn out at or before
  `throttleDownTime`. `throttleDownStage` is an empty lexicon, while the other
  two stage keys describe the usable full-thrust and core-only phases.
- `overload1`: maintaining `glim1` would require a negative main throttle
  before booster burnout. The remaining burn is predicted at main throttle
  zero.

The helper prints progress directly to the kOS terminal. Its diagnostics mark
the full-thrust estimate, core throttle-down, constant-g activation, ideal
throttle floor, overload fallback, and final result. During the bounded root
solve it prints every Newton/bisection iteration with elapsed constant-g time
and booster mass error, so computation remains visibly active on slow CPUs.

## Vehicle and sequence integration

`configure_booster_core_stages` is the integration entry point used by launch
configuration files. It accepts booster, core, and event settings followed by
the user-defined `vehicle`, `sequence`, `controls`, and `mission` structures.
It passes `mission["payload"]` to `make_throttle_stage_config`, mutates the two
supplied lists, and returns the calculated stage-config lexicon. Launch files
using this helper must define the payload key; set it to zero for a flight with
no payload.

While building the profile, `make_throttle_stage_config` also publishes
`BoosterEngineLabel`, `CoreEngineLabel`, and `CoreThrottleTarget` as globals for
the event delegates loaded later by PEGAS. The core thrust-limit setting is

\[
\texttt{CoreThrottleTarget}
=100\frac{d-l_C}{1-l_C}.
\]

The delegates select engines with
`e:tag:contains(CoreEngineLabel)`, intentionally using substring matching rather
than equality. This permits one engine tag to carry several functional labels.
Consequently labels must be nonempty and should be chosen so that unrelated
engine tags do not contain them. In kOS, an empty substring matches every string
and would cause the delegates to change the thrust limit of every engine.

Generated stages are prepended to `vehicle` in flight order only when their
predicted end time is strictly later than `controls["upfgActivation"]`. A stage
ending exactly at activation is already complete and is omitted. The candidate
end times are throttle-down for the full-thrust phase, booster burnout for the
throttled booster/core phase, and the returned `coreSeperationTime` for the
core-only phase. The upper stages already supplied by the user retain their
relative order.

Throttle-down, booster-separation, and throttle-up events are inserted into the
user's existing `sequence`. The input sequence must already be ordered by
`time`. Insertion preserves ascending time order and places generated events
after existing events with the same timestamp. Throttle-down and throttle-up
events are omitted when the profile status is `no_core_throttling`.

## Live booster staging

Launch files may select the single-command strategy by declaring:

```ks
DECLARE GLOBAL BoosterStagingType IS "DefaultBoosterStaging".
```

Vehicles that require several consecutive KSP staging commands use:

```ks
DECLARE GLOBAL BoosterStagingType IS "ConsecutiveBoosterStaging".
DECLARE GLOBAL BoosterStagingArgs IS LEXICON(
    "stagingNumber", 2,
    "timeInterval", 0.3,
    "sepDelay", 0.3
).
```

`stagingNumber` is the positive integer number of `STAGE.` commands to issue.
`timeInterval` is the minimum non-negative interval in seconds between those
commands. `sepDelay` is the non-negative delay in seconds from detected burnout
to the first command. `STAGE:READY` must also be true before every command. If
it is not ready when a deadline is reached, the callback stages on the first
later invocation for which it is ready.

`sepDelay` controls actual physical staging and applies only to
`ConsecutiveBoosterStaging`. It is independent of `boosterSeparationDelay`,
which shifts UPFG's predicted `jettison` mass event. Use `stagingNumber = 1`
when one physical separation command is required but it must be delayed after
live burnout detection.

For either valid recognized mode, when at least one engine tag contains
`BoosterEngineLabel`, the generated booster `jettison` event has
`staging = FALSE`. It remains at
`jettisonTime + boosterSeparationDelay` and still supplies `massLost`, so PEGAS
creates the predicted virtual stage required by UPFG, but the event handler does
not issue `STAGE.`. If `BoosterStagingType` is absent or invalid, required
consecutive-mode arguments are absent or invalid, or no matching booster engine
exists, the generated event has `staging = TRUE` and retains legacy timed
physical separation. Configuration errors produce a high-priority PEGAS UI
warning.

`addons/booster_staging.ks` is loaded inside the PEGAS program context. It
selects the configured callback, caches every engine whose tag contains
`BoosterEngineLabel`, and creates a recurring trigger directly at add-on scope:

```ks
WHEN TRUE THEN {
    RETURN NOT _StagingCallback().
}
```

A booster-staging callback is a bounded, no-explicit-wait state-machine step.
It returns `FALSE` while monitoring or while more separation actions remain,
and returns `TRUE` only after its complete sequence has finished. A kOS trigger
is preserved when its body returns `TRUE`, hence the wrapper negates the
callback result. This permits a future callback to perform one staging action,
return `FALSE`, and perform another action on a later invocation. `STAGE.` still
has its built-in one-physics-tick yield.

Burnout is detected when a selected engine reports both `IGNITION` and
`FLAMEOUT`, avoiding the normal unignited engine state. Both supplied callbacks
shut down all selected booster engines when burnout is first detected.
`DefaultBoosterStagingCallback` then issues one command as soon as
`STAGE:READY` is true and returns `TRUE`.

`ConsecutiveBoosterStagingCallback` issues the requested number of commands,
never more than one per invocation. It returns `FALSE` between commands and
waits `sepDelay` before the first command. It then uses both `timeInterval` and
`STAGE:READY` to decide when each later command is eligible. After issuing
command `stagingNumber`, it returns `TRUE` and the wrapper trigger expires. The
completed sequence and its actual time after liftoff are sent to PEGAS's UI.
Physical staging does not use `boosterSeparationDelay` in either mode.

Engine selection intentionally uses `TAG:CONTAINS`, allowing tags to carry
multiple labels. An empty or overly broad booster label can match unrelated
engines. The add-on avoids direct terminal printing because PEGAS redraws its
own terminal UI. It pushes only completed-separation messages and configuration
fallback warnings through `pushUIMessage`.

The live trigger and UPFG's mass model deliberately remain independent. If the
actual separation differs from the predicted mass-event time, UPFG uses the
wrong booster mass over that interval. The implementation does not dynamically
resynchronize UPFG because doing so would require invasive changes to its stage
and convergence logic. `coreThrottleUpDelay` likewise remains relative to the
predicted burnout time, not the detected physical separation.

## Full-thrust and throttled-core flight

Let \(g_0\) be standard gravity. For booster and core engine groups, define

\[
v_B=I_Bg_0,\qquad v_C=I_Cg_0,
\]

where \(I_B,I_C\) are specific impulses. Their full-thrust mass flows are

\[
q_B=\frac{T_B}{v_B},\qquad q_C=\frac{T_C}{v_C}.
\]

Let \(P\) be `payloadMass`. In all equations below, the core wet and dry masses
are the physical prediction masses

\[
m_{C,w}=m_{C,w,\mathrm{input}}+P,\qquad
m_{C,d}=m_{C,d,\mathrm{input}}+P.
\]

Thus payload is part of \(m_C\) and total vehicle mass \(M\), but not of the
booster mass. Before core throttle-down, the masses are linear functions of
time:

\[
m_B(t)=m_{B,w}-q_Bt,\qquad
m_C(t)=m_{C,w}-q_Ct.
\]

Thus the unthrottled booster burnout time is

\[
t_{B,0}=\frac{m_{B,w}-m_{B,d}}{q_B}.
\]

If \(t_{B,0}\le t_d\), core throttling is cancelled and the status is
`no_core_throttling`.

After \(t_d\), let \(u\in[0,1]\) be KSP main throttle, \(l_B,l_C\) the physical
minimum throttle levels, and \(d\) the core throttle-down level. Thrust is

\[
T_B(u)=T_B\left[l_B+(1-l_B)u\right],
\]

\[
T_C(u)=T_C\left[l_C+(d-l_C)u\right].
\]

For compactness, define

\[
a_T=T_B(1-l_B)+T_C(d-l_C),\qquad
b_T=T_Bl_B+T_Cl_C,
\]

\[
a_m=\frac{T_B(1-l_B)}{v_B}+\frac{T_C(d-l_C)}{v_C},\qquad
b_m=\frac{T_Bl_B}{v_B}+\frac{T_Cl_C}{v_C}.
\]

Then total thrust and positive propellant flow are affine in main throttle:

\[
T(u)=a_Tu+b_T,\qquad q(u)=a_mu+b_m.
\]

At \(u=1\), the combined thrust is \(T_B+dT_C\) and the combined flow is
\(q_B+dq_C\). Until the first g-limit is reached, both component masses
therefore remain linear in time.

## Constant-g solution

Let

\[
G=g_{\mathrm{lim},1}g_0.
\]

At constant g-load, \(T=GM\), so the required main throttle is

\[
u(M)=\frac{GM-b_T}{a_T}.
\]

Substitution into the total-mass equation gives the linear ODE

\[
\dot M=-a_m\frac{GM-b_T}{a_T}-b_m=-\alpha M-\beta,
\]

with

\[
\alpha=\frac{a_mG}{a_T},\qquad
\beta=b_m-\frac{a_mb_T}{a_T}.
\]

If \(\tau\) is time since constant-g flight starts and \(M_0\) is the mass at
that instant, the solution is

\[
M(\tau)=\left(M_0+\frac{\beta}{\alpha}\right)e^{-\alpha\tau}
-\frac{\beta}{\alpha}.
\]

For the booster alone, define

\[
a_B=\frac{T_B(1-l_B)}{v_B},\qquad
b_B=\frac{T_Bl_B}{v_B},
\]

\[
p=\frac{a_BG}{a_T},\qquad r=b_B-\frac{a_Bb_T}{a_T}.
\]

Its ODE is \(\dot m_B=-pM-r\). Integrating the total-mass solution produces

\[
m_B(\tau)=m_{B,0}
-\frac{p}{\alpha}\left(M_0+\frac{\beta}{\alpha}\right)
\left(1-e^{-\alpha\tau}\right)
+\left(\frac{p\beta}{\alpha}-r\right)\tau.
\]

Because this is an exponential plus a linear term, its inverse is not expressed
using the elementary functions available in kOS. The helper solves
\(m_B(\tau)-m_{B,d}=0\) with Newton steps constrained to a bracket. A Newton
step outside the bracket is replaced by bisection. Iteration stops after 32
steps at most, and may stop early when the mass error is at most \(10^{-3}\) kg
or the bracket width is at most \(10^{-6}\) s.

## Minimum-throttle overload

The ideal requested main throttle reaches zero at

\[
M_f=\frac{b_T}{G}.
\]

When \(M_0>M_f\), the elapsed constant-g time to this point is

\[
\tau_f=\frac{1}{\alpha}
\ln\left(\frac{M_0+\beta/\alpha}{M_f+\beta/\alpha}\right).
\]

If the booster mass at \(\tau_f\) is at or below dry mass, the bounded root is
found in \([0,\tau_f]\). Otherwise the status becomes `overload1`. From that
point the internal prediction uses exact main throttle \(u=0\), giving constant
flows \(b_B\) for the booster and \(b_m\) for the whole vehicle. The remaining
time is

\[
\Delta t=\frac{m_B(\tau_f)-m_{B,d}}{b_B}.
\]

This exact-zero value is deliberately an internal burnout calculation. PEGAS
continues to own the actual flight throttle controller.

At booster burnout, the remaining core mass is obtained from mass conservation:

\[
m_{C,j}=M_j-m_{B,d}.
\]

## Core-only g-limit and separation time

After booster jettison the core is restored to full thrust. Let

\[
G_2=g_{\mathrm{lim},2}g_0,\qquad
q_C=\frac{T_C}{I_Cg_0}.
\]

Without a g-limit, the remaining core burn duration would be

\[
\Delta t_{C,f}=\frac{m_{C,j}-m_{C,d}}{q_C}.
\]

Full thrust reaches `glim2` at mass and elapsed time

\[
M_{C,g}=\frac{T_C}{G_2},\qquad
\Delta t_{C,g}=\max\left(0,\frac{m_{C,j}-M_{C,g}}{q_C}\right).
\]

If \(\Delta t_{C,g}\ge\Delta t_{C,f}\), the core never reaches the limit and
the full-thrust duration is used. Otherwise the mass at g-limit activation is
\(M_{C,0}=m_{C,j}-q_C\Delta t_{C,g}\). The minimum-throttle mass is

\[
M_{C,\min}=\frac{T_Cl_C}{G_2}.
\]

For a single engine group at constant g, mass falls exponentially with rate
\(g_{\mathrm{lim},2}/I_C\). If \(m_{C,d}\ge M_{C,\min}\), the limit can be
maintained through separation and

\[
\Delta t_C=\Delta t_{C,g}
+\frac{I_C}{g_{\mathrm{lim},2}}
\ln\left(\frac{M_{C,0}}{m_{C,d}}\right).
\]

If dry mass is below \(M_{C,\min}\), constant-g flight ends at the throttle
floor. The remaining burn uses constant minimum thrust:

\[
\Delta t_C=\Delta t_{C,g}
+\frac{I_C}{g_{\mathrm{lim},2}}
\ln\left(\frac{M_{C,0}}{M_{C,\min}}\right)
+\frac{M_{C,\min}-m_{C,d}}{q_Cl_C}.
\]

If the core starts at or below \(M_{C,\min}\), `glim2` cannot be maintained
even at throttle-up and the entire remaining burn is predicted at minimum
throttle. Finally,

\[
\texttt{coreSeperationTime}=t_j+\Delta t_C.
\]

## Mapping to PEGAS stages

The throttled-core logical stage declares nominal engine thrusts \(T_B\) and
\(dT_C\). Its aggregate PEGAS minimum throttle is

\[
\text{minThrottle}_1=\frac{b_T}{T_B+dT_C}.
\]

This makes PEGAS's stage-level conversion from desired thrust fraction back to
KSP main throttle agree with the combined affine thrust model. The stage also
declares `gLim = glim1`. The post-jettison core stage declares its full thrust,
`minThrottle = l_C`, and `gLim = glim2`.

For an ordinary profile, physical-model mass continuity is enforced by

\[
M_{\text{full,dry}}=M_{\text{down,total}},
\]

\[
M_{\text{down,dry}}=m_{B,d}+m_{C,j},\qquad
M_{\text{up,total}}=m_{C,j}.
\]

Let a hat denote a mass written into a returned PEGAS stage lexicon. Payload is
removed from every returned mass field:

\[
\widehat M_{\text{full,total}}=M_{\text{full,total}}-P,\qquad
\widehat M_{\text{full,dry}}=M_{\text{full,dry}}-P,
\]

\[
\widehat M_{\text{down,total}}=M_{\text{down,total}}-P,\qquad
\widehat M_{\text{down,dry}}=M_{\text{down,dry}}-P,
\]

\[
\widehat M_{\text{up,total}}=M_{\text{up,total}}-P,\qquad
\widehat M_{\text{up,dry}}=m_{C,d}-P.
\]

Consequently the payload-free stage definitions still satisfy

\[
\widehat M_{\text{full,dry}}=\widehat M_{\text{down,total}},\qquad
\widehat M_{\text{down,dry}}-m_{B,d}=\widehat M_{\text{up,total}}.
\]

PEGAS later restores \(P\) to every one of these wet and dry masses.

All three logical stages use `jettison = FALSE` and `ignition = FALSE`. Core
throttle-limit changes remain scheduled events in the caller's launch sequence.
Booster mass loss also remains a scheduled event, while physical booster
separation is either performed by that event in legacy mode or by the live
staging callback.
