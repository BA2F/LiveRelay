#include "my_application.h"
#include <cstring>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Present only this engine's own window after an explicit workbench request.
static void owner_window_method(FlMethodChannel* channel, FlMethodCall* call,
                                gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  const char* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "backend") == 0) {
    const char* backend = "other";
#ifdef GDK_WINDOWING_X11
    if (GDK_IS_X11_DISPLAY(display)) backend = "x11";
#endif
#ifdef GDK_WINDOWING_WAYLAND
    if (GDK_IS_WAYLAND_DISPLAY(display)) backend = "wayland";
#endif
    g_autoptr(FlValue) result = fl_value_new_string(backend);
    fl_method_call_respond_success(call, result, nullptr);
    return;
  }
  if (g_strcmp0(method, "requestActivationToken") == 0) {
    g_autofree char* token = nullptr;
#ifdef GDK_WINDOWING_WAYLAND
    // The initiating window's seat/event serial is retained by GDK. A
    // background presentation client cannot mint a valid user interaction.
    if (GDK_IS_WAYLAND_DISPLAY(display) && gtk_window_is_active(window) &&
        gdk_wayland_display_query_registry(display, "xdg_activation_v1")) {
      g_autoptr(GdkAppLaunchContext) context =
          gdk_display_get_app_launch_context(display);
      g_autoptr(GAppInfo) info = g_app_info_create_from_commandline(
          "live_relay", "LiveRelay", G_APP_INFO_CREATE_SUPPORTS_STARTUP_NOTIFICATION,
          nullptr);
      if (info != nullptr) {
        token = g_app_launch_context_get_startup_notify_id(
            G_APP_LAUNCH_CONTEXT(context), info, nullptr);
      }
    }
#endif
    g_autoptr(FlValue) result = token == nullptr
        ? fl_value_new_null() : fl_value_new_string(token);
    fl_method_call_respond_success(call, result, nullptr);
    return;
  }
  if (g_strcmp0(method, "activate") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  const char* token = nullptr;
  if (fl_value_get_type(args) != FL_VALUE_TYPE_NULL) {
    if (fl_value_get_type(args) != FL_VALUE_TYPE_STRING ||
        strlen(fl_value_get_string(args)) == 0 ||
        strlen(fl_value_get_string(args)) > 4096) {
      fl_method_call_respond_error(call, "INVALID_TOKEN", "Invalid activation token",
                                   nullptr, nullptr);
      return;
    }
    token = fl_value_get_string(args);
  }
#ifdef GDK_WINDOWING_WAYLAND
  if (token != nullptr && GDK_IS_WAYLAND_DISPLAY(display)) {
    // GDK consumes the token on the next focus request; never persist it or
    // place it in the environment inherited by another presentation client.
    gdk_wayland_display_set_startup_notification_id(display, token);
  }
#endif
  guint32 timestamp = GDK_CURRENT_TIME;
  gtk_widget_show(GTK_WIDGET(window));
#ifdef GDK_WINDOWING_X11
  GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(window));
  if (native != nullptr && GDK_IS_X11_WINDOW(native)) {
    gdk_window_set_events(native, static_cast<GdkEventMask>(
        gdk_window_get_events(native) | GDK_PROPERTY_CHANGE_MASK));
    timestamp = gdk_x11_get_server_time(native);
  }
#endif
  gtk_window_present_with_time(window, timestamp);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "LiveRelay");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "LiveRelay");
  }

  gtk_window_set_default_size(window, 1280, 720);
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable != nullptr) {
    g_autofree gchar* directory = g_path_get_dirname(executable);
    g_autofree gchar* icon = g_build_filename(directory, "data", "flutter_assets",
        "assets", "brand", "icon-256.png", nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) owner_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "liverelay/owner_window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(owner_channel, owner_window_method,
      g_object_ref(window), g_object_unref);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
