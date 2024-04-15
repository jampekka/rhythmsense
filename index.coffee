Plotly = require "plotly.js-dist"
$ = require 'jquery'
Tone = require 'tone'

allbeats = []

# TODO: Refactor these
click_sample = null
complete_sample = null
hit_sample = null

n_listening = 15
n_muted = 30

# Debugging
#n_listening = 3
#n_muted = 3

bpm = 100


load_sample = (ctx, url) ->
	buf = await fetch url
	buf = await buf.arrayBuffer()
	buf = await ctx.decodeAudioData(buf)
	buf.channelInterpretation = "speakers"
	return buf

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
# TODO: Parametrize. Perhaps create a class
run_trial = -> new Promise (resolve) ->
	context = new Tone.Context()

	metronome_gain = new Tone.Gain(context: context).toDestination()
	metronome = new Tone.Player
		context: context
		url: click_sample
	metronome.connect metronome_gain
	
	# This is not really used
	context.transport.bpm.value = bpm
	
	onBeat = (time) ->
		metronome.start time
	
	# Don't use the transport bpm, operate on time diffs directly
	beat_to_beat = 1/(bpm/60)
	metronome_repeat = context.transport.scheduleRepeat onBeat, beat_to_beat
	console.log metronome_repeat
	context.transport.start()

	beats = []
	allbeats.push beats
	console.log allbeats

	hitter = new Tone.Player
		context: context
		url: hit_sample
	#.toDestination()
	hitter_pan = new Tone.Panner
		context: context
		pan: 0
	hitter.chain hitter_pan, context.destination
	
	endChime = new Tone.Player
		context: context
		url: complete_sample
	.toDestination()

	controller = new AbortController()
	onHit = (ev) ->
		hitter.start(0.0)
		beats.push ev.timeStamp/1000
		
		if beats.length == n_listening
			metronome_gain.gain.rampTo 0, 0.3
		
		if beats.length == n_muted + n_listening
			teardown()
		
	
	teardown = ->
		controller.abort()
		metronome.stop()
		
		endChime.start(0)
		
		# The chime seems to play to the end even though
		# we dispose. Unexpected, but makes things a bit easier.
		context.dispose()
		#context.transport.stop()
		resolve()
	

	onkeydown = (ev) ->
		return if ev.repeat
		return if ev.key != " "
		onHit(ev)

	document.addEventListener "keydown", onkeydown,
		signal: controller.signal
		useCapture: true
	document.addEventListener "pointerdown", onHit,
		signal: controller.signal
		useCapture: true

wait_for_event = (el=document, ev="click") -> new Promise (resolve) ->
	el.addEventListener ev, resolve, once: true



setup = () ->
	render()
	beatIndicator.innerHTML = "Click to start"
	while true
		await wait_for_event beatIndicator
		# TODO: Load these from a suspended (or offline?) context
		# and wrap to an object.
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
