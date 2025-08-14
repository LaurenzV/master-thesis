#import "template.typ": template

#let title = "High-performance 2D graphics rendering on the CPU using sparse strips"
#let thesis_type = "Master Thesis"
#let author = "Laurenz Stampfl"
#let advisors = (
  "Prof. Dr. Ralf Jung",
  "Dr. Raph Levien" 
)
#let department = "Department of Computer Science, ETH Zürich"

#let abstract = [
  #lorem(100)
]

#show: doc => template(
  title,
  thesis_type,
  author,
  advisors,
  department,
  abstract,
  doc
)

= Introduction

#lorem(50)

== Another heading

#lorem(600)

= Preliminaries

== How doe this work?

#lorem(3000)

Hi there

This is some more text that I want to try out, let's see how that pans out.

#lorem(3000)

Lemme type some more stuff, it still seems to work flawlessly!