async = require 'async'
convert = require 'convert-source-map'
combine = require 'combine-source-map'

TsCompiler = require './tsCompiler'

fs = require 'fs'
tsLibDefs = fs.readFileSync(__dirname + '/lib.d.ts', encoding: 'utf8')
tsSup = fs.readFileSync(__dirname + '/Sup.ts', encoding: 'utf8')
tsSupDefs = fs.readFileSync(__dirname + '/Sup.d.ts', encoding: 'utf8')

globalNames = ["Sup.ts"]
globals = { "Sup.ts": tsSup }

scriptNames = []
scripts = {}

actorComponentTypesByName = {}
actorComponentAccessors = ""

exports.init = (player, callback) ->
  player.behaviorClasses = {}
  player.createActor = (name, parentActor) -> new window.Sup.Actor name, parentActor
  player.createComponent = (type, actor, config) ->
    if type == 'Behavior'
      behaviorClass = player.behaviorClasses[config.behaviorName]
      if ! behaviorClass?
        throw new Error "Could not find a behavior class named \"#{config.behaviorName}\" for actor \"#{actor.getName()}\". Make sure you're using the class name, not the script's name and that the class is declared before the behavior component is created (or before the scene is loaded)."
      new behaviorClass actor.__inner, config.properties
    else
      if ! actorComponentTypesByName[type]?
        actorComponentTypesByName[type] = window
        parts = SupAPI.contexts["typescript"].plugins[type].exposeActorComponent.className.split "."
        actorComponentTypesByName[type] = actorComponentTypesByName[type][part] for part in parts
      new actorComponentTypesByName[type] actor

  for pluginName, plugin of SupAPI.contexts["typescript"].plugins
    if plugin.code?
      globalNames.push "#{pluginName}.ts"
      globals["#{pluginName}.ts"] = plugin.code

    tsSupDefs += plugin.defs if plugin.defs?

    if plugin.exposeActorComponent?
      actorComponentAccessors += "#{plugin.exposeActorComponent.propertyName}: #{plugin.exposeActorComponent.className}; "

  callback()
  return

exports.start = (player, callback) ->
  console.log "Compiling scripts..."

  globals["Sup.ts"] = globals["Sup.ts"].replace "// INSERT_COMPONENT_ACCESSORS", actorComponentAccessors
  tsSupDefs = tsSupDefs.replace "// INSERT_COMPONENT_ACCESSORS", actorComponentAccessors
  jsGlobals = TsCompiler globalNames, globals, "#{tsLibDefs}\ndeclare var console, window, localStorage, player, SupEngine, SupRuntime;", sourceMap: false
  if jsGlobals.errors.length > 0
    for error in jsGlobals.errors
      console.log "#{error.file}(#{error.position.line}): #{error.message}"

  else
    results = TsCompiler scriptNames, scripts, "#{tsLibDefs}#{tsSupDefs}", sourceMap: true
    if results.errors.length > 0
      for error in results.errors
        console.log "#{error.file}(#{error.position.line}): #{error.message}"

    else
      console.log "Compilation successful!"

      getLineCounts = (string) =>
        count = 1; index = -2
        loop
          index = string.indexOf("\n",index+1)
          break if index == -1
          count += 1
        return count

      line = getLineCounts( jsGlobals.script ) + 2
      combinedSourceMap = combine.create('bundle.js')
      for file in results.files
        comment = convert.fromObject( results.sourceMaps[file.name] ).toComment();
        combinedSourceMap.addFile( { sourceFile: file.name, source: file.text + "\n#{comment}" }, {line} )
        line += ( getLineCounts( file.text ) )

      convertedSourceMap = convert.fromBase64(combinedSourceMap.base64()).toObject();
      url = URL.createObjectURL(new Blob([ JSON.stringify(convertedSourceMap) ]));
      code = jsGlobals.script + results.script + "//# sourceMappingURL=#{url}"
      scriptFunction = new Function 'player', code
      scriptFunction player

  callback()
  return

exports.loadAsset = (player, entry, callback) ->
  scriptNames.push entry.name
  player.getAssetData "assets/#{entry.id}/script.txt", 'text', (err, script) ->
    scripts["#{entry.name}.ts"] = "#{script}\n"
    callback null, script
    return
  return
