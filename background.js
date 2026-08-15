/* ============================================================
   Animated economics background for the homepage.
   Four layers drawn on one full-page fixed canvas:
     1. A drifting network graph whose nodes are economic
        variables (pi, y, i, epsilon, Sigma, ...) — VAR-style
        interactions appear as edges between nearby nodes.
     2. Floating equations (Taylor rule, NK Phillips curve,
        VAR / TVP-VAR, stochastic volatility ...), each in its
        own colour.
     3. Small 2-D impulse-response panels that draw themselves,
        hold, fade out, and respawn elsewhere.
     4. A filled, shaded 3-D time-varying IRF SURFACE, drawn in the
        style of MATLAB's surf() and held at a fixed viewpoint
        (axes: horizon h, time t, response size) — the signature
        TVP-VAR graphic. Its shape also evolves over time.

   ------------------------------------------------------------
   HOW TO CUSTOMISE: edit the STYLE block below.
     intensity   master visibility knob. 1 = current look,
                 0.5 = very subtle, 1.5-2 = bold.
     speed       1 = current pace, 2 = twice as fast.
     palette     the colours used across all layers.
     surface     size/position/spin of the 3-D IRF surface.
   Equations and node labels are edited further down in the
   EQUATIONS and LABELS arrays.
   ============================================================ */

