using GLib;
using Gtk;

public class WacomWindow : Gtk.ApplicationWindow {
    private delegate void MenuAction ();
    private delegate void MappingAction (string target);
    private WacomClient client = new WacomClient ();
    private WacomDevice[] devices = {};
    private WacomDevice? selected;
    private Gtk.ComboBoxText device_combo = new Gtk.ComboBoxText ();
    private Gtk.Notebook notebook = new Gtk.Notebook ();
    private Gtk.Label notice = new Gtk.Label ("");
    private Gtk.ComboBoxText profile_combo = new Gtk.ComboBoxText ();
    private bool refreshing = false;
    private string selected_output = "desktop";
    private HashTable<string, string> full_areas = new HashTable<string, string> (str_hash, str_equal);

    public WacomWindow (Gtk.Application app) {
        Object (application: app, title: _("Graphics Tablet"), default_width: 850,
                default_height: 650, window_position: Gtk.WindowPosition.CENTER);
        var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        add (root);
        root.pack_start (make_menubar (), false, false, 0);

        var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        top.margin = 18;
        top.pack_start (new Gtk.Label (_("Tablet device")), false, false, 0);
        device_combo.hexpand = true;
        top.pack_start (device_combo, true, true, 0);
        var refresh = new Gtk.Button.from_icon_name ("view-refresh", Gtk.IconSize.BUTTON);
        refresh.tooltip_text = _("Refresh connected devices");
        refresh.clicked.connect (() => refresh_devices ());
        top.pack_start (refresh, false, false, 0);
        root.pack_start (top, false, false, 0);

        notice.xalign = 0;
        notice.margin_start = 18;
        notice.margin_end = 18;
        notice.get_style_context ().add_class ("dim-label");
        root.pack_start (notice, false, false, 0);
        notebook.margin_start = 12;
        notebook.margin_end = 12;
        notebook.margin_top = 12;
        notebook.margin_bottom = 12;
        root.pack_start (notebook, true, true, 0);

        client.device_error.connect ((message) => show_error (message));
        device_combo.changed.connect (() => {
            if (refreshing) return;
            int index = device_combo.get_active ();
            selected = index >= 0 && index < devices.length ? devices[index] : null;
            selected_output = "desktop";
            rebuild_pages ();
        });
        refresh_devices ();
        show_all ();
    }

    private Gtk.MenuBar make_menubar () {
        var bar = new Gtk.MenuBar ();
        var file = new Gtk.MenuItem.with_mnemonic (_("_File"));
        var file_menu = new Gtk.Menu ();
        file.set_submenu (file_menu);
        add_menu_item (file_menu, _("_Refresh Devices"), () => refresh_devices ());
        add_menu_item (file_menu, _("_Quit"), () => close ());
        bar.append (file);
        var tools = new Gtk.MenuItem.with_mnemonic (_("_Tools"));
        var tools_menu = new Gtk.Menu ();
        tools.set_submenu (tools_menu);
        add_menu_item (tools_menu, _("_Test Tablet…"), () => show_tester ());
        add_menu_item (tools_menu, _("_Reset Current Tool…"), () => reset_current ());
        bar.append (tools);
        var help = new Gtk.MenuItem.with_mnemonic (_("_Help"));
        var help_menu = new Gtk.Menu ();
        help.set_submenu (help_menu);
        add_menu_item (help_menu, _("_About"), () => {
            var about = new Gtk.AboutDialog ();
            about.transient_for = this;
            about.modal = true;
            about.program_name = _("MATE Graphics Tablet");
            about.comments = _("Configure Wacom X11 driver settings.");
            about.version = "0.1.0";
            about.run ();
            about.destroy ();
        });
        bar.append (help);
        return bar;
    }

    private void add_menu_item (Gtk.Menu menu, string label, MenuAction callback) {
        var item = new Gtk.MenuItem.with_mnemonic (label);
        item.activate.connect (() => { callback (); });
        menu.append (item);
    }

