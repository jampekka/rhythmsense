get_logger = (session_id) ->
	session_id ?= session_id = new Date() .toISOString()
	
	dir = "rhythmsense_log"
	file = session_id + ".jsons"

	worker = get_worker()
	worker.postMessage {dir, file}

	await new Promise (accept) ->
		worker.addEventListener "message", accept, once: true
	
	(data) ->
		worker.postMessage data

get_worker = ->
	#code = __WORKER_HACK__.toString().replace /^function .+\{?|\}$/g, ''
	#console.log __WORKER_HACK__.toString()
	#workerBlob = new Blob code, type: 'text/javascript'
	#workerUrl = URL.createObjectURL workerBlob
	new Worker 'dist/log_worker.js'

read_logs = ->
	fs_root = await navigator.storage.getDirectory()
	log_dir = await fs_root.getDirectoryHandle "rhythmsense_log"

	for await [name, handle] from log_dir.entries()
		file = await handle.getFile()
		# TODO: Could be a lot faster
		data = (await file.text()).split '\n'
		rows = []
		for line in data
			continue if not line
			rows.push JSON.parse line
		yield [name, rows]

module.exports = {get_logger, read_logs}
