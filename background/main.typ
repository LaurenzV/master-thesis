#import "@preview/subpar:0.2.2"
#import "../utils.typ": todo

= Background <background>
In this chapter, we will introduce some of the basic notions of 2D rendering and explain a number of important concepts.

== 2D rendering <rendering_intro>
Nowadays, people mostly take it for granted that they can use their computers for various activities and interact with it seamlessly without any hiccups. This is possible thanks to a tight feedback loop, where users can observe the current _state_ of their system via their displays and based on this make decisions on what to do next by controlling their mouse and keyboard. For example, they expect to be able to navigate and scroll through web pages without significant delay. When writing an e-mail, the typed words should immediately show up on the display so that they can be seen and edited in the case of typos.

However, something that is often not appreciated is that there actually is _a lot of_ work happening in the background to ensure that the user has a seemless experience when doing the above-mentioned activities. One fundamental reason for this is that there exists a huge gap between the representation of graphical information in our applications and the way displays can actually show information to the user. This gap needs to be bridged in some way. This mismatch is exemplified in @comparison_vector_raster.

#subpar.grid(
  figure(image("/assets/facebook_modal.png"), caption: [
    The modal as a 180x225 image.
  ]),
  <comparison_raster>,

  figure(image("/assets/facebook_modal.svg"), caption: [
    The modal as a vector graphic.
  ]),
  <comparison_vector>,

  columns: (1fr, 1fr),
  caption: [A comparison between a rasterized image and a vector graphic, based on a recreation of the Facebook login modal @facebook_login.],
  label: <comparison_vector_raster>,
  placement: auto,
)

Computer displays only understand one language: the language of pixels. Computer screens are made up by a rectangular grid of small individual pixels (usually anywhere between 1000 and 4000 pixels in a single direction) that can emit varying intensities of red, green and blue at the same time. By mixing and matching those intensities in certain ways, other intermediate color such as orange, purple or white can be simulated. By making each pixel emit a specific color, we can simulate nearly any graphical effect that can then be interpreted by the user. @comparison_raster shows a Facebook login modal as it is displayed on a screen with a resolution of 180x225 pixels. When looking at this picture from afar, it is very easy to discern the login modal. However, a considerable disadvantage of this pixel-based graphics model is that it is inherently lossy: Once you render the modal at a specific pixel resolution and approximate its contents by pixels, there is no way to recover the original information anymore. As a result, when trying to zoom into @comparison_raster to scale it up, instead of becoming more readable, the result will contain very noticeable pixel artifacts and become even _harder_ to read.

This is in stark contrast to the graphics model used by web browsers and other applications, where the contents of a graphics object are instead represented using _vector drawing instructions_. Conceptually, the viewable area is usually interpreted as a continuous coordinate system. Inside of this coordinate system, drawing instructions can be emitted, such as _draw a line from point A to point B_ or _draw a curve from point C to point D, while intersecting the point E on the way_. The exact semantics of these basic primitives will be defined more precisely in @drawing_primitives.

By combining these primitives in various ways, the outline of virtually any arbitrary shape can be defined in a mathematically precise way. This includes simple shapes like for example rectangles or circles, but also extends to more complex shapes such as whole letters of the alphabet. Finally, by combining multiple shapes and specifying the color those shapes should be painted with, nearly any kind of graphical object can be produced, including the modal in @comparison_vector. An important consequence of this type of representation is that it is _resolution-independent_ and thus makes the object _arbitrarily scalable_ at any resolution. No matter how much you zoom into @comparison_vector, the text and the shapes always remain crisp in quality.

However, this divergence between the way applications represent graphics and the way computer screens display them means that there must be some intermediate step that, given a specific pixel resolution, performs the (inherently lossy) conversion from continuous vector space to the discrete pixel space, as fast and accurately as possible. Performing this translation step is the fundamental task of a _2D graphics renderer_.

