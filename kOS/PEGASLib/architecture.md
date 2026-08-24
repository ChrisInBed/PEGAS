# Booster-core stage profile

`make_throttle_stage_config` converts a parallel booster/core burn into the three
logical stages expected by PEGAS. The first stage represents the initial
full-thrust burn, the second represents the core-throttled booster burn, and the
third represents the core after booster separation. PEGAS creates the
constant-acceleration virtual stages associated with `gLim`; the helper still
has to predict booster burnout explicitly so that the separation time and the
core mass at separation are correct.

## Inputs and result

`boosterInfo` and `coreInfo` are lexicons with these fields:

| Field | Units | Meaning |
| --- | --- | --- |
| `massWet` | kg | Initial mass of the engine group and everything assigned to it |
| `massDry` | kg | Mass remaining when that engine group runs out of propellant |
| `thrust` | N | Maximum vacuum thrust |
| `isp` | s | Vacuum specific impulse |
| `throttleMinLevel` | 0-1 | Physical engine throttle at KSP main throttle zero |

`eventInfo` contains `throttleDownTime` in seconds, `throttleDownLevel` as the
core's physical throttle after throttling down, and the acceleration limits
`glim1` and `glim2` in multiples of standard gravity. The optional
`boosterSeparationDelay` and `coreThrottleUpDelay` fields are offsets from
predicted booster burnout. They default to zero and the separation delay,
respectively.

The returned lexicon has `fullStage`, `throttleDownStage`, and
`throttleUpStage`; `status`; `jettisonMass`; `throttleDownTime`; and
`jettisonTime`. The jettison time is measured from liftoff and is the predicted
instant at which booster mass reaches `massDry`. It does not include a
mechanical separation delay. `throttleDownTime` always echoes the requested
event time, including when `no_core_throttling` cancels that event.

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
the user-defined `vehicle`, `sequence`, and `controls` structures. It calls
`make_throttle_stage_config`, mutates the two supplied lists, and returns the
calculated stage-config lexicon.

Generated stages are prepended to `vehicle` in flight order only when their
predicted end time is strictly later than `controls["upfgActivation"]`. A stage
ending exactly at activation is already complete and is omitted. The candidate
end times are throttle-down for the full-thrust phase, booster burnout for the
throttled booster/core phase, and the analytically predicted `glim2` burnout for
the core-only phase. The upper stages already supplied by the user retain their
relative order.

Throttle-down, booster-separation, and throttle-up events are inserted into the
user's existing `sequence`. The input sequence must already be ordered by
`time`. Insertion preserves ascending time order and places generated events
after existing events with the same timestamp. Throttle-down and throttle-up
events are omitted when the profile status is `no_core_throttling`.

## Full-thrust and throttled-core flight

Let \(g_0\) be standard gravity. For booster and core engine groups, define

\[
v_B=I_Bg_0,\qquad v_C=I_Cg_0,
\]

where \(I_B,I_C\) are specific impulses. Their full-thrust mass flows are

\[
q_B=\frac{T_B}{v_B},\qquad q_C=\frac{T_C}{v_C}.
\]

Before core throttle-down, the masses are linear functions of time:

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

For an ordinary profile, mass continuity is enforced by

\[
M_{\text{full,dry}}=M_{\text{down,total}},
\]

\[
M_{\text{down,dry}}=m_{B,d}+m_{C,j},\qquad
M_{\text{up,total}}=m_{C,j}.
\]

All three logical stages use `jettison = FALSE` and `ignition = FALSE`; the
physical separation and core throttle-limit changes remain scheduled events in
the caller's launch sequence.
