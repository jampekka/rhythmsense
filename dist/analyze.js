(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };

  // logging.coffee
  var require_logging = __commonJS({
    "logging.coffee"(exports, module) {
      (function() {
        var get_logger, get_worker;
        get_logger = async function(session_id) {
          var dir, file, worker;
          if (session_id == null) {
            session_id = session_id = (/* @__PURE__ */ new Date()).toISOString();
          }
          dir = "rhythmsense_log";
          file = session_id + ".jsons";
          worker = get_worker();
          worker.postMessage({ dir, file });
          await new Promise(function(accept) {
            return worker.addEventListener("message", accept, {
              once: true
            });
          });
          return function(data) {
            return worker.postMessage(data);
          };
        };
        get_worker = function() {
          return new Worker("dist/log_worker.js");
        };
        module.exports = { get_logger };
      }).call(exports);
    }
  });

  // analyze.coffee
  var require_analyze = __commonJS({
    "analyze.coffee"(exports) {
      (function() {
        var list_logs, logging, read_logs;
        logging = require_logging();
        read_logs = async function* () {
          var data, file, fs_root, handle, i, len, line, log_dir, name, ref, results, rows, x;
          fs_root = await navigator.storage.getDirectory();
          log_dir = await fs_root.getDirectoryHandle("rhythmsense_log");
          ref = log_dir.entries();
          results = [];
          for await (x of ref) {
            [name, handle] = x;
            file = await handle.getFile();
            data = (await file.text()).split("\n");
            rows = [];
            for (i = 0, len = data.length; i < len; i++) {
              line = data[i];
              if (!line) {
                continue;
              }
              rows.push(JSON.parse(line));
            }
            results.push(yield [name, rows]);
          }
          return results;
        };
        list_logs = async function() {
          var log, name, ref, results, x;
          ref = read_logs();
          results = [];
          for await (x of ref) {
            [name, log] = x;
            console.log(name);
            results.push(console.log(log));
          }
          return results;
        };
        list_logs();
      }).call(exports);
    }
  });
  require_analyze();
})();
//# sourceMappingURL=analyze.js.map