== Drawing Primitives <drawing_primitives>
As mentioned above, a set of very basic drawing primitives is required to be able to define the outlines of graphical objects. By combining dozens or even hundreds of these primitives, we can build nearly any arbitrarily complex shape. There is no unanimously recognized set of such building blocks, and different specifications have different requirements in this regard. For example, the PDF (portable document format) specification only defines lines and cubic Bézier curves as the basic path-building primitives #cite(<pdf_spec>, supplement: [p. 132-133]), while the SVG (scalable vector graphics) specification additionally also allows using quadratic Bézier curves and elliptic arc curves #cite(<svg1_spec>, supplement: [ch. 8]).

Nevertheless, in general, there are three path-building primitives that are used nearly universally, and any other primitives that might be defined in certain specifications can usually be approximated by them: _Lines_, _quadratic Bézier curves_ and _cubic Bézier curves_.

Each type of primitive has a start point $P_0$ and an end point $P_1$ defined in the 2D coordinate system. We can then define a parametric variable $t in [0.0, 1.0]$ as well as a parametric function $F$ such that $F(0) = P_0$, $F(1) = P_1$, and $F(t) = P_i$, where $P_i$ simply represents the position of the interpolated point for the given drawing primitive. Conceptually, we then evaluate the function _infinitely_ many times for all values in the interval $[0, 1]$ and can then plot its exact representation.

=== Lines
The definition of lines is relatively straight-forward and illustrated in @line_definition. Given our start and end points $P_0$ and $P_1$, we can use the formula $F(t) = P_0 + t (P_1 - P_0)$ to perform a simple linear interpolation and evaluate it #cite(<mathematics_for_computer_graphics>, supplement: [p. 218]). When doing so for all $t in [0,1]$, we end up with a straight line that connects the two points.

#figure(
  image("assets/lines.pdf"),
  caption: [The course of a straight line between two points $P_0$ and $P_1$.],
) <line_definition>

=== Quadratic Bézier curves
For quadratics Bézier curves, things are a bit different. While we still have the start and end points $P_0$ and $P_1$, we have a third point $P_2$ which is called the _control point_. Given these points, the formula for evaluating the curve is given by $P_0(1 - t)^2 + 2 * (1 - t) t P_2 + P_1 * t^2$ #cite(<mathematics_for_computer_graphics>, supplement: [p. 239]). The evaluation of a quadratic Bézier curve can be nicely visualized by thinking of it as a linear interpolation applied twice, as can be seen in @quads_definition.

Assume we want to evaluate the curve at $t = 0.3$. We first start by finding the point $P_0P_2$ by linearly interpolating the points $P_0$ and $P_2$ with our given $t$. We do the same for the line spanning the points $P_2$ and $P_1$ to end up with the point $P_2P_1$. Then, we simply connect the points $P_0P_2$ and $P_2P_1$, and perform another round of linear interpolation with our value $t$, which will then yield the final point on the curve. Similarly to simple line segments, we perform this evaluation for all $t in [0, 1]$ to end up with the final curve as it is visualized on the right in @quads_definition.

#figure(
  image("assets/quads.pdf"),
  caption: [Visualizations of the evaluation of a quadratic curve.],
) <quads_definition>

=== Cubic Bézier curves
Cubic Bézier curves follow the same pattern as quadratic curves, the only difference being that we have an additional control point $P_3$, and therefore need to run three rounds of linear interpolation to evaluate a point on the curve. The formula is given by $P_0(1 - t)^3 + P_2 3t(1 - t)^2 + P_3 3t^2(1 - t) + P_1t^3$ #cite(<mathematics_for_computer_graphics>, supplement: [p. 240]). In @cubics_definition, we can once again gain a better intuition of this formula by visualizing the whole process of evaluation by repeatedly subdividing the curve using linear interpolation with our parametric value $t$, until we have computed the final point.

#figure(
  image("assets/cubics.pdf"),
  caption: [Visualizations of the evaluation of a cubic curve.],
) <cubics_definition>

