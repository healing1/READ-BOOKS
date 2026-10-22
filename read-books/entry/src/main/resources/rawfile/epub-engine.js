/* Trusted application code, injected by ArkWeb controller. Book scripts are disabled by CSP. */
(function () {
  'use strict';
  if (window.ReadBooks) return;
  let config = {}, page = 0, pages = 1, step = 1, token = '', applying = false;
  let vertical = false, fixed = false, restore = null, timer = 0, touch = null;
  let requestedFont = '';
  let contentNodes = null, geometry = [], headings = [], direction = 'ltr';
  let layoutEpoch = 0, presented = false, presenting = false, motionUntil = 0;
  let gutter = 0, edgesOpen = false, edgeTimer = 0;
  let inputHeld = false;
  let replayTurns = 0, replayTimer = 0;
  const html = document.documentElement, body = document.body;
  const style = document.createElement('style');
  style.id = 'readbooks-style';
  document.head.appendChild(style);
  const emit = data => console.info(token + JSON.stringify(data));
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  function elements() {
    if (!contentNodes) contentNodes = Array.from(body.querySelectorAll('p,h1,h2,h3,h4,li,figure,img,table,div,section,svg'));
    return contentNodes;
  }
  function indexGeometry() {
    // Book scripts cannot mutate the DOM. Re-index only when layout, images or fonts change.
    geometry = elements().map(node => node.getBoundingClientRect());
    headings = Array.from(body.querySelectorAll('h1[id],h2[id],h3[id],h4[id],h5[id],h6[id]'))
      .map(node => ({ id: node.id, rect: node.getBoundingClientRect() }));
  }
  function neutralColor(value) {
    const parts = String(value || '').match(/[\d.]+/g);
    if (!parts || parts.length < 3 || (parts.length > 3 && Number(parts[3]) === 0)) return false;
    const rgb = parts.slice(0, 3).map(Number);
    return Math.max(...rgb) - Math.min(...rgb) < 28;
  }
  function themeInk(next) {
    // Change neutral paper/ink, not the publisher's colored ornaments or images.
    const marks = Array.from(body.querySelectorAll('*')).filter(node => !node.closest('svg') && !/^(IMG|CANVAS|VIDEO)$/i.test(node.tagName))
      .map(node => { const author = getComputedStyle(node); return { node, ink: neutralColor(author.color), paper: neutralColor(author.backgroundColor) }; });
    // Batch style reads before attribute writes; interleaving these forces repeated style calculation.
    for (const { node, ink, paper } of marks) {
      node.removeAttribute('data-readbooks-neutral-ink');
      node.removeAttribute('data-readbooks-neutral-paper');
      if (ink) node.setAttribute('data-readbooks-neutral-ink', '');
      if (paper) node.setAttribute('data-readbooks-neutral-paper', '');
    }
    return `body,[data-readbooks-neutral-ink]{color:${next.text}!important}body,[data-readbooks-neutral-paper]{background-color:transparent!important}a,a *{color:${next.dark ? '#9AC2FF' : '#245BA0'}!important}`;
  }
  function readingRect(r) {
    if (fixed) return r;
    // Geometry is in document coordinates. Computing the selected destination requires no DOM reads,
    // even while a compositor transition or finger drag is between two pages.
    const sign = !vertical && direction === 'rtl' ? 1 : -1;
    const dx = vertical ? 0 : sign * page * step;
    const dy = vertical ? -page * step : 0;
    return { left: r.left + dx, right: r.right + dx, top: r.top + dy, bottom: r.bottom + dy,
      width: r.width, height: r.height };
  }
  function locator() {
    let found = -1, distance = Infinity;
    geometry.forEach((rect, i) => {
      const r = readingRect(rect);
      if (r.width <= 0 || r.height <= 0 || r.right <= gutter || r.bottom <= 0 || r.left >= innerWidth - gutter || r.top >= innerHeight) return;
      // A paragraph continued from an earlier column must not restore its earlier start.
      if (vertical ? r.top < -1 : r.left < gutter - 1) return;
      const d = Math.abs(vertical ? r.top : r.left - gutter) + Math.abs(r.top) * 0.05;
      if (d < distance) { distance = d; found = i; }
    });
    return { element: found, fraction: pages > 1 ? page / (pages - 1) : 0 };
  }
  function report() {
    let fragment = '';
    headings.forEach(heading => {
      const r = readingRect(heading.rect);
      if (vertical ? r.top < innerHeight : r.left < innerWidth - gutter) fragment = heading.id;
    });
    emit({ type: 'position', page, pages, locator: locator(), images: document.images.length,
      loadedImages: Array.from(document.images).filter(img => img.complete && img.naturalWidth > 0).length,
      fixed, vertical, rtl: direction === 'rtl', fragment });
  }
  function measure() {
    if (fixed) { pages = 1; return; }
    pages = Math.max(1, Math.ceil(((vertical ? body.scrollHeight : body.scrollWidth) + 1) / step - 0.01));
  }
  function clipEdges(open) {
    if (edgesOpen === open && html.style.clipPath) return;
    edgesOpen = open;
    html.style.clipPath = `inset(0px ${open ? 0 : gutter}px)`;
  }
  // Same release policy as PageTurnMotion.ets; regression tests compare both paths.
  function pageSettle(distance, span, velocity = null) {
    const remaining = Math.abs(distance);
    if (remaining < 0.5) return { duration: 0, firstY: 0 };
    const fraction = Math.min(1, remaining / Math.max(1, span));
    const ceiling = 200 + 120 * Math.sqrt(fraction);
    const floor = 160 + 60 * Math.sqrt(fraction);
    const speed = velocity === null ? 0 : Math.max(0, Math.sign(distance) * velocity);
    const duration = Math.round(speed > 0.05 ? Math.max(floor, ceiling / (1 + speed * 60 / Math.max(1, span))) : ceiling);
    return { duration, firstY: velocity === null ? 0.28 : Math.min(0.4, speed * duration / remaining * 0.2) };
  }
  function sampleVelocity(point) {
    const now = Date.now(), x = pointerX(point), elapsed = now - touch.sampleTime;
    if (elapsed <= 0) return;
    if (x !== touch.sampleX) {
      const speed = elapsed > 100 ? 0 : (x - touch.sampleX) / elapsed;
      touch.velocity = touch.velocity * speed > 0 ? touch.velocity * 0.35 + speed * 0.65 : speed;
      touch.sampleX = x; touch.sampleTime = now; touch.movedAt = now;
    } else if (now - touch.movedAt > 80) { touch.velocity = 0; touch.sampleTime = now; }
  }
  function handoffBody() {
    // A new gesture can reach the chapter boundary while the previous in-chapter
    // transition is paused. Let that small remainder finish inside the moving native
    // surface; otherwise cancelling the chapter drag leaves the old spread half shown.
    if (!touch.edge && !fixed && !vertical && Math.abs(touch.position - (direction === 'rtl' ? 1 : -1) * page * step) > 0.5) {
      display(page, true, touch.velocity);
    }
    touch.edge = true;
  }
  function closeEdges() { motionUntil = 0; clipEdges(false); }
  function display(index, animated, velocity = null, sharedMotion = null) {
    const sign = !vertical && direction === 'rtl' ? 1 : -1;
    const origin = touch && !vertical ? touch.position : sign * page * step;
    page = clamp(index, 0, pages - 1);
    clearTimeout(edgeTimer);
    if (!fixed) {
      const motion = sharedMotion || pageSettle(sign * page * step - origin, step, velocity);
      const moving = animated && !config.reduceMotion && motion.duration > 0;
      // Keep the original type area at rest, but let moving text reach the physical screen edge.
      // The Web viewport spans the whole screen; this clip changes only at gesture boundaries.
      clipEdges(moving);
      motionUntil = moving ? Date.now() + motion.duration : 0;
      if (moving) edgeTimer = setTimeout(closeEdges, motion.duration + 50);
      body.style.transition = moving ? `transform ${motion.duration}ms cubic-bezier(.2,${motion.firstY},.55,1)` : 'none';
      body.style.transform = vertical ? `translate3d(0,${-page * step}px,0)` : `translate3d(${sign * page * step}px,0,0)`;
    }
    report();
  }
  function restoreLocator(value) {
    if (!value) return 0;
    if (Number.isInteger(value.element) && value.element >= 0 && geometry[value.element]) {
      const r = geometry[value.element];
      return Math.floor(Math.max(0, vertical ? r.top : r.left - gutter) / step);
    }
    return Math.round(clamp(Number(value.fraction) || 0, 0, 1) * Math.max(0, pages - 1));
  }
  function anchor(fragment) {
    if (!fragment) return false;
    let id = fragment;
    try { id = decodeURIComponent(fragment); } catch (_) {}
    const node = document.getElementById(id) || document.getElementsByName(id)[0];
    if (!node) return false;
    body.style.transition = 'none';
    if (!fixed) body.style.transform = 'none';
    const r = node.getBoundingClientRect();
    display(fixed ? 0 : Math.floor(Math.max(0, vertical ? r.top : r.left - gutter) / step), false);
    return true;
  }
  function layout(next, target) {
    applying = true;
    clearTimeout(replayTimer); replayTurns = 0;
    layoutEpoch++;
    const current = target || (token ? locator() : null);
    config = next; token = next.token; fixed = !!next.fixed;
    // ASYNC_RENDER Web surfaces can receive input even under an opaque-zero
    // ArkUI wrapper. Warm documents must never turn themselves off their edge.
    inputHeld = !!next.warm;
    clearTimeout(edgeTimer); edgesOpen = false; motionUntil = 0; touch = null;
    gutter = clamp(Number(next.gutter) || 0, 0, Math.max(0, (innerWidth - 120) / 2));
    html.style.clipPath = `inset(0px ${gutter}px)`;
    body.style.transition = 'none'; body.style.transform = 'none';
    style.textContent = '';
    const author = getComputedStyle(body);
    direction = author.direction;
    vertical = !fixed && author.writingMode.startsWith('vertical');
    const gap = next.spread && !vertical ? 48 : 0;
    const width = Math.max(120, innerWidth - gutter * 2), height = Math.max(120, innerHeight);
    const backgroundImage = String(author.backgroundImage || 'none');
    const hasBackground = /url\(/i.test(backgroundImage);
    const picturePage = !fixed && String(body.textContent || '').replace(/\s/g, '').length < 30 &&
      (hasBackground || document.images.length > 0 || !!body.querySelector('svg'));
    step = vertical ? height : width + gap;
    const family = next.font ? `@font-face{font-family:ReaderUser;src:url('${next.font}');font-display:swap}body,body *{font-family:ReaderUser!important}` : '';
    const type = !next.publisher ? `html{font-size:${next.fontSize}px!important}body{font-size:1rem!important}p,li,div,blockquote{line-height:${next.lineHeight}!important}` : '';
    const paper = `html{background:${next.background ? 'transparent' : next.bg}!important;color-scheme:${next.dark ? 'dark' : 'light'}}`;
    // Preserve illustrations in night mode: change text/surfaces, never invert the image pixels.
    const ink = next.dark || next.paper || next.background ? themeInk(next) : '';
    if (fixed) {
      const viewport = document.querySelector('meta[name="readbooks-publisher-viewport"]');
      const source = viewport ? viewport.content : '';
      const svg = body.querySelector('svg');
      const vb = svg && svg.viewBox && svg.viewBox.baseVal;
      const w = Number((source.match(/width\s*=\s*([\d.]+)/i) || [])[1]) || (vb && vb.width) || parseFloat(author.width) || width;
      const h = Number((source.match(/height\s*=\s*([\d.]+)/i) || [])[1]) || (vb && vb.height) || parseFloat(author.height) || height;
      const scale = Math.min(width / w, height / h);
      style.textContent = paper + ink + `html{overflow:hidden!important}body{position:absolute!important;margin:0!important;width:${w}px!important;height:${h}px!important;left:${gutter+(width-w*scale)/2}px!important;top:${(height-h*scale)/2}px!important;transform-origin:0 0!important;transform:scale(${scale})!important}`;
    } else {
      const flow = picturePage ? `width:${width}px!important;height:${height}px!important;column-count:auto!important;column-width:auto!important` : vertical ? `width:${width}px!important;min-height:${height}px!important;column-count:auto!important;column-width:auto!important` :
        `width:${width}px!important;height:${height}px!important;column-width:${next.spread ? (width-gap)/2 : width}px!important;column-gap:${gap}px!important;column-fill:auto!important`;
      // Phone-sized cover backgrounds otherwise crop almost the whole portrait on a wide Pad.
      // Keep artwork intact, including CSS backgrounds (not just <img>), and stop fixed backgrounds
      // from being re-rasterized against the viewport during the page's transform animation.
      const backgroundFit = hasBackground ? `body{background-attachment:scroll!important;${picturePage || author.backgroundSize === 'cover' ? 'background-size:contain!important;background-position:center!important;background-repeat:no-repeat!important;' : ''}}` : '';
      const standalone = picturePage ? `body{display:flex!important;align-items:center!important;justify-content:center!important}body>div,body>p,body>section,body>a{box-sizing:border-box!important;display:flex;align-items:center;justify-content:center;width:100%!important;height:100%!important;max-height:100%!important;margin:0!important;padding:0!important;text-indent:0!important}body img{width:auto!important;height:auto!important;max-width:100%!important;max-height:100%!important}body svg{width:100%!important;height:100%!important}` : '';
      style.textContent = paper + family + type + ink + `html{margin:0!important;padding:0!important;overflow:hidden!important;width:100%!important;height:100%!important}body{box-sizing:border-box!important;position:relative!important;left:${gutter}px!important;margin:0!important;padding:0!important;will-change:transform;${flow}}img,svg,video{max-width:100%!important;max-height:${Math.max(100, height - 8)}px!important;object-fit:contain;break-inside:avoid}img{height:auto!important}figure,table{max-width:100%;break-inside:avoid}h1,h2,h3{break-after:avoid}` + backgroundFit + standalone;
    }
    measure(); indexGeometry(); display(restoreLocator(current), false);
    const jumped = next.fragment ? anchor(next.fragment) : false;
    config.fragment = '';
    applying = false;
    // Keep the original semantic anchor across startup resize/font loads. Deriving a
    // fresh anchor from each intermediate layout can drift backwards by one spread.
    restore = jumped ? locator() : current || locator();
    if (requestedFont !== (next.font || '')) {
      requestedFont = next.font || '';
      const pendingFont = requestedFont;
      if (pendingFont && !fixed && document.fonts) {
        // A font selected after startup must reflow once its real glyph metrics arrive.
        document.fonts.load('18px ReaderUser').then(() => {
          if (requestedFont === pendingFont) stableReflow();
        }).catch(() => {});
      }
    }
  }
  async function present() {
    if (presented || presenting) return;
    presenting = true;
    const presentationToken = token;
    try {
      const started = Date.now();
      if (document.fonts) await document.fonts.ready;
      const fontReady = Date.now();
      // Resolve intrinsic dimensions first. A prepared offscreen neighbour additionally
      // decodes its illustrations below; the visible old page remains intact during that work.
      const visible = Array.from(document.images).filter(img => {
        const r = img.getBoundingClientRect();
        return r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight;
      });
      await Promise.all(visible.map(img => img.complete ? Promise.resolve() : new Promise(resolve => {
        const ready = () => { img.removeEventListener('load', ready); img.removeEventListener('error', ready); resolve(); };
        img.addEventListener('load', ready); img.addEventListener('error', ready);
        if (img.complete) ready();
      })));
      const imagesReady = Date.now();
      if (presentationToken !== token) return;
      if (config.warm) {
        // This happens on an offscreen neighbour while the current page remains visible.
        // Decode both inline illustrations and publisher background artwork before surface handoff.
        const backgrounds = [getComputedStyle(body).backgroundImage, getComputedStyle(html).backgroundImage]
          .flatMap(value => Array.from(String(value || '').matchAll(/url\(["']?([^"')]+)["']?\)/g), match => match[1]));
        const backgroundPictures = backgrounds.map(src => { const img = new Image(); img.src = src; return img; });
        await Promise.all([...visible, ...backgroundPictures].map(img => typeof img.decode === 'function' ? img.decode().catch(() => {}) : Promise.resolve()));
        if (presentationToken !== token) return;
      }
      clearTimeout(timer);
      layout(config, restore || locator());
      const laidOut = Date.now();
      let stable;
      do {
        stable = layoutEpoch;
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      } while (stable !== layoutEpoch && presentationToken === token);
      if (presentationToken !== token) return;
      // The HTML was invisible from parsing onward. Publish only final, stable spread geometry.
      const guard = document.getElementById('readbooks-first-paint');
      if (guard) guard.remove();
      presented = true;
      emit({ type: 'ready', spread: !!config.spread, width: innerWidth, height: innerHeight,
        timing: [fontReady - started, imagesReady - fontReady, laidOut - imagesReady, Date.now() - laidOut].join('/') });
    } catch (_) { if (presentationToken === token) emit({ type: 'error' }); }
  }
  function stableReflow() {
    if (applying || !token) return;
    clearTimeout(timer);
    timer = setTimeout(() => {
      if ((touch && (touch.dragging || touch.paused)) || Date.now() < motionUntil) { stableReflow(); return; }
      layout(config, restore || locator());
    }, 60);
  }
  body.querySelectorAll('img').forEach(img => { img.addEventListener('load', stableReflow); img.addEventListener('error', stableReflow); });
  if (document.fonts) document.fonts.ready.then(stableReflow);
  addEventListener('resize', stableReflow);
  function go(delta, velocity = null) {
    if (!Number.isFinite(delta) || !Math.trunc(delta)) return;
    delta = Math.trunc(delta);
    // A cold handoff may carry multiple inputs. Present each page, never compress
    // three pages into the same 320 ms translation used by a single tap.
    if (Math.abs(delta) > 1) {
      replayTurns += delta - Math.sign(delta);
      delta = Math.sign(delta);
    }
    if (page + delta < 0 || page + delta >= pages) {
      const carry = replayTurns; replayTurns = 0; clearTimeout(replayTimer);
      emit({ type: 'turn', delta: Math.sign(delta), carry });
      return;
    }
    display(page + delta, true, velocity); restore = locator();
    scheduleReplay();
  }
  function scheduleReplay() {
    clearTimeout(replayTimer);
    if (!replayTurns) return;
    replayTimer = setTimeout(() => {
      if (touch || inputHeld || Date.now() < motionUntil) { scheduleReplay(); return; }
      const delta = Math.sign(replayTurns); replayTurns -= delta;
      if (page + delta < 0 || page + delta >= pages) {
        const carry = replayTurns; replayTurns = 0;
        emit({ type: 'turn', delta, carry });
      } else go(delta);
    }, Math.max(32, motionUntil - Date.now() + 16));
  }
  document.addEventListener('click', event => {
    if (inputHeld || Date.now() < suppressClickUntil) { event.preventDefault(); return; }
    const link = event.target.closest && event.target.closest('a');
    if (link) {
      event.preventDefault(); event.stopPropagation();
      const href = link.href || link.getAttribute('href');
      emit({ type: 'link', href }); return;
    }
    if (getSelection().toString()) return;
    if (event.clientX < innerWidth * .2) go(-1);
    else if (event.clientX > innerWidth * .8) go(1);
    else emit({ type: 'controls' });
  }, true);
  let suppressClickUntil = 0;
  const pointerX = p => Number.isFinite(p.screenX) ? p.screenX : p.clientX;
  const pointerY = p => Number.isFinite(p.screenY) ? p.screenY : p.clientY;
  document.addEventListener('selectionchange', () => emit({ type: 'selection', selected: !!getSelection().toString() }));
  document.addEventListener('touchstart', e => {
    if (inputHeld) return;
    if (e.touches.length === 1) {
      // A new contact is intentional, not the synthetic click belonging to the previous swipe.
      suppressClickUntil = 0;
      let origin = (direction === 'rtl' ? 1 : -1) * page * step;
      const paused = !vertical && !fixed && Date.now() < motionUntil;
      if (paused) {
        // Read once only when interrupting an active transition, never in touchmove.
        try { origin = new DOMMatrixReadOnly(getComputedStyle(body).transform).m41; } catch (_) {}
        // Freeze at contact. Otherwise the old transition keeps moving until the first
        // move event, and using its older origin then visibly pulls the page backwards.
        clearTimeout(edgeTimer); motionUntil = 0;
        body.style.transition = 'none';
        body.style.transform = `translate3d(${origin}px,0,0)`;
      }
      const x = pointerX(e.touches[0]), now = Date.now();
      touch = { x, y: pointerY(e.touches[0]), origin, position: origin, paused, dragging: false, edge: false,
        sampleX: x, sampleTime: now, movedAt: now, velocity: 0 };
    }
    else { if (touch && (touch.dragging || touch.paused)) display(page, true, 0); touch = null; }
  }, { passive: true });
  document.addEventListener('touchmove', e => {
    if (inputHeld || !touch || vertical || applying || e.touches.length !== 1 || getSelection().toString()) return;
    sampleVelocity(e.touches[0]);
    const dx = pointerX(e.touches[0]) - touch.x, dy = pointerY(e.touches[0]) - touch.y;
    if (!touch.dragging && (Math.abs(dx) < 10 || Math.abs(dx) <= Math.abs(dy) * 1.4)) return;
    const began = !touch.dragging;
    touch.dragging = true; e.preventDefault();
    const delta = (direction === 'rtl' ? dx > 0 : dx < 0) ? 1 : -1;
    if (config.nativeBoundary && (touch.edge || page + delta < 0 || page + delta >= pages)) {
      handoffBody(); return; // Native current + prepared neighbour move together in window coordinates.
    }
    if (fixed) return;
    if (began) { clearTimeout(edgeTimer); motionUntil = 0; }
    clipEdges(true);
    body.style.transition = 'none';
    touch.position = touch.origin + clamp(dx, -step, step);
    body.style.transform = `translate3d(${touch.position}px,0,0)`;
  }, { passive: false });
  document.addEventListener('touchend', e => {
    if (inputHeld || !touch) return;
    if (touch.edge) { clearTimeout(edgeTimer); closeEdges(); suppressClickUntil = Date.now() + 500; touch = null; return; }
    if (!e.changedTouches.length || getSelection().toString()) {
      if (touch.dragging || touch.paused) display(page, true, 0);
      touch = null; return;
    }
    sampleVelocity(e.changedTouches[0]);
    const dx = pointerX(e.changedTouches[0]) - touch.x, dy = pointerY(e.changedTouches[0]) - touch.y;
    // A very short/fast drag may arrive as down + up with no DOM touchmove.
    // Still suppress its synthetic click, or a cancelled edge drag becomes a tap-turn.
    const horizontal = Math.abs(dx) >= 10 && Math.abs(dx) > Math.abs(dy) * 1.4;
    if (horizontal) {
      suppressClickUntil = Date.now() + 500;
      const delta = (direction === 'rtl' ? dx > 0 : dx < 0) ? 1 : -1;
      if (config.nativeBoundary && !vertical && (page + delta < 0 || page + delta >= pages)) { handoffBody(); touch = null; return; }
    }
    if (Math.abs(dx) > 55 && Math.abs(dx) > Math.abs(dy) * 1.4) {
      suppressClickUntil = Date.now() + 500;
      // Snap to the current page before a chapter handoff; intra-chapter motion starts at the finger.
      const delta = (direction === 'rtl' ? dx > 0 : dx < 0) ? 1 : -1;
      if (config.nativeBoundary && !vertical && (page + delta < 0 || page + delta >= pages)) { handoffBody(); touch = null; return; }
      if (page + delta < 0 || page + delta >= pages) display(page, true, touch.velocity);
      go(delta, touch.velocity);
    } else if (touch.dragging || horizontal) { suppressClickUntil = Date.now() + 500; display(page, true, touch.velocity); }
    else if (touch.paused) { display(page, true, 0); }
    touch = null;
  }, { passive: true });
  document.addEventListener('touchcancel', () => { if (touch && (touch.dragging || touch.paused) && !touch.edge) display(page, true, 0); touch = null; }, { passive: true });
  body.addEventListener('transitionend', event => {
    if (event.target === body && event.propertyName === 'transform' && !touch) { clearTimeout(edgeTimer); closeEdges(); }
  });
  async function seek(value, fragment) {
    const seekingToken = token;
    display(restoreLocator(value), false);
    if (fragment) anchor(fragment);
    restore = locator();
    // Hidden warm Web surfaces may throttle requestAnimationFrame indefinitely.
    // The target transform is synchronous; bound the paint acknowledgement so an
    // already laid-out next chapter cannot remain permanently marked unready.
    await Promise.race([
      new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))),
      new Promise(resolve => setTimeout(resolve, 80))
    ]);
    if (seekingToken === token) { report(); emit({ type: 'ready' }); }
  }
  function holdInput(held) {
    if (held && touch && !touch.edge && (touch.dragging || touch.paused)) display(page, true, 0);
    inputHeld = !!held; touch = null;
    suppressClickUntil = held ? Date.now() + 500 : 0;
  }
  function externalStart() {
    let origin = (direction === 'rtl' ? 1 : -1) * page * step;
    if (!fixed && Date.now() < motionUntil) {
      try { origin = new DOMMatrixReadOnly(getComputedStyle(body).transform).m41; } catch (_) {}
    }
    inputHeld = true;
    clearTimeout(edgeTimer); motionUntil = 0;
    touch = { external: true, dragging: true, origin, position: origin };
    body.style.transition = 'none';
    if (!fixed) body.style.transform = `translate3d(${origin}px,0,0)`;
  }
  function externalMove(fraction) {
    if (!touch || !touch.external || !Number.isFinite(fraction) || fixed) return;
    touch.position = touch.origin + clamp(fraction, -1, 1) * innerWidth;
    clipEdges(true);
    body.style.transform = `translate3d(${touch.position}px,0,0)`;
  }
  function externalFinish(delta, motion) {
    if (!touch || !touch.external) return;
    display(page + Math.max(-1, Math.min(1, delta)), true, null, motion);
    restore = locator(); touch = null;
  }
  function externalCancel() {
    if (touch && touch.external) display(page, false);
    touch = null; inputHeld = false;
  }
  window.ReadBooks = { layout, go, anchor, holdInput, externalStart, externalMove, externalFinish, externalCancel, seek: (value, fragment) => { void seek(value, fragment); },
    prepare: (next, value) => { presented = false; presenting = false; layout(next, value); void present(); },
    present: () => { void present(); }, state: () => JSON.stringify({ page, pages, locator: locator() }) };
})();
