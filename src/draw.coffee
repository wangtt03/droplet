# Copyright (c) 2014 Anthony Bau (dab1998@gmail.com)
# MIT License
#
# Minimalistic HTML5 canvas wrapper. Mainly used as conveneince tools in Droplet.

## Private (convenience) functions
BEVEL_SIZE = 1.5
EPSILON = 0.00001

helper = require './helper.coffee'
SVG_STANDARD = helper.SVG_STANDARD

# ## _area ##
# Signed area of the triangle formed by vectors [ab] and [ac]
_area = (a, b, c) -> (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)

# ## _intersects ##
# Test the intersection of two line segments
_intersects = (a, b, c, d) ->
  ((_area(a, b, c) > 0) != (_area(a, b, d) > 0)) and ((_area(c, d, a) > 0) != (_area(c, d, b) > 0))

_bisector = (a, b, c, magnitude = 1) ->
  if a.equals(b) or b.equals(c)
    return null

  sample = a.from(b).normalize()

  diagonal = sample.plus(
    sampleB = c.from(b).normalize()
  )

  if diagonal.almostEquals ZERO
    return null
  else if sample.almostEquals sampleB
    return null

  diagonal = diagonal.normalize()

  scalar = magnitude / Math.sqrt((1 - diagonal.dot(sample) ** 2))

  diagonal.x *= scalar
  diagonal.y *= scalar

  if _area(a, b, c) < 0
    diagonal.x *= -1
    diagonal.y *= -1

  return diagonal

max = (a, b) -> `(a > b ? a : b)`
min = (a, b) -> `(b > a ? a : b)`

toRGB = (hex) ->
  # Convert to 6-char hex if not already there
  if hex.length is 4
    hex = (c + c for c in hex).join('')[1..]

  # Extract integers from hex
  r = parseInt hex[1..2], 16
  g = parseInt hex[3..4], 16
  b = parseInt hex[5..6], 16

  return [r, g, b]

zeroPad = (str, len) ->
  if str.length < len
    ('0' for [str.length...len]).join('') + str
  else
    str

twoDigitHex = (n) -> zeroPad Math.round(n).toString(16), 2

toHex = (rgb) ->
  return '#' + (twoDigitHex(k) for k in rgb).join ''

memoizedAvgColor = {}

avgColor = (a, factor, b) ->
  c = (a + ',' + factor + ',' + b)
  if c of memoizedAvgColor
    return memoizedAvgColor[c]
  a = toRGB a
  b = toRGB b

  newRGB = (a[i] * factor + b[i] * (1 - factor) for k, i in a)

  return memoizedAvgColor[c] = toHex newRGB

