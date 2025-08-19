#import "@preview/subpar:0.2.2"

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

This is in stark contrast to the graphics model used by web browsers and other applications, where the contents of a graphics object are instead represented using _vector drawing instructions_. Conceptually, the viewable area is usually interpreted as a y-down, continuous coordinate system. Inside of this coordinate system, drawing instructions can be emitted, such as _draw a line from point A to point B_ or _draw a curve from point C to point D, while intersecting the point E on the way_. The exact semantics of these basic primitives will be defined more precisely in @primitives.

By combining these primitives in different ways, the outline of virtually any arbitrary shape can be defined in a mathematically precise way. This includes simple shapes like for example rectangles or circles, but also extends to more complex shapes such as whole letters of the alphabet. Finally, by combining multiple shapes and specifying colors those shapes should be painted with, nearly any kind of graphical object can be produced, including the modal in @comparison_vector. An important consequence of this type of representation is that it is resolution-independent and thus makes the object _arbitrarily scalable_ at any resolution. This can be seen in @comparison_vector, where no matter how much you zoom into the figure, the text and the shapes always remain crisp in quality.

However, this divergence between the way applications represent graphics and the way computer screens display them means that there must be some intermediate step that, given a specific pixel resolution, performs the (inherently lossy) conversion from continuous vector space to the discrete pixel space, as fast and accurately as possible. Performing this translation step is the fundamental task of a _2D graphics renderer_.

== Primitives <primitives>