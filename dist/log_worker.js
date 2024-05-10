(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // log_worker.coffee
  var require_log_worker = __commonJS({
    "log_worker.coffee"(exports) {
      (function() {
        var file_handle, initialize, write_log_entry;
        file_handle = null;
        initialize = async function(msg) {
          var dir, file, fs_root, log_dir, log_file;
          ({ dir, file } = msg.data);
          fs_root = await navigator.storage.getDirectory();
          log_dir = await fs_root.getDirectoryHandle(dir, {
            create: true
          });
          log_file = await log_dir.getFileHandle(file, {
            create: true
          });
          file_handle = await log_file.createSyncAccessHandle();
          addEventListener("message", write_log_entry);
          return self.postMessage("initialized");
        };
        write_log_entry = function(entry) {
          if (file_handle == null) {
            console.error("Got a log entry before the file was opened!");
            return;
          }
          entry = entry.data;
          entry = JSON.stringify(entry) + "\n";
          entry = new TextEncoder().encode(entry);
          file_handle.write(entry);
          return file_handle.flush();
        };
        addEventListener("message", initialize, {
          once: true
        });
      }).call(exports);
    }
  });
  require_log_worker();
})();
//# sourceMappingURL=log_worker.js.map
