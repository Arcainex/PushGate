// push_gates ui
// by XanderP  -  discord.gg/cMqazwj6c7

const $ = (id) => document.getElementById(id);

let cfg = {};
let gate = null;      // the gate the player is stood next to
let anims = [];
let animOn = 0;

function post(name, data) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

// ------------------------------------------------------------- the prompt

function showPrompt(p) {
    if (typeof p.py === 'number') {
        document.documentElement.style.setProperty('--py', p.py + 'vh');
    }

    $('promptKey').textContent = p.key || 'E';
    $('promptText').textContent = p.text || 'Push the gate';

    // bar only while actually pushing, otherwise its just noise
    if (typeof p.ratio === 'number') {
        $('promptBar').classList.remove('hidden');
        $('promptFill').style.width = Math.round(p.ratio * 100) + '%';
    } else {
        $('promptBar').classList.add('hidden');
    }

    $('prompt').classList.remove('hidden');
}

function hidePrompt() {
    $('prompt').classList.add('hidden');
}

// --------------------------------------------------------------- the menu

function paint() {
    // which grab method
    document.querySelectorAll('#interact button').forEach((b) => {
        b.classList.toggle('on', b.dataset.v === cfg.interact);

        // grey out target scripts that arent running
        const missing =
            (b.dataset.v === 'ox'   && !cfg.has_ox) ||
            (b.dataset.v === 'qb'   && !cfg.has_qb) ||
            (b.dataset.v === 'bs19' && !cfg.has_bs19);
        b.classList.toggle('gone', missing);
    });

    const running = [];
    if (cfg.has_ox) running.push('ox_target');
    if (cfg.has_qb) running.push('qb-target');
    if (cfg.has_bs19) running.push('BS19 target');
    $('interactHint').textContent = running.length
        ? 'Running on this server: ' + running.join(', ')
        : 'No target script found, hold key is the only option right now.';

    $('pushScale').value = cfg.pushScale;
    $('pushScaleV').textContent = Number(cfg.pushScale).toFixed(2);

    $('grabDistance').value = cfg.grabDistance;
    $('grabDistanceV').textContent = Number(cfg.grabDistance).toFixed(1);

    $('promptY').value = cfg.promptY;
    $('promptYV').textContent = Math.round(cfg.promptY);
    // move it live while your dragging so you can see where it lands
    document.documentElement.style.setProperty('--py', cfg.promptY + 'vh');

    $('faceGate').checked = !!cfg.faceGate;

    paintGate();
    paintAnims();
}

function paintGate() {
    const box = $('gate');

    if (!gate) {
        box.innerHTML = '<div class="gate__none">Walk up to a gate to edit it</div>';
        return;
    }

    box.innerHTML = `
        <div class="gate__name">
            <b>${gate.name}</b><br>
            slides ${Number(gate.travel).toFixed(1)}m on ${gate.axis}
        </div>
        <div class="gate__acts">
            <button data-a="axis">Change axis</button>
            <button data-a="less">&minus; 0.5m</button>
            <button data-a="more">+ 0.5m</button>
            <button data-a="reset">Shut it</button>
        </div>`;

    box.querySelectorAll('button').forEach((b) => {
        b.onclick = () => post('gateAction', { action: b.dataset.a });
    });
}

function paintAnims() {
    const box = $('anim');
    box.innerHTML = '';

    if (!anims.length) {
        box.innerHTML = '<div class="gate__none">None configured</div>';
        return;
    }

    const note = document.createElement('div');
    note.className = 'anim-note';
    note.textContent = 'Click one to wear it now. Struck through means the dictionary '
                     + 'is not on this build, so it can never play.';
    box.appendChild(note);

    anims.forEach((a, i) => {
        const b = document.createElement('button');
        b.innerHTML = `<span class="a-dict">${a.dict}</span><br>`
                    + `<span class="a-clip">${a.clip}</span>`;
        b.classList.toggle('on', i === animOn);
        if (a.missing) b.classList.add('gone');
        b.onclick = () => {
            if (a.missing) return;
            animOn = i;
            paintAnims();
            post('setAnim', { index: i });
        };
        box.appendChild(b);
    });
}

$('customAnim').onclick = async () => {
    const dict = $('customDict').value.trim();
    const clip = $('customClip').value.trim();
    const status = $('customAnimStatus');
    status.textContent = 'Checking animation...';
    try {
        const response = await post('customAnim', { dict, clip });
        const result = await response.json();
        status.textContent = result.message || 'Could not load the animation.';
        if (result.ok) {
            anims.push({ dict, clip, missing: false });
            animOn = result.index - 1;
            paintAnims();
        }
    } catch (_) {
        status.textContent = 'Could not check the animation. Try again.';
    }
};

// ------------------------------------------------------------------ wiring

document.querySelectorAll('#interact button').forEach((b) => {
    b.onclick = () => {
        if (b.classList.contains('gone')) return;
        cfg.interact = b.dataset.v;
        paint();
    };
});

$('pushScale').oninput = (e) => {
    cfg.pushScale = parseFloat(e.target.value);
    $('pushScaleV').textContent = cfg.pushScale.toFixed(2);
};

