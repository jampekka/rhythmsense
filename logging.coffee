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
	log_dir = await fs_root.getDirectoryHandle "rhythmsense_log", create: true
	for await [name, handle] from log_dir.entries()
		file = await handle.getFile()
		# TODO: Could be a lot faster
		data = (await file.text()).split '\n'
		rows = []
		for line in data
			continue if not line
			rows.push JSON.parse line
		console.log [name, rows]
		yield [name, rows]

# Maybe doesn't belong here
analyze_accuracy = (trial) ->
	r = {trial...}
	hits = [trial.hits...]
	n_valid = (hits.length - 1)
	
	r.hit_durations = hits.map (v, i) -> (v - hits[i-1])
	r.hit_bpms = r.hit_durations.map (v) -> 60/v
	r.hit_bpm_errors = r.hit_bpms.map (v) -> v - trial.bpm
	r.hit_bpm_errors_abs = r.hit_bpm_errors.map Math.abs
	r.hit_bpm_mad = r.hit_bpm_errors_abs[1...].reduce (acc, v) ->
		acc + v/n_valid
	r.hit_bpm_score = 100 - (r.hit_bpm_mad/trial.bpm)*100
	r.hit_bpm_mean_error = r.hit_bpm_errors[1...].reduce (acc, v) -> acc + v/n_valid

	return r

module.exports = {get_logger, read_logs, analyze_accuracy}