    private void show_error (string message) {
        var dialog = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL,
                                            Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE,
                                            "%s", message);
        dialog.run ();
        dialog.destroy ();
    }

    private void refresh_devices () {
        string old_id = selected != null ? selected.id : "";
        refreshing = true;
        device_combo.remove_all ();
        devices = client.list_devices ();
        int active = 0;
        for (int i = 0; i < devices.length; i++) {
            device_combo.append_text ("%s — %s".printf (devices[i].name, kind_label (devices[i].kind)));
            if (devices[i].id == old_id) active = i;
        }
        device_combo.set_active (devices.length > 0 ? active : -1);
        selected = devices.length > 0 ? devices[active] : null;
        if (old_id != (selected != null ? selected.id : "")) selected_output = "desktop";
        refreshing = false;
        rebuild_pages ();
    }

    private Gtk.Box page (string title, string detail) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
        box.margin = 18;
        var heading = new Gtk.Label (null);
        heading.set_markup ("<span size='large' weight='bold'>%s</span>".printf (Markup.escape_text (title)));
        heading.xalign = 0;
        box.pack_start (heading, false, false, 0);
        var desc = new Gtk.Label (detail);
        desc.xalign = 0;
        desc.set_line_wrap (true);
        desc.get_style_context ().add_class ("dim-label");
        box.pack_start (desc, false, false, 0);
        return box;
    }

    private string kind_label (string kind) {
        switch (kind) {
        case "stylus": return _("Stylus");
        case "eraser": return _("Eraser");
        case "cursor": return _("Cursor");
        case "pad": return _("Pad");
        case "touch": return _("Touch");
        default: return kind;
        }
    }

    private void append_page (Gtk.Widget content, string label) {
        var scroll = new Gtk.ScrolledWindow (null, null);
        scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.add (content);
        notebook.append_page (scroll, new Gtk.Label (label));
    }

    private Gtk.Grid group (Gtk.Box parent, string title) {
        var frame = new Gtk.Frame (title);
        frame.shadow_type = Gtk.ShadowType.NONE;
        var grid = new Gtk.Grid ();
        grid.margin = 12;
        grid.row_spacing = 10;
        grid.column_spacing = 18;
        frame.add (grid);
        parent.pack_start (frame, false, false, 0);
        return grid;
    }

    private void row (Gtk.Grid grid, int index, string label, Gtk.Widget control, string? hint = null) {
        var l = new Gtk.Label (label);
        l.xalign = 0;
        l.halign = Gtk.Align.START;
        grid.attach (l, 0, index, 1, 1);
        control.hexpand = true;
        grid.attach (control, 1, index, 1, 1);
        if (hint != null) control.tooltip_text = hint;
    }

    private void rebuild_pages () {
        while (notebook.get_n_pages () > 0) notebook.remove_page (0);
        if (selected == null) {
            notice.label = _("No Wacom X11 tablet was detected. Connect a tablet and choose File → Refresh Devices.");
            var empty = page (_("No tablet detected"), _("The Wacom X11 driver must expose the device to xsetwacom. This dialog works in an X11 session."));
            var button = new Gtk.Button.with_label (_("Refresh Devices"));
            button.clicked.connect (() => refresh_devices ());
            empty.pack_start (button, false, false, 0);
            append_page (empty, _("Tablet"));
        } else {
            notice.label = _("Changes apply immediately to the selected %s tool.").printf (kind_label (selected.kind));
            append_page (make_overview (), _("Overview"));
            append_page (make_mapping (), _("Mapping"));
            if (selected.kind == "stylus" || selected.kind == "eraser" || selected.kind == "cursor")
                append_page (make_pen (), _("Pen"));
            if (selected.kind == "pad") append_page (make_pad (), _("Pad"));
            if (selected.kind == "touch") append_page (make_touch (), _("Touch"));
            append_page (make_profiles (), _("Profiles"));
        }
        notebook.show_all ();
    }

    private Gtk.Widget make_overview () {
        var box = page (_("Tablet overview"), _("Choose a device above to configure its individual pen, eraser, pad, or touch tool."));
        var grid = group (box, _("Connected tools"));
        for (int i = 0; i < devices.length; i++) {
            var name = new Gtk.Label (devices[i].name);
            name.xalign = 0;
            var type = new Gtk.Label (kind_label (devices[i].kind));
            type.xalign = 0;
            row (grid, i, devices[i].id, name);
            grid.attach (type, 2, i, 1, 1);
        }
        var test = new Gtk.Button.with_label (_("Test Tablet…"));
        test.clicked.connect (() => show_tester ());
        box.pack_start (test, false, false, 0);
        return box;
    }

    private Gtk.ComboBoxText choice (Gtk.Grid grid, int row_index, string label,
                                      string parameter, string[] values, string[] labels,
                                      bool write_only = false) {
        var combo = new Gtk.ComboBoxText ();
        for (int i = 0; i < values.length; i++) combo.append (values[i], labels[i]);
        if (!write_only) {
            string current = client.read (selected, parameter).strip ();
            for (int i = 0; i < values.length; i++)
                if (values[i].down () == current.down ()) combo.set_active (i);
            combo.sensitive = client.supports (selected, parameter);
        } else combo.set_active (0);
        combo.changed.connect (() => {
            if (combo.get_active_id () != null)
                client.set_parameter (selected, parameter, {combo.get_active_id ()});
        });
        row (grid, row_index, label, combo);
        return combo;
    }

    private Gtk.SpinButton number (Gtk.Grid grid, int row_index, string label,
                                   string parameter, double min, double max, double step,
                                   string? hint = null) {
        var spin = new Gtk.SpinButton.with_range (min, max, step);
        string raw = client.read (selected, parameter);
        double current;
        if (double.try_parse (raw, out current)) spin.set_value (current);
        spin.sensitive = client.supports (selected, parameter);
        spin.value_changed.connect (() => client.set_parameter (selected, parameter, {"%d".printf (spin.get_value_as_int ())}));
        row (grid, row_index, label, spin, hint);
        return spin;
    }

    private Gtk.Switch toggle (Gtk.Grid grid, int row_index, string label, string parameter) {
        var sw = new Gtk.Switch ();
        string current = client.read (selected, parameter).down ();
        sw.active = current == "on" || current == "1";
        sw.sensitive = client.supports (selected, parameter);
        sw.notify["active"].connect (() => client.set_parameter (selected, parameter, {sw.active ? "on" : "off"}));
        row (grid, row_index, label, sw);
        return sw;
    }

    private Gtk.Widget make_mapping () {
        var box = page (_("Screen and tablet mapping"), _("Set tracking, screen output, orientation, and the active area of this tool."));
        var tracking = group (box, _("Tracking"));
        choice (tracking, 0, _("Tracking mode"), "Mode", {"Absolute", "Relative"}, {_("Pen (absolute)"), _("Mouse (relative)")});
        var rotate = choice (tracking, 1, _("Orientation"), "Rotate", {"none", "cw", "half", "ccw"},
                {_("Normal"), _("Clockwise"), _("Upside down (left-handed)"), _("Counterclockwise")});

        var display = group (box, _("Display"));
        string[] outputs = client.outputs ();
        var output = new Gtk.ComboBoxText ();
        foreach (string name in outputs) output.append (name, name == "desktop" ? _("Entire desktop") : name);
        bool choosing = false;
        bool has_custom = false;
        // Selects an output in the list, adding a custom entry for a rectangle.
        MenuAction show_output = () => {
            choosing = true;
            if (!output.set_active_id (selected_output)) {
                if (has_custom) output.remove (outputs.length);
                output.append (selected_output, _("Custom: %s").printf (selected_output));
                output.set_active_id (selected_output);
                has_custom = true;
            }
            choosing = false;
        };
        show_output ();
        row (display, 0, _("Map to screen"), output, _("Applies to the current X11 display layout."));
        var note = new Gtk.Label (_("Screen mappings are applied once. Reapply after changing the display layout."));
        note.xalign = 0;
        note.set_line_wrap (true);
        display.attach (note, 0, 1, 2, 1);

        int desktop_width, desktop_height;
        if (!client.output_size ("desktop", out desktop_width, out desktop_height)) {
            desktop_width = 1920; desktop_height = 1080;
        }
        var screen = new AreaSelector (360, 200);
        screen.set_surface (0, 0, desktop_width, desktop_height);
        foreach (string name in outputs) {
            int ox, oy, ow, oh;
            if (name == "desktop") continue;
            if (client.output_geometry (name, out ox, out oy, out ow, out oh))
                screen.add_region (ox, oy, ow, oh, name);
        }
        screen.changed.connect (() => {
            screen.caption = "%d×%d+%d+%d".printf ((int) Math.round (screen.area_width), (int) Math.round (screen.area_height),
                                                    (int) Math.round (screen.area_x), (int) Math.round (screen.area_y));
        });
        display.attach (screen, 0, 2, 2, 1);
        var rectangle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var width = new Gtk.SpinButton.with_range (1, desktop_width, 1);
        var height = new Gtk.SpinButton.with_range (1, desktop_height, 1);
        var x = new Gtk.SpinButton.with_range (0, desktop_width - 1, 1);
        var y = new Gtk.SpinButton.with_range (0, desktop_height - 1, 1);
        Gtk.SpinButton[] rectangle_fields = {width, height, x, y};
        foreach (var field in rectangle_fields) {
            field.set_width_chars (5);
            rectangle.pack_start (field, false, false, 0);
        }
        row (display, 3, _("Screen rectangle (W × H + X + Y)"), rectangle,
             _("Maps to a custom X11 screen rectangle in pixels."));
        link_spins (screen, {x, y, width, height}, false);
        int sx, sy, sw, sh;
        if (!client.output_geometry (selected_output, out sx, out sy, out sw, out sh)) {
            sx = 0; sy = 0; sw = desktop_width; sh = desktop_height;
        }
        screen.set_area (sx, sy, sw, sh);
        var apply_rectangle = new Gtk.Button.with_label (_("Map to Rectangle"));
        display.attach (apply_rectangle, 1, 4, 1, 1);

        var area = group (box, _("Active tablet area"));
        bool area_supported = client.supports (selected, "Area");
        var tablet = new AreaSelector (360, 200);
        tablet.changed.connect (() => {
            double full_width, full_height;
            tablet.get_surface_size (out full_width, out full_height);
            tablet.caption = "%.0f%% × %.0f%%".printf (tablet.area_width * 100 / full_width,
                                                       tablet.area_height * 100 / full_height);
        });
        area.attach (tablet, 0, 0, 2, 1);
        var keep_ratio = new Gtk.CheckButton.with_label (_("Keep the screen rectangle's aspect ratio"));
        area.attach (keep_ratio, 1, 1, 1, 1);
        var fields = new Gtk.SpinButton[4];
        string[] labels = {_("Left"), _("Top"), _("Right"), _("Bottom")};
        for (int i = 0; i < 4; i++) {
            fields[i] = new Gtk.SpinButton.with_range (0, 100000, 1);
            row (area, i + 2, labels[i], fields[i]);
        }
        link_spins (tablet, fields, true);
        // Shows the driver's full and current area; the full one changes with rotation.
        MenuAction load_tablet = () => {
            int[] full = tablet_extent ();
            tablet.set_surface (full[0], full[1], full[2] - full[0], full[3] - full[1]);
            foreach (var field in fields) field.set_range (0, int.max (full[2], full[3]));
            var current = client.read (selected, "Area").split (" ");
            double[] values = {full[0], full[1], full[2], full[3]};
            for (int i = 0; i < 4 && i < current.length; i++) {
                double n;
                if (double.try_parse (current[i], out n)) values[i] = n;
            }
            tablet.set_area (values[0], values[1], values[2] - values[0], values[3] - values[1]);
        };
        load_tablet ();

        MenuAction apply_area = () => {
            string[] coordinates = {};
            foreach (var field in fields) coordinates += "%d".printf (field.get_value_as_int ());
            client.set_parameter (selected, "Area", coordinates);
        };
        tablet.committed.connect (() => apply_area ());
        keep_ratio.toggled.connect (() => {
            tablet.lock_ratio = keep_ratio.active ? screen.area_width / screen.area_height : 0;
            if (keep_ratio.active) apply_area ();
        });
        screen.changed.connect (() => {
            if (keep_ratio.active) tablet.lock_ratio = screen.area_width / screen.area_height;
        });
        // Maps the stylus to a screen rectangle or output and refits a locked tablet area.
        MappingAction map_to = (target) => {
            if (!client.set_parameter (selected, "MapToOutput", {target})) return;
            selected_output = target;
            show_output ();
            if (keep_ratio.active) apply_area ();
        };
        MenuAction map_rectangle = () => {
            map_to ("%dx%d+%d+%d".printf (width.get_value_as_int (), height.get_value_as_int (),
                                          x.get_value_as_int (), y.get_value_as_int ()));
        };
        screen.committed.connect (() => map_rectangle ());
        apply_rectangle.clicked.connect (() => map_rectangle ());
        output.changed.connect (() => {
            string? name = output.get_active_id ();
            if (choosing || name == null) return;
            int ox, oy, ow, oh;
            if (client.output_geometry (name, out ox, out oy, out ow, out oh)) screen.set_area (ox, oy, ow, oh);
            map_to (name);
        });
        rotate.changed.connect (() => {
            full_areas.remove (selected.id);
            load_tablet ();
        });

        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var apply = new Gtk.Button.with_label (_("Apply Area"));
        apply.clicked.connect (() => apply_area ());
        buttons.pack_start (apply, false, false, 0);
        var reset = new Gtk.Button.with_label (_("Use Full Tablet"));
        reset.clicked.connect (() => {
            if (!client.set_parameter (selected, "ResetArea", {})) return;
            keep_ratio.active = false;
            load_tablet ();
        });
        buttons.pack_start (reset, false, false, 0);
        var fit = new Gtk.Button.with_label (_("Fit Area to Screen"));
        fit.tooltip_text = _("Crop the current tablet area to the screen rectangle's aspect ratio, keeping it centered.");
        fit.clicked.connect (() => {
            double left = tablet.area_x, top = tablet.area_y;
            double tablet_width = tablet.area_width, tablet_height = tablet.area_height;
            double screen_ratio = screen.area_width / screen.area_height;
            if (tablet_width / tablet_height > screen_ratio) {
                double new_width = tablet_height * screen_ratio;
                left += (tablet_width - new_width) / 2.0;
                tablet_width = new_width;
            } else {
                double new_height = tablet_width / screen_ratio;
                top += (tablet_height - new_height) / 2.0;
                tablet_height = new_height;
            }
            tablet.set_area (left, top, tablet_width, tablet_height);
            apply_area ();
        });
        buttons.pack_start (fit, false, false, 0);
        area.attach (buttons, 1, 6, 1, 1);
        area.sensitive = area_supported;
        return box;
    }

    /* Keeps the fallback spin buttons {x, y, width or right, height or bottom}
     * and the selector showing the same rectangle. */
    private void link_spins (AreaSelector selector, Gtk.SpinButton[] fields, bool corners) {
        // Closures do not keep parameter arrays alive, so hold a copy.
        Gtk.SpinButton[] spins = fields;
        bool syncing = false;
        selector.changed.connect (() => {
            syncing = true;
            spins[0].value = Math.round (selector.area_x);
            spins[1].value = Math.round (selector.area_y);
            spins[2].value = Math.round (corners ? selector.area_x + selector.area_width : selector.area_width);
            spins[3].value = Math.round (corners ? selector.area_y + selector.area_height : selector.area_height);
            syncing = false;
        });
        foreach (var spin in spins) {
            spin.value_changed.connect (() => {
                if (syncing) return;
                double left = spins[0].value, top = spins[1].value;
                selector.set_area (left, top, corners ? spins[2].value - left : spins[2].value,
                                   corners ? spins[3].value - top : spins[3].value);
            });
        }
    }

    private int[] tablet_extent () {
        string? cached = full_areas.lookup (selected.id);
        int[] area = {};
        if (cached != null) {
            foreach (string part in cached.split (" ")) area += int.parse (part);
            return area;
        }
        if (!client.full_area (selected, out area)) return {0, 0, 16000, 10000};
        full_areas.insert (selected.id, "%d %d %d %d".printf (area[0], area[1], area[2], area[3]));
        return area;
    }

    private Gtk.Widget make_pen () {
        var box = page (_("Pen and eraser"), _("Pressure, side buttons, and filtering are configured for the selected tool."));
        var pressure = group (box, _("Pressure"));
        number (pressure, 0, _("Tip threshold"), "Threshold", 0, 2047, 1,
                _("Minimum pressure that produces a tip click (driver scale 0–2047)."));
        toggle (pressure, 1, _("Pressure recalibration"), "PressureRecalibration");
        var curve = new Gtk.Button.with_label (_("Edit Pressure Curve…"));
        curve.clicked.connect (() => edit_curve ());
        row (pressure, 2, _("Pressure curve"), curve);
        curve.sensitive = client.supports (selected, "PressureCurve");

        var buttons = group (box, _("Stylus buttons"));
        for (int i = 1; i <= 3; i++) add_action_row (buttons, i - 1, _("Button %d").printf (i), "Button", i.to_string ());
        toggle (buttons, 3, _("Buttons require tablet contact"), "TabletPCButton");

        var filtering = group (box, _("Motion filtering"));
        number (filtering, 0, _("Raw sample count"), "RawSample", 1, 20, 1);
        number (filtering, 1, _("Suppress distance"), "Suppress", 0, 100, 1);
        number (filtering, 2, _("Pan scroll threshold"), "PanScrollThreshold", 0, 100000, 10);
        if (selected.kind == "cursor")
            number (filtering, 3, _("Cursor proximity"), "CursorProximity", 0, 255, 1);
        var serial = group (box, _("Tool identity"));
        var bind = new Gtk.Entry ();
        bind.text = client.read (selected, "BindToSerial", "0");
        bind.sensitive = client.supports (selected, "BindToSerial");
        row (serial, 0, _("Bind to tool serial"), bind, _("0 accepts any tool of this type."));
        var apply_serial = new Gtk.Button.with_label (_("Apply Serial"));
        apply_serial.sensitive = bind.sensitive;
        apply_serial.clicked.connect (() => {
            string value = bind.text.strip ();
            if (!Regex.match_simple ("^[0-9]+$", value)) { show_error (_("Enter a numeric serial number or 0.")); return; }
            client.set_parameter (selected, "BindToSerial", {value});
        });
        serial.attach (apply_serial, 1, 1, 1, 1);
        return box;
    }

    private void edit_curve () {
        string[] current = client.read (selected, "PressureCurve").split (" ");
        var dialog = new Gtk.Dialog.with_buttons (_("Pressure Curve"), this, Gtk.DialogFlags.MODAL,
                                                   _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                   _("_Apply"), Gtk.ResponseType.OK);
        var grid = new Gtk.Grid ();
        grid.margin = 18; grid.row_spacing = 10; grid.column_spacing = 12;
        var coords = new Gtk.SpinButton[4];
        string[] names = {_("Control point 1 X"), _("Control point 1 Y"), _("Control point 2 X"), _("Control point 2 Y")};
        for (int i = 0; i < 4; i++) {
            coords[i] = new Gtk.SpinButton.with_range (0, 100, 1);
            double n = 0;
            if (i < current.length && double.try_parse (current[i], out n)) coords[i].set_value (n);
            row (grid, i, names[i], coords[i]);
        }
        var preview = new Gtk.DrawingArea ();
        preview.set_size_request (240, 200);
        grid.attach (preview, 0, 4, 2, 1);
        foreach (var coord in coords) coord.value_changed.connect (() => preview.queue_draw ());
        preview.draw.connect ((cr) => {
            double width = preview.get_allocated_width ();
            double height = preview.get_allocated_height ();
            double pad = 16;
            cr.set_source_rgb (0.96, 0.96, 0.96); cr.paint ();
            cr.set_source_rgb (0.7, 0.7, 0.7); cr.set_line_width (1);
            cr.rectangle (pad, pad, width - 2 * pad, height - 2 * pad); cr.stroke ();
            cr.set_source_rgb (0.25, 0.42, 0.72); cr.set_line_width (3);
            cr.move_to (pad, height - pad);
            cr.curve_to (pad + coords[0].value / 100.0 * (width - 2 * pad),
                         height - pad - coords[1].value / 100.0 * (height - 2 * pad),
                         pad + coords[2].value / 100.0 * (width - 2 * pad),
                         height - pad - coords[3].value / 100.0 * (height - 2 * pad),
                         width - pad, pad);
            cr.stroke ();
            return false;
        });
        dialog.get_content_area ().add (grid);
        dialog.show_all ();
        if (dialog.run () == Gtk.ResponseType.OK) {
            string[] args = {};
            foreach (var coord in coords) args += "%d".printf (coord.get_value_as_int ());
            client.set_parameter (selected, "PressureCurve", args);
        }
        dialog.destroy ();
    }

    private void add_action_row (Gtk.Grid grid, int index, string label, string parameter, string? sub = null) {
        string[] key = {};
        if (sub != null) key += sub;
        string current = sub == null ? client.read (selected, parameter) : client.read (selected, parameter + " " + sub);
        var button = new Gtk.Button.with_label (current.length > 0 ? current : _("Choose action…"));
        button.clicked.connect (() => edit_action (label, parameter, key, button));
        row (grid, index, label, button);
        button.sensitive = client.supports (selected, sub == null ? parameter : parameter + " " + sub);
    }

    private string control_label (string control) {
        switch (control) {
        case "AbsWheelUp": return _("Ring up");
        case "AbsWheelDown": return _("Ring down");
        case "AbsWheel2Up": return _("Second ring up");
        case "AbsWheel2Down": return _("Second ring down");
        case "DialCW": return _("Dial clockwise");
        case "DialCCW": return _("Dial counterclockwise");
        case "Dial2CW": return _("Second dial clockwise");
        case "Dial2CCW": return _("Second dial counterclockwise");
        case "RelWheelUp": return _("Wheel up");
        case "RelWheelDown": return _("Wheel down");
        case "RelWheel2Up": return _("Second wheel up");
        case "RelWheel2Down": return _("Second wheel down");
        default: return control;
        }
    }

    private void edit_action (string label, string parameter, string[] key, Gtk.Button button) {
        var dialog = new Gtk.Dialog.with_buttons (label, this, Gtk.DialogFlags.MODAL,
                                                   _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                   _("_Apply"), Gtk.ResponseType.OK);
        var grid = new Gtk.Grid ();
        grid.margin = 18; grid.row_spacing = 10; grid.column_spacing = 12;
        var actions = new Gtk.ComboBoxText ();
        string[] ids = {"default", "0", "1", "2", "3", "key", "button", "pan", "modetoggle", "custom"};
        string[] labels = {_("Application / driver default"), _("Do nothing"), _("Left click"), _("Middle click"), _("Right click"),
                           _("Send keyboard keys"), _("Send mouse button"), _("Pan with pen"), _("Toggle pen/mouse mode"), _("Custom driver action")};
        for (int i = 0; i < ids.length; i++) actions.append (ids[i], labels[i]);
        actions.set_active (0);
        row (grid, 0, _("Action"), actions);
        var entry = new Gtk.Entry ();
        entry.placeholder_text = _("Example: ctrl z, 8, or key +ctrl z -ctrl");
        row (grid, 1, _("Keys, button, or action"), entry);
        var record = new Gtk.Button.with_label (_("Record Shortcut"));
        record.clicked.connect (() => {
            actions.set_active_id ("key");
            record.label = _("Press shortcut now…");
            record.grab_focus ();
        });
        record.key_press_event.connect ((event) => {
            string? keyname = Gdk.keyval_name (event.keyval);
            if (keyname == null || keyname.has_prefix ("Control_") || keyname.has_prefix ("Shift_") ||
                keyname.has_prefix ("Alt_") || keyname.has_prefix ("Super_")) return true;
            string keys = "";
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) keys += "ctrl ";
            if ((event.state & Gdk.ModifierType.MOD1_MASK) != 0) keys += "alt ";
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0) keys += "shift ";
            keys += keyname;
            entry.text = keys;
            record.label = keys;
            return true;
        });
        grid.attach (record, 1, 2, 1, 1);
        var info = new Gtk.Label (_("For keys, enter X11 key names separated by spaces. Custom actions use xsetwacom syntax."));
        info.xalign = 0; info.set_line_wrap (true);
        grid.attach (info, 0, 3, 2, 1);
        dialog.get_content_area ().add (grid);
        dialog.show_all ();
        if (dialog.run () == Gtk.ResponseType.OK) {
            string? id = actions.get_active_id ();
            string value = id ?? "default";
            if (value == "key") value = "key " + entry.text.strip ();
            if (value == "button") value = "button " + entry.text.strip ();
            if (value == "custom") value = entry.text.strip ();
            string[] args = {};
            foreach (string part in key) args += part;
            if (value != "default") args += value;
            if (client.set_parameter (selected, parameter, args)) button.label = value;
        }
        dialog.destroy ();
    }

    private Gtk.Widget make_pad () {
        var box = page (_("Tablet pad"), _("Assign actions to ExpressKeys, rings, dials, strips, and wheels supported by this pad."));
        var buttons = group (box, _("ExpressKeys"));
        int count = 0;
        for (int i = 1; i <= 32; i++) {
            if (!client.supports (selected, "Button %d".printf (i))) continue;
            add_action_row (buttons, count++, _("Button %d").printf (i), "Button", i.to_string ());
        }
        if (count == 0) buttons.attach (new Gtk.Label (_("No configurable buttons found")), 0, 0, 2, 1);
        var wheels = group (box, _("Rings, dials, strips, and wheels"));
        string[] controls = {"AbsWheelUp", "AbsWheelDown", "AbsWheel2Up", "AbsWheel2Down",
                             "DialCW", "DialCCW", "Dial2CW", "Dial2CCW",
                             "RelWheelUp", "RelWheelDown", "RelWheel2Up", "RelWheel2Down"};
        count = 0;
        foreach (string control in controls)
            if (client.supports (selected, control)) add_action_row (wheels, count++, control_label (control), control);
        if (count == 0) wheels.attach (new Gtk.Label (_("No configurable ring or wheel found")), 0, 0, 2, 1);
        return box;
    }

    private Gtk.Widget make_touch () {
        var box = page (_("Touch"), _("Touch and gesture settings exposed by the installed Wacom X11 driver."));
        var basic = group (box, _("Touch input"));
        toggle (basic, 0, _("Enable touch"), "Touch");
        choice (basic, 1, _("Tracking mode"), "Mode", {"Absolute", "Relative"}, {_("Map to screen"), _("Move cursor")});
        var gestures = group (box, _("Gestures"));
        toggle (gestures, 0, _("Enable gestures"), "Gesture");
        number (gestures, 1, _("Scroll distance"), "ScrollDistance", 0, 100000, 1);
        number (gestures, 2, _("Zoom distance"), "ZoomDistance", 0, 100000, 1);
        number (gestures, 3, _("Tap time (ms)"), "TapTime", 0, 10000, 1);
        toggle (gestures, 4, _("Invert scrolling"), "InvertScroll");
        return box;
    }

    private string profile_path () {
        return Path.build_filename (Environment.get_user_config_dir (), "mate-wacom", "profiles.ini");
    }

    private string profile_prefix () {
        return selected.name.replace ("[", "(").replace ("]", ")") + "/" + selected.kind + "/";
    }

    private Gtk.Widget make_profiles () {
        var box = page (_("Profiles"), _("Save and apply named sets of driver settings for the selected tool."));
        var grid = group (box, _("Saved profiles"));
        profile_combo = new Gtk.ComboBoxText ();
        var keyfile = new KeyFile ();
        try {
            keyfile.load_from_file (profile_path (), KeyFileFlags.NONE);
            foreach (string name in keyfile.get_groups ()) {
                if (name.has_prefix (profile_prefix ())) profile_combo.append_text (name.substring (profile_prefix ().length));
            }
        } catch (Error e) { }
        profile_combo.set_active (0);
        row (grid, 0, _("Profile"), profile_combo);
        var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var save = new Gtk.Button.with_label (_("Save Current Settings…"));
        save.clicked.connect (() => save_profile ());
        buttons.pack_start (save, false, false, 0);
        var apply = new Gtk.Button.with_label (_("Apply Profile"));
        apply.clicked.connect (() => apply_profile ());
        buttons.pack_start (apply, false, false, 0);
        var remove = new Gtk.Button.with_label (_("Delete Profile"));
        remove.clicked.connect (() => delete_profile ());
        buttons.pack_start (remove, false, false, 0);
        grid.attach (buttons, 1, 1, 1, 1);
        return box;
    }

    private string[] profile_parameters () {
        string[] params = {"Mode", "Rotate", "Area", "PressureCurve", "Threshold", "RawSample",
                           "Suppress", "PressureRecalibration", "TabletPCButton", "Touch", "Gesture",
                           "ScrollDistance", "ZoomDistance", "TapTime", "PanScrollThreshold"};
        for (int i = 1; i <= 32; i++) params += "Button %d".printf (i);
        string[] controls = {"AbsWheelUp", "AbsWheelDown", "AbsWheel2Up", "AbsWheel2Down",
                             "DialCW", "DialCCW", "Dial2CW", "Dial2CCW",
                             "RelWheelUp", "RelWheelDown", "RelWheel2Up", "RelWheel2Down"};
        foreach (string control in controls) params += control;
        return params;
    }

    private void save_profile () {
        var dialog = new Gtk.Dialog.with_buttons (_("Save Profile"), this, Gtk.DialogFlags.MODAL,
                                                   _("_Cancel"), Gtk.ResponseType.CANCEL,
                                                   _("_Save"), Gtk.ResponseType.OK);
        var entry = new Gtk.Entry ();
        entry.margin = 16; entry.placeholder_text = _("Profile name");
        dialog.get_content_area ().add (entry);
        dialog.show_all ();
        if (dialog.run () == Gtk.ResponseType.OK && entry.text.strip ().length > 0) {
            string group_name = profile_prefix () + entry.text.strip ().replace ("[", "(").replace ("]", ")");
            var keyfile = new KeyFile ();
            try { keyfile.load_from_file (profile_path (), KeyFileFlags.NONE); } catch (Error e) { }
            foreach (string param in profile_parameters ()) {
                string value;
                if (client.get_parameter (selected, param, out value)) keyfile.set_string (group_name, param, value.strip ());
            }
            keyfile.set_string (group_name, "ScreenOutput", selected_output);
            try {
                DirUtils.create_with_parents (Path.get_dirname (profile_path ()), 0700);
                FileUtils.set_contents (profile_path (), keyfile.to_data ());
            } catch (Error e) { show_error (e.message); }
            rebuild_pages ();
        }
        dialog.destroy ();
    }

    private void apply_profile () {
        string? name = profile_combo.get_active_text ();
        if (name == null) return;
        var keyfile = new KeyFile ();
        try {
            keyfile.load_from_file (profile_path (), KeyFileFlags.NONE);
            string group_name = profile_prefix () + name;
            foreach (string param in profile_parameters ()) {
                if (!keyfile.has_key (group_name, param)) continue;
                string value = keyfile.get_string (group_name, param);
                string[] args = {};
                if (param == "Area" || param == "PressureCurve") {
                    foreach (string part in value.split (" "))
                        if (part.length > 0) args += part;
                } else {
                    args += value;
                }
                string command = param;
                if (param.has_prefix ("Button ")) {
                    command = "Button";
                    args = {param.substring (7), value};
                }
                client.set_parameter (selected, command, args);
            }
            if (keyfile.has_key (group_name, "ScreenOutput")) {
                selected_output = keyfile.get_string (group_name, "ScreenOutput");
                client.set_parameter (selected, "MapToOutput", {selected_output});
            }
            rebuild_pages ();
        } catch (Error e) { show_error (e.message); }
    }

    private void delete_profile () {
        string? name = profile_combo.get_active_text ();
        if (name == null) return;
        var keyfile = new KeyFile ();
        try {
            keyfile.load_from_file (profile_path (), KeyFileFlags.NONE);
            keyfile.remove_group (profile_prefix () + name);
            FileUtils.set_contents (profile_path (), keyfile.to_data ());
            rebuild_pages ();
        } catch (Error e) { show_error (e.message); }
    }

    private void reset_current () {
        if (selected == null) return;
        var dialog = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
                                            Gtk.ButtonsType.OK_CANCEL,
                                            _("Reset the selected tool's active area and button mappings?"));
        if (dialog.run () == Gtk.ResponseType.OK) {
            client.set_parameter (selected, "ResetArea", {});
            for (int i = 1; i <= 32; i++)
                if (client.supports (selected, "Button %d".printf (i)))
                    client.set_parameter (selected, "Button", {i.to_string ()});
            rebuild_pages ();
        }
        dialog.destroy ();
    }

    private void show_tester () {
        var dialog = new Gtk.Dialog.with_buttons (_("Tablet Tester"), this, Gtk.DialogFlags.MODAL,
                                                   _("_Close"), Gtk.ResponseType.CLOSE);
        dialog.set_default_size (650, 400);
        var box = dialog.get_content_area ();
        var info = new Gtk.Label (_("Draw here to test pointer motion and button events."));
        info.margin = 12;
        box.pack_start (info, false, false, 0);
        var area = new Gtk.DrawingArea ();
        area.set_size_request (600, 300);
        area.add_events (Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK |
                         Gdk.EventMask.BUTTON_RELEASE_MASK);
        double last_x = -1, last_y = -1;
        var strokes = new double[0];
        area.button_press_event.connect ((event) => { last_x = event.x; last_y = event.y; return true; });
        area.button_release_event.connect ((event) => { last_x = -1; last_y = -1; return true; });
        area.motion_notify_event.connect ((event) => {
            if (last_x >= 0 && (event.state & Gdk.ModifierType.BUTTON1_MASK) != 0) {
                strokes += last_x; strokes += last_y; strokes += event.x; strokes += event.y;
                area.queue_draw ();
            }
            last_x = event.x; last_y = event.y;
            return true;
        });
        area.draw.connect ((cr) => {
            cr.set_source_rgb (1, 1, 1); cr.paint ();
            cr.set_source_rgb (0.2, 0.3, 0.7); cr.set_line_width (2);
            for (int i = 0; i + 3 < strokes.length; i += 4) {
                cr.move_to (strokes[i], strokes[i + 1]); cr.line_to (strokes[i + 2], strokes[i + 3]);
            }
            cr.stroke ();
            return false;
        });
        box.pack_start (area, true, true, 0);
        var clear = new Gtk.Button.with_label (_("Clear"));
        clear.clicked.connect (() => { strokes = new double[0]; area.queue_draw (); });
        box.pack_start (clear, false, false, 8);
        dialog.show_all ();
        dialog.run ();
        dialog.destroy ();
    }
}

public class WacomApp : Gtk.Application {
    public WacomApp () {
        Object (application_id: "org.mate.WacomProperties", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void activate () {
        Gtk.Settings.get_default ().gtk_dialogs_use_header = false;
        var window = new WacomWindow (this);
        window.present ();
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = Environment.get_variable ("MATE_WACOM_LOCALEDIR") ?? LOCALEDIR;
        Intl.bindtextdomain ("mate-wacom", locale_dir);
        Intl.bind_textdomain_codeset ("mate-wacom", "UTF-8");
        Intl.textdomain ("mate-wacom");
        return new WacomApp ().run (args);
    }
}