$('grabDistance').oninput = (e) => {
    cfg.grabDistance = parseFloat(e.target.value);
    $('grabDistanceV').textContent = cfg.grabDistance.toFixed(1);
};

$('promptY').oninput = (e) => {
    cfg.promptY = parseFloat(e.target.value);
    $('promptYV').textContent = Math.round(cfg.promptY);
    document.documentElement.style.setProperty('--py', cfg.promptY + 'vh');

    // show the prompt while dragging so you can actually see it move
    $('promptKey').textContent = 'E';
    $('promptText').textContent = 'Push the gate';
    $('promptBar').classList.add('hidden');
    $('prompt').classList.remove('hidden');
    clearTimeout(window._pyHide);
    window._pyHide = setTimeout(() => $('prompt').classList.add('hidden'), 1200);
};

$('faceGate').onchange = (e) => { cfg.faceGate = e.target.checked; };

$('apply').onclick = () => post('apply', cfg);
$('dump').onclick  = () => post('dump', {});
$('close').onclick = () => post('close', {});

document.onkeyup = (e) => {
    if (e.key === 'Escape') post('close', {});
};

// --------------------------------------------------------------- from lua

window.addEventListener('message', (ev) => {
    const d = ev.data || {};

    if (d.action === 'prompt') {
        d.show ? showPrompt(d) : hidePrompt();

    } else if (d.action === 'menu') {
        if (d.show) {
            cfg = d.config || {};
            gate = d.gate || null;
            anims = d.anims || [];
            animOn = d.animOn || 0;
            paint();
            $('menu').classList.remove('hidden');
            restorePlace();
        } else {
            $('menu').classList.add('hidden');
        }

    } else if (d.action === 'gate') {
        // player walked up to a different gate while the menu is open
        gate = d.gate || null;
        paintGate();
    }
});


// --------------------------------------------------------------- the window

/* MOVING AND RESIZING THE PANEL.

   Resizing is CSS (resize: both on #menu) - the browser does it, we just draw
   a visible grip in style.css because the default one is invisible on a dark
   panel.

   Moving is this. Worth knowing: the panel used to be centred with
   `transform: translate(-50%, -50%)`, and you cannot drag something that is
   also being offset by a transform - you set left/top and the transform moves
   it somewhere else, so it jumps the moment you grab it. So the transform is
   gone and JS centres it once, the first time it opens.

   Position is kept in localStorage, so it stays where you put it between
   sessions. It is a UI preference on one person's screen; the server has no
   business having an opinion about it. */

const PLACE_KEY = 'pg_menu_place';

function clampIntoView(el) {
    const r = el.getBoundingClientRect();
    let left = r.left, top = r.top;

    // never let the title bar leave the screen, or you cannot grab it back
    const margin = 40;
    left = Math.min(Math.max(left, margin - r.width), window.innerWidth - margin);
    top  = Math.min(Math.max(top, 0), window.innerHeight - 34);

    el.style.left = left + 'px';
    el.style.top = top + 'px';
}

function restorePlace() {
    const el = $('menu');
    let p = null;
    try { p = JSON.parse(localStorage.getItem(PLACE_KEY) || 'null'); } catch (e) { p = null; }

    if (p && typeof p.left === 'number') {
        el.style.left = p.left + 'px';
        el.style.top = p.top + 'px';
        if (p.w) el.style.width = p.w + 'px';
        if (p.h) el.style.height = p.h + 'px';
    } else {
        // first open: centre it
        el.style.left = Math.round((window.innerWidth - el.offsetWidth) / 2) + 'px';
        el.style.top = Math.round((window.innerHeight - el.offsetHeight) / 2) + 'px';
    }
    clampIntoView(el);
}

function savePlace() {
    const el = $('menu');
    const r = el.getBoundingClientRect();
    try {
        localStorage.setItem(PLACE_KEY, JSON.stringify({
            left: Math.round(r.left), top: Math.round(r.top),
            w: Math.round(r.width), h: Math.round(r.height),
        }));
    } catch (e) { /* private mode, blocked storage - not worth caring about */ }
}

(function makeDraggable() {
    const el = $('menu');
    const bar = document.querySelector('.menu__head');
    if (!el || !bar) return;

    let dragging = false, offX = 0, offY = 0;

    bar.addEventListener('mousedown', (e) => {
        // the close button is in the title bar and must still close
        if (e.target.closest('#close')) return;
        const r = el.getBoundingClientRect();
        dragging = true;
        offX = e.clientX - r.left;
        offY = e.clientY - r.top;
        document.body.classList.add('dragging');
        e.preventDefault();
    });

    window.addEventListener('mousemove', (e) => {
        if (!dragging) return;
        el.style.left = (e.clientX - offX) + 'px';
        el.style.top = (e.clientY - offY) + 'px';
    });

    window.addEventListener('mouseup', () => {
        if (!dragging) return;
        dragging = false;
        document.body.classList.remove('dragging');
        clampIntoView(el);
        savePlace();
    });

    // resize is the browser's, so watch for it rather than driving it
    if (window.ResizeObserver) {
        let t;
        new ResizeObserver(() => {
            clearTimeout(t);
            t = setTimeout(savePlace, 250);
        }).observe(el);
    }

    window.addEventListener('resize', () => clampIntoView(el));
})();
