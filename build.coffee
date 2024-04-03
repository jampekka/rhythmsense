coffeeScriptPlugin = require 'esbuild-coffeescript'
esbuild = require 'esbuild'

context = () ->
    ctx = await esbuild.context
        entryPoints: ['index.coffee']
        outdir: 'dist'
        sourcemap: true
        bundle: true
        plugins: [coffeeScriptPlugin()]

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