(function () {
  "use strict";

  var STYLE = {
    intensity:   1.0,             // master opacity multiplier
    speed:       1.0,             // master speed multiplier
    ink:         "29, 41, 61",    // axes & small labels (dark slate)

    // colour palette, [R, G, B] — used by equations, nodes, panels,
    // and (first three entries) the 3-D surface gradient
    palette: [
      [105, 179, 162],            // teal
      [42, 120, 214],             // blue
      [232, 161, 0],              // amber
      [128, 100, 162],            // purple
      [227, 73, 72]               // coral
    ],

    edgeAlpha:   0.20,            // network edges
    nodeAlpha:   0.55,            // nodes
    labelAlpha:  0.70,            // variable labels (pi, y, i, ...)
    linkDist:    150,             // px distance for an edge to appear

    eqAlphaMin:  0.20,            // floating equations (min–max)
    eqAlphaMax:  0.34,
    eqSizeMin:   14,
    eqSizeMax:   23,

    panelAlpha:  0.34,            // 2-D impulse-response panels

    surface: {                    // 3-D time-varying IRF surface
      // Drawn as a filled, shaded surface in the style of MATLAB's surf():
      // colour-mapped faces with a mesh drawn over them. The viewpoint is
      // fixed (no spin); the surface still drifts, because its SHAPE keeps
      // evolving — see `evolve` below.
      alpha:     0.34,            // axes and their labels
      faceAlpha: 0.45,            // shaded faces — raise for a more solid surface
      edgeAlpha: 0.30,            // mesh over the faces (MATLAB EdgeAlpha)
      colormap:  "parula",        // "parula" = MATLAB default; "site" = page palette
      size:      0.44,            // fraction of min(width, height)
      posX:      0.80,            // centre, fraction of width (wide screens)
      posY:      0.56,            // centre, fraction of height
      azimuth:   -0.80,           // fixed view, radians (MATLAB view az = -46 deg)
      elevation: 0.485,           // vertical squash = sin(29 deg), MATLAB view el
      evolve:    0.0028           // how fast the surface reshapes
    }
  };

  var canvas = document.getElementById("econ-bg");
  if (!canvas) return;

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    canvas.remove();
    return;
  }

  var ctx = canvas.getContext("2d");
  var W, H, DPR;
  var INK = STYLE.ink;
  var PAL = STYLE.palette;

  function al(a) { return Math.min(1, a * STYLE.intensity); }
  function rgba(c, a) { return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + a + ")"; }
  function mix(c1, c2, t) {
    return [Math.round(c1[0] + (c2[0] - c1[0]) * t),
            Math.round(c1[1] + (c2[1] - c1[1]) * t),
            Math.round(c1[2] + (c2[2] - c1[2]) * t)];
  }

  /* Frame-rate independence.
     Every speed in this file was tuned by eye on a 60 Hz screen, where one
     frame is 16.67 ms. Advancing by a fixed amount per FRAME means a 120 Hz
     monitor runs the whole animation at double speed, and 144 Hz at 2.4x.
     `step` is the number of 60 Hz frames the last frame actually took, so
     motion is multiplied by it and the animation runs at the same pace on
     any display. It is clamped so that a slow frame — or coming back from a
     background tab, where the gap can be seconds — cannot teleport anything. */
  var FRAME_MS = 1000 / 60;
  var lastTime = 0;
  var step = 1;

  function updateStep(now) {
    if (!lastTime) { lastTime = now; step = 1; return; }
    step = Math.min(3, (now - lastTime) / FRAME_MS);
    lastTime = now;
  }

  function resize() {
    DPR = Math.min(window.devicePixelRatio || 1, 2);
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = W * DPR;
    canvas.height = H * DPR;
    canvas.style.width = W + "px";
    canvas.style.height = H + "px";
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  }
  resize();
  window.addEventListener("resize", function () {
    resize();
    if (typeof refitNodes === "function") refitNodes();
  });

  /* ---------------- Layer 1: variable network ---------------- */

  var LABELS = ["π", "y", "i", "ε", "β", "Σ", "r*", "Δm",
                "u", "σ", "Eₜ", "φ"];
  function nodeCount() {
    return Math.max(26, Math.min(48, Math.round(W * H / 32000)));
  }
  var nodes = [];

  function makeNode(i) {
    return {
      x: Math.random() * W,
      y: Math.random() * H,
      vx: (Math.random() - 0.5) * 0.35 * STYLE.speed,
      vy: (Math.random() - 0.5) * 0.35 * STYLE.speed,
      r: 2 + Math.random() * 2.5,
      color: PAL[i % PAL.length],
      label: i < LABELS.length ? LABELS[i] : null
    };
  }
  for (var i = 0; i < nodeCount(); i++) nodes.push(makeNode(i));

  /* The node count is derived from the viewport area, but was only ever
     computed at startup — so a window resize (or a phone rotating) left the
     field too sparse or too crowded until reload. Top up or trim instead. */
  function refitNodes() {
    var want = nodeCount();
    while (nodes.length < want) nodes.push(makeNode(nodes.length));
    if (nodes.length > want) nodes.length = want;
  }

  function drawNetwork() {
    var LD = STYLE.linkDist;
    for (var a = 0; a < nodes.length; a++) {
      for (var b = a + 1; b < nodes.length; b++) {
        var dx = nodes[a].x - nodes[b].x;
        var dy = nodes[a].y - nodes[b].y;
        var d2 = dx * dx + dy * dy;
        if (d2 < LD * LD) {
          var alpha = al(STYLE.edgeAlpha * (1 - Math.sqrt(d2) / LD));
          ctx.strokeStyle = rgba(mix(nodes[a].color, nodes[b].color, 0.5), alpha);
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(nodes[a].x, nodes[a].y);
          ctx.lineTo(nodes[b].x, nodes[b].y);
          ctx.stroke();
        }
      }
    }
    for (var k = 0; k < nodes.length; k++) {
      var n = nodes[k];
      n.x += n.vx * step; n.y += n.vy * step;
      if (n.x < -20) n.x = W + 20; if (n.x > W + 20) n.x = -20;
      if (n.y < -20) n.y = H + 20; if (n.y > H + 20) n.y = -20;

      ctx.fillStyle = rgba(n.color, al(n.label ? STYLE.labelAlpha : STYLE.nodeAlpha));
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2);
      ctx.fill();

      if (n.label) {
        ctx.font = "italic 15px 'Source Serif 4', Georgia, serif";
        ctx.fillStyle = rgba(n.color, al(STYLE.labelAlpha));
        ctx.fillText(n.label, n.x + 7, n.y - 6);
      }
    }
  }

  /* ---------------- Layer 2: floating equations ---------------- */

  var EQUATIONS = [
    "yₜ = cₜ + B₁,ₜ yₜ₋₁ + uₜ",
    "πₜ = βEₜ[πₜ₊₁] + κxₜ + εₜ",
    "iₜ = r* + π* + φπ(πₜ − π*) + φyỹₜ",
    "Ωₜ = Aₜ⁻¹ΣₜΣₜ′(Aₜ⁻¹)′",
    "log σₜ = log σₜ₋₁ + ηₜ",
    "IRF(h) = eᵢ′ J Φₜʰ J′ Aₜ⁻¹Σₜ",
    "Eₜ[mₜ₊₁ Rₜ₊₁] = 1",
    "Y = C + I + G + NX",
    "MV = PY",
    "Δyₜ = α + βΔxₜ + εₜ",
    "βₜ = βₜ₋₁ + νₜ,  νₜ ~ N(0, Q)",
    "uₜ ~ N(0, Ωₜ)"
  ];

  // Most equations live on the LEFT side of the page (away from
  // the 3-D surface); every third one may roam the full width.
  var floats = EQUATIONS.map(function (eq, idx) {
    var region = (idx % 3 === 2) ? 1 : 0.5;   // fraction of width used
    return {
      text: eq,
      region: region,
      x: Math.random() * W * region,
      y: Math.random() * H,
      vy: -(0.12 + Math.random() * 0.22) * STYLE.speed,
      vx: (Math.random() - 0.5) * 0.06 * STYLE.speed,
      size: STYLE.eqSizeMin + Math.random() * (STYLE.eqSizeMax - STYLE.eqSizeMin),
      color: PAL[idx % PAL.length],
      alpha: STYLE.eqAlphaMin + Math.random() * (STYLE.eqAlphaMax - STYLE.eqAlphaMin)
    };
  });

  function drawEquations() {
    for (var i = 0; i < floats.length; i++) {
      var f = floats[i];
      f.x += f.vx * step; f.y += f.vy * step;
      if (f.y < -30) { f.y = H + 30; f.x = Math.random() * W * f.region; }
      ctx.font = "italic " + f.size + "px 'Source Serif 4', Georgia, serif";
      ctx.fillStyle = rgba(f.color, al(f.alpha));
      ctx.fillText(f.text, f.x, f.y);
    }
  }

  /* ------- Layer 3: self-drawing 2-D impulse-response panels ------- */

  var N_PANELS = W > 900 ? 2 : 1;
  var panels = [];

  function makePanel() {
    var w = 170 + Math.random() * 90;
    return {
      x: Math.random() * (W - w - 40) + 20,
      y: Math.random() * (H - 160) + 40,
      w: w,
      h: 80 + Math.random() * 40,
      amp: 0.5 + Math.random() * 0.5,
      lam: 0.10 + Math.random() * 0.12,
      hump: 2 + Math.random() * 5,
      sign: Math.random() < 0.5 ? 1 : -1,
      color: PAL[Math.floor(Math.random() * PAL.length)],
      progress: 0,
      life: 0,
      HOLD: 260,
      FADE: 120
    };
  }
  for (var p = 0; p < N_PANELS; p++) {
    var pan = makePanel();
    pan.progress = Math.random();
    panels.push(pan);
  }

  function irf(pan, h) {
    return pan.sign * pan.amp * h * Math.exp(-pan.lam * (h - pan.hump));
  }

  function drawPanel(pan) {
    var alpha = al(STYLE.panelAlpha);
    if (pan.life > pan.HOLD) {
      alpha *= Math.max(0, 1 - (pan.life - pan.HOLD) / pan.FADE);
    }
    var zero = pan.y + pan.h * 0.55;

    ctx.strokeStyle = "rgba(" + INK + "," + alpha * 0.8 + ")";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(pan.x, pan.y);
    ctx.lineTo(pan.x, pan.y + pan.h);
    ctx.lineTo(pan.x + pan.w, pan.y + pan.h);
    ctx.stroke();

    ctx.setLineDash([3, 4]);
    ctx.beginPath();
    ctx.moveTo(pan.x, zero);
    ctx.lineTo(pan.x + pan.w, zero);
    ctx.stroke();
    ctx.setLineDash([]);

    var H_MAX = 24;
    var upto = Math.max(2, Math.floor(H_MAX * Math.min(1, pan.progress)));
    var scale = pan.h * 0.32 / pan.amp / 3.2;
    ctx.strokeStyle = rgba(pan.color, Math.min(1, alpha * 3.2));
    ctx.lineWidth = 1.8;
    ctx.beginPath();
    for (var h = 0; h <= upto; h++) {
      var px = pan.x + (h / H_MAX) * pan.w;
      var py = zero - irf(pan, h) * scale * 3.2;
      if (h === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.stroke();

    ctx.fillStyle = rgba(pan.color, alpha * 0.5);
    ctx.beginPath();
    for (var h2 = 0; h2 <= upto; h2++) {
      var bx = pan.x + (h2 / H_MAX) * pan.w;
      var by = zero - irf(pan, h2) * scale * 3.2 - 9;
      if (h2 === 0) ctx.moveTo(bx, by); else ctx.lineTo(bx, by);
    }
    for (var h3 = upto; h3 >= 0; h3--) {
      ctx.lineTo(pan.x + (h3 / H_MAX) * pan.w,
                 zero - irf(pan, h3) * scale * 3.2 + 9);
    }
    ctx.closePath();
    ctx.fill();

    if (pan.progress < 1) pan.progress += 0.006 * STYLE.speed * step;
    else pan.life += STYLE.speed * step;
    if (pan.life > pan.HOLD + pan.FADE) {
      var fresh = makePanel();
      for (var key in fresh) pan[key] = fresh[key];
    }
  }

  /* ------- Layer 4: filled 3-D time-varying IRF surface -------
     With irf-surface.js present this is the ESTIMATED surface: the response
     of inflation to an activity shock, over horizon h and time t, from the
     hybrid TVP-BVAR with stochastic volatility. Real responses go negative,
     which the parametric stand-in below never did.

     Without it, the fallback is z(h, t) = A(t) · h · exp(−λ(t) · h), with A
     and λ drifting so the ridge rises and falls — the right SHAPE for a
     TVP-VAR impulse response, but invented. */

  var surfPhase = 0;     // shape evolution (fallback surface only)
  var surfReveal = 0;    // 0..1, how much of the real surface has drawn itself in

  /* Real estimated impulse responses, if irf-surface.js loaded ahead of this
     file. That script is generated from the MCMC output of the hybrid TVP-BVAR
     (see the header it carries) and simply assigns a global — deliberately not
     fetched as JSON, because fetch() is blocked under file:// and the surface
     would silently fall back whenever the page is opened from disk.
     Without it, the parametric surface below is used instead, so the homepage
     never depends on the data file being present. */
  var IRF = (typeof window !== "undefined" && window.__IRF_SURFACE__) || null;
  var HAVE_IRF = !!(IRF && IRF.z && IRF.nh > 1 && IRF.nt > 1);

  // With real data the grid is whatever was estimated (horizons x time points).
  // Otherwise: coarser than a wireframe would need, because once the faces are
  // filled a dense mesh reads as noise, and this is the density MATLAB shows.
  var NH = HAVE_IRF ? IRF.nh : 25;   // grid points along horizon
  var NT = HAVE_IRF ? IRF.nt : 19;   // grid points along time

  // Height field for the current frame, filled once per frame by drawSurface().
  var zGrid = new Float64Array(NH * NT);

  // MATLAB's parula, sampled at nine stops.
  var PARULA = [
    [ 53,  42, 135], [ 15,  92, 221], [ 18, 125, 216], [  7, 156, 207],
    [ 21, 177, 180], [ 89, 189, 140], [165, 190, 107], [225, 185,  82],
    [249, 251,  14]
  ];

  function rampAt(stops, t) {
    t = Math.max(0, Math.min(1, t));
    var seg = t * (stops.length - 1), i = Math.floor(seg);
    return mix(stops[i], stops[Math.min(i + 1, stops.length - 1)], seg - i);
  }

  // Painter's algorithm: faces must be drawn back to front. The viewpoint no
  // longer rotates, so that order never changes and is worked out once here
  // rather than re-sorted on every frame. Scaling by `size` cannot reorder it,
  // so screen size is irrelevant.
  var surfQuads = (function () {
    var az = STYLE.surface.azimuth;
    var sinT = Math.sin(az), cosT = Math.cos(az);
    var q = [];
    for (var ti = 0; ti < NT - 1; ti++) {
      for (var hi = 0; hi < NH - 1; hi++) {
        var x = ((hi + 0.5) / (NH - 1) - 0.5);
        var y = ((ti + 0.5) / (NT - 1) - 0.5);
        q.push({ h: hi, t: ti, d: x * sinT + y * cosT });
      }
    }
    q.sort(function (a, b) { return a.d - b.d; });   // farthest first
    return q;
  })();

  function surfZ(hi, ti) {
    if (HAVE_IRF) return IRF.z[hi][ti];           // estimated response
    var hh = hi * 16 / (NH - 1);                  // horizon 0..16
    var tt = ti / (NT - 1);                       // time in [0,1]
    var A   = 0.55 + 0.45 * Math.sin(2 * Math.PI * tt + surfPhase);
    var lam = 0.30 + 0.08 * Math.cos(2 * Math.PI * tt * 0.8 + surfPhase * 0.6);
    return A * hh * Math.exp(-lam * hh);          // roughly in [0, 1.3]
  }

  function drawSurface() {
    var S = STYLE.surface;
    var size = Math.min(W, H) * S.size;
    var cx = W > 900 ? W * S.posX : W * 0.5;
    var cy = H * S.posY;
    var zScale = size * 0.32;
    var cosT = Math.cos(S.azimuth), sinT = Math.sin(S.azimuth);

    function proj(hi, ti, z) {
      var x = (hi / (NH - 1) - 0.5) * size;
      var y = (ti / (NT - 1) - 0.5) * size;
      var xr = x * cosT - y * sinT;
      var yr = x * sinT + y * cosT;
      return [cx + xr, cy + yr * S.elevation - z * zScale];
    }

    var alpha = al(S.alpha);

    // Evaluate the height field ONCE per frame into a flat grid. Reading it
    // back costs an array lookup; calling surfZ() per corner instead meant
    // every interior vertex was recomputed four times over — 2203 evaluations
    // of sin/cos/exp per frame where there are only NH*NT = 475 distinct ones.
    // Colour also needs the frame's min and max, which this pass collects.
    var zLo = Infinity, zHi = -Infinity, zAbs = 0;
    for (var si = 0; si < NH; si++) {
      for (var sj = 0; sj < NT; sj++) {
        var zv = surfZ(si, sj);
        zGrid[si * NT + sj] = zv;
        if (zv < zLo) zLo = zv;
        if (zv > zHi) zHi = zv;
        if (Math.abs(zv) > zAbs) zAbs = Math.abs(zv);
      }
    }
    // Estimated responses are in percentage points (roughly -0.3 to 0.8 here),
    // the fallback runs 0 to 1.3. Scale by the largest absolute value so either
    // fills the same space on screen. Dividing rather than shifting keeps zero
    // at zero, so the parts of the response that go NEGATIVE still read as
    // dipping below the base plane instead of being flattened onto it.
    var heightScale = 1.2 / (zAbs || 1);
    function zAt(hi, ti) { return zGrid[hi * NT + ti] * heightScale; }

    // Colour encodes the SIZE of the response. MATLAB stretches the colormap
    // across whatever the data actually spans (caxis auto), so do the same and
    // rescale to this frame's range — against a fixed ceiling the surface only
    // ever samples the blue end of parula and looks washed out.
    // zAt() returns heights already multiplied by heightScale, so the colour
    // range has to be scaled the same way or every face maps to one end of it.
    var zLoS = zLo * heightScale, zHiS = zHi * heightScale;
    var zSpan = (zHiS - zLoS) || 1;
    var SITE_RAMP = [PAL[1], PAL[0], PAL[2], PAL[4]];
    function zColor(z) {
      var t = (z - zLoS) / zSpan;
      return S.colormap === "site" ? rampAt(SITE_RAMP, t) : rampAt(PARULA, t);
    }

    // Filled faces, back to front, each outlined with the mesh line that
    // MATLAB draws over the surface. Stroking every quad also hides the
    // hairline seams that canvas anti-aliasing leaves between fills.
    var faceA = al(S.faceAlpha);
    var edgeA = al(S.edgeAlpha);
    ctx.lineWidth = 0.7;
    ctx.lineJoin = "round";

    /* The estimated surface is a fixed object — nothing about it evolves, so
       without this it would simply sit there. Sweeping it in along the time
       axis once, then holding, gives it the same "draws itself" behaviour the
       2-D panels have, without animating anything the data does not do. */
    var revealTo = HAVE_IRF ? surfReveal * (NT - 1) : (NT - 1);

    for (var qi = 0; qi < surfQuads.length; qi++) {
      var h = surfQuads[qi].h, t = surfQuads[qi].t;
      if (t > revealTo) continue;
      var z00 = zAt(h, t),         z10 = zAt(h + 1, t);
      var z11 = zAt(h + 1, t + 1), z01 = zAt(h, t + 1);
      var p00 = proj(h, t, z00),         p10 = proj(h + 1, t, z10);
      var p11 = proj(h + 1, t + 1, z11), p01 = proj(h, t + 1, z01);

      ctx.beginPath();
      ctx.moveTo(p00[0], p00[1]);
      ctx.lineTo(p10[0], p10[1]);
      ctx.lineTo(p11[0], p11[1]);
      ctx.lineTo(p01[0], p01[1]);
      ctx.closePath();

      ctx.fillStyle = rgba(zColor((z00 + z10 + z11 + z01) / 4), faceA);
      ctx.fill();
      ctx.strokeStyle = "rgba(" + INK + "," + edgeA + ")";
      ctx.stroke();
    }

    // axes from the (h=0, t=0, z=0) corner
    var o  = proj(0, 0, 0);
    var eh = proj(NH - 1, 0, 0);
    var et = proj(0, NT - 1, 0);
    var ez = proj(0, 0, 1.35);
    ctx.strokeStyle = "rgba(" + INK + "," + alpha * 0.9 + ")";
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(o[0], o[1]); ctx.lineTo(eh[0], eh[1]); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(o[0], o[1]); ctx.lineTo(et[0], et[1]); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(o[0], o[1]); ctx.lineTo(ez[0], ez[1]); ctx.stroke();

    ctx.font = "italic 12px 'Source Serif 4', Georgia, serif";
    ctx.fillStyle = "rgba(" + INK + "," + Math.min(1, alpha * 1.6) + ")";
    ctx.fillText("horizon (h)", eh[0] + 5, eh[1] + 4);
    ctx.fillText("time (t)", et[0] + 5, et[1] + 4);
    ctx.fillText("IRFₜ(h)", ez[0] + 5, ez[1] - 4);

    // No spin — the viewpoint is fixed.
    if (HAVE_IRF) {
      // Real data: sweep in once, then hold. surfPhase would do nothing.
      if (surfReveal < 1) surfReveal = Math.min(1, surfReveal + 0.004 * STYLE.speed * step);
    } else {
      surfPhase += S.evolve * STYLE.speed * step;
    }
  }

  /* ---------------- main loop ---------------- */

  var visible = true;     // tab is in the foreground
  var onScreen = true;    // canvas is actually within the viewport
  var queued = false;

  function resume() {
    if (!visible || !onScreen || queued) return;
    // Discard the elapsed time accumulated while paused, or the first frame
    // back would carry a step of seconds.
    lastTime = 0;
    queued = true;
    requestAnimationFrame(tick);
  }

  document.addEventListener("visibilitychange", function () {
    visible = !document.hidden;
    resume();
  });

  /* The canvas is position:fixed and full-page, so it stops being visible
     once the reader scrolls into the page content — but nothing here noticed
     that, and the loop went on drawing behind the article. */
  if (typeof IntersectionObserver === "function") {
    new IntersectionObserver(function (entries) {
      onScreen = entries[0].isIntersecting;
      resume();
    }, { threshold: 0 }).observe(canvas);
  }

  /* Honour a reduced-motion preference that is turned on AFTER load, not just
     the value read at startup. */
  var motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  var onMotionChange = function (e) {
    if (e.matches) { visible = false; canvas.remove(); }
  };
  if (motionQuery.addEventListener) motionQuery.addEventListener("change", onMotionChange);
  else if (motionQuery.addListener) motionQuery.addListener(onMotionChange);

  function tick(now) {
    queued = false;
    if (!visible || !onScreen) return;
    updateStep(now || 0);
    ctx.clearRect(0, 0, W, H);
    drawEquations();
    drawNetwork();
    drawSurface();
    for (var i = 0; i < panels.length; i++) drawPanel(panels[i]);
    queued = true;
    requestAnimationFrame(tick);
  }
  queued = true;
  requestAnimationFrame(tick);
})();
