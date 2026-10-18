using GLib;

public class WacomDevice : Object {
    public string name;
    public string kind;
    public string id;

    public WacomDevice (string name, string kind, string id) {
        this.name = name;
        this.kind = kind;
        this.id = id;
    }
}

/* A thin UI adapter to the installed X11 driver tool. No tablet protocol,
 * hardware database, or settings daemon is implemented here. */
public class WacomClient : Object {
    public signal void device_error (string message);

    private bool run (string[] argv, out string output, bool report = true) {
        output = "";
        try {
            string stderr_text;
            int status;
            Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH,
                                null, out output, out stderr_text, out status);
            if (status == 0)
                return true;
            if (report)
                device_error (stderr_text.strip ().length > 0 ? stderr_text.strip () : _("xsetwacom failed"));
        } catch (SpawnError e) {
            if (report)
                device_error (e.message);
        }
        return false;
    }

    public WacomDevice[] list_devices () {
        WacomDevice[] devices = {};
        string output;
        if (!run ({"xsetwacom", "--list", "devices", null}, out output))
            return devices;
        try {
            var re = new Regex ("^(.+?)\\s+id:\\s*([0-9]+)\\s+type:\\s*([A-Za-z]+)", RegexCompileFlags.MULTILINE);
            MatchInfo match;
            if (re.match (output, 0, out match)) {
                do {
                    devices += new WacomDevice (match.fetch (1).strip (),
                                                match.fetch (3).down (), match.fetch (2));
                } while (match.next ());
            }
        } catch (RegexError e) {
            device_error (e.message);
        }
        return devices;
    }

    public bool get_parameter (WacomDevice device, string parameter, out string value) {
        string[] argv = {"xsetwacom", "get", device.id};
        foreach (string part in parameter.split (" ")) argv += part;
        argv += null;
        return run (argv, out value, false);
    }

    public bool supports (WacomDevice device, string parameter) {
        string value;
        return get_parameter (device, parameter, out value);
    }

    public bool set_parameter (WacomDevice device, string parameter, string[] values) {
        string[] argv = {"xsetwacom", "set", device.id, parameter};
        foreach (string value in values)
            argv += value;
        argv += null;
        string output;
        return run (argv, out output);
    }

    public string read (WacomDevice device, string parameter, string fallback = "") {
        string value;
        return get_parameter (device, parameter, out value) ? value.strip () : fallback;
    }

    public string[] outputs () {
        string output;
        string[] names = {"desktop"};
        if (run ({"xrandr", "--query", null}, out output, false)) {
            try {
                var re = new Regex ("^([^\\s]+) connected", RegexCompileFlags.MULTILINE);
                MatchInfo match;
                if (re.match (output, 0, out match)) {
                    do { names += match.fetch (1); } while (match.next ());
                }
            } catch (RegexError e) { }
        }
        return names;
    }

    public bool output_size (string name, out int width, out int height) {
        width = 0; height = 0;
        string output;
        if (name != "desktop") {
            try {
                var geometry = new Regex ("^([0-9]+)x([0-9]+)[+-]");
                MatchInfo match;
                if (geometry.match (name, 0, out match)) {
                    int.try_parse (match.fetch (1), out width);
                    int.try_parse (match.fetch (2), out height);
                    return width > 0 && height > 0;
                }
            } catch (RegexError e) { }
        }
        if (!run ({"xrandr", "--query", null}, out output, false)) return false;
        try {
            string expression = name == "desktop"
                ? "current ([0-9]+) x ([0-9]+)"
                : "^" + Regex.escape_string (name) + " connected(?: primary)? ([0-9]+)x([0-9]+)";
            var re = new Regex (expression, RegexCompileFlags.MULTILINE);
            MatchInfo match;
            if (!re.match (output, 0, out match)) return false;
            int.try_parse (match.fetch (1), out width);
            int.try_parse (match.fetch (2), out height);
            return width > 0 && height > 0;
        } catch (RegexError e) { return false; }
    }
}
