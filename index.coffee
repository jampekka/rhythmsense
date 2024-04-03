Plotly = require "plotly.js-dist"
$ = require 'jquery'

SampleSourceNode = require 'samplesourcenode'

allbeats = []

ctx = null
click_sample = null
complete_sample = null
hit_sample = null

n_listening = 10
n_muted = 30
bpm = 100


load_sample = (ctx, url) ->
	buf = await fetch url
	buf = await buf.arrayBuffer()
	buf = await ctx.decodeAudioData(buf)
	buf.channelInterpretation = "speakers"
	return buf

play_sample = (ctx, buffer) ->
	b = ctx.createBufferSource()
	b.buffer = buffer
	b.connect ctx.destination
	b.start()

render = ->
	data = []

	data.push
		x: [0, n_listening + n_muted]
		y: [bpm, bpm]
		line:
			color: "white"
		type: "line"
	
	data.push
		x: [n_listening, n_listening]
		y: [bpm - 5, bpm + 5]
		line:
			color: "white"
		type: "line"

	for beats in allbeats
		continue if beats.length < 2
		durs = beats.map (v, i) -> 60/(v - beats[i-1])
			
		x = beats.slice(1).map (x) -> x - beats[0]
		x = [1..x.length]
		durs = durs.slice(1)
		
		s = 0.8
		rolling = durs[0]
		meandurs = durs.map (v) ->
			rolling = s*rolling + (1 - s)*v
		
		data.push
			x: x
			y: durs
			type: "scatter"

	Plotly.react "footer", data,
		paper_bgcolor: "black"
		plot_bgcolor: "black"
		showlegend: false
		font:
			color: "white"

#onEvent = (el, event, callback) ->

STOP = Symbol("STOP")
listen = (el, event, opts, callback) ->
	if not opts?
		callback = opts
		opts = {}
	callback = opts if not opts?
	aborter = new AbortController()
	handler = (args...) ->
		ret = callback(args...)
		if ret == STOP
			aborter.abort()

	opts = {opts..., {signal: aborter.signal}...}
	el.addEventListener event, handler, opts

beatIndicator = document.querySelector "#beatindicator"
run_trial = -> new Promise (resolve) ->
	click_gain = ctx.createGain()
	click_gain.connect ctx.destination
	
	"""
	# TODO: Better buffer source node
	clicker = ctx.createBufferSource()
	clicker.buffer = click_sample
	clicker.connect click_gain
	clicker.loop = true
	clicker.loopEnd = 1/(bpm/60)
	clicker.start()
	listen clicker, "stop", ->
		console.log "Clickerstop"
	"""
	
	# TODO: Could reuse the clicker
	clicker = await SampleSourceNode ctx, buffer: click_sample
	clicker.loopEnd.value = 1/(bpm/60)
	clicker.connect click_gain
	clicker.start()
	

	beats = []
	allbeats.push beats
	console.log allbeats

	controller = new AbortController()
	click = (ev) ->
		return if ev.repeat
		return if ev.key != " "
		
		# TODO: Huge latency/jitter here
		b = ctx.createBufferSource()
		b.buffer = hit_sample
		bpan = ctx.createStereoPanner()
		bpan.pan.value = -1
		b.start()
		b.connect ctx.destination
		
		###
		d = ctx.createDelay()
		echo_bpm = bpm - 30
		echo_delay = 1/(echo_bpm/60)/2
		d.delayTime.value = echo_delay
		dg = ctx.createGain()
		dpan = ctx.createStereoPanner()
		dpan.pan.value = 1.0
		dg.gain.value = 0.8
		b.connect(d).connect(dpan).connect(dg).connect(ctx.destination)

		d = ctx.createDelay()
		echo_bpm = bpm
		echo_delay = 1/(echo_bpm/60)/2
		d.delayTime.value = echo_delay
		dg = ctx.createGain()
		dpan = ctx.createStereoPanner()
		dpan.pan.value = 1.0
		dg.gain.value = 0.8
		b.connect(d).connect(dpan).connect(dg).connect(ctx.destination)
		###
		
		play_sample ctx, hit_sample
		beats.push ev.timeStamp/1000
		return if beats.length < 2
		
		if beats.length == n_listening
			click_gain.gain.linearRampToValueAtTime 0, ctx.currentTime + 0.3
		
		#setInterval render, 0

		if beats.length > n_muted + n_listening
			controller.abort()
			clicker.stop()
			play_sample ctx, complete_sample
			resolve()

	document.addEventListener "keydown", click,
		signal: controller.signal
		useCapture: true

wait_for_event = (el=document, ev="click") -> new Promise (resolve) ->
	el.addEventListener ev, resolve, once: true



setup = () ->
	render()
	beatIndicator.innerHTML = "Click to start"
	while true
		await wait_for_event beatIndicator
		if not ctx
			ctx = new AudioContext()
			click_sample = await load_sample(ctx, 'click.flac')
			complete_sample = await load_sample(ctx, 'complete.oga')
			hit_sample = await load_sample(ctx, 'hit.wav')
		
		#TODO: bi.innerHTML = "Get ready to tap"
		#TODO: Tap to the beat
		beatIndicator.innerHTML = "Beat to the rythm"
		await run_trial()
		render()
	
setup()
