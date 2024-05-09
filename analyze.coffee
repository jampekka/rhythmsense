Plotly = require "plotly.js-dist"
d3 = require 'd3'
mj = require 'mathjs'

{read_logs, analyze_accuracy} = require './logging.coffee'

get_session_data = (log_events) ->
	session =
		trials: []
	for row in log_events
		if row.type == "experiment_start"
			session.name = row.name
		if row.type == "trial_starting"
			trial = {
				row...,
				hits: []
			}
			session.trials.push trial
		if row.type == "trialstart"
			trial = {trial..., row...}
		if row.type == "hit"
			trial.hits.push row.timestamp/1000
	return session

render_bpm_graph = (session) ->
	{n_listening, n_muted, min_bpm, max_bpm} = session.trials[0]
	data = []
	data.push
		x: [0, n_listening + n_muted]
		y: [0, 0]
		line:
			color: "black"
		type: "line"
		showlegend: false
	
	data.push
		x: [n_listening, n_listening]
		y: [-5, 5]
		line:
			color: "black"
		type: "line"
		showlegend: false
	
	for trial in session.trials
		r = analyze_accuracy trial
		continue if r.hit_bpm_errors < 2
		
		#durs = r.hit_bpms
		durs = r.hit_bpm_errors
		x = [0..durs.length]
		
		s = 0.8
		rolling = durs[0]
		meandurs = durs.map (v) ->
			rolling = s*rolling + (1 - s)*v
		
		rel_bpm = (trial.bpm - min_bpm)/(max_bpm - min_bpm)
		data.push
			x: x
			y: durs
			type: "scatter"
			name: "BPM " + trial.bpm.toFixed 1
			line:
				color: d3.interpolateViridis rel_bpm
	
	layout =
		#showlegend: false
		autosize: true
		xaxis:
			title: "Beat number"
		yaxis:
			title: "BPM error"
	config = responsive: true
	# TODO: This currently overflows the legend and the axis texts.
	# don't know why.
	Plotly.newPlot "bpm_graph", data, layout, config

render_error_graph = (session) ->
	{n_listening, n_muted, min_bpm, max_bpm} = session.trials[0]
	bpms = []
	errors = []
	echos = []
	for trial in session.trials
		continue if trial.bpm != 70
		r = analyze_accuracy trial
		bpms.push trial.bpm
		silent = r.hit_bpms.slice(r.n_listening + 1)
		silent_mean_error = mj.evaluate "mean(silent - bpm)", {silent, bpm: trial.bpm}
		
		#console.log silent_mad, silent, trial.bpm
		#errors.push silent_mad
		errors.push silent_mean_error
		echo = trial.echos[0]
		echos.push (trial.echos[0] ? 0)/trial.bpm
	
	data = [
		x: echos
		y: errors
		type: "scatter"
		mode: "markers"
		marker:
			color: bpms
	]
	config = responsive: true
	layout =
		autosize: true
		xaxis:
			title: "Echo to BPM ratio"
		yaxis:
			title: "Mean BPM error"

	Plotly.newPlot "error_graph", data, layout, config

zip = require "@zip.js/zip.js"
saveFile = (filename, blob) ->
	element = document.createElement("a")
	url = URL.createObjectURL blob
	element.setAttribute "href", url
	element.setAttribute "download", filename
	element.click()
	URL.revokeObjectURL(url)

download_opfs = ->
	fs_root = await navigator.storage.getDirectory()
	zipFs = new zip.fs.FS()
	await zipFs.root.addFileSystemHandle fs_root
	blob = await zipFs.exportBlob()
	saveFile "rhythmsense.zip", blob

do ->
	document.querySelector "#download_all"
		.addEventListener 'click', download_opfs

	sessions = []
	
	sessions_el = document.querySelector "#session_selector"
	for await [name, log] from read_logs()
		data = get_session_data log
		continue if not data.trials.length
		sessions.push [name, data]
		
	sessions.sort().reverse()
	sessions = Object.fromEntries sessions
	
	for fname, session of sessions
		if session.name
			name = "#{session.name} #{fname}"
		else
			name = fname
		sessions_el.innerHTML += """
		<option value="#{fname}">#{name}</option>
		"""

	select_session = (name) ->
		sessions_el.value = name
		url = new URL window.location.href
		url.searchParams.set 'session', name
		history.replaceState null, "", url
		session = sessions[name]
		await render_bpm_graph session
		await render_error_graph session
	
	
	sessions_el.addEventListener "change", (ev) ->
		select_session ev.target.value
	
	session = new URL(window.location.href).searchParams.get('session') ? Object.keys(sessions)[0]
	select_session session

