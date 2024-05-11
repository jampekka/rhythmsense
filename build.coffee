#coffeeScriptPlugin = require 'esbuild-coffeescript'
#{sassPlugin} = require 'esbuild-sass-plugin'
esbuild = require 'esbuild'

context = () ->
	ctx = await esbuild.context
		entryPoints: ['index.coffee', 'analyze.coffee', 'log_worker.coffee', 'style.scss']
		outdir: 'dist'
		sourcemap: true
		bundle: true
		plugins: [
			require("esbuild-coffeescript")(inlineMap: true)
			require("esbuild-sass-plugin").sassPlugin
				cache: false
		]

run = () ->
	cmd = process.argv[2] ? "build"
	if cmd == "build"
		await (await context()).rebuild()
		process.exit() # Hacky
	else if cmd == "serve"
		console.log await (await context()).serve servedir: "."
	else
		console.log "Unrecognized command #{build}"
run()
