browserify = require 'browserify'
coffeeify = require 'coffeeify'
watchify = require 'watchify'

livereload = require 'tiny-lr'

path = require 'path'
fs = require 'fs'

if process.env.LANGUAGE
  ignoredLanguages = ["./src/languages/!(#{process.env.LANGUAGE}).coffee"]

serveNoDottedFiles = (connect, options, middlewares) ->
  # Avoid leaking .git/.svn or other dotted files from test servers.
  middlewares.unshift (req, res, next) ->
    if req.url.indexOf('/.') < 0 then return next()
    res.statusCode = 404
    res.setHeader('Content-Type', 'text/html')
    res.end "Cannot GET #{req.url}"
  return middlewares

module.exports = (grunt) ->
  # Assemble a list of files not to try to
  # do browserify on; these are the ones that contain
  # require() calls from different modules systems or
  # are already packaged.
  NO_PARSE = [
    path.resolve('./vendor/coffee-script.js')
    path.resolve('./vendor/acorn.js')
    path.resolve('./vendor/skulpt.js')
    path.resolve('./dist/droplet-full.js')
  ]

  grunt.initConfig
    pkg: grunt.file.readJSON 'package.json'

    bowercopy:
      options:
        clean: true
      vendor:
        options:
          destPrefix: 'vendor'
        files:
          'ace' : 'ace-builds/src-noconflict'
          'coffee-script.js' : 'coffee-script/extras/coffee-script.js'
          'quadtree.js' : 'quadtree/quadtree.js'
          'qunit.js' : 'qunit/qunit/qunit.js'
          'qunit.css' : 'qunit/qunit/qunit.css'
          'acorn.js' : 'acorn/acorn.js'
          'sax.js': 'sax/lib/sax.js'

    qunit:
      options:
        timeout: 60000
        page:
          viewportSize:
            width: 1000
            height: 1000
      all:
        urls:
          (for x in grunt.file.expand('test/*.html')
            'http://localhost:8942/' + x)

    mochaTest:
      test:
        src: [
          'test/src/parserTests.coffee'
          'test/src/modelTests.coffee'
        ]
        options:
          reporter: 'list'
          compilers:
            'coffee': 'coffee-script/register'
          timeout: 20000

    browserify:
      build:
        files:
          'dist/droplet-full.js': ['./src/main.coffee']
        options:
          ignore: ignoredLanguages
          transform: ['coffeeify']
          browserifyOptions:
            standalone: 'droplet'
            noParse: NO_PARSE
          banner: '''
          /* Droplet.
           * Copyright (c) <%=grunt.template.today('yyyy')%> Anthony Bau.
           * MIT License.
           *
           * Date: <%=grunt.template.today('yyyy-mm-dd')%>
           */
          '''
      test:
        files:
          'test/js/ctest.js': ['test/src/ctest.coffee']
          'test/js/tests.js': ['test/src/tests.coffee']
          'test/js/uitest.js': ['test/src/uitest.coffee']
          'test/js/jstest.js': ['test/src/jstest.coffee']
          'test/js/cstest.js': ['test/src/cstest.coffee']
          'test/js/htmltest.js': ['test/src/htmltest.coffee']
        options:
          transform: ['coffeeify']
          browserifyOptions:
            noParse: NO_PARSE

    cssmin:
      options:
        banner: '''
          /* Droplet. | (c) <%=grunt.template.today('yyyy')%> Anthony Bau. | MIT License.
           */
          '''
      minify:
        src: ['css/droplet.css']
        dest: 'dist/droplet.min.css'
        ext: '.min.css'

    uglify:
      options:
        banner: '''
          /* Droplet. | (c) <%=grunt.template.today('yyyy')%> Anthony Bau. | MIT License.
           */
        '''
        sourceMap: true

      build:
        files:
          'dist/droplet-full.min.js': [
            'dist/droplet-full.js'
          ]

    connect:
      testserver:
        options:
          hostname: '0.0.0.0'
          port: 8001
          middleware: serveNoDottedFiles
      qunitserver:
        options:
          hostname: '0.0.0.0'
          port: 8942
          middleware: serveNoDottedFiles

  grunt.loadNpmTasks 'grunt-bowercopy'
  grunt.loadNpmTasks 'grunt-banner'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-connect'
  grunt.loadNpmTasks 'grunt-contrib-cssmin'
  grunt.loadNpmTasks 'grunt-contrib-qunit'
  grunt.loadNpmTasks 'grunt-mocha-test'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-browserify'

  grunt.registerTask 'default',
    ['build']

  grunt.registerTask 'build',
    ['browserify:build']

  grunt.registerTask 'dist',
    ['build', 'uglify', 'cssmin']

  grunt.registerTask 'buildtests',
    ['browserify:test']

  grunt.registerTask 'all',
    ['dist', 'buildtests', 'test']

  grunt.task.registerTask 'test',
    'Run unit tests, or just one test.',
    (testname) ->
      if testname
        grunt.config 'qunit.all', ['test/' + testname + '.html']
      else
        grunt.config 'qunit.all', (x for x in grunt.file.expand('test/*.html'))
      grunt.task.run 'connect:qunitserver'
      grunt.task.run 'qunit:all'
      grunt.task.run 'mochaTest'

  grunt.task.registerTask 'watchify', ->
    # Prevent the task from terminating
    @async()

    b = browserify {
      cache: {}
      packageCache: {}
      noParse: NO_PARSE
      delay: 100
      standalone: 'droplet'
    }

    b.require './src/main.coffee'
    b.transform coffeeify

    w = watchify(b)

    # Compile once through first
    stream = fs.createWriteStream 'dist/droplet-full.js'
    w.bundle().pipe stream

    stream.once 'close', ->
      console.log 'Initial bundle complete.'

      lrserver = livereload()

      lrserver.listen 36729, ->
        console.log 'Livereload server listening on 36729'

      w.on 'update', ->
        console.log 'File changed...'
        stream = fs.createWriteStream 'dist/droplet-full.js'
        try
          w.bundle().pipe stream
          stream.once 'close', ->
            console.log 'Rebuilt.'
            lrserver.changed {
              body: {
                files: ['dist/droplet-full.js']
              }
            }
        catch e
          console.log 'BUILD FAILED.'
          console.log e.stack

  grunt.registerTask 'testserver', ['connect:testserver', 'watchify']
