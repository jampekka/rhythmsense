$ = require 'jquery'
lobos = require 'lobos'

#{AudioContext} = require 'standardized-audio-context'


logging = require './logging.coffee'

log_events = []

logger = await logging.get_logger()

log = (type, data, extraheader={}) ->
	header = {
		"type": type
		"timestamp": performance.now()
		"utc": Date.now()
		extraheader...
	}
	

	row = [header, data]
	logger row
	#console.log {header, data}
	log_events.push row
#log "session_start", {}

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

# TODO: Should be named audioTimeout
audioInterval = (ctx, interval, cb) -> new Promise (accept) ->
	done = ->
		if cb
			accept(cb())
		else
			accept()
	setTimeout done, interval*1000
	
	# Doesn't work on iOS safari at least
	###
	dummyNode = ctx.createConstantSource()
	dummyNode.addEventListener "ended", ->
		if cb
			accept(cb())
		else
			accept()
	interval -= ctx.baseLatency*2
	dummyNode.start()
	dummyNode.stop(ctx.currentTime + interval)
	###

playSample = (ctx, sample, output) ->
	source = ctx.createBufferSource()
	source.buffer = sample
	source.connect output ? ctx.destination
	source.start()

waitSample = (ctx, sample, output) -> new Promise (accept) ->
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
run_trial = (samples, trial_spec) -> new Promise (resolve) ->
	{bpm, n_listening, n_muted, echos=[]} = trial_spec
	context = new AudioContext latencyHint: "interactive"
	
	ctxlog = (type, data={}) ->
		log type, data, {audio_time: context.currentTime}
	
	ctxlog "trialstart", trial_spec
	
	beat_interval = 1/(bpm/60)
	metronome = new Metronome context, samples.click, beat_interval
	metronome.output.gain.value = 1.0
	metronome.output.connect context.destination
	
	onBeat = (time) ->
		# Maybe stop the transport instead?
		#return if not metronomeOn
		ctxlog "tickscheduled", scheduled_at: time
		timeToEvent = time - context.currentTime
		
		#timing = {delay: timeToEvent*1000, animTiming...}
		#beatIndicator.animate metronomeAnim, timing
	metronome.addEventListener "tickscheduled", (ev) -> onBeat ev.detail.at

	hitter = context.createGain()
	hitter.connect context.destination
	
	for echo in echos
		echo = 1/(echo/60)
		delay = context.createDelay echo*2
		delay.delayTime.value = echo
		gain = context.createGain()
		gain.gain.value = 0.05
		hitter
			.connect delay
			.connect gain
			.connect context.destination

	beats = []
	metronome.start()
	controller = new AbortController()
	prev_beat_timestamp = null
	onHit = (ev) ->
		ev_dump = logging.dump_primitives ev
		ctxlog "hit_event", ev_dump

		timestamp = ev.timeStamp/1000
		if prev_beat_timestamp? and (timestamp - prev_beat_timestamp) < 0.1
			return
		prev_beat_timestamp = timestamp

		ctxlog "hit", ev_dump
		# This fails to play sometimes!
		playSample context, samples.hit, hitter
		

		beatIndicator.animate hitAnim, animTiming
		beats.push timestamp
		
		# TODO: Fade out instead?
		if beats.length == n_listening
			#metronome.output.gain.linearRampToValueAtTime 0, context.currentTime + 0.1
			metronome.stop()
		
		if beats.length == n_muted + n_listening
			teardown()
		
	
	teardown = ->
		controller.abort()
		await waitSample context, samples.complete
		
		context.close()
		resolve {trial_spec..., hits: beats}
	

	onkeydown = (ev) ->
		return if ev.repeat
		return if ev.key != " "
		onHit(ev)

	document.addEventListener "keydown", onkeydown,
		signal: controller.signal
		capture: true
		passive: true
	
	document.addEventListener "pointerdown", onHit,
		signal: controller.signal
		capture: true
		passive: true

wait_for_event = (el=document, ev="click") -> new Promise (resolve) ->
	el.addEventListener ev, resolve, once: true

shuffleArray = (array) ->
	array = array.slice()
	for _, i in array
		j = Math.floor(Math.random() * (i + 1))
		[array[i], array[j]] = [array[j], array[i]]
	return array

main_el = document.querySelector "#main_container"