== Fills and strokes <fills-and-strokes>
#subpar.grid(
  figure(image("assets/dragon_outline.svg"), caption: [
    The outline of a dragon.
    #linebreak()#linebreak()
  ]),
  <dragon_outline>,
  figure(image("assets/dragon_filled.svg"), caption: [
    The dragon painted using a blue fill.
    #linebreak()#linebreak()
  ]),

  <dragon_filled>,
  figure(image("assets/dragon_stroked.svg"), caption: [
    The dragon painted using a blue stroke of width 2 pixels.
  ]),
  <dragon_stroked>,

  columns: (1fr, 1fr, 1fr),
  caption: [Illustration of the different drawing modes.],
  label: <drawing_modes>,
  placement: auto,
)

We now know how we can define the outline of a shape using lines and curves, but how can we actually _draw_ it? In general, we distinguish between two different types of drawing modes: _filling_ and _stroking_. @drawing_modes illustrates the difference between those. In @dragon_outline, we can see the outline of a dragon, which has been specified using the basic building blocks we just defined in @drawing_primitives

In the case of _filling_, we determine all of the areas on the drawing canvas that are _inside_ of the outline we defined (how exactly these are determined will be elaborated in @fill_rules) and paint them using the specified color, as can be seen in @dragon_filled.

_Stroking_ on the other hand uses a different approach. Stroking a shape is analogously equivalent to using a marker with a specific color and width, and using it to trace the outline of the shape. In doing so, all of the outer parts of the shape will be painted in that color. The visual effect of this drawing mode can be observed in @dragon_stroked.

== Fill rules <fill_rules>
Another important problem to be aware of is the question of which parts of a shape are actually considered to be on the "inside" and thus should be colored. For simple shapes such as rectangles or circles, it is intuitively obvious which areas are inside of the shape. But when trying to analyze more complex, self-intersecting paths, just relying on intuition is not sufficient anymore. There is a need for a clear definition of "insideness", such that it is always possible to unambiguously determine whether a point on the drawing area is inside of the shape or not.

In order to do so, we first need to introduce the concept of _winding numbers_. Remember that our shapes are built using lines and curves, which always have a start and an end point. Consequently, each path has an inherent direction. This is illustrated in @star_outline, where we have the outline of a star as well as red arrows that indicate the direction of each line. In order to determine whether any arbitrary point, is inside of the shape, we keep track of a winding number counter (which is initially 0) and shoot an imaginary ray into any arbitrary direction. Every time that ray intersects a path of the shape, we check the direction in which the path intersects our ray. We increase the winding number counter if the direction is left-to-right, and decrease it if it is right-to-left #cite(<svg1_spec>, supplement: [ch. 11]).

#subpar.grid(
  figure(image("assets/star_outline.svg"), caption: [
    Analysis of winding number in two locations .
  ]),
  <star_outline>,
  figure(image("assets/star_nonzero.svg"), caption: [
    The star painted using the non-zero fill rule.
  ]),

  <star_nonzero>,
  figure(image("assets/star_evenodd.svg"), caption: [
    The star painted using the even-odd fill rule.
  ]),
  <star_evenodd>,

  columns: (1fr, 1fr, 1fr),
  caption: [Illustration of the different fill rules.],
  label: <fill_rules_illlustration>,
)

#let orange-point = {
  text(fill: rgb("#ff7911ff"))[orange point]
}
#let blue-point = text(fill: rgb("#000080ff"))[blue point]
#let fuchsia-point = text(fill: rgb("#ff00ffff"))[fuchsia point]

Let us consider the #orange-point and its corresponding ray in @star_outline first. It intersects the shape twice and in both cases the direction is left-to-right. As a consequence, the winding number is two. The #blue-point only has one left-to-right intersection with a path, and therefore has a winding number of one. Finally, the #fuchsia-point first has a right-to-left intersection, resulting in an intermediate winding number of -1. However, it then intersects the path a second time left-to-right, resulting in a final winding number of zero.

