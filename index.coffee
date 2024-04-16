Plotly = require "plotly.js-dist"
$ = require 'jquery'
#Tone = require 'tone'

allbeats = []

# TODO: Refactor these
click_sample = null
complete_sample = null
hit_sample = null

n_listening = 15
n_muted = 30

# Debugging
#n_listening = 1
#n_muted = 100

bpm = 100

echos = [
	1.0
	1/(bpm/60)/2
	#1/(bpm/60)*1.5
]


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

easeInOffset = 0.1
###
hitAnim = [
	borderColor: "var(--beatRingColor)"
	offset: 0.0
,
	borderColor: "var(--beatRingHitColor)"
	offset: easeInOffset
	easing: "ease-in"
,
	borderColor: "var(--beatRingColor)"
	easing: "ease-out"
]
###

metronomeAnim = [
	borderColor: "var(--beatRingColor)"
	#borderWidth: "var(--beatBorderWidth)"
	#margin: 0
	offset: 0.0
,
	borderColor: "var(--beatRingHitColor)"
	#borderWidth: "var(--beatBorderHitWidth)"
	offset: easeInOffset
	#margin: "var(--beatBorderWidth)"
	easing: "ease-in"
,
	borderColor: "var(--beatRingColor)"
	#borderWidth: "var(--beatBorderWidth)"
	#margin: 0
	easing: "ease-out"
]

hitAnim = [
	backgroundColor: "var(--beatBgColor)"
	#borderColor: "var(--beatBgColor)"
	offset: 0.0
,
	backgroundColor: "var(--beatBgHitColor)"
	#borderColor: "var(--beatBgHitColor)"
	easing: "ease-in"
	offset: easeInOffset
,
	backgroundColor: "var(--beatBgColor)"
	#borderColor: "var(--beatBgColor)"
	easing: "ease-out"
]

animTiming =
	duration: 0.2*1000

audioInterval = (ctx, interval, cb) -> new Promise (accept) ->
	dummyNode = ctx.createConstantSource()
	dummyNode.addEventListener "ended", ->
		if cb
			accept(cb())
		else
			accept()
	interval -= ctx.baseLatency*2
	dummyNode.start()
	dummyNode.stop(ctx.currentTime + interval)

playSample = (ctx, sample, output) -> new Promise (accept) ->
	source = ctx.createBufferSource()
	source.buffer = sample
	source.addEventListener "ended", accept
	source.connect output ? ctx.destination
	source.start()

class Metronome extends EventTarget
	constructor: (@context, @sample, @interval) ->
		super()
		@output = @context.createGain()
		@_playing = false
		@_nextScheduledTime = null

	_scheduleSample: (@_nextScheduledTime) ->
		# Check if we're late
		if @_nextScheduledTime < @context.currentTime
			console.error "Metronome tick late by", @context.currentTime - @_nextScheduledTime
		@dispatchEvent new CustomEvent "tickscheduled",
			detail:
				at: @_nextScheduledTime
		source = @context.createBufferSource()
		source.buffer = @sample
		source.connect @output
		source.start @_nextScheduledTime
	
	start: ->
		return if @playing # We could return the ongoing promise if we'd be nice
		@_playing = true
		# Schedule the first sample at interval latency to try to get it to play
		# exactly on the scheduled time
		@_scheduleSample @context.currentTime + @interval
		while true
			if not @_playing
				@_nextScheduledTime = null
				return
			# Wait for fourth the interval. Just a random figure. Hope
			# it works.
			await audioInterval @context, @interval/4
			# If the previous sample hasn't started yet,
			# continue waiting until it has
			if @_nextScheduledTime > @context.currentTime
				continue
			# The previous sample has been played. Schedule a new one.
			# In theory we could schedule more samples ahead, but this
			# will probably suffice in practice.
			@_scheduleSample @_nextScheduledTime + @interval
			

	stop: ->
		# Could try to stop the scheduled sample,
		# but don't bother for now.
		@_playing = false

		

