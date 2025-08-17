#import "@preview/subpar:0.2.2"

= Introduction
Nowadays, people mostly take it for granted that they can use their computers for various activities and interact with it seamlessly without any hiccups. This is possible thanks to a tight feedback loop, where users can observe the current _state_ of their system via their displays and based on this make decisions on what to do next by controlling their mouse and keyboard. For example, when browsing a web page, they expect to be able to navigate and scroll through web pages without significant delay. When writing an e-mail, the typed words should immediately show up on the display so that they can be seen and edited in the case of a typo.

However, something that is often not appreciated is that their actually is _a lot of_ work happening in the background to ensure that the user has a seemless experience when doing the above-mentioned activities. One fundamental reason for this is that there exists a huge gap between the representation of graphical information in our applications and the way displays can actually show information to the user that needs to be bridged. This mismatch is exemplified in @comparison_vector_raster.

On the side of a web browser, the contents of a page are represented using _vector drawing instructions_. Conceptually, the viewable area is interpreted as a (in most cases) y-down, continuous coordinate system. Inside of this coordinate system, drawing instructions can be emitted, such as _draw a line from point A to point B_ or _draw a curve from point B to point C, while intersecting point D on the way_. These basic primitives will be defined more precisely in @preliminaries.

By combining these primitives in different ways, the outline of virtually any arbitrary shape can be defined in a mathematically precise way. This includes simple shapes like for example rectangles or circles, but also extends to more complex shapes such as whole letters of the alphabet

#subpar.grid(
  figure(image("/assets/facebook_modal.svg"), caption: [
    The modal as a vector graphic.
  ]), <comparison_vector>,
  figure(image("/assets/facebook_modal.png"), caption: [
    The modal as a 180x225 image.
  ]), <comparison_raster>,
  columns: (1fr, 1fr),
  caption: [A comparison between a vector graphic and a rasterized image, based on a recreation of the Facebook login modal @facebook_login.],
  label: <comparison_vector_raster>,
)

