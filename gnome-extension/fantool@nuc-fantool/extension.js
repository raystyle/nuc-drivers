// fantool@nuc-fantool v3: NUC X15 thermal/power/fan indicator for GNOME Shell 45+
// 数据源:/run/fanctl-omc.state(fanctl v2.3 起含 cpuW/gpuW)+ /run/perfmode.state。
// 面板 = 温度(阈值分级着色) + 总功率 + 双扇转速;点开 = 详情菜单。GNOME 内零子进程。
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

const C_VAL = '#f2f2f2', C_DIM = '#8f8f8c', C_WARM = '#ffaa44', C_HOT = '#ff5555';

function readKv(path) {
    try {
        const [ok, c] = GLib.file_get_contents(path);
        if (!ok) return null;
        const o = {};
        String(c).trim().split(/\s+/).forEach(kv => {
            const i = kv.indexOf('=');
            if (i > 0) o[kv.slice(0, i)] = kv.slice(i + 1);
        });
        return o;
    } catch (e) { return null; }
}

function readText(path) {
    try {
        const [ok, c] = GLib.file_get_contents(path);
        return ok ? String(c).trim() : '';
    } catch (e) { return ''; }
}

function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

function tempColor(t) {
    if (t >= 80) return C_HOT;
    if (t >= 70) return C_WARM;
    return C_VAL;
}

export default class FantoolStatusExtension extends Extension {
    enable() {
        this._button = new PanelMenu.Button(0.0, 'nuc-fantool-status', true);
        this._label = new St.Label({ y_align: Clutter.ActorAlign.CENTER });
        this._label.clutter_text.use_markup = true;
        this._label.set_style('margin: 0 10px; font-feature-settings: "tnum"; letter-spacing: 0.3px;');
        this._button.add_child(this._label);

        this._menuLabel = new St.Label({ style: 'padding: 12px 16px; line-spacing: 6px;' });
        this._menuLabel.clutter_text.use_markup = true;
        const section = new PopupMenu.PopupMenuSection();
        section.actor.add_actor(this._menuLabel);
        this._button.menu.addMenuItem(section);
        this._button.menu.connect('open-state-changed', (m, open) => { if (open) this._renderMenu(); });

        Main.panel.addToStatusArea('nuc-fantool-status', this._button, 0, 'right');
        this._tick();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._tick();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._timer) { GLib.source_remove(this._timer); this._timer = 0; }
        this._button?.destroy();
        this._button = null;
        this._label = null;
        this._menuLabel = null;
    }

    _tick() {
        const s = readKv('/run/fanctl-omc.state');
        if (!s || s.cpu === undefined) {
            this._label.clutter_text.set_markup(`<span foreground="${C_DIM}">fan …</span>`);
            return;
        }
        const t = Math.max(parseInt(s.cpu, 10) || 0, parseInt(s.gpu, 10) || 0);
        const w = (parseInt(s.cpuW, 10) || 0) + (parseInt(s.gpuW, 10) || 0);
        const sep = '<span foreground="#4a4a48">  </span>';
        const parts = [
            `<span foreground="${tempColor(t)}" font_weight="bold">${t}</span><span foreground="${C_DIM}" size="smaller">°</span>`,
            `<span foreground="${C_DIM}" size="smaller">⚡</span><span foreground="${C_VAL}">${w}</span><span foreground="${C_DIM}" size="smaller">W</span>`,
            `<span foreground="${C_DIM}" size="smaller">⟳</span><span foreground="${C_VAL}">${esc(s.fan1 ?? '?')}<span foreground="${C_DIM}">·</span>${esc(s.fan2 ?? '?')}</span>`,
        ];
        this._label.clutter_text.set_markup(parts.join(sep));
    }

    _renderMenu() {
        const s = readKv('/run/fanctl-omc.state') ?? {};
        const perf = readText('/run/perfmode.state') || '(未设)';
        const kbd = readText('/run/kbdlight.state') || '(未设)';
        const row = (k, v) =>
            `<span foreground="${C_DIM}">${esc(k)}</span>  <span foreground="${C_VAL}">${esc(v)}</span>`;
        const lines = [
            row('CPU', `${s.cpu ?? '?'}°C · ${s.cpuW ?? '?'}W`),
            row('GPU', `${s.gpu ?? '?'}°C · ${s.gpuW ?? '?'}W`),
            row('风扇', `${s.fan1 ?? '?'} / ${s.fan2 ?? '?'} rpm`),
            row('fan2 目标', `${s.target ?? '?'} rpm`),
            row('性能档', perf),
            row('键盘灯', kbd),
            `<span foreground="${C_DIM}" size="smaller">sudo perfmode / kbdlight 调整,详见 nuc-drivers</span>`,
        ];
        this._menuLabel.clutter_text.set_markup(lines.join('\n'));
    }
}
