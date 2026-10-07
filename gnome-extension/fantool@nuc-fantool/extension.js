// fantool@nuc-fantool: NUC X15 thermal/fan status indicator for GNOME Shell 45+
// Reads /run/fanctl-omc.state only (cpu/gpu/fan1/fan2/target, 由 fanctl-omc v2.2 每 2-5 秒写入;
// v2.2 起 uniwill hwmon 已不存在,数据源: coretemp + nvidia-smi + /dev/ec,见 fanctl-omc.sh 头注).
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

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
        const s = readState();
        if (!s || s.cpu === undefined) {
            this._label.set_text('fan: no state');
            return;
        }
        const t = Math.max(parseInt(s.cpu, 10) || 0, parseInt(s.gpu, 10) || 0);
        const tgt = s.target !== undefined ? `→${s.target}` : '';
        this._label.set_text(`${t}°C ${s.fan1 ?? '?'}·${s.fan2 ?? '?'}${tgt}`);
    }
}
