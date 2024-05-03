Plotly = require "plotly.js-dist"
d3 = require 'd3'

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
			text: "Beat number"
		yaxis:
			text: "BPM error"
	config = responsive: true
	# TODO: This currently overflows the legend and the axis texts.
	# don't know why.
	plot = Plotly.react "bpm_graph", data, layout, config

do ->
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
		render_bpm_graph sessions[name]
	
	
	sessions_el.addEventListener "change", (ev) ->
		select_session ev.target.value
	select_session Object.keys(sessions)[0]

