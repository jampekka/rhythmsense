Plotly = require "plotly.js-dist"
$ = require 'jquery'

log_events = []

fs_root = await navigator.storage.getDirectory()
# TODO: May in theory not be unique
session_id = new Date() .toISOString()
log_dir = await fs_root.getDirectoryHandle "rhythmsense_log", create: true
log_file = await log_dir.getFileHandle session_id + ".jsons", create: true
# TODO: Doesn't work in Safari apparently. Maybe make a worker logger
# anyway?
log_writer = await log_file.createWritable()
log = (type, data) ->
	header =
		type: type
		timestamp: performance.now()
		utc: Date.now()
	
	data = {header..., data...}
	log_writer.write JSON.stringify(data) + "\n"
	log_events.push data
log "session_start", {session_id}

load_sample = (ctx, url) ->
	buf = await fetch url
	buf = await buf.arrayBuffer()
	buf = await ctx.decodeAudioData(buf)
	buf.channelInterpretation = "speakers"
	return buf

get_sessions = ->
	sessions = []
	for row in log_events
		if row.type == "trialstart"
			session = {
				bpm: row.bpm
				echos: row.echos
				hits: []
			}
			sessions.push session
		if row.type == "hit"
			session.hits.push row.timestamp/1000
	return sessions

render = ({n_listening, n_muted}) ->
	data = []
	
	data.push
		x: [0, n_listening + n_muted]
		y: [0, 0]
		line:
			color: "white"
		type: "line"
	
	data.push
		x: [n_listening, n_listening]
		y: [-5, 5]
		line:
			color: "white"
		type: "line"
	
	for session in get_sessions()
		beats = session.hits
		continue if beats.length < 2
		durs = beats.map (v, i) -> 60/(v - beats[i-1]) - session.bpm
			
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
			name: Math.round session.bpm, 1

	Plotly.react "footer", data,
		paper_bgcolor: "black"
		plot_bgcolor: "black"
		#showlegend: false
		font:
			color: "white"

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
run_trial = ({bpm, samples, n_listening, n_muted, echos=[]}) -> new Promise (resolve) ->
	context = new AudioContext latencyHint: 0
	ctxlog = (type, data={}) ->
		log type, {audio_time: context.currentTime, data...}
	
	ctxlog "trialstart", {bpm, echos, n_listening, n_muted}
	
	beat_interval = 1/(bpm/60)
	metronome = new Metronome context, samples.click, beat_interval
	metronome.output.connect context.destination
	
	onBeat = (time) ->
		# Maybe stop the transport instead?
		#return if not metronomeOn
		ctxlog "tickscheduled", scheduled_at: time
		timeToEvent = time - context.currentTime
		timing = {delay: timeToEvent*1000, animTiming...}
		beatIndicator.animate metronomeAnim, timing
		#metronome.start time
	metronome.addEventListener "tickscheduled", (ev) -> onBeat ev.detail.at

	beats = []
	allbeats.push beats
	console.log allbeats

	hitter = context.createGain()
	hitter.connect context.destination
	
	for echo in echos
		# TODO: This doesn't work for long echos. Likely
		# the sample node gets disconnected/destroyed and its
		# data doesn't get kept? Or then the max delay bugs out?
		# TODO: Works on Firefox, fails on Chromium
		echo = 1/(echo/60)
		console.log echo
		delay = context.createDelay echo*2
		delay.delayTime.value = echo
		gain = context.createGain()
		gain.gain.value = 0.5
		hitter
			.connect delay
			.connect gain
			.connect context.destination


	metronome.start()
	controller = new AbortController()
	onHit = (ev) ->
		ctxlog "hit", ev
		playSample context, samples.hit, hitter
		

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
		await playSample context, samples.complete
		
		context.close()
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
	
	# Create a context to load the samples. This can be
	# done without user interaction
	ctx = new AudioContext()
	ctx.suspend()

	samples =
		click: await load_sample ctx, 'click.flac'
		# NOTE: On Chomium this has to be mono for the delays to work. If it's
		# stereo. Probably related to:
		# https://github.com/WebAudio/web-audio-api/issues/1719
		hit: await load_sample ctx, 'hit.mono.wav'
		complete: await load_sample ctx, 'complete.oga'
	
	n_listening = 10
	n_muted = 30

	render {n_listening, n_muted}
	beatIndicator.innerHTML = "Click to start"
	while true
		await wait_for_event beatIndicator
		# TODO: Load these from a suspended (or offline?) context
		# and wrap to an object.
		if not click_sample
			ctx = new AudioContext()
			click_sample = await load_sample(ctx, 'click.flac')
			complete_sample = await load_sample(ctx, 'complete.oga')
			hit_sample = await load_sample(ctx, 'hit.mono.wav')
		
		#TODO: bi.innerHTML = "Get ready to tap"
		#TODO: Tap to the beat
		beatIndicator.innerHTML = "Beat to the rhythm"
		bpm = Math.random()*100 + 50
		echos = []
		trial_spec = {
			bpm
			echos
			n_listening: 10
			n_muted: 30
		}

		# Debug
		trial_spec.n_listening = 1; trial_spec.n_muted = 3
		log "trial_starting", trial_spec
		await run_trial {samples: samples, trial_spec...}
		render {n_listening, n_muted}
	
setup()
