#include "my_application.h"
#include <glib.h>
#include <cstring>

static GLogWriterOutput suppress_benign_gdk_logs(GLogLevelFlags log_level,
                                                 const GLogField* fields,
                                                 gsize n_fields,
                                                 gpointer user_data) {
  for (gsize i = 0; i < n_fields; i++) {
    if (fields[i].key != nullptr && strcmp(fields[i].key, "MESSAGE") == 0) {
      const char* message = static_cast<const char*>(fields[i].value);
      if (message != nullptr) {
        if (strstr(message, "Unable to load") && strstr(message, "cursor theme")) {
          return G_LOG_WRITER_HANDLED;
        }
        if (strstr(message, "gdk_device_get_source") && strstr(message, "GDK_IS_DEVICE")) {
          return G_LOG_WRITER_HANDLED;
        }
      }
    }
  }
  return g_log_writer_default(log_level, fields, n_fields, user_data);
}

int main(int argc, char** argv) {
  g_log_set_writer_func(suppress_benign_gdk_logs, nullptr, nullptr);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