setup = () ->
	# Create a context to load the samples. This can be
	# done without user interaction
	
	ctx = new AudioContext()
	ctx.suspend()

	# TODO: Use 808 for all samples?
	# Sample from http://smd-records.com/tr808/?page_id=14
	samples =
		#click: await load_sample ctx, 'click.flac'
		#click: await load_sample ctx, 'sounds/808/TR808WAV/BD/BD5025.WAV'
		click: await load_sample ctx, 'sounds/808/TR808WAV/CL/CL.WAV'
		# NOTE: On Chomium this has to be mono for the delays to work. If it's
		# stereo. Probably related to:
		# https://github.com/WebAudio/web-audio-api/issues/1719
		#hit: await load_sample ctx, 'sounds/808_snare_7525.flac'
		# TODO: A bit too low and too much reverb(?)
		hit: await load_sample ctx, 'sounds/808/TR808WAV/HT/HT10.WAV'
		complete: await load_sample ctx, 'complete.flac'
	await ctx.close()
	#n_listening = 10
	#n_muted = 30
	
	n_listening = 10
	n_muted = 20

	# Debug
	#n_listening = 1; n_muted = 3; repetitions = 1
	
	expopts = {
		n_listening
		n_muted
		min_bpm: 60
		max_bpm: 160
	}
	
	gap_width = 120
	speed_of_sound = 340
	distances = [30, 40, 60]
	echo_at_distance = (d) ->
		d*2/speed_of_sound

	#fixed_bpms = distances.map (d) ->
	#	#echo_delay = d*2/speed_of_sound
	#	echo_delay = echo_at_distance d
	#	return 60/echo_delay/2
	
	fixed_bpms = [100, 70, 130]
	#fixed_echos = fixed_bpms.map (v) -> v*2

	no_echo_trials = fixed_bpms.map (v) -> bpm: v, echos: []
	intro_trials = no_echo_trials
	

	#no_echo_trials = Array(repetitions).fill(no_echo_trials).flat()
	good_echo_multipliers = [1.0, 2.0]
	bad_echo_multipliers = [0.9, 1.1, 1.9, 2.1]
	
	good_echo_trials = []
	for bpm, i in fixed_bpms
		for m in good_echo_multipliers
			echo = bpm*m
			good_echo_trials.push bpm: bpm, echos: [echo]
	
	bad_echo_trials = []
	for bpm, i in fixed_bpms
		for m in bad_echo_multipliers
			echo = bpm*m
			bad_echo_trials.push bpm: bpm, echos: [echo]
	
	# TODO: The sampling could be nicer?
	#random_bpms = (new lobos.Sobol(1)).take(10).map (v) ->
	#	v*(expopts.max_bpm - expopts.min_bpm) + expopts.min_bpm
	
	min_echo = 1.5
	max_echo = 2.5
	#random_echo_bpms = [random_bpms..., random_bpms...]
	#random_echos = shuffleArray (new lobos.Sobol(1)).take random_echo_bpms.length
	#random_echos = random_echos.map (v) ->
	#	v*(expopts.max_bpm - expopts.min_bpm) + expopts.min_bpm
	#	
	#	v*(max_echo - min_echo) + min_echo
	
	random_echo_trials = (new lobos.Sobol(2)).take(20).map ([bpm, echo]) ->
		bpm = bpm*(expopts.max_bpm - expopts.min_bpm) + expopts.min_bpm
		echo = echo*(max_echo - min_echo) + min_echo
		bpm: bpm, echos: [echo*bpm]
	
	random_bpm_trials = random_echo_trials[...10].map (t) ->
		{t..., echos: []}

	#random_bpm_trials = 
	#random_echo_trials = random_echo_bpms.map (bpm, i) ->
	#	bpm: bpm, echos: random_echos[i]
	
	trial_block = [
		no_echo_trials...,
		no_echo_trials...,
		
		good_echo_trials...,
		good_echo_trials...,
		
		bad_echo_trials...
		
		# TODO: Shouldn't maybe repeat these
		# to get more coverage instead of repetitions?
		random_bpm_trials...
		random_echo_trials...
	]

	
	trials = [
		no_echo_trials...,
		shuffleArray(trial_block)...,
		#shuffleArray(trial_block)...
	]
	
	duration = trials.reduce ((total, t) ->
		total + 60/t.bpm*(expopts.n_listening + expopts.n_muted) + 5),
		0
	console.log "Estimated session duration", duration/60
	
	# TODO: A total mess
	btn = document.querySelector "#start_button"
	btn.innerHTML = "Waiting for consent"
	form = document.querySelector "#consent_form"
	all_accepted = false
	$(form).change ->
		boxes = $('#consent_form input[type="checkbox"]')
		console.log boxes
		all_accepted = false
		btn.innerHTML = "Waiting for consent"
		for el in boxes
			if not $(el).prop("checked")
				all_accepted = false
				return
		all_accepted = true
		btn.innerHTML = "Start!"
		$(btn).addClass "btn-success"
	
	while true
		await wait_for_event document.querySelector "#start_button"
		if all_accepted
			break
	# This makes the AudioContext to stay suspended on iOS
	#document.querySelector("body").requestFullscreen navigationUI: "hide"
	
	name_el = document.querySelector "#name_input"
	log "experiment_start",
		name: name_el.value
	#render expopts
	main_el.setAttribute "state", "play"
	beatIndicator.innerHTML = "Tap to the beat"
	


	#rng = new lobos.Sobol 1
	#rng.next # Skip the first 0
	for trial_spec, i in trials
		main_el.setAttribute "state", "play"
		
		#TODO: bi.innerHTML = "Get ready to tap"
		#TODO: Tap to the beat
		beatIndicator.innerHTML = "Tap to the rhythm"
		#bpm = rng.next*(expopts.max_bpm - expopts.min_bpm) + expopts.min_bpm
		#echos = [bpm*0.7]
		trial_spec = {
			trial_spec...
			expopts...
			trial_number: i
		}
		
		log "trial_starting", trial_spec
		console.log "trial_starting", trial_spec
		result = await run_trial samples, trial_spec
		
		main_el.setAttribute "state", "feedback"
		
		analyzed = logging.analyze_accuracy result
		document.querySelector("#feedback_message").innerHTML = """
			<p>Trial #{i+1} of #{trials.length}</p>
			<p>Accuracy #{Math.round analyzed.hit_bpm_score}%</p>
			"""
		await wait_for_event document.querySelector "#again_button"
	main_el.setAttribute "state", "end"

setup()
