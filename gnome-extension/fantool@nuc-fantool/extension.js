// fantool@nuc-fantool: NUC X15 thermal/fan status indicator for GNOME Shell 45+
// Reads uniwill hwmon (temps + fan RPM) and /run/fanctl-omc.state (service target).
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

function hwmonUniwill() {
    try {
        const dir = GLib.Dir.open('/sys/class/hwmon', 0);
        let name;
        while ((name = dir.read_name()) !== null) {
            const base = `/sys/class/hwmon/${name}`;
            try {
                const [ok, c] = GLib.file_get_contents(`${base}/name`);
                if (ok && String(c).trim() === 'uniwill') return base;
            } catch (e) { continue; }
        }
    } catch (e) { /* no hwmon root */ }
    return null;
}

function readInt(path) {
    try {
        const [ok, c] = GLib.file_get_contents(path);
        if (ok) return parseInt(String(c).trim(), 10);
    } catch (e) { /* file gone */ }
    return null;
}

function readState() {
    try {
        const [ok, c] = GLib.file_get_contents('/run/fanctl-omc.state');
        if (!ok) return null;
        const o = {};
        String(c).trim().split(/\s+/).forEach(kv => {
            const i = kv.indexOf('=');
            if (i > 0) o[kv.slice(0, i)] = kv.slice(i + 1);
        });
        return o;
    } catch (e) { return null; }
}

export default class FantoolStatusExtension extends Extension {
    enable() {
        this._button = new PanelMenu.Button(0.0, 'nuc-fantool-status', true);
        this._label = new St.Label({
            text: 'fan …',
            y_align: Clutter.ActorAlign.CENTER,
            style: 'margin: 0 8px; font-feature-settings: "tnum";',
        });
        this._button.add_child(this._label);
        Main.panel.addToStatusArea('nuc-fantool-status', this._button, 0, 'right');
        this._tick();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._tick();
            return GLib.SOURCE_CONTINUE;
        });
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        this._button?.destroy();
        this._button = null;
        this._label = null;
    }

    _tick() {
        const base = hwmonUniwill();
        if (!base) {
            this._label.set_text('fan: no hwmon');
            return;
        }
        const cpu = readInt(`${base}/temp1_input`);
        const gpu = readInt(`${base}/temp2_input`);
        const fan1 = readInt(`${base}/fan1_input`);
        const fan2 = readInt(`${base}/fan2_input`);
        const s = readState();
        const t = Math.max(cpu ?? 0, gpu ?? 0);
        const celsius = Number.isFinite(t) ? Math.round(t / 100) / 10 : '?';
        const tgt = s && s.target !== undefined ? `→${s.target}` : '';
        this._label.set_text(`${celsius}°C ${fan1 ?? '?'}·${fan2 ?? '?'}${tgt}`);
    }
}