We conceptually repeat the above calculation for each point in the drawing area. Once we know all winding numbers, we can simply apply the fill rule to determine whether a point should be painted or not: For the _non-zero_ winding rule, we paint the point if and only if the winding number is not equal to zero. For the _even-odd_ winding rule, we paint the point if and only if the winding number is an odd number. The difference becomes apparent when contrasting @star_nonzero and @star_evenodd. In both cases, the #fuchsia-point remains unpainted, since the winding number is zero. The #blue-point _is_ painted in both cases, since one is both, not equal to zero and also an odd number. Things start to differ when looking at the #orange-point, though. According to the non-zero rule, the point _is_ painted since two is not equal to zero. However, it is not painted according to the even-odd rule, because two is not an odd number.

== Colors <colors>
In order to be able to paint shapes using certain colors, we need to be able to somehow _specify_ those colors. The specification of colors is an incredibly multi-faceted and complex topic; covering all the details that are involved in the different ways colors can be defined is beyond the scope of this work. Instead, we will limit our explanations to defining RGB colors in the sRGB color space @srgb_color_space. The sRGB color space is used frequently in the context of computer devices and the default color space in many web graphics specifications such as SVG #cite(<svg1_spec>, supplement: [ch. 12]) or HTML Canvas #cite(<html_spec>, supplement: [ch. 4.12]).

#let color-grid = [
  #let color-rect(fill) = box[#rect(
    width: 1.2em,
    height: 1.2em,
    fill: fill,
    stroke: 1pt,
  )];

  #let color-el(r, g, b) = grid(
    align: horizon,
    columns: 2,
    column-gutter: 4pt,
    color-rect(rgb(r, g, b)),
    [
      R: #r, G: #g, B: #b \
    ],
  )

  #grid(
    columns: (1fr, 1fr, 1fr),
    column-gutter: 8pt,
    row-gutter: 8pt,
    align: horizon + left,
    [], color-el(0, 0, 0), [],
    color-el(255, 0, 0), color-el(0, 255, 0), color-el(0, 0, 255),
    color-el(128, 128, 0), color-el(36, 19, 140), color-el(200, 0, 220),
    [], color-el(255, 255, 255),
  )
]

#figure(
  color-grid,
  caption: [The result of mixing the color primaries with different intensities.],
) <color-primaries>

In this color model, we define our colors using the three primaries red, green, and blue, which can be activated with varying degrees of intensity. How these intensities are described depends on the underlying number type that we use. When using 32-bit floating point numbers (from now we will shorten this to `f32`, as is the convention in Rust), $0.0$ usually stands for no activation at all, while $1.0$ stands for full activation. It is also common to use 8-bit unsigned integers (often shortened to `u8`) to represent the RGB intensities, in which case 0 stands for no activation and 255 stands for full activation. @color-primaries shows some of the resulting colors that can be achieved by mixing intensities in certain ways: Enabling none of the primaries gives you a black color, while fully enabling all results in white. Fully activating one of the primaries while disabling all other ones results in the primary color itself. And finally, by using various combinations of intensities, many different intermediate colors can be created.

== Opacity
So far, we have only considered the situation of drawing a _single_ shape in a specific color. In doing so, we expect all areas covered by the shape to be painted using the specified color. However, what happens if we draw 2 shapes in different colors that overlap each other? How will the area that contains the overlaps be painted?

The answer depends on the _opacity_ (also known as alpha) of the color. In @colors, it was mentioned that a color is specified by the three components red, green and blue. In reality, there usually is a fourth component that is called _alpha_. The alpha value specifies how transparent the color should be. If the value is 0 (0%), it means that the color is completely _transparent_, i.e. completely invisible. If the value is 1.0 (100%), the color is completely _opaque_, i.e. completely visible. By choosing a value between 0 and 1.0, we can make a color semi-transparent. Similarly to colors, we can also specify opacity using values between 0 and 255 instead. We use the term _RGBA_ to denote storing RGB colors with an additional alpha channel.

#figure(
  grid(
    columns: 4,
    gutter: 1em,
    image("assets/rects_0.svg"),
    image("assets/rects_25.svg"),
    image("assets/rects_75.svg"),
    image("assets/rects_100.svg"),
  ),
  caption: [Painting overlapping shapes with varying opacities and a white background. From left to right: 0%, 25%, 75% and 100% opacities.],
  placement: auto,
) <opacities-fig>

