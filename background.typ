#import "@preview/subpar:0.2.2"
#import "utils.typ": mid-fig

= Background <background>
In this chapter, we will introduce some of the basic ideas and concepts of 2D rendering.

== 2D rendering
Nowadays, people mostly take it for granted that they can use their computers for various activities and interact with it seamlessly without any hiccups. This is possible thanks to a tight feedback loop, where users can observe the current _state_ of their system via their displays and based on this make decisions on what to do next by controlling their mouse and keyboard. For example, they expect to be able to navigate and scroll through web pages without significant delay. When writing an e-mail, the typed words should immediately show up on the display so that they can be seen and edited in the case of a typo.

However, something that is often not appreciated is that there actually is _a lot of_ work happening in the background to ensure that the user has a seemless experience when doing the above-mentioned activities. One fundamental reason for this is that there exists a huge gap between the representation of graphical information in our applications and the way displays can actually show information to the user. This gap needs to be bridged in some way. This mismatch is exemplified in @comparison_vector_raster.

#subpar.grid(
    figure(image("/assets/facebook_modal.png"), caption: [
    The modal as a 180x225 image.
  ]), <comparison_raster>,
  figure(image("/assets/facebook_modal.svg"), caption: [
    The modal as a vector graphic.
  ]), <comparison_vector>,
  columns: (1fr, 1fr),
  caption: [A comparison between a rasterized image and a vector graphic, based on a recreation of the Facebook login modal @facebook_login.],
  label: <comparison_vector_raster>,
  placement: auto
)

Computer displays only understand one language: the language of pixels. Computer screens are made up by a rectangular grid of small individual pixels (usually anywhere between 1000 and 4000 pixels in a single direction) that can emit varying intensities of red, green and blue at the same time. By mixing and matching those intensities in certain ways, other intermediate color such as orange, purple or white can be simulated. By making each pixel emit a specific color, we can simulate nearly any graphical effect that can then be interpreted by the user. @comparison_raster shows a Facebook login modal as it is displayed on a screen with a resolution of 180x225 pixels. When looking at this picture from afar, it is very easy to discern the login modal. However, a considerable disadvantage of this pixel-based graphics model is that it's inherently lossy: Once you render the modal at a specific pixel resolution and approximate its contents by pixels, there is no way to recover the original information anymore. As a result, when trying to zoom into @comparison_raster to scale it up, instead of becoming more readable, the result will contain very noticeable pixel artifacts and become even _harder_ to read.

This is in stark contrast to the graphics model used by web browsers and other applications, where the contents of a graphics object are instead represented using _vector drawing instructions_. Conceptually, the viewable area is usually interpreted as a continuous coordinate system. Inside of this coordinate system, drawing instructions can be emitted, such as _draw a line from point A to point B_ or _draw a curve from point C to point D, while intersecting the point E on the way_. The exact semantics of these basic primitives will be defined more precisely in @primitives.

By combining these primitives in different ways, the outline of virtually any arbitrary shape can be defined in a mathematically precise way. This includes simple shapes like for example rectangles or circles, but also extends to more complex shapes such as whole letters of the alphabet. Finally, by combining multiple shapes and specifying colors those shapes should be painted with, nearly any kind of graphical object can be produced, including the modal in @comparison_vector. An important consequence of this type of representation is that it is resolution-independent and thus makes the object _arbitrarily scalable_ at any resolution. This can be seen in @comparison_vector, where no matter how much you zoom into the figure, the text and the shapes always remain crisp in quality.

However, this divergence between the way applications represent graphics and the way computer screens display them means that there must be some intermediate step that, given a specific pixel resolution, performs the (inherently lossy) conversion from continuous vector space to the discrete pixel space, as fast and accurately as possible. Performing this translation step is the fundamental task of a _2D graphics renderer_.

== Drawing Primitives <primitives>
As mentioned above, a set of very basic drawing primitives is required to be able to define the outlines of graphical objects. By combining dozens or even hundreds of these primitives, we can build nearly any arbitrarily complex shape. There is no unanimously recognized set of such building blocks, and different specifications have different requirements in this regard. For example, the PDF (portable document format) specification only defines lines and cubic Bézier curves as the basic path-building primitives #cite(<pdf_spec>, supplement: [p. 132-133]), while the SVG (scalable vector graphics) specification additionally also allows using quadratic Bézier curves and elliptic arc curves #cite(<svg1_spec>, supplement: [ch. 8]).

Nevertheless, in general there are three path-building primitives that are used nearly universally, and any other primitives that might be defined in certain specifications can usually be approximated by them: _Lines_, _quadratic Bézier curves_ and _cubic Bézier curves_.

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

== Fills and strokes
We know now how we can define the outline of a shape we want to draw.

== Fill rules

== Colors

== Anti-aliasing

== Paints