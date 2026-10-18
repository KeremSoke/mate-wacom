using GLib;
using Gtk;

/* A scaled preview of a surface (the X screen or the tablet) with a movable,
 * resizable rectangle on top. Everything is a themed widget: a frame for the
 * surface, frames for regions such as monitors, and buttons for the area and
 * its resize handle. */
public class AreaSelector : Gtk.Frame {
    /* Emitted for every change, including while dragging. */
    public signal void changed ();
    /* Emitted when the user finishes dragging. */
    public signal void committed ();

    public double area_x { get; private set; }
    public double area_y { get; private set; }
    public double area_width { get; private set; default = 1; }
    public double area_height { get; private set; default = 1; }

    private Gtk.Fixed surface = new Gtk.Fixed ();
    private Gtk.Button area = new Gtk.Button ();
    private Gtk.Label caption_label = new Gtk.Label (null);
    private Gtk.Button handle = new Gtk.Button.from_icon_name ("view-fullscreen-symbolic", Gtk.IconSize.MENU);
    private Gtk.Widget[] regions = {};
    private int max_width;
    private int max_height;
    private int surface_pixels_width = 1;
    private int surface_pixels_height = 1;
    private double origin_x = 0;
    private double origin_y = 0;
    private double surface_width = 1;
    private double surface_height = 1;
    private double scale = 1;
    private double ratio = 0;
    private bool resizing = false;
    private bool dragging = false;
    private double press_x;
    private double press_y;
    private double start_x;
    private double start_y;
    private double start_width;
    private double start_height;

    public AreaSelector (int max_width, int max_height) {
        this.max_width = max_width;
        this.max_height = max_height;
        shadow_type = Gtk.ShadowType.IN;
        halign = Gtk.Align.CENTER;
        get_style_context ().add_class ("view");
        add (surface);

        caption_label.set_ellipsize (Pango.EllipsizeMode.END);
        caption_label.width_chars = 0;
        caption_label.justify = Gtk.Justification.CENTER;
        area.add (caption_label);
        area.get_style_context ().add_class ("suggested-action");
        area.opacity = 0.85;
        area.tooltip_text = _("Drag to move");
        handle.tooltip_text = _("Drag to resize");
        surface.put (area, 0, 0);
        surface.put (handle, 0, 0);

        connect_drag (area, false, "move");
        connect_drag (handle, true, "nwse-resize");
        // Hidden widgets have no size, so place the handle again once shown.
        handle.show.connect_after (() => layout ());
        layout ();
    }

    /* Ratio of width to height the area is kept at, or 0 for none. */
    public double lock_ratio {
        get { return ratio; }
        set {
            ratio = value;
            set_area (area_x, area_y, area_width, area_height);
        }
    }

    public string caption {
        set { caption_label.set_markup ("<small>%s</small>".printf (Markup.escape_text (value))); }
    }

    public void set_surface (double x, double y, double width, double height) {
        origin_x = x;
        origin_y = y;
        surface_width = double.max (width, 1);
        surface_height = double.max (height, 1);
        scale = double.min (max_width / surface_width, max_height / surface_height);
        surface_pixels_width = (int) Math.round (surface_width * scale);
        surface_pixels_height = (int) Math.round (surface_height * scale);
        surface.set_size_request (surface_pixels_width, surface_pixels_height);
        foreach (var region in regions) region.destroy ();
        regions = {};
        set_area (area_x, area_y, area_width, area_height);
    }

    public void get_surface_size (out double width, out double height) {
        width = surface_width;
        height = surface_height;
    }

    /* Adds a labelled frame, such as a monitor, below the area. */
    public void add_region (double x, double y, double width, double height, string name) {
        var frame = new Gtk.Frame (null);
        frame.shadow_type = Gtk.ShadowType.ETCHED_IN;
        var label = new Gtk.Label (name);
        label.set_ellipsize (Pango.EllipsizeMode.END);
        label.width_chars = 0;
        label.valign = Gtk.Align.START;
        label.margin = 2;
        label.get_style_context ().add_class ("dim-label");
        frame.add (label);
        int px = to_pixels (x - origin_x), py = to_pixels (y - origin_y);
        frame.set_size_request (int.min (to_pixels (width), surface_pixels_width - px),
                                int.min (to_pixels (height), surface_pixels_height - py));
        surface.put (frame, px, py);
        frame.show_all ();
        regions += frame;
        // Keep the area and its handle stacked above every region.
        surface.remove (area);
        surface.remove (handle);
        surface.put (area, 0, 0);
        surface.put (handle, 0, 0);
        layout ();
    }

    /* Sets the area in surface units, clamped to the surface and lock ratio. */
    public void set_area (double x, double y, double width, double height) {
        double min = minimum_size ();
        width = width.clamp (min, surface_width);
        height = height.clamp (min, surface_height);
        if (ratio > 0) {
            if (width / height > ratio) width = height * ratio;
            else height = width / ratio;
        }
        area_x = x.clamp (origin_x, origin_x + surface_width - width);
        area_y = y.clamp (origin_y, origin_y + surface_height - height);
        area_width = width;
        area_height = height;
        layout ();
        changed ();
    }

    private int to_pixels (double units) {
        return (int) Math.round (units * scale);
    }

    private double minimum_size () {
        int width, height;
        handle.get_preferred_width (out width, null);
        handle.get_preferred_height (out height, null);
        return (int.max (width, height) + 8) / scale;
    }

    private void layout () {
        int px = to_pixels (area_x - origin_x), py = to_pixels (area_y - origin_y);
        int width = int.min (to_pixels (area_width), surface_pixels_width - px);
        int height = int.min (to_pixels (area_height), surface_pixels_height - py);
        area.set_size_request (width, height);
        surface.move (area, px, py);
        int handle_width, handle_height;
        handle.get_preferred_width (out handle_width, null);
        handle.get_preferred_height (out handle_height, null);
        surface.move (handle, px + width - handle_width, py + height - handle_height);
        caption_label.visible = width >= 72 && height >= 48;
    }

    private void connect_drag (Gtk.Button button, bool resize, string cursor) {
        button.add_events (Gdk.EventMask.POINTER_MOTION_MASK);
        button.enter_notify_event.connect ((event) => {
            event.window.set_cursor (new Gdk.Cursor.from_name (button.get_display (), cursor));
            return false;
        });
        button.button_press_event.connect ((event) => {
            if (event.button != 1) return false;
            dragging = true;
            resizing = resize;
            press_x = event.x_root;
            press_y = event.y_root;
            start_x = area_x;
            start_y = area_y;
            start_width = area_width;
            start_height = area_height;
            return false;
        });
        button.motion_notify_event.connect ((event) => {
            if (!dragging) return false;
            double dx = (event.x_root - press_x) / scale, dy = (event.y_root - press_y) / scale;
            if (!resizing) {
                set_area (start_x + dx, start_y + dy, area_width, area_height);
                return true;
            }
            double min = minimum_size ();
            double available_width = origin_x + surface_width - area_x;
            double available_height = origin_y + surface_height - area_y;
            double width = (start_width + dx).clamp (min, available_width);
            double height = (start_height + dy).clamp (min, available_height);
            if (ratio > 0) {
                height = width / ratio;
                if (height > available_height) {
                    height = available_height;
                    width = height * ratio;
                }
            }
            set_area (area_x, area_y, width, height);
            return true;
        });
        button.button_release_event.connect ((event) => {
            if (event.button != 1 || !dragging) return false;
            dragging = false;
            if (area_x != start_x || area_y != start_y ||
                area_width != start_width || area_height != start_height)
                committed ();
            return false;
        });
    }
}