The effect of varying the opacity can be observed @opacities-fig, where a green rectangle with varying opacities is drawn on top of a fully opaque red rectangle. In case the opacity is 0%, the green rectangle cannot be seen at all. In the case of 100%, the overlapping areas are painted completely in green. In all other cases, the background still shines through to a certain degree, depending on how high the transparency is. As a result, the overlapping area of the two rectangles takes on a color that is somewhere "in-between" red and green.

=== Premultiplied alpha
Another important concept related to representation of color is the distinction between _premultiplied_ vs. _non-premultiplied_ alpha. We now know that we can store the RGBA colors using four numbers, each number representing one channel. A fully green color with 50% opacity can be compactly represented using the tuple $(0.0, 1.0, 0.0, 0.5)$. Storing the alpha explicitly as a separate channel is referred to as _non-premultiplied alpha_ representation.

However, as will be demonstrated in @compositing, an issue is that many of the compositing formulas require multiplying the RGB channels with the alpha value. Redoing this computation every time is expensive, giving rise to the idea of performing this multiplication _ahead of time_ and storing the color implicitly with the alpha channel multiplied. This is referred to as _premultiplied alpha_ representation @image_compositing_fundamentals.

For example, given our above example $(0.0, 1.0, 0.0, 0.5)$, in order to convert it into premultiplied representation we simply need to multiply the RGB channels with the alpha value, which results in the tuple $(0.0 * 0.5, 1.0 * 0.5, 0.0 * 0.5, 0.5) = (0.0, 0.5, 0.0, 0.5)$. Doing calculations using premultiplied alpha whenever possible is incredible important to ensure high performance, as it can drastically reduce the number of computations that need to be done per pixel.

== Compositing <compositing>
#todo([Figure out how to summarize this briefly.])

== Blending 

#todo([Add section on blending? (probably not worth it)])

== Anti-aliasing

As was elaborated in @rendering_intro, the main goal of 2D rendering is to convert vector graphics into pixel representation. However, a fundamental problem is that since vector graphics are defined in a continuous space, it is possible that certain parts of the shape only _partially_ cover a pixel, as can be seen for example in @butterfly_outlined. Since a pixel can only emit one specific color, there is no direct way of retaining that information after the conversion process. There are two ways this problem can be dealt with.

#subpar.grid(
figure(image("assets/butterfly_outlined_zoomed.pdf", width: 60%), caption: [
    Examples of pixel coverages.
  ]), <butterfly_outlined>,

  grid(columns: (60%, 40%), [
    #figure(image("assets/butterfly_anti_aliased.pdf"), caption: [
    Rasterizing with anti-aliasing. #linebreak()  #linebreak()
  ]) <butterfly_anti_aliased>
  ],
  [
    #figure(image("assets/butterfly_no_anti_aliasing.pdf", width: 74%), caption: [
    Rasterizing without anti-aliasing.
  ]) <butterfly_aliased>
  ],
),
  columns: (1fr),
  caption: [A butterfly rasterized to a 20x20 screen with and without anti-aliasing.],
  placement: auto,
) <butterfly_rasterization>

First, we can completely discard information about partial coverages and fully paint the pixel with the color if more than half of the pixel is covered, and not paint it at all in the other case. The result can be seen in @butterfly_aliased. By using this method, the resulting shape will look noticeable blocky. These artifacts are referred to as _aliasing artifacts_ @anti_aliasing_techniques and are usually undesirable. For example, when rendering text at a very low resolution, the letters might become very hard to read.

Because of this, it is common to render with _anti-aliasing_ enabled. When looking at @butterfly_anti_aliased, it is apparent that the edges of the butterfly are much smoother and easier to look at. This effect is achieved by "simulating" the partial coverage of pixels by applying an additional opacity so that parts of the background still shine through. In @butterfly_anti_aliased, all pixels that are strictly within the shape are still painted using a fully opaque, blue color, while edge pixels appear much lighter due to the additional opacity.