# TODO: Parametrize. Perhaps create a class
run_trial = -> new Promise (resolve) ->
	
	#nativeContext = new AudioContext
	#	latencyHint: 0

	#context = new Tone.Context
	#	#context: nativeContext
	#	#lookAhead: 0
	#	latencyHint: 0
	
	context = new AudioContext latencyHint: 0
	
	#metronome_gain = new Tone.Gain(context: context).toDestination()
	#metronome = new Tone.Player
	#	context: context
	#	url: click_sample
	#metronome.connect metronome_gain
	
	beat_interval = 1/(bpm/60)
	metronome = new Metronome context, click_sample, beat_interval
	metronome.output.connect context.destination
	
	# This is not really used
	#context.transport.bpm.value = bpm
	
	onBeat = (time) ->
		# Maybe stop the transport instead?
		#return if not metronomeOn
		timeToEvent = time - context.currentTime
		timing = {delay: timeToEvent*1000, animTiming...}
		beatIndicator.animate metronomeAnim, timing
		#metronome.start time
	metronome.addEventListener "tickscheduled", (ev) -> onBeat ev.detail.at

	# Don't use the transport bpm, operate on time diffs directly
	#metronome_repeat = context.transport.scheduleRepeat onBeat, beat_to_beat
	#context.transport.start()

	beats = []
	allbeats.push beats
	console.log allbeats

	###
	nativeCtx = context.rawContext._nativeContext
	hitter = new Tone.Player
		context: context
		url: hit_sample
	#.toDestination()
	hitter_pan = new Tone.Panner
		context: context
		pan: 0
	###
	
	#hitter.chain hitter_pan, context.destination
	
	
	hitter = context.createGain()
	hitter.connect context.destination
	
	for echo in echos
		# TODO: This doesn't work for long echos. Likely
		# the sample node gets disconnected/destroyed and its
		# data doesn't get kept? Or then the max delay bugs out?
		# TODO: Works on Firefox, fails on Chromium
		#delay = new Tone.Delay
		#	context: context
		#	delayTime: echo
		#	maxDelay: 2.0
		#gain = new Tone.Gain
		#	context: context
		#	gain: 0.5
		#console.log "Adding delay", echo
		#hitter_pan.chain delay, context.destination
		delay = context.createDelay echo*2
		console.log echo
		delay.delayTime.value = echo
		#gain = context.createGain()
		#gain.gain.value = 0.5
		hitter
			.connect delay
			#.connect gain
			.connect context.destination


	#endChime = new Tone.Player
	#	context: context
	#	url: complete_sample
	#.toDestination()
	

	metronome.start()
	controller = new AbortController()
	onHit = (ev) ->
		#hitter.start(0.0)
		#source = new Tone.ToneBufferSource
		#	context: context
		#	url: hit_sample
		#source = ctx.createBufferSource()
		#source.buffer = hit_sample
		#source.connect hitter_pan
		#source.start 0
		playSample context, hit_sample, hitter

		beatIndicator.animate hitAnim, animTiming
		beats.push ev.timeStamp/1000
		
		# TODO: Fade out instead?
		if beats.length == n_listening
			#metronome.output.gain.linearRampToValueAtTime 0, context.currentTime + 0.1
			metronome.stop()
		
		if beats.length == n_muted + n_listening
			teardown()
		
	
	teardown = ->
		controller.abort()
		#metronome.stop()
		await playSample context, complete_sample
		#endChime.start(0)
		
		context.close()
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
		if not click_sample
			ctx = new AudioContext()
			click_sample = await load_sample(ctx, 'click.flac')
			complete_sample = await load_sample(ctx, 'complete.oga')
			hit_sample = await load_sample(ctx, 'hit.wav')
		
		#TODO: bi.innerHTML = "Get ready to tap"
		#TODO: Tap to the beat
		beatIndicator.innerHTML = "Beat to the rhythm"
		await run_trial()
		render()
	
setup()