exports.Draw = class Draw
  ## Public functions
  constructor: (@ctx) ->
    canvas = document.createElement('canvas')
    @measureCtx = canvas.getContext '2d'
    @fontSize = 15
    @fontFamily = 'Courier New, monospace'
    @fontAscent = -2
    @fontBaseline = 10

    @measureCtx.font = "#{@fontSize}px #{@fontFamily}"

    @ctx.style.fontFamily = @fontFamily
    @ctx.style.fontSize = @fontSize

    self = this

    # ## Point ##
    # A point knows its x and y coordinate, and can do some vector operations.
    @Point = Point

    # ## Size ##
    # A Size knows its width and height.
    @Size = Size

    # ## Rectangle ##
    # A Rectangle knows its upper-left corner, width, and height,
    # and can do rectangular overlap, polygonal intersection,
    # and rectangle or point union (point union is called "swallow").
    @Rectangle = Rectangle
    # ## NoRectangle ##
    # NoRectangle is an alternate constructor for Rectangle which starts
    # the rectangle as nothing (without even a location). It can gain location and size
    # via unite() and swallow().
    @NoRectangle = class NoRectangle extends Rectangle
      constructor: -> super(null, null, 0, 0)

    # ## ElementWrapper ###
    @ElementWrapper = class ElementWrapper
      constructor: (@element) ->
        if @element?
          @element.style.display = 'none'
        @active = false
        @parent = @element?.parentNode ? self.ctx

      manifest: ->
        unless @element?
          @element = @makeElement()
          @getParentElement().appendChild @element

          unless @active
            @element.style.display = 'none'
        else unless @element.parentNode?
          @getParentElement().appendChild @element

      deactivate: ->
        if @active
          @active = false
          @element?.style?.display = 'none'

      activate: ->
        @manifest()
        unless @active
          @active = true
          @element?.style?.display = ''

      focus: ->
        @activate()
        @getParentElement().appendChild @element

      getParentElement: ->
        if @parent instanceof ElementWrapper
          @parent.manifest()
          return @parent.element
        else
          return @parent

      setParent: (parent) ->
        @parent = parent

        if @element?
          parent = @getParentElement()
          unless parent is @element.parentNode
            parent.appendChild @element

      destroy: ->
        if @element?
          if @element.parentNode?
            @element.parentNode.removeChild @element

    @Group = class Group extends ElementWrapper
      constructor: ->
        super()

      makeElement: ->
        return document.createElementNS SVG_STANDARD, 'g'

    # ## Path ##
    # This is called Path, but is forced to be closed so is actually a polygon.
    # It can do fast translation and rectangular intersection.
    @Path = class Path extends ElementWrapper
      constructor: (@_points = [], @bevel = false, @style) ->
        @_cachedTranslation = new Point 0, 0
        @_cacheFlag = true
        @_bounds = new NoRectangle()

        @_clearCache()

        @style = helper.extend {
          'strokeColor': 'none'
          'lineWidth': 1
          'fillColor': 'none'
          'dotted': ''
        }, @style

        super()

      _clearCache: ->
        if @_cacheFlag
          # If we have no points, return the empty rectangle
          # as our bounding box
          if @_points.length is 0
            @_bounds = new NoRectangle()
            @_lightBevelPath = @_darkBevelPath = ''

          # Otherwise, find our bounding box based
          # on our points.
          else
            # Bounds
            minX = minY = Infinity
            maxX = maxY = 0
            for point in @_points
              minX = min minX, point.x
              maxX = max maxX, point.x

              minY = min minY, point.y
              maxY = max maxY, point.y

            @_bounds.x = minX; @_bounds.y = minY
            @_bounds.width = maxX - minX; @_bounds.height = maxY - minY

            # Light bevels
            subpaths = []
            outsidePoints = []
            insidePoints = []
            for point, i in @_points[1..]
              if (point.x > @_points[i].x and point.y <= @_points[i].y) or
                 (point.y < @_points[i].y and point.x >= @_points[i].x)
                if outsidePoints.length is 0
                  insetCoord = @getInsetCoordinate i, BEVEL_SIZE
                  if insetCoord?
                    outsidePoints.push @_points[i]
                    insidePoints.push insetCoord
                insetCoord = @getInsetCoordinate i + 1, BEVEL_SIZE
                if insetCoord?
                  outsidePoints.push point
                  insidePoints.push insetCoord
              else unless point.equals(@_points[i]) or outsidePoints.length is 0
                subpaths.push(
                  'M' + outsidePoints.concat(insidePoints.reverse()).map((point) -> "#{point.x} #{point.y}").join(" L") + ' Z'
                )
                outsidePoints.length = insidePoints.length = 0

            if @_points[0].x > @_points[@_points.length - 1].x or
                @_points[0].y < @_points[@_points.length - 1].y
              if outsidePoints.length is 0
                insetCoord = @getInsetCoordinate @_points.length - 1, BEVEL_SIZE
                if insetCoord?
                  outsidePoints.push @_points[@_points.length - 1]
                  insidePoints.push insetCoord
              insetCoord = @getInsetCoordinate 0, BEVEL_SIZE
              if insetCoord?
                outsidePoints.push @_points[0]
                insidePoints.push insetCoord

            if outsidePoints.length > 0
              subpaths.push(
                'M' + outsidePoints.concat(insidePoints.reverse()).map((point) -> "#{point.x} #{point.y}").join(" L") + ' Z'
              )

            @_lightBevelPath = subpaths.join(' ')

            # Dark bevels
            subpaths = []
            outsidePoints = []
            insidePoints = []
            for point, i in @_points[1..]
              if (point.x < @_points[i].x and point.y >= @_points[i].y) or
                 (point.y > @_points[i].y and point.x <= @_points[i].x)
                if outsidePoints.length is 0
                  insetCoord = @getInsetCoordinate i, BEVEL_SIZE
                  if insetCoord?
                    outsidePoints.push @_points[i]
                    insidePoints.push insetCoord

                insetCoord = @getInsetCoordinate i + 1, BEVEL_SIZE
                if insetCoord?
                  outsidePoints.push point
                  insidePoints.push insetCoord
              else unless point.equals(@_points[i]) or outsidePoints.length is 0
                subpaths.push(
                  'M' + outsidePoints.concat(insidePoints.reverse()).map((point) -> "#{point.x} #{point.y}").join(" L") + ' Z'
                )
                outsidePoints.length = insidePoints.length = 0

            if @_points[0].x < @_points[@_points.length - 1].x or
                @_points[0].y > @_points[@_points.length - 1].y
              if outsidePoints.length is 0
                insetCoord = @getInsetCoordinate @_points.length - 1, BEVEL_SIZE
                if insetCoord?
                  outsidePoints.push @_points[@_points.length - 1]
                  insidePoints.push insetCoord
              insetCoord = @getInsetCoordinate 0, BEVEL_SIZE
              if insetCoord?
                outsidePoints.push @_points[0]
                insidePoints.push insetCoord

            if outsidePoints.length > 0
              subpaths.push(
                'M' + outsidePoints.concat(insidePoints.reverse()).map((point) -> "#{point.x} #{point.y}").join(" L") + ' Z'
              )

            @_darkBevelPath = subpaths.join(' ')

            @_cacheFlag = false

      _setPoints_raw: (points) ->
        @_points = points
        @_cacheFlag = true
        @_updateFlag = true

      setMarkStyle: (style) ->
        if style? and style.color isnt @markColor?
          @markColor = style.color
          @_markFlag = true
        else if @markColor?
          @markColor = null
          @_markFlag = true

      setPoints: (points) ->
        if points.length isnt @_points.length
          @_setPoints_raw points
          return
        for el, i in points
          unless @_points[i].equals(el)
            @_setPoints_raw points
            return
        return

      push: (point) ->
        @_points.push point
        @_cacheFlag = true
        @_updateFlag = true

      unshift: (point) ->
        @_points.unshift point
        @_cacheFlag = true
        @_updateFlag = true

      reverse: ->
        @_points.reverse()
        return this

      # ### Point containment ###
      # Accomplished with ray-casting
      contains: (point) ->
        @_clearCache()

        if @_points.length is 0 then return false

        unless @_bounds.contains point then return false

        # "Ray" to the left
        dest = new Point @_bounds.x - 10, point.y

        # Count intersections
        count = 0
        last = @_points[@_points.length - 1]
        for end in @_points
          if _intersects(last, end, point, dest) then count += 1
          last = end

        return count % 2 is 1

      equals: (other) ->
        unless other instanceof Path
          return false
        if other._points.length isnt @_points.length
          return false
        for el, i in other._points
          unless @_points[i].equals(el)
            return false
        return true

      # ### Rectangular intersection ###
      # Succeeds if any edges intersect or either shape is
      # entirely within the other.
      intersects: (rectangle) ->
        @_clearCache()

        if @_points.length is 0 then return false

        if not rectangle.overlap @_bounds then return false
        else
          # Try each pair of edges for intersections
          last = @_points[@_points.length - 1]
          rectSides = [
            new Point rectangle.x, rectangle.y
            new Point rectangle.right(), rectangle.y
            new Point rectangle.right(), rectangle.bottom()
            new Point rectangle.x, rectangle.bottom()
          ]
          for end in @_points
            lastSide = rectSides[rectSides.length - 1]
            for side in rectSides
              if _intersects(last, end, lastSide, side) then return true
              lastSide = side
            last = end

          # Intersections failed; see if we contain the rectangle.
          # Note that if we contain the rectangle we must contain all of its vertices,
          # so it suffices to test one vertex.
          if @contains rectSides[0] then return true

          # We don't contain the rectangle; see if it contains us.
          if rectangle.contains @_points[0] then return true

          # No luck
          return false

      bounds: -> @_clearCache(); @_bounds

      translate: (vector) ->
        @_cachedTranslation.translate vector
        @_cacheFlag = true

      getCommandString: ->
        if @_points.length is 0
          return ''

        pathCommands = []

        pathCommands.push "M#{Math.round(@_points[0].x)} #{Math.round(@_points[0].y)}"
        for point in @_points
          pathCommands.push "L#{Math.round(point.x)} #{Math.round(point.y)}"
        pathCommands.push "L#{Math.round(@_points[0].x)} #{Math.round(@_points[0].y)}"
        pathCommands.push "Z"
        return pathCommands.join ' '

      getInsetCoordinate: (i, length) ->
        j = i; prev = @_points[i]
        while prev.equals(@_points[i]) and j > i - @_points.length
          j--
          prev = @_points[j %% @_points.length]

        k = i; next = @_points[i]
        while next.equals(@_points[i]) and k < i + @_points.length
          k++
          next = @_points[k %% @_points.length]

        vector = _bisector prev, @_points[i], next, length
        return null unless vector?

        point = @_points[i].plus vector

        return point

      getLightBevelPath: -> @_clearCache(); @_lightBevelPath
      getDarkBevelPath: ->
        @_clearCache()
        unless @_darkBevelPath?
          debugger
        return @_darkBevelPath

      # TODO unhackify
      makeElement: ->
        @_clearCache()

        pathElement = document.createElementNS SVG_STANDARD, 'path'

        if @style.fillColor?
          pathElement.setAttribute 'fill', @style.fillColor

        @__lastFillColor = @style.fillColor
        @__lastStrokeColor = @style.strokeColor
        @__lastLineWidth = @style.lineWidth
        @__lastDotted = @style.dotted
        @__lastCssClass = @style.cssClass
        @__lastTransform = @style.transform

        pathString = @getCommandString()

        if pathString.length > 0
          pathElement.setAttribute 'd', pathString

        if @bevel
          @backgroundPathElement = pathElement
          @backgroundPathElement.setAttribute 'class', 'droplet-background-path'
          pathElement = document.createElementNS SVG_STANDARD, 'g'

          @lightPathElement = document.createElementNS SVG_STANDARD, 'path'
          @lightPathElement.setAttribute 'fill', avgColor @style.fillColor, 0.7, '#FFF'
          if pathString.length > 0
            @lightPathElement.setAttribute 'd', @getLightBevelPath()
          @lightPathElement.setAttribute 'class', 'droplet-light-bevel-path'

          @darkPathElement = document.createElementNS SVG_STANDARD, 'path'
          @darkPathElement.setAttribute 'fill', 'none'
          @darkPathElement.setAttribute 'stroke', avgColor @style.fillColor, 0.7, '#000'
          if pathString.length > 0
            @darkPathElement.setAttribute 'd', @getCommandString()
          @darkPathElement.setAttribute 'class', 'droplet-dark-bevel-path'

          pathElement.appendChild @backgroundPathElement
          # pathElement.appendChild @lightPathElement
          pathElement.appendChild @darkPathElement
        else
          pathElement.setAttribute 'stroke', @style.strokeColor
          pathElement.setAttribute 'stroke-width', @style.lineWidth
          if (@style.dotted?.length ? 0) > 0
            pathElement.setAttribute 'stroke-dasharray', @style.dotted

        if @style.cssClass?
          pathElement.setAttribute 'class', @style.cssClass

        if @style.transform?
          pathElement.setAttribute 'transform', @style.transform

        return pathElement

      update: ->
        return unless @element?
        if @style.fillColor isnt @__lastFillColor
          @__lastFillColor = @style.fillColor

          if @bevel
            @backgroundPathElement.setAttribute 'fill', @style.fillColor
            @lightPathElement.setAttribute 'fill', avgColor @style.fillColor, 0.7, '#FFF'
            @darkPathElement.setAttribute 'fill', avgColor @style.fillColor, 0.7, '#000'
          else
            @element.setAttribute 'fill', @style.fillColor

        if not @bevel and @style.strokeColor isnt @__lastStrokeColor
          @__lastStrokeColor = @style.strokeColor
          @element.setAttribute 'stroke', @style.strokeColor

        if not @bevel and @style.dotted isnt @__lastDotted
          @__lastDotted = @style.dotted
          @element.setAttribute 'stroke-dasharray', @style.dotted

        if not @bevel and @style.lineWidth isnt @__lastLineWidth
          @__lastLineWidth = @style.lineWidth
          @element.setAttribute 'stroke-width', @style.lineWidth

        if @style.cssClass? and @style.cssClass isnt @_lastCssClass
          @_lastCssClass = @style.cssClass
          @element.setAttribute 'class', @style.cssClass

        if @style.transform? and @style.transform isnt @_lastTransform
          @_lastTransform = @style.transform
          @element.setAttribute 'transform', @style.transform

        if @_markFlag
          if @markColor?
            if @bevel
              @backgroundPathElement.setAttribute 'stroke', @markColor
              @backgroundPathElement.setAttribute 'stroke-width', '2'
              @lightPathElement.setAttribute 'visibility', 'hidden'
              @darkPathElement.setAttribute 'visibility', 'hidden'
            else
              @element.setAttribute 'stroke', @markColor
              @element.setAttribute 'stroke-width', '2'
          else
            if @bevel
              @backgroundPathElement.setAttribute 'stroke', 'none'
              @lightPathElement.setAttribute 'visibility', 'visible'
              @darkPathElement.setAttribute 'visibility', 'visible'
            else
              @element.setAttribute 'stroke', @style.strokeColor
              @element.setAttribute 'stroke-width', @style.lineWidth

        if @_updateFlag
          @_updateFlag = false
          pathString = @getCommandString()
          if pathString.length > 0
            if @bevel
              @backgroundPathElement.setAttribute 'd', pathString
              @lightPathElement.setAttribute 'd', @getLightBevelPath()
              @darkPathElement.setAttribute 'd', @getCommandString()
            else
              @element.setAttribute 'd', pathString

      clone: ->
        clone = new Path(@_points.slice(0), @bevel, {
          lineWidth: @style.lineWidth
          fillColor: @style.fillColor
          strokeColor: @style.strokeColor
          dotted: @style.dotted
          cssClass: @style.cssClass
        })
        clone._clearCache()
        clone.update()
        return clone

    # ## Text ##
    # A Text element. Mainly this exists for computing bounding boxes, which is
    # accomplished via ctx.measureText().
    @Text = class Text extends ElementWrapper
      constructor: (@point, @value) ->
        @__lastValue = @value
        @__lastPoint = @point.clone()

        @_bounds = new Rectangle @point.x, @point.y, self.measureCtx.measureText(@value).width, self.fontSize

        super()

      clone: -> new Text @point, @value
      equals: (other) -> other? and @point.equals(other.point) and @value is other.value

      bounds: -> @_bounds
      contains: (point) -> @_bounds.contains point

      setPosition: (point) -> @translate point.from @point

      makeElement: ->
        element = document.createElementNS SVG_STANDARD, 'text'
        #element.setAttribute 'fill', '#444'

        # We use the alphabetic baseline and add the distance
        # to base ourselves to avoid a chrome bug where text zooming
        # doesn't work for non-alphabetic baselines
        element.setAttribute 'x', @point.x
        element.setAttribute 'y', @point.y + self.fontBaseline - self.fontAscent / 2
        element.setAttribute 'dominant-baseline', 'alphabetic'

        #element.setAttribute 'font-family', self.fontFamily
        #element.setAttribute 'font-size', self.fontSize

        text = document.createTextNode @value.replace(/ /g, '\u00A0') # Preserve whitespace
        element.appendChild text

        return element

      update: ->
        return unless @element?
        unless @point.equals(@__lastPoint)
          @__lastPoint = @point.clone()
          @element.setAttribute 'x', @point.x
          @element.setAttribute 'y', @point.y + self.fontBaseline - self.fontAscent / 2

        unless @value is @__lastValue
          @__lastValue = @value
          @element.removeChild(@element.lastChild)
          text = document.createTextNode @value.replace(/ /g, '\u00A0')
          @element.appendChild text

  refreshFontCapital:  ->
    metrics = helper.fontMetrics(@fontFamily, @fontSize)
    @fontAscent = metrics.prettytop
    @fontBaseline = metrics.baseline

  setGlobalFontSize:  (size) ->
    @fontSize = size
    @ctx.style.fontSize = size
    @measureCtx.font = "#{@fontSize}px #{@fontFamily}"
    @refreshFontCapital()

  setGlobalFontFamily:  (family) ->
    @fontFamily = family
    @ctx.style.fontFamily = family
    @measureCtx.font = "#{@fontSize}px #{@fontFamily}"
    @refreshFontCapital()

  getGlobalFontSize:  -> @fontSize

