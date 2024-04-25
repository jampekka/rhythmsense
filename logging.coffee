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

module.exports = {get_logger}
