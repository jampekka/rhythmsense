file_handle = null

initialize = (msg) ->
	{dir, file} = msg.data
	fs_root = await navigator.storage.getDirectory()
	log_dir = await fs_root.getDirectoryHandle dir, create: true
	log_file = await log_dir.getFileHandle file, create: true
	file_handle = await log_file.createSyncAccessHandle()
	addEventListener "message", write_log_entry

	self.postMessage "initialized"

write_log_entry = (entry) ->
	if not file_handle?
		console.error "Got a log entry before the file was opened!"
		return
	entry = entry.data
	entry = JSON.stringify(entry) + "\n"
	entry = (new TextEncoder()).encode entry
	file_handle.write entry
	file_handle.flush()
	console.log "Wrote log"

addEventListener "message", initialize, once: true