It is worth highlighting that by doing the above, we are _conflating_ two very distinct concepts: The alpha value of a color and the coverage of a pixel are not inherently related to each other, it just so happens that when rasterizing images, using color alpha to approximate pixel coverage usually works well in practice. But, this approach isn't flawless and can lead to so-called _conflation-artifacts_ @gpu_accelerated_path_rendering. The effects of this phenomenon can be observed in @conflation_figure, where we are drawing two fully opaque triangles that overlap each other. Since the green triangle completely overlaps the red one, there should be no visible red paint.

#figure(
  block(width: 60%, grid(
    row-gutter: 1em,
    column-gutter: 1em,
    columns: (1fr, 1fr, 1fr),
    image("assets/triangle_grid.svg", width: 100%),
    image("assets/triangle_red.svg", width: 100%),
    image("assets/triangle_red_green.svg", width: 100%),
    image("assets/triangle_grid.svg", width: 100%),
    image("assets/triangle_raster_red.svg", width: 100%),
    image("assets/triangle_raster_red_green.svg", width: 100%)
  )),
  caption: [Drawing and rasterizing two completely overlapping triangles.]
) <conflation_figure>

However, upon rasterization, something different happens: When we first draw the red triangle, we use an opacity of 50% for the pixels that are only partially covered by the shape. The same happens when drawing the second triangle in green. The crucial detail here is that since we previously _converted_ pixel coverage to color opacities for the edge pixels, we will compose a green pixel with 50% opacity on top of a red pixel with 50% opacity, resulting in a brownish color along the edges instead of a fully green one.

== Complex Paints

Up until now, we have always painted our shapes using a single color. While this is by far the most common operation, there are actually many different kinds of fills that can be used. The exact set of filling primitives that is available can vary: For example, in the case of SVG and HTML Canvas, the two main types of paint are _gradients_ and _patterns_ #cite(<svg1_spec>, supplement: [ch. 13]) #cite(<html_spec>, supplement: [ch. 4.12.5.1.10]). The PDF specification, however, defines some additional paints, including triangle meshes and Coons patch meshes #cite(<pdf_spec>, supplement: [p. 192-201]). In this section, we will narrow our focus on the two above-mentioned paints commonly used in web rendering. Instead of explaining the exact semantics of patterns as they are specified in the SVG specification, we will make a simplification and only talk about plain _image fills_, which can be viewed as a subset of pattern fills.

=== Gradients
Conceptually, gradients represent smooth transitions between two or multiple colors. We consider a  a parametric variable $t$ that ranges between 0.0 and 1.0 and assign a number of colors to a specific position on that range. For example, we could assign the color blue to the position 0.0, the color red to the position 0.4, the color yellow to the position 0.7 and finally the color green to the position 1.0. All of the other positions that have not been explicitly specified are calculated by doing a linear interpolation between the given stops. The result of mapping out the whole range is visualized in @gradient_line.

#figure(
  image("assets/gradient_rectangle.pdf", width: 80%),
  caption: [Visualization of a gradient line with the stops `(blue, 0.0)`, `(red, 0.4)`, `(yellow, 0.7)` and `(green, 1.0)`.]
) <gradient_line>

Once we have a mapping from $t$ values to a color, we simply need to define another mapping from the $(x, y)$ position of a pixel to a $t$ value, so that we know how to color that pixel. There are three commonly used type of gradients that define this mapping in different ways: _Linear gradients_, _radial gradients_ and _sweep gradients_. Examples of applying those paint types to the shape of a butterfly can be seen in @gradients_rect.

#subpar.grid(
  figure(image("assets/rect_linear.svg"), caption: [
    Linear gradient.
  ]),
  <rect_linear>,

  figure(image("assets/rect_radial.svg"), caption: [
    Radial gradient.
  ]),
  <rect_radial>,

  figure(image("assets/rect_sweep.svg"), caption: [
    Sweep gradient.
  ]),
  <rect_sweep>,
  columns: (1fr, 1fr, 1fr),
  caption: [The shape of a rectangle filled using a linear, radial and sweep gradient.],
  label: <gradients_rect>,
) 

