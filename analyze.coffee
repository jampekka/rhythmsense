Plotly = require "plotly.js-dist"
d3 = require 'd3'

{read_logs} = require './logging.coffee'


get_session_data = (log_events) ->
	session =
		trials: []
	for row in log_events
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
		beats = trial.hits
		continue if beats.length < 2
		durs = beats.map (v, i) -> 60/(v - beats[i-1]) - trial.bpm
			
		x = beats.slice(1).map (x) -> x - beats[0]
		x = [1..x.length]
		durs = durs.slice(1)
		
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
	sessions = {}
	
	sessions_el = document.querySelector "#session_selector"
	for await [name, log] from read_logs()
		sessions[name] = get_session_data log
		sessions_el.innerHTML += """
		<option value="#{name}">#{name}</option>
		"""
	
	select_session = (name) ->
		render_bpm_graph sessions[name]
	
	select_session Object.keys(sessions)[0]
	
	sessions_el.addEventListener "change", (ev) ->
		select_session ev.target.value