exports.Point = class Point
  constructor: (@x, @y) ->

  clone: -> new Point @x, @y

  magnitude: -> Math.sqrt @x * @x + @y * @y

  times: (scalar) -> new Point @x * scalar, @y * scalar

  normalize: -> @times 1 / @magnitude()

  translate: (vector) ->
    @x += vector.x; @y += vector.y

  add: (x, y) -> @x += x; @y += y

  dot: (other) -> @x * other.x + @y * other.y

  plus: ({x, y}) -> new Point @x + x, @y + y

  toMagnitude: (mag) ->
    r = mag / @magnitude()
    return new Point @x * r, @y * r

  copy: (point) ->
    @x = point.x; @y = point.y
    return @

  from: (point) -> new Point @x - point.x, @y - point.y

  clear: -> @x = @y = 0

  equals: (point) -> point.x is @x and point.y is @y

  almostEquals: (point) ->
    Math.abs(point.x - @x) < EPSILON and
    Math.abs(point.y - @y) < EPSILON

ZERO = new Point 0, 0

exports.Size = class Size
  constructor: (@width, @height) ->
  equals: (size) ->
    @width is size.width and @height is size.height
  @copy: (size) ->
    new Size(size.width, size.height)

exports.Rectangle = class Rectangle
      constructor: (@x, @y, @width, @height) ->

      contains: (point) -> @x? and @y? and not ((point.x < @x) or (point.x > @x + @width) or (point.y < @y) or (point.y > @y + @height))

      equals: (other) ->
        unless other instanceof Rectangle
          return false
        return @x is other.x and
        @y is other.y and
        @width is other.width and
        @height is other.height

      copy: (rect) ->
        @x = rect.x; @y = rect.y
        @width = rect.width; @height = rect.height
        return @

      clone: ->
        rect = new Rectangle(0, 0, 0, 0)
        rect.copy this
        return rect

      clear: -> @width = @height = 0; @x = @y = null

      bottom: -> @y + @height
      right: -> @x + @width

      unite: (rectangle) ->
        unless @x? and @y? then @copy rectangle
        else unless rectangle.x? and rectangle.y? then return
        else
          @width = max(@right(), rectangle.right()) - (@x = min @x, rectangle.x)
          @height = max(@bottom(), rectangle.bottom()) - (@y = min @y, rectangle.y)

      swallow: (point) ->
        unless @x? and @y? then @copy new Rectangle point.x, point.y, 0, 0
        else
          @width = max(@right(), point.x) - (@x = min @x, point.x)
          @height = max(@bottom(), point.y) - (@y = min @y, point.y)

      overlap: (rectangle) -> @x? and @y? and not ((rectangle.right()) < @x or (rectangle.bottom() < @y) or (rectangle.x > @right()) or (rectangle.y > @bottom()))

      translate: (vector) ->
        @x += vector.x; @y += vector.y

      upperLeftCorner: -> new Point @x, @y

      toPath: ->
        path = new Path()
        path.push new Point(point[0], point[1]) for point in [
          [@x, @y]
          [@x, @bottom()]
          [@right(), @bottom()]
          [@right(), @y]
        ]
        return path

exports._collinear = _collinear = (a, b, c) ->
  first = b.from(a).normalize()
  second = c.from(b).normalize()
  return first.almostEquals(second) or first.almostEquals(second.times(-1))