In the case of a linear gradient, we define a start and end point along which the gradient should interpolate. In the case of @rect_linear, the start point is in the top-left corner and the end point in the bottom-right corner. The visual effect will be a linear variation of the gradient line in a diagonal direction.

For radial gradients, we define the position and radius of a start circle as well as an end circle. In @rect_radial, the start and end circles are both positioned in the center, while the start radius is set to 0 and the end radius to the maximum. The visual result of this gradient is a progression of the interpolated colors in a circular fashion, as if the inner circle "expanded" to the outer circle while varying the color.

Finally, sweep gradients are colored by setting a center point as well as a start and end angle. In @rect_sweep, the center point has been set in the middle, and the radii are 0#sym.degree and 360#sym.degree respectively. In the end, the colors of the gradient line will vary as the angle of the position of the pixel from the center increases.

=== Images
As was mentioned in @rendering_intro, it is highly desirable to represent content as vector graphics whenever possible, as it allows for arbitrary scaling without any loss of precision. However, it is clear that this is not always possible, because many objects simply cannot be represented as vector graphics, like for example images taken with a camera.

The fundamental difficulty of rendering images in 2D graphics is that the input image might not have the same resolution as the rendered image. For instance, if an input image has a resolution of 1000x800 pixels but our output display has a resolution of 1350x1080, we need to apply a scaling factor of 1.35 to the image for it to render correctly. To do this, we need to _resample_ the image to determine what color each pixel on the display should be to accurately reproduce the original image at the higher resolution. In order to achieve this, three methods are commonly used: _Nearest-neighbor interpolation_, _bilinear interpolation_ and _bicubic interpolation_ #cite(<digital_image_processing>, supplement: [p. 87-89]). @patterns_rect contrasts the different scaling methods using the 10x10 pixels input image in @input_image scaled by a factor of 50.

#subpar.grid(
  [], figure(image("assets/texture_nearest_neighbor.png", width: 30%), caption: [
    The input image.
  ]),
  <input_image>, [],
figure(image("assets/rect_nearest_neighbor.svg"), caption: [
    Nearest-neighbor interpolation.
  ]),
  <rect_nearest_neighbor>,
figure(image("assets/rect_bilinear.svg"), caption: [
    Bilinear interpolation. #linebreak() #linebreak()
  ]),
  <rect_bilinear>,

  figure(image("assets/rect_bicubic.svg"), caption: [
    Bicubic interpolation. #linebreak() #linebreak()
  ]),
  <rect_bicubic>,
  columns: (1fr, 1fr, 1fr),
  caption: [The shape of a rectangle filled using a 50x scaled image using nearest-neighbor, bilinear and bicubic interpolation.],
  label: <patterns_rect>,
  placement: auto
) 

In the case of nearest-neighbor interpolation, the algorithm is very straight-forward: It simply calculates the position of the new pixel in the old image by multiplying it with the inverse scale, and then samples the color value of the closest pixel. The result in @rect_nearest_neighbor shows that by using this interpolation method, the "block-like" structure of the original input image is preserved. In certain cases, this can be a desirable property (imagine for example rendering a heat map as it can be created with libraries like `matplotlib`, where you want to ensure that the individual cells retain their color), but in many cases, this interpolation method can cause artifacts, and is therefore not often used #cite(<digital_image_processing>, supplement: [p. 88]). The main advantage is that it is computationally very cheap.

When performing bilinear interpolation, we do not only consider a single nearest neighbor, but actually the four nearest neighbors. We then assign a weight to each neighbor based on the exact location we are sampling and interpolate across those 4 pixels. The same applies to bicubic interpolation, with the only difference that we consider 16 neighbors instead #cite(<digital_image_processing>, supplement: [p. 88]). The results for bilinear interpolation can be observed in @rect_bilinear, where the boundaries appear much smoother due to the interpolation. At first glance, the bicubic interpolation in @rect_bicubic has a very similar effect to the bilinear interpolation in @rect_bilinear, but looking at it closer, it does become apparent that the bilinear version has some very subtle "star-like" artifacts in some places that are not present in the bicubic version. However, the cost for the slightly better quality is a much higher computational intensity per pixel.
