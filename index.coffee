Plotly = require "plotly.js-dist"
$ = require 'jquery'

allbeats = []

ctx = null
click_sample = null
complete_sample = null
hit_sample = null

n_listening = 10
n_muted = 20
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
			color: "black"
		type: "line"
	
	data.push
		x: [n_listening, n_listening]
		y: [bpm - 5, bpm + 5]
		line:
			color: "black"
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

	Plotly.react "undersphere", data

run_trial = -> new Promise (resolve) ->
	click_gain = ctx.createGain()
	click_gain.connect ctx.destination
	clicker = ctx.createBufferSource()
	clicker.buffer = click_sample
	clicker.connect click_gain
	clicker.loop = true
	clicker.loopEnd = 1/(bpm/60)
	clicker.start()
	console.log("clicking")

	beats = []
	allbeats.push beats
	console.log allbeats

	controller = new AbortController()
	click = (ev) ->
		return if ev.repeat
		return if ev.key != " "
		play_sample ctx, hit_sample
		beats.push ev.timeStamp/1000
		return if beats.length < 2
		
		if beats.length == n_listening
			click_gain.gain.linearRampToValueAtTime 0, ctx.currentTime + 0.3
		
		setInterval render, 0

		if beats.length > n_muted + n_listening
			controller.abort()
			clicker.stop()
			play_sample ctx, complete_sample
			resolve()

	document.addEventListener "keydown", click,
		signal: controller.signal
		useCapture: true

wait_for_click = (el=document) -> new Promise (resolve) ->
	document.addEventListener "click", resolve, once: true



setup = () ->
	render()
	while true
		await wait_for_click()
		if not ctx
			ctx = new AudioContext()
			click_sample = await load_sample(ctx, 'click.flac')
			complete_sample = await load_sample(ctx, 'complete.oga')
			hit_sample = await load_sample(ctx, 'hit.wav')
		await run_trial()
	
setup()
